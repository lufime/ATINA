BEGIN;
SELECT plan(9);

INSERT INTO private.atina_site_presence (session_id, last_seen_at, nickname, account_player_id)
VALUES
  ('a1000000-0000-4000-8000-000000000001', statement_timestamp(), 'Nome repetido', 'b1000000-0000-4000-8000-000000000001'),
  ('a1000000-0000-4000-8000-000000000002', statement_timestamp(), 'Nome repetido', 'b1000000-0000-4000-8000-000000000001'),
  ('a1000000-0000-4000-8000-000000000003', statement_timestamp(), 'Nome repetido', 'b1000000-0000-4000-8000-000000000002'),
  ('a1000000-0000-4000-8000-000000000004', statement_timestamp(), 'Nome repetido', NULL);

CREATE TEMP TABLE atina_online_test_snapshot AS
SELECT public.atina_online_player_stats() AS stats;

SELECT is(
  (SELECT (stats->'counts'->>'humans')::integer FROM atina_online_test_snapshot),
  3,
  'Two sessions for one account count as one human; another account and one guest count separately'
);

SELECT is(
  (SELECT jsonb_array_length(stats->'humans') FROM atina_online_test_snapshot),
  3,
  'The human directory contains one row per unique identity'
);

SELECT is(
  (SELECT count(DISTINCT player->>'id')::integer
     FROM atina_online_test_snapshot,
          jsonb_array_elements(stats->'humans') AS player),
  3,
  'Human identity keys are unique even when nicknames are identical'
);

SELECT is(
  (SELECT count(DISTINCT player->>'nickname')::integer
     FROM atina_online_test_snapshot,
          jsonb_array_elements(stats->'humans') AS player),
  1,
  'Identical nicknames do not merge different human identities'
);

SELECT is(
  (SELECT (stats->'counts'->>'bots')::integer FROM atina_online_test_snapshot),
  (SELECT jsonb_array_length(stats->'bots') FROM atina_online_test_snapshot),
  'The bot count matches the unique bot directory'
);

SELECT is(
  (SELECT (stats->'counts'->>'total')::integer FROM atina_online_test_snapshot),
  (SELECT (stats->'counts'->>'humans')::integer + (stats->'counts'->>'bots')::integer
     FROM atina_online_test_snapshot),
  'Total online is exactly humans plus bots'
);

SELECT is(
  public.atina_online_player_count(),
  (SELECT (stats->'counts'->>'total')::integer FROM atina_online_test_snapshot),
  'The legacy integer counter uses the same source of truth'
);

SELECT is(
  jsonb_array_length(public.atina_v2_online_players()),
  (SELECT (stats->'counts'->>'total')::integer FROM atina_online_test_snapshot),
  'The legacy directory returns the same unique total'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM atina_online_test_snapshot,
         jsonb_array_elements(stats->'humans') AS player
    WHERE player->>'type' <> 'human'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM atina_online_test_snapshot,
         jsonb_array_elements(stats->'bots') AS player
    WHERE player->>'type' <> 'bot'
  ),
  'Humans and bots are explicitly typed in the directory'
);

SELECT * FROM finish();
ROLLBACK;
