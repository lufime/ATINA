begin;
select plan(12);

select has_table('private', 'atina_v2_players', 'player records are private');
select has_table('private', 'atina_v2_progress_events', 'progress events are private');
select ok(
  (select relrowsecurity from pg_class where oid = 'private.atina_v2_players'::regclass),
  'RLS is enabled for player records'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'private.atina_v2_progress_events'::regclass),
  'RLS is enabled for progress events'
);
select ok(
  not has_table_privilege('anon', 'private.atina_v2_players', 'SELECT'),
  'anon cannot read player records directly'
);
select ok(
  not has_table_privilege('authenticated', 'private.atina_v2_progress_events', 'INSERT'),
  'authenticated cannot insert progress events directly'
);
select ok(
  has_function_privilege('anon', 'public.atina_v2_player_profile(text,text)', 'EXECUTE'),
  'anon can use the pseudonym profile RPC'
);
select ok(
  has_function_privilege('anon', 'public.atina_v2_record_local_progress(uuid,text)', 'EXECUTE'),
  'anon can use the server-validated progress RPC'
);
select ok(
  not has_table_privilege('anon', 'private.atina_v2_players', 'SELECT'),
  'private schema data is not directly accessible to anon'
);
select has_column('private', 'atina_v2_local_sessions', 'player_id', 'sessions bind to a single player');
select ok(
  has_function_privilege('anon', 'public.atina_v2_start_local_game(text,text,text,integer,text)', 'EXECUTE'),
  'anon can start a session with an optional registered player token'
);
select ok(
  has_function_privilege('anon', 'public.atina_v2_record_local_progress(uuid,text)', 'EXECUTE')
  and to_regprocedure('public.atina_v2_record_local_progress(uuid,text,text)') is null,
  'XP award RPC no longer accepts a caller-selected player token'
);

select * from finish();
rollback;
