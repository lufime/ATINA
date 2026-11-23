BEGIN;
SELECT plan(3);

SELECT has_function(
  'public',
  'atina_challenge_catalog_progress',
  ARRAY['text'],
  'Challenge catalog progress RPC exists'
);

SELECT ok(
  has_function_privilege('anon','public.atina_challenge_catalog_progress(text)','EXECUTE'),
  'Anonymous API role can invoke the RPC with its account session token'
);

SELECT throws_ok(
  $$ select public.atina_challenge_catalog_progress('not-a-session-token') $$,
  '28000',
  'Sessão inválida.',
  'Malformed session tokens are rejected'
);

SELECT * FROM finish();
ROLLBACK;
