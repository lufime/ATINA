-- pgTAP wrapper: execute the assertions as one reported test.
begin;
select plan(1);
select lives_ok($atina_test$
-- Structural regression checks for 20261113160000_atina_social_games_foundation.
-- Run only after the matching migration in an isolated test database.
do $atina_assertions$
declare
  expected text[] := array[
    'atina_social_rooms','atina_social_players','atina_social_teams',
    'atina_social_content','atina_social_rounds','atina_social_submissions',
    'atina_social_justifications','atina_social_votes',
    'atina_social_mystery_events','atina_social_taboo_turns',
    'atina_social_action_log'
  ];
  actual_count integer;
  missing text[];
  exposed_count integer;
begin
  select count(*) into actual_count
  from information_schema.tables
  where table_schema = 'private'
    and table_name = any(expected);

  if actual_count <> cardinality(expected) then
    raise exception 'Expected % private tables, found %', cardinality(expected), actual_count;
  end if;

  select array_agg(x) into missing
  from unnest(expected) x
  where not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = x and c.relrowsecurity
  );
  if missing is not null then
    raise exception 'RLS missing on tables: %', missing;
  end if;

  select count(*) into exposed_count
  from information_schema.role_table_grants
  where table_schema = 'private'
    and table_name = any(expected)
    and grantee in ('anon','authenticated','PUBLIC');
  if exposed_count <> 0 then
    raise exception 'Unexpected direct grants on private social tables: %', exposed_count;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'atina_social_rooms_host_player_fk'
      and connamespace = 'private'::regnamespace
  ) then
    raise exception 'Host/player deferred FK is missing';
  end if;
end
$atina_assertions$;
$atina_test$, '20261113160000_atina_social_games_foundation: all assertions execute without error');
select * from finish();
rollback;
