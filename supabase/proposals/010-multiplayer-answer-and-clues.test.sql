BEGIN;
SELECT plan(13);
CREATE TEMP TABLE _host AS SELECT public.atina_create_room('Host 010',4) AS value;
CREATE TEMP TABLE _guest AS SELECT public.atina_join_room('Guest 010',(SELECT value->>'code' FROM _host)) AS value;
SELECT public.atina_set_room_ready((SELECT (value->>'room_id')::uuid FROM _guest),(SELECT value->>'token' FROM _guest),true);
SELECT public.atina_start_room((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host));
SELECT public.atina_start_room_challenges((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),'medium',60,NULL);

CREATE TEMP TABLE _initial AS
SELECT public.atina_room_state((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host)) AS value;
SELECT is((SELECT value->'game_state'->>'mode' FROM _initial),'challenges','room state exposes challenge mode');
SELECT ok((SELECT NOT ((value->'game_state') ? 'answer') FROM _initial),'room state omits answer');
SELECT is((SELECT jsonb_array_length(value->'game_state'->'clues') FROM _initial),1,'only first clue visible initially');

CREATE TEMP TABLE _revealed AS
SELECT public.atina_reveal_room_clue((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host)) AS value;
SELECT is((SELECT value->>'status' FROM _revealed),'revealed','host can reveal next clue');
SELECT is((SELECT jsonb_array_length(value->'state'->'clues') FROM _revealed),2,'reveal returns exactly two clues');

CREATE TEMP TABLE _wrong AS
SELECT public.atina_submit_room_answer((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),'resposta deliberadamente errada') AS value;
SELECT is((SELECT value->>'status' FROM _wrong),'wrong','server rejects wrong answer text');
SELECT is((SELECT (value->>'penalty')::integer FROM _wrong),10,'wrong answer penalty calculated server-side');
SELECT ok((SELECT NOT ((value->'state') ? 'answer') FROM _wrong),'answer is not returned in public state');

CREATE TEMP TABLE _right AS
SELECT public.atina_submit_room_answer(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT c.answer FROM private.atina_challenges c
   WHERE c.challenge_id=(SELECT (value->'state'->>'challenge_id')::integer FROM _revealed))
) AS value;
SELECT is((SELECT value->>'status' FROM _right),'correct','server accepts correct answer text');
SELECT ok((SELECT (value->>'points')::integer>0 FROM _right),'server calculates positive points');
SELECT ok((SELECT (value->>'score')::integer>0 FROM _right),'server updates participant score');
SELECT is((SELECT value->>'status' FROM (
  SELECT public.atina_submit_room_answer(
    (SELECT (value->>'room_id')::uuid FROM _host),
    (SELECT value->>'token' FROM _host),
    'repeat attempt'
  ) AS value
) x),'already_correct','correct player cannot score twice in same challenge');
SELECT throws_ok(
  format('SELECT public.atina_reveal_room_clue(%L::uuid,%L)',
    (SELECT value->>'room_id' FROM _host),(SELECT value->>'token' FROM _guest)),
  'P0001','Só o anfitrião pode revelar pistas.','guest cannot reveal clues'
);
SELECT * FROM finish();
ROLLBACK;
