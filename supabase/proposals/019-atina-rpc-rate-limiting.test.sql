BEGIN;
SELECT plan(12);

SELECT set_config('request.method','POST',true);
SELECT set_config('request.headers','{"x-forwarded-for":"198.51.100.10"}',true);

-- Unrelated API paths must pass without consuming ATINA quota.
SELECT set_config('request.path','rpc/unrelated_function',true);
SELECT lives_ok('SELECT public.atina_pre_request_rate_limit()','unrelated RPC is not rate limited by ATINA hook');
SELECT is((SELECT count(*)::integer FROM private.atina_rpc_rate_limits),0,'unrelated RPC does not write rate-limit state');

-- Create/join operations are capped at 10 per IP and endpoint per minute.
SELECT set_config('request.path','rpc/atina_create_room',true);
DO $$
BEGIN
  FOR i IN 1..10 LOOP
    PERFORM public.atina_pre_request_rate_limit();
  END LOOP;
END;
$$;
SELECT is((SELECT request_count FROM private.atina_rpc_rate_limits
 WHERE rpc_name='atina_create_room'
 AND ip_hash=extensions.digest(convert_to('198.51.100.10','UTF8'),'sha256')),10,'first ten room-creation requests are allowed');
SELECT throws_ok('SELECT public.atina_pre_request_rate_limit()','PGRST',
 'eleventh room-creation request is rejected');

-- Different source IP receives an independent bucket.
SELECT set_config('request.headers','{"x-forwarded-for":"198.51.100.11"}',true);
SELECT lives_ok('SELECT public.atina_pre_request_rate_limit()','another IP receives an independent allowance');
SELECT is((SELECT request_count FROM private.atina_rpc_rate_limits
 WHERE rpc_name='atina_create_room'
 AND ip_hash=extensions.digest(convert_to('198.51.100.11','UTF8'),'sha256')),1,'second IP starts at one request');

-- Polling limit supports the current three-second lobby refresh cadence.
SELECT set_config('request.path','rpc/atina_room_state',true);
SELECT set_config('request.headers','{"x-forwarded-for":"203.0.113.20"}',true);
DO $$
BEGIN
  FOR i IN 1..120 LOOP
    PERFORM public.atina_pre_request_rate_limit();
  END LOOP;
END;
$$;
SELECT is((SELECT request_count FROM private.atina_rpc_rate_limits
 WHERE rpc_name='atina_room_state'
 AND ip_hash=extensions.digest(convert_to('203.0.113.20','UTF8'),'sha256')),120,'room-state polling allows 120 requests per minute');
SELECT throws_ok('SELECT public.atina_pre_request_rate_limit()','PGRST',
 '121st room-state request is rejected');

-- Missing IP information fails closed for ATINA RPCs.
SELECT set_config('request.path','rpc/atina_join_room',true);
SELECT set_config('request.headers','{}',true);
SELECT throws_ok('SELECT public.atina_pre_request_rate_limit()','PGRST',
 'missing client IP fails closed');

SELECT ok(NOT has_table_privilege('anon','private.atina_rpc_rate_limits','select'),'anon cannot read rate-limit state');
SELECT ok(NOT has_table_privilege('authenticated','private.atina_rpc_rate_limits','select'),'authenticated cannot read rate-limit state');
SELECT ok((SELECT EXISTS(
  SELECT 1 FROM pg_roles r,unnest(r.rolconfig) c
  WHERE r.rolname='authenticator'
    AND c='pgrst.db_pre_request=public.atina_pre_request_rate_limit'
)),'PostgREST pre-request hook is configured on authenticator');

SELECT * FROM finish();
ROLLBACK;
