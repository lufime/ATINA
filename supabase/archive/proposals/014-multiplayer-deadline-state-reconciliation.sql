-- Reconcile multiplayer round deadlines from the authoritative room-state poll.
CREATE OR REPLACE FUNCTION public.atina_room_state(p_room_id uuid,p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_me public.atina_room_players%rowtype;
  v_room public.atina_rooms%rowtype;
  v_game private.atina_room_game_state%rowtype;
  v_players jsonb;
  v_team_proposal jsonb;
  v_team text;
  v_now timestamptz;
  v_state jsonb;
BEGIN
  SELECT * INTO v_me FROM public.atina_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;

  SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sala não encontrada.'; END IF;

  SELECT * INTO v_game FROM private.atina_room_game_state
  WHERE room_id=p_room_id FOR UPDATE;

  -- Read the clock only after all relevant row locks have been acquired.
  v_now:=clock_timestamp();
  IF FOUND AND v_game.status='active' AND NOT v_game.round_locked
     AND v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_room_game_state
    SET round_locked=true,updated_at=v_now
    WHERE room_id=p_room_id;
    v_state:=private.atina_room_public_state(p_room_id)
      || jsonb_build_object('feedback','Tempo esgotado.','locked',true);
    UPDATE public.atina_rooms
    SET game_state=v_state,state_version=state_version+1,updated_at=v_now
    WHERE id=p_room_id
    RETURNING * INTO v_room;
  END IF;

  UPDATE public.atina_room_players SET last_seen_at=v_now WHERE id=v_me.id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'nickname',p.nickname,'is_host',p.is_host,'ready',p.ready,
    'team',p.team_label,'score',p.score
  ) ORDER BY p.created_at,p.id),'[]'::jsonb)
  INTO v_players FROM public.atina_room_players p WHERE p.room_id=p_room_id;

  v_team:=v_me.team_label;
  IF v_team IS NOT NULL THEN
    SELECT jsonb_build_object(
      'id',pr.id,'team',pr.team_label,'proposer_id',pr.proposer_id,
      'proposer',pp.nickname,'answer',pr.answer_text,'status',pr.status,
      'votes',coalesce((SELECT jsonb_agg(jsonb_build_object('player_id',v.player_id,'agrees',v.agrees) ORDER BY v.created_at)
        FROM public.atina_room_team_votes v WHERE v.proposal_id=pr.id),'[]'::jsonb)
    ) INTO v_team_proposal
    FROM public.atina_room_team_proposals pr
    JOIN public.atina_room_players pp ON pp.id=pr.proposer_id
    WHERE pr.room_id=p_room_id AND pr.team_label=v_team
      AND pr.challenge_index=coalesce((v_room.game_state->>'pos')::integer,-1)
    ORDER BY pr.created_at DESC LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'room_id',v_room.id,'code',v_room.code,'status',v_room.status,
    'max_players',v_room.max_players,'is_host',v_me.is_host,
    'player_id',v_me.id,'ready',v_me.ready,'team',v_team,
    'my_score',v_me.score,'players',v_players,
    'game_state',v_room.game_state,
    'team_proposal',v_team_proposal,
    'timeouts',jsonb_build_object(
      'player_remaining_seconds',v_me.player_timeout_seconds,
      'team_remaining_seconds',CASE WHEN v_team IS NULL THEN 0 ELSE 3600 END
    )
  );
END;
$function$;
