-- Remove os backends de Mímicas e da aventura Detetive.
-- Preserva contas, rankings, desafios normais e salas de outros modos.

CREATE OR REPLACE FUNCTION public.atina_v2_room_state(p_room_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_me public.atina_v2_room_players%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_game private.atina_v2_room_game_state%rowtype;
 v_players jsonb;
 v_team_proposal jsonb;
 v_team text;
 v_now timestamptz;
 v_state jsonb;
 v_pause jsonb;
 v_player_used integer := 0;
 v_team_used integer := 0;
BEGIN
 -- Ordinary polling is read-only: do not lock the player, room, or game rows.
 SELECT * INTO v_me FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256');
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;

 -- Refresh presence at most once every 15 seconds, before acquiring room/game locks.
 v_now:=clock_timestamp();
 UPDATE public.atina_v2_room_players SET last_seen_at=v_now
  WHERE id=v_me.id AND (last_seen_at IS NULL OR last_seen_at < v_now-interval '15 seconds');

 SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sala não encontrada.'; END IF;

 -- Acquire the room lock only when an expired pause must be finalized.
 v_pause := v_room.game_state->'pause';
 IF v_pause IS NOT NULL AND (v_pause->>'ends_at')::timestamptz <= clock_timestamp() THEN
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  v_pause := v_room.game_state->'pause';
  IF v_pause IS NOT NULL AND (v_pause->>'ends_at')::timestamptz <= clock_timestamp() THEN
   v_now := clock_timestamp();
   v_state := jsonb_set(
    jsonb_set(v_room.game_state-'pause','{deadline}',
      to_jsonb(CASE WHEN coalesce((v_pause->>'remaining_seconds')::integer,0)>0
        THEN floor(extract(epoch FROM v_now)*1000)::bigint
             + coalesce((v_pause->>'remaining_seconds')::integer,0)*1000
        ELSE 0 END),true),
    '{revision}',to_jsonb(coalesce((v_room.game_state->>'revision')::integer,0)+1),true);
   UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now
    WHERE id=p_room_id RETURNING * INTO v_room;
  END IF;
 END IF;

 -- Check the game clock without locking. If it has expired, serialize only
 -- the one-time transition, using the same room -> game lock order as actions.
 SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id;
 IF FOUND AND v_game.status='active' AND NOT v_game.round_locked
    AND v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=clock_timestamp() THEN
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF FOUND AND v_game.status='active' AND NOT v_game.round_locked
     AND v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=clock_timestamp() THEN
   UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=clock_timestamp()
    WHERE room_id=p_room_id RETURNING * INTO v_game;
   v_state:=private.atina_v2_room_public_state(p_room_id)||jsonb_build_object('feedback','Tempo esgotado.','locked',true);
   UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=clock_timestamp()
    WHERE id=p_room_id RETURNING * INTO v_room;
  END IF;
 END IF;


 SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'nickname',p.nickname,'is_host',p.is_host,'ready',p.ready,'team',p.team_label,'score',p.score) ORDER BY p.created_at,p.id),'[]'::jsonb)
 INTO v_players FROM public.atina_v2_room_players p WHERE p.room_id=p_room_id;
 v_team:=v_me.team_label;
 IF v_team IS NOT NULL THEN
  SELECT jsonb_build_object('id',pr.id,'team',pr.team_label,'proposer_id',pr.proposer_id,'proposer',pp.nickname,'answer',pr.answer_text,'status',pr.status,
   'votes',coalesce((SELECT jsonb_agg(jsonb_build_object('player_id',v.player_id,'agrees',v.agrees) ORDER BY v.created_at) FROM public.atina_v2_room_team_votes v WHERE v.proposal_id=pr.id),'[]'::jsonb))
  INTO v_team_proposal FROM public.atina_v2_room_team_proposals pr JOIN public.atina_v2_room_players pp ON pp.id=pr.proposer_id
  WHERE pr.room_id=p_room_id AND pr.team_label=v_team AND pr.challenge_index=coalesce((v_room.game_state->>'pos')::integer,-1)
  ORDER BY pr.created_at DESC LIMIT 1;
 END IF;
 SELECT coalesce(used_seconds,0) INTO v_player_used
 FROM private.atina_v2_room_timeout_budgets
 WHERE room_id=p_room_id AND scope='player' AND scope_key=v_me.id::text;
 SELECT coalesce(used_seconds,0) INTO v_team_used
 FROM private.atina_v2_room_timeout_budgets
 WHERE room_id=p_room_id AND scope='team' AND scope_key=v_team;
 RETURN jsonb_build_object('room_id',v_room.id,'code',v_room.code,'status',v_room.status,'max_players',v_room.max_players,
  'is_host',v_me.is_host,'player_id',v_me.id,'ready',v_me.ready,'team',v_team,'my_score',v_me.score,'players',v_players,
  'game_state',v_room.game_state,'team_proposal',v_team_proposal,
  'timeouts',jsonb_build_object('player_remaining_seconds',greatest(0,3600-coalesce(v_player_used,0)),
   'team_remaining_seconds',CASE WHEN v_team IS NULL THEN 0 ELSE greatest(0,3600-coalesce(v_team_used,0)) END));
END;
$function$
;

-- Apaga apenas registos de resposta pertencentes às salas dos modos removidos.
delete from public.atina_v2_room_answers a
using public.atina_v2_rooms r
where r.id=a.room_id
  and r.game_state->>'mode' in ('mimicas','detetive_aventura');

delete from public.atina_room_answers a
using public.atina_rooms r
where r.id=a.room_id
  and r.game_state->>'mode'='mimicas';

-- As FKs em cascata removem apenas participantes, sessões e estado destas salas.
delete from public.atina_v2_rooms
where game_state->>'mode' in ('mimicas','detetive_aventura');

delete from public.atina_rooms
where game_state->>'mode'='mimicas';

-- Remove as RPCs exclusivas dos dois modos; mantém as RPCs genéricas de salas.
do $drop_mode_rpcs$
declare
  v_function record;
begin
  for v_function in
    select p.oid::regprocedure as signature
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
     where p.prokind='f'
       and n.nspname='public'
       and (
         p.proname like 'atina_detective_%'
         or p.proname like 'atina%mime%'
         or p.proname in ('atina_publish_game_state','atina_v2_publish_game_state')
       )
  loop
    execute format('drop function %s',v_function.signature);
  end loop;
end;
$drop_mode_rpcs$;

-- Remove tabelas privadas exclusivas dos modos, sem CASCADE.
drop table if exists private.atina_detective_interactions;
drop table if exists private.atina_detective_discoveries;
drop table if exists private.atina_detective_characters;
drop table if exists private.atina_detective_evidence;
drop table if exists private.atina_detective_sessions;
drop table if exists private.atina_detective_case_templates;

drop table if exists private.atina_v2_mime_rounds;
drop table if exists private.atina_mime_rounds;
drop table if exists private.atina_mime_cards;
