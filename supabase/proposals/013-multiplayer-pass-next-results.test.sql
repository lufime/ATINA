BEGIN;
SELECT plan(9);
CREATE TEMP TABLE _host AS SELECT public.atina_create_room('Host 013',4) AS value;
CREATE TEMP TABLE _guest AS SELECT public.atina_join_room('Guest 013',(SELECT value->>'code' FROM _host)) AS value;
SELECT public.atina_set_room_ready((SELECT (value->>'room_id')::uuid FROM _guest),(SELECT value->>'token' FROM _guest),true);
SELECT public.atina_start_room((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host));
SELECT public.atina_start_room_challenges((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),'medium',60,NULL);

CREATE TEMP TABLE _pass AS
SELECT public.atina_pass_room_challenge((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host)) AS value;
SELECT is((SELECT value->>'status' FROM _pass),'passed','host can pass current challenge');
SELECT ok((SELECT (value->'state'->>'locked')::boolean FROM _pass),'pass locks the round');
SELECT ok((SELECT value->'state'->>'answer' IS NOT NULL FROM _pass),'solution is revealed only after round lock');

CREATE TEMP TABLE _next AS
SELECT public.atina_next_room_challenge((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host)) AS value;
SELECT is((SELECT value->>'status' FROM _next),'next','host advances to next server-selected challenge');
SELECT is((SELECT (value->'state'->>'pos')::integer FROM _next),1,'position advances on the server');
SELECT is((SELECT jsonb_array_length(value->'state'->'clues') FROM _next),1,'new challenge reveals only first clue');
SELECT ok((SELECT value->'state'->>'answer' IS NULL FROM _next),'new challenge does not disclose solution');

SELECT throws_ok(
  format('SELECT public.atina_next_room_challenge(%L::uuid,%L)',
    (SELECT value->>'room_id' FROM _host),(SELECT value->>'token' FROM _guest)),
  'P0001','Só o anfitrião pode avançar o desafio.','guest cannot advance challenge'
);

UPDATE private.atina_room_game_state
SET challenge_queue=ARRAY[challenge_queue[position]],position=1
WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host);
SELECT public.atina_pass_room_challenge((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host));
CREATE TEMP TABLE _completed AS
SELECT public.atina_next_room_challenge((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host)) AS value;
SELECT is((SELECT value->>'status' FROM _completed),'completed','last challenge completes room');
SELECT is((SELECT count(*)::integer FROM public.atina_room_results WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),2,'server writes final results for all participants');
SELECT * FROM finish();
ROLLBACK;
