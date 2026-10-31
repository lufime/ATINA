BEGIN;
SELECT plan(7);
CREATE TEMP TABLE _host AS SELECT public.atina_create_room('Host 014',4) AS value;
CREATE TEMP TABLE _guest AS SELECT public.atina_join_room('Guest 014',(SELECT value->>'code' FROM _host)) AS value;
SELECT public.atina_set_room_ready((SELECT (value->>'room_id')::uuid FROM _guest),(SELECT value->>'token' FROM _guest),true);
SELECT public.atina_start_room((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host));
SELECT public.atina_start_room_challenges((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),'medium',60,NULL);

UPDATE private.atina_room_game_state
SET deadline_at=clock_timestamp()-interval '1 second'
WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host);

CREATE TEMP TABLE _state AS
SELECT public.atina_room_state((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host)) AS value;

SELECT is((SELECT value->'game_state'->>'mode' FROM _state),'challenges','room state still identifies challenge mode after timeout');
SELECT is((SELECT (value->'game_state'->>'locked')::boolean FROM _state),true,'polling state closes expired round');
SELECT ok((SELECT value->'game_state'->>'answer' IS NOT NULL FROM _state),'solution appears after server-side timeout');
SELECT ok((SELECT round_locked FROM private.atina_room_game_state WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),'private round state is locked on timeout');
SELECT is((SELECT value->>'status' FROM _state),'playing','room remains in playing status until host advances');
SELECT throws_ok(
  format('SELECT public.atina_room_state(%L::uuid,%L)',
    (SELECT value->>'room_id' FROM _host),'invalid-token'),
  'P0001','Sessão da sala inválida.','invalid token cannot poll room state'
);
SELECT ok((SELECT (value->'game_state'->>'deadline')::numeric>0 FROM _state),'public state retains the server deadline for display');
SELECT * FROM finish();
ROLLBACK;
