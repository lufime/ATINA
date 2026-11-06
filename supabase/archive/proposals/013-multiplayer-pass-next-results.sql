-- Server-authoritative pass, next challenge and room completion.
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
  SELECT * INTO v_challenge FROM private.atina_challenges
  WHERE challenge_id=v_game.challenge_queue[v_game.position] AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Desafio atual indisponível.'; END IF;
  SELECT coalesce(jsonb_agg(cl.value ORDER BY cl.ordinality),'[]'::jsonb)
  INTO v_clues
  FROM jsonb_array_elements(v_challenge.clues) WITH ORDINALITY cl(value,ordinality)
  WHERE cl.ordinality<=v_game.revealed_clues;
  RETURN jsonb_build_object(
    'mode','challenges','protocol_version',1,
    'challenge_id',v_challenge.challenge_id,'category',v_challenge.category,
    'emoji',v_challenge.emoji,'clues',v_clues,'image_url',v_challenge.image_url,
    'answer',CASE WHEN v_game.round_locked THEN v_challenge.answer ELSE NULL END,
    'pos',v_game.position-1,'queue_length',cardinality(v_game.challenge_queue),
    'revealed',v_game.revealed_clues,'timedMode',v_game.timed_mode_seconds,
    'deadline',CASE WHEN v_game.deadline_at IS NULL THEN 0 ELSE extract(epoch FROM v_game.deadline_at)*1000 END,
    'locked',v_game.round_locked,'revision',v_room.state_version
  );
END;
$function$;
REVOKE ALL ON FUNCTION private.atina_room_public_state(uuid) FROM public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.atina_pass_room_challenge(p_room_id uuid,p_token text)
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
  v_state jsonb;
  v_status text;
BEGIN
  SELECT * INTO v_player FROM public.atina_room_players
  WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND OR NOT v_player.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode passar o desafio.'; END IF;
  SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id FOR UPDATE;
  SELECT * INTO v_game FROM private.atina_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' THEN RAISE EXCEPTION 'A ronda não está ativa.'; END IF;
  v_now:=clock_timestamp();
  v_status:=CASE WHEN v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN 'timeout' ELSE 'passed' END;
  UPDATE private.atina_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
  v_state:=private.atina_room_public_state(p_room_id)||jsonb_build_object(
    'feedback',CASE WHEN v_status='timeout' THEN 'Tempo esgotado.' ELSE 'Desafio passado.' END,
    'locked',true
  );
  UPDATE public.atina_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
  RETURN jsonb_build_object('status',v_status,'state',v_state);
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_next_room_challenge(p_room_id uuid,p_token text)
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
  v_state jsonb;
  v_results jsonb;
BEGIN
  SELECT * INTO v_player FROM public.atina_room_players
  WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND OR NOT v_player.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode avançar o desafio.'; END IF;
  SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
  SELECT * INTO v_game FROM private.atina_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' THEN RAISE EXCEPTION 'A ronda não está ativa.'; END IF;
  v_now:=clock_timestamp();

  IF v_game.position<cardinality(v_game.challenge_queue) THEN
    UPDATE private.atina_room_game_state
    SET position=position+1,revealed_clues=1,round_locked=false,
        deadline_at=CASE WHEN timed_mode_seconds=0 THEN NULL
          ELSE v_now+make_interval(secs=>timed_mode_seconds) END,
        updated_at=v_now
    WHERE room_id=p_room_id;
    v_state:=private.atina_room_public_state(p_room_id);
    UPDATE public.atina_rooms
    SET game_state=v_state,state_version=state_version+1,updated_at=v_now
    WHERE id=p_room_id;
    RETURN jsonb_build_object('status','next','state',v_state);
  END IF;

  UPDATE private.atina_room_game_state
  SET status='completed',round_locked=true,updated_at=v_now
  WHERE room_id=p_room_id;

  INSERT INTO public.atina_room_results(room_id,player_id,nickname,team_label,score,completed_at)
  SELECT p.room_id,p.id,p.nickname,p.team_label,p.score,v_now
  FROM public.atina_room_players p
  WHERE p.room_id=p_room_id
  ON CONFLICT(room_id,player_id) DO UPDATE
  SET nickname=excluded.nickname,team_label=excluded.team_label,
      score=excluded.score,completed_at=excluded.completed_at;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'player_id',r.player_id,'nickname',r.nickname,'team',r.team_label,'score',r.score
  ) ORDER BY r.score DESC,r.nickname),'[]'::jsonb)
  INTO v_results
  FROM public.atina_room_results r WHERE r.room_id=p_room_id;

  UPDATE public.atina_rooms
  SET status='completed',
      game_state=jsonb_build_object(
        'mode','completed','protocol_version',1,
        'pos',cardinality(v_game.challenge_queue),
        'queue_length',cardinality(v_game.challenge_queue),
        'locked',true,'revision',state_version+1
      ),
      state_version=state_version+1,updated_at=v_now
  WHERE id=p_room_id;

  RETURN jsonb_build_object('status','completed','results',v_results);
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_pass_room_challenge(uuid,text) FROM public;
REVOKE ALL ON FUNCTION public.atina_next_room_challenge(uuid,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_pass_room_challenge(uuid,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_next_room_challenge(uuid,text) TO anon,authenticated;
