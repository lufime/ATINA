-- Post-upgrade assertions against the synthetic legacy fixture.
do $$
begin
  if (select count(*) from public.atina_rooms) <> 4 then raise exception 'Legacy rooms were not preserved'; end if;
  if (select count(*) from public.atina_room_players) <> 4 then raise exception 'Legacy players were not preserved'; end if;
  if (select count(*) from private.atina_mime_cards) <> 48 then raise exception 'Legacy MIME cards were changed'; end if;
  if (select count(*) from private.atina_mime_secrets) <> 0 then raise exception 'Legacy MIME secrets changed'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='atina_room_players' and column_name='is_ready') then raise exception 'Legacy is_ready column missing'; end if;
  if exists(select 1 from information_schema.columns where table_schema='public' and table_name='atina_room_players' and column_name='ready') then raise exception 'Legacy room player table was rewritten'; end if;
  if to_regprocedure('public.atina_room_state(uuid,text)') is null then raise exception 'Legacy room_state RPC missing'; end if;
  if to_regprocedure('public.atina_create_room(text,integer)') is null then raise exception 'Legacy create_room RPC missing'; end if;
  if to_regprocedure('public.atina_join_room(text,text)') is null then raise exception 'Legacy join_room RPC missing'; end if;
  if to_regprocedure('public.atina_start_mime_round(uuid,text,integer,uuid,integer)') is null then raise exception 'Legacy start_mime_round RPC missing'; end if;
  if not exists(select 1 from pg_constraint where conname='atina_mime_secrets_card_id_fkey') then raise exception 'Legacy MIME card FK missing'; end if;
  if not (select relrowsecurity from pg_class where oid='public.atina_rooms'::regclass) then raise exception 'Legacy room RLS disabled'; end if;
  if not (select relrowsecurity from pg_class where oid='private.atina_mime_cards'::regclass) then raise exception 'Legacy MIME card RLS disabled'; end if;
  if to_regclass('public.atina_v2_rooms') is null or to_regclass('public.atina_v2_room_players') is null then raise exception 'V2 multiplayer tables missing'; end if;
  if to_regclass('private.atina_v2_local_sessions') is null or to_regclass('private.atina_v2_mime_rounds') is null then raise exception 'V2 private tables missing'; end if;
  if to_regclass('private.atina_v2_mime_cards') is not null then raise exception 'A duplicate MIME card table was created'; end if;
  if has_table_privilege('anon','public.atina_v2_rooms','SELECT') then raise exception 'anon can directly read v2 rooms'; end if;
  if has_table_privilege('authenticated','public.atina_v2_room_players','SELECT') then raise exception 'authenticated can directly read v2 players'; end if;
  if not has_function_privilege('anon','public.atina_v2_create_room(text,integer)','EXECUTE') then raise exception 'anon cannot execute v2 room RPC'; end if;
end
$$;


-- Exercise the local Party contract: capped queue, final-round double points,
-- and alternating teams. The fixture contains one synthetic challenge, so it is
-- necessarily the final round.
do $$
declare
  v_started jsonb;
  v_result jsonb;
  v_next jsonb;
  v_session_id uuid;
  v_token text;
begin
  v_started := public.atina_v2_start_local_game('party','easy',null,0);
  v_session_id := (v_started->'state'->>'session_id')::uuid;
  v_token := v_started->>'token';
  if v_session_id is null or v_token is null then raise exception 'Party session did not start'; end if;
  if (v_started->'state'->>'queue_size')::integer > 10 then raise exception 'Party queue exceeds ten challenges'; end if;
  v_result := public.atina_v2_local_submit_answer(v_session_id,v_token,'teste');
  if coalesce((v_result->'last_result'->>'party_final_round_bonus')::boolean,false) is not true then
    raise exception 'Party final-round bonus was not recorded';
  end if;
  if (v_result->'last_result'->>'points')::integer <> 20 then
    raise exception 'Party final-round score should double the 10-point base';
  end if;
  v_next := public.atina_v2_local_next_challenge(v_session_id,v_token);
  if (v_next->>'current_player')::integer <> 2 then raise exception 'Party did not alternate to team two'; end if;
end
$$;

-- Exercise v2 multiplayer room creation and the server-authoritative Mímicas
-- secret path without changing any of the legacy fixture's rooms or cards.
do $$
declare
  v_host jsonb;
  v_guest jsonb;
  v_state jsonb;
  v_secret jsonb;
  v_room_id uuid;
  v_host_token text;
  v_guest_token text;
  v_guest_id uuid;
begin
  v_host := public.atina_v2_create_room('Anfitrião',4);
  v_room_id := (v_host->>'room_id')::uuid;
  v_host_token := v_host->>'token';
  v_guest := public.atina_v2_join_room('Convidado',v_host->>'code');
  v_guest_token := v_guest->>'token';
  v_guest_id := (v_guest->>'player_id')::uuid;
  perform public.atina_v2_set_room_ready(v_room_id,v_guest_token,true);
  perform public.atina_v2_start_room(v_room_id,v_host_token);
  v_state := public.atina_v2_start_mime_round(v_room_id,v_host_token,0,v_guest_id,0);
  if v_state->>'mode' <> 'mimicas' or v_state ? 'answer' then
    raise exception 'Mímicas public state exposed an invalid payload';
  end if;
  v_secret := public.atina_v2_get_mime_secret(v_room_id,v_guest_token);
  if coalesce(v_secret->>'word','') = '' then raise exception 'Mímicas representative did not receive the secret'; end if;
end
$$;
