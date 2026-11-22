-- pgTAP regression checks for multiplayer challenge count RPC contract.
BEGIN;
SELECT plan(5);
SELECT has_function('public', 'atina_v2_start_room_challenges', ARRAY['uuid','text','text','integer','text','integer'], 'RPC accepts challenge_count');
SELECT ok(position('p_challenge_count' in pg_get_functiondef('public.atina_v2_start_room_challenges(uuid,text,text,integer,text,integer)'::regprocedure)) > 0, 'RPC definition contains count argument');
SELECT ok(position('between 1 and 1000' in lower(pg_get_functiondef('public.atina_v2_start_room_challenges(uuid,text,text,integer,text,integer)'::regprocedure))) > 0, 'RPC validates count range');
SELECT ok(position('limit p_challenge_count' in lower(pg_get_functiondef('public.atina_v2_start_room_challenges(uuid,text,text,integer,text,integer)'::regprocedure))) > 0, 'queue selection is limited to requested count');
SELECT ok(position('atina_record_room_challenge_exposure' in pg_get_functiondef('public.atina_v2_start_room_challenges(uuid,text,text,integer,text,integer)'::regprocedure)) > 0, 'no-repeat exposure recording remains in start RPC');
SELECT * FROM finish();
ROLLBACK;
