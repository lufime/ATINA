-- Enforce the same active-team gate for every individual answer.
-- This closes the NULL team_label bypass and uses a consistent room -> player -> game lock order.

CREATE OR REPLACE FUNCTION private.atina_v2_validate_room_turn_actor(
  p_room_id uuid,
  p_player_id uuid,
  p_allow_multi_member_team boolean DEFAULT false
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_team_label text;
  v_team_size integer;
  v_game private.atina_v2_room_game_state%rowtype;
BEGIN
  SELECT team_label INTO v_team_label
    FROM public.atina_v2_room_players
   WHERE id=p_player_id AND room_id=p_room_id;

  IF NOT FOUND OR v_team_label IS NULL THEN
    RAISE EXCEPTION 'O jogador não pertence a uma equipa.';
  END IF;

  SELECT * INTO v_game
    FROM private.atina_v2_room_game_state
   WHERE room_id=p_room_id;

  IF NOT FOUND OR cardinality(v_game.team_order)=0
     OR v_game.active_team_index<1
     OR v_game.active_team_index>cardinality(v_game.team_order)
     OR v_team_label IS DISTINCT FROM v_game.team_order[v_game.active_team_index] THEN
    RAISE EXCEPTION 'Só a equipa que tem a vez pode responder.';
  END IF;

  SELECT count(*) INTO v_team_size
    FROM public.atina_v2_room_players
   WHERE room_id=p_room_id AND team_label=v_team_label;

  IF NOT p_allow_multi_member_team AND v_team_size<>1 THEN
    RAISE EXCEPTION 'As equipas com vários membros têm de usar proposta e votação.';
  END IF;

  RETURN v_team_label;
END;
$function$;

REVOKE ALL ON FUNCTION private.atina_v2_validate_room_turn_actor(uuid,uuid,boolean)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.atina_v2_submit_room_answer(
  p_room_id uuid,p_token text,p_answer text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_now timestamptz;
  v_correct boolean;
  v_base integer;
  v_speed integer:=0;
  v_points integer:=0;
  v_score integer;
  v_prior_correct boolean;
  v_state jsonb;
  v_multiplier integer:=1;
  v_bonus integer:=0;
  v_penalty integer:=10;
BEGIN
  IF p_answer IS NULL OR char_length(btrim(p_answer))=0 OR char_length(p_answer)>300 THEN
    RAISE EXCEPTION 'Resposta vazia ou demasiado longa.';
  END IF;

  -- All room actions acquire locks in the same order to avoid cross-RPC deadlocks.
  SELECT * INTO v_room
    FROM public.atina_v2_rooms
   WHERE id=p_room_id
   FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN
    RAISE EXCEPTION 'A partida não está ativa.';
  END IF;

  SELECT * INTO v_player
    FROM public.atina_v2_room_players
   WHERE room_id=p_room_id
     AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sessão da sala inválida.';
  END IF;

  SELECT * INTO v_game
    FROM private.atina_v2_room_game_state
   WHERE room_id=p_room_id
   FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' THEN
    RAISE EXCEPTION 'A partida não tem uma ronda ativa.';
  END IF;

  PERFORM private.atina_v2_validate_room_turn_actor(p_room_id,v_player.id,false);

  v_now:=clock_timestamp();
  IF v_game.round_locked OR (v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now) THEN
    IF NOT v_game.round_locked THEN
      UPDATE private.atina_v2_room_game_state
         SET round_locked=true,team_turn_advanced=false,updated_at=v_now
       WHERE room_id=p_room_id;
      v_state:=private.atina_v2_room_public_state(p_room_id)
        || jsonb_build_object('feedback','Tempo esgotado.','locked',true);
      UPDATE public.atina_v2_rooms
         SET game_state=v_state,state_version=state_version+1,updated_at=v_now
       WHERE id=p_room_id;
    END IF;
    RETURN jsonb_build_object('status','locked','score',v_player.score,
      'state',coalesce(v_state,private.atina_v2_room_public_state(p_room_id)));
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.atina_v2_room_answers
     WHERE room_id=p_room_id AND player_id=v_player.id
       AND challenge_index=v_game.position-1 AND is_correct
  ) INTO v_prior_correct;
  IF v_prior_correct THEN
    RETURN jsonb_build_object('status','already_correct','correct',true,'score',v_player.score,'points',0);
  END IF;

  v_correct:=private.atina_v2_challenge_answer_matches(
    v_game.challenge_queue[v_game.position],btrim(p_answer)
  );
  v_multiplier:=coalesce((v_game.special_card->>'multiplier')::integer,1);
  v_bonus:=coalesce((v_game.special_card->>'bonus')::integer,0);
  v_penalty:=CASE v_game.special_card->>'id'
    WHEN 'shield' THEN 0 WHEN 'reduced_penalty' THEN 5 ELSE 10 END;

  IF v_correct THEN
    SELECT CASE WHEN c.image_url IS NOT NULL
      THEN (ARRAY[20,16,12,8,6,5])[v_game.revealed_clues]
      ELSE (ARRAY[20,16,12,8,5])[v_game.revealed_clues] END
      INTO v_base
      FROM private.atina_challenges c
     WHERE c.challenge_id=v_game.challenge_queue[v_game.position] AND c.active;
    IF v_game.deadline_at IS NOT NULL THEN
      v_speed:=greatest(0,floor(ceil(extract(epoch FROM (v_game.deadline_at-v_now)))/10)::integer);
    END IF;
    v_points:=(v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END)*v_multiplier+v_bonus;
    UPDATE public.atina_v2_room_players
       SET score=score+v_points,last_seen_at=v_now
     WHERE id=v_player.id RETURNING score INTO v_score;
  ELSE
    UPDATE public.atina_v2_room_players
       SET score=greatest(0,score-v_penalty),last_seen_at=v_now
     WHERE id=v_player.id RETURNING score INTO v_score;
  END IF;

  INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
  VALUES(p_room_id,v_player.id,v_game.position-1,v_correct,v_points,v_now);

  IF v_correct THEN
    UPDATE private.atina_v2_room_game_state
       SET round_locked=true,team_turn_advanced=true,updated_at=v_now
     WHERE room_id=p_room_id;
    v_state:=private.atina_v2_room_public_state(p_room_id);
    UPDATE public.atina_v2_rooms
       SET game_state=v_state,state_version=state_version+1,updated_at=v_now
     WHERE id=p_room_id;
  ELSE
    v_state:=private.atina_v2_room_public_state(p_room_id);
  END IF;

  RETURN jsonb_build_object(
    'status',CASE WHEN v_correct THEN 'correct' ELSE 'wrong' END,
    'correct',v_correct,'points',v_points,'score',v_score,
    'penalty',CASE WHEN v_correct THEN 0 ELSE v_penalty END,'state',v_state
  );
END;
$function$;
