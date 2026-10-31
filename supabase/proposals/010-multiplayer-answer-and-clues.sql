-- Authoritative multiplayer answer submission and clue reveal.
CREATE OR REPLACE FUNCTION private.atina_room_public_state(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_game private.atina_room_game_state%rowtype;
  v_challenge private.atina_challenges%rowtype;
  v_room public.atina_rooms%rowtype;
  v_clues jsonb;
BEGIN
  SELECT * INTO v_game FROM private.atina_room_game_state WHERE room_id=p_room_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id;
  SELECT * INTO v_challenge
  FROM private.atina_challenges
  WHERE challenge_id=v_game.challenge_queue[v_game.position] AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Desafio atual indisponível.'; END IF;

  SELECT coalesce(jsonb_agg(cl.value ORDER BY cl.ordinality),'[]'::jsonb)
  INTO v_clues
  FROM jsonb_array_elements(v_challenge.clues) WITH ORDINALITY cl(value,ordinality)
  WHERE cl.ordinality <= v_game.revealed_clues;

  RETURN jsonb_build_object(
    'mode','challenges',
    'protocol_version',1,
    'challenge_id',v_challenge.challenge_id,
    'category',v_challenge.category,
    'emoji',v_challenge.emoji,
    'clues',v_clues,
    'image_url',v_challenge.image_url,
    'pos',v_game.position-1,
    'queue_length',cardinality(v_game.challenge_queue),
    'revealed',v_game.revealed_clues,
    'timedMode',v_game.timed_mode_seconds,
    'deadline',CASE WHEN v_game.deadline_at IS NULL THEN 0 ELSE extract(epoch FROM v_game.deadline_at)*1000 END,
    'locked',v_game.round_locked,
    'revision',v_room.state_version
  );
END;
$function$;
REVOKE ALL ON FUNCTION private.atina_room_public_state(uuid) FROM public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.atina_reveal_room_clue(p_room_id uuid,p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player public.atina_room_players%rowtype;
  v_room public.atina_rooms%rowtype;
  v_game private.atina_room_game_state%rowtype;
  v_total integer;
  v_now timestamptz;
  v_state jsonb;
BEGIN
  SELECT * INTO v_player FROM public.atina_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND OR NOT v_player.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode revelar pistas.'; END IF;

  SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id FOR UPDATE;
  SELECT * INTO v_game FROM private.atina_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' OR v_game.round_locked THEN
    RAISE EXCEPTION 'A ronda não está ativa.';
  END IF;
  v_now:=clock_timestamp();
  IF v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
    UPDATE public.atina_rooms SET game_state=coalesce(private.atina_room_public_state(p_room_id),'{}'::jsonb) || jsonb_build_object('feedback','Tempo esgotado.','locked',true),
      state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
    RETURN jsonb_build_object('status','timeout','state',private.atina_room_public_state(p_room_id));
  END IF;

  SELECT jsonb_array_length(clues) INTO v_total
  FROM private.atina_challenges
  WHERE challenge_id=v_game.challenge_queue[v_game.position] AND active;
  IF v_game.revealed_clues>=v_total THEN
    RETURN jsonb_build_object('status','unchanged','state',private.atina_room_public_state(p_room_id));
  END IF;

  UPDATE private.atina_room_game_state
  SET revealed_clues=revealed_clues+1,updated_at=v_now
  WHERE room_id=p_room_id;
  v_state:=private.atina_room_public_state(p_room_id);
  UPDATE public.atina_rooms
  SET game_state=v_state,state_version=state_version+1,updated_at=v_now
  WHERE id=p_room_id;
  RETURN jsonb_build_object('status','revealed','state',v_state);
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_submit_room_answer(
  p_room_id uuid,
  p_token text,
  p_answer text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player public.atina_room_players%rowtype;
  v_room public.atina_rooms%rowtype;
  v_game private.atina_room_game_state%rowtype;
  v_now timestamptz;
  v_correct boolean;
  v_base integer;
  v_speed integer:=0;
  v_points integer:=0;
  v_score integer;
  v_prior_correct boolean;
  v_state jsonb;
BEGIN
  IF p_answer IS NULL OR char_length(btrim(p_answer))=0 OR char_length(p_answer)>300 THEN
    RAISE EXCEPTION 'Resposta vazia ou demasiado longa.';
  END IF;

  SELECT * INTO v_player FROM public.atina_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;

  SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
  SELECT * INTO v_game FROM private.atina_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' THEN RAISE EXCEPTION 'A partida não tem uma ronda ativa.'; END IF;

  v_now:=clock_timestamp();
  IF v_game.round_locked OR (v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now) THEN
    IF NOT v_game.round_locked THEN
      UPDATE private.atina_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
      v_game.round_locked:=true;
      v_state:=private.atina_room_public_state(p_room_id) || jsonb_build_object('feedback','Tempo esgotado.','locked',true);
      UPDATE public.atina_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
    END IF;
    RETURN jsonb_build_object('status','locked','score',v_player.score,'state',coalesce(v_state,private.atina_room_public_state(p_room_id)));
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.atina_room_answers
    WHERE room_id=p_room_id AND player_id=v_player.id
      AND challenge_index=v_game.position-1 AND is_correct
  ) INTO v_prior_correct;
  IF v_prior_correct THEN
    RETURN jsonb_build_object('status','already_correct','correct',true,'score',v_player.score,'points',0);
  END IF;

  v_correct:=private.atina_challenge_answer_matches(
    v_game.challenge_queue[v_game.position],btrim(p_answer)
  );

  IF v_correct THEN
    SELECT CASE
      WHEN v_game.revealed_clues>=jsonb_array_length(c.clues) THEN
        CASE WHEN c.image_url IS NOT NULL THEN (ARRAY[20,16,12,8,6,5])[v_game.revealed_clues]
             ELSE (ARRAY[20,16,12,8,5])[v_game.revealed_clues] END
      WHEN c.image_url IS NOT NULL THEN (ARRAY[20,16,12,8,6,5])[v_game.revealed_clues]
      ELSE (ARRAY[20,16,12,8,5])[v_game.revealed_clues]
    END
    INTO v_base
    FROM private.atina_challenges c
    WHERE c.challenge_id=v_game.challenge_queue[v_game.position] AND c.active;
    IF v_game.deadline_at IS NOT NULL THEN
      v_speed:=greatest(0,floor(extract(epoch FROM (v_game.deadline_at-v_now))/10)::integer);
    END IF;
    v_points:=v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END;
    UPDATE public.atina_room_players
    SET score=score+v_points,last_seen_at=v_now
    WHERE id=v_player.id RETURNING score INTO v_score;
  ELSE
    UPDATE public.atina_room_players
    SET score=greatest(0,score-10),last_seen_at=v_now
    WHERE id=v_player.id RETURNING score INTO v_score;
  END IF;

  INSERT INTO public.atina_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
  VALUES(p_room_id,v_player.id,v_game.position-1,v_correct,v_points,v_now);

  RETURN jsonb_build_object(
    'status',CASE WHEN v_correct THEN 'correct' ELSE 'wrong' END,
    'correct',v_correct,
    'points',v_points,
    'score',v_score,
    'penalty',CASE WHEN v_correct THEN 0 ELSE 10 END,
    'state',private.atina_room_public_state(p_room_id)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_reveal_room_clue(uuid,text) FROM public;
REVOKE ALL ON FUNCTION public.atina_submit_room_answer(uuid,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_reveal_room_clue(uuid,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_submit_room_answer(uuid,text,text) TO anon,authenticated;
