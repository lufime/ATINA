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
  if to_regclass('public.atina_v2_rooms') is null or to_regclass('public.atina_v2_room_players') is null then raise exception 'V2 multiplayer tables missing'; end if;
  if to_regclass('private.atina_v2_local_sessions') is null or to_regclass('private.atina_v2_mime_rounds') is null then raise exception 'V2 private tables missing'; end if;
  if to_regclass('private.atina_v2_mime_cards') is not null then raise exception 'A duplicate MIME card table was created'; end if;
  if has_table_privilege('anon','public.atina_v2_rooms','SELECT') then raise exception 'anon can directly read v2 rooms'; end if;
  if has_table_privilege('authenticated','public.atina_v2_room_players','SELECT') then raise exception 'authenticated can directly read v2 players'; end if;
  if not has_function_privilege('anon','public.atina_v2_create_room(text,integer)','EXECUTE') then raise exception 'anon cannot execute v2 room RPC'; end if;
end
$$;
