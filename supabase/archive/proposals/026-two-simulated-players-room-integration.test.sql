BEGIN;

-- Two isolated simulated participants use the same public room RPCs and
-- server-side turn validation as ordinary participants. No hosted services
-- or persistent accounts are involved; the transaction is rolled back.

INSERT INTO private.atina_challenges
  (challenge_id,category,emoji,clues,answer,accepted_answers,difficulty,active)
VALUES
  (-990026,'__ci_two_simulated_players__','🧪',
   '["pista um","pista dois","pista três","pista quatro","pista cinco"]'::jsonb,
   'Resposta simulada 026 A','["resposta simulada 026 a"]'::jsonb,'medium',true),
  (-990027,'__ci_two_simulated_players__','🧪',
   '["pista um","pista dois","pista três","pista quatro","pista cinco"]'::jsonb,
   'Resposta simulada 026 B','["resposta simulada 026 b"]'::jsonb,'medium',true);

SELECT plan(10);

CREATE TEMP TABLE _host AS
SELECT public.atina_v2_create_room('Simulado 026 A',2) AS value;

CREATE TEMP TABLE _guest AS
SELECT public.atina_v2_join_room(
  'Simulado 026 B',(SELECT value->>'code' FROM _host)
) AS value;

UPDATE public.atina_v2_room_players
   SET is_bot=true
 WHERE id IN (
   (SELECT (value->>'player_id')::uuid FROM _host),
   (SELECT (value->>'player_id')::uuid FROM _guest)
 );

SELECT is((SELECT count(*)::integer FROM public.atina_v2_room_players
  WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host) AND is_bot),2,
  'both isolated simulated participants are present in the same room');

SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _host),'Equipa A');

SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _guest),'Equipa B');

SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),true);

SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _guest),true);

SELECT public.atina_v2_start_room(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host));

CREATE TEMP TABLE _started AS
SELECT public.atina_v2_start_room_challenges(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  'medium',0,'__ci_two_simulated_players__'
) AS value;

SELECT is((SELECT value->'state'->>'active_team' FROM _started),'Equipa A',
  'the first simulated participant receives the first turn');

CREATE TEMP TABLE _wrong AS
SELECT public.atina_v2_submit_room_answer(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  'resposta deliberadamente errada'
) AS value;

SELECT is((SELECT value->>'status' FROM _wrong),'wrong',
  'the first simulated participant can submit a wrong answer');
SELECT ok((SELECT NOT round_locked FROM private.atina_v2_room_game_state
  WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),
  'a wrong answer leaves the active simulated participant able to retry');

CREATE TEMP TABLE _correct_a AS
SELECT public.atina_v2_submit_room_answer(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT c.answer FROM private.atina_challenges c
    JOIN private.atina_v2_room_game_state g
      ON c.challenge_id=g.challenge_queue[g.position]
   WHERE g.room_id=(SELECT (value->>'room_id')::uuid FROM _host))
) AS value;

SELECT is((SELECT value->>'status' FROM _correct_a),'correct',
  'the first simulated participant can retry and answer correctly');
SELECT ok((SELECT round_locked AND team_turn_advanced
  FROM private.atina_v2_room_game_state
  WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),
  'the correct answer closes the first participant turn');

DO $seed$
DECLARE
  v_i integer;
  v_seed double precision;
  v_first_roll double precision;
BEGIN
  FOR v_i IN 0..100 LOOP
    v_seed:=-1+(v_i*0.02);
    PERFORM setseed(v_seed);
    v_first_roll:=random();
    IF v_first_roll>=0.20 THEN
      PERFORM setseed(v_seed);
      RETURN;
    END IF;
  END LOOP;
  RAISE EXCEPTION 'Could not select a deterministic no-card test seed.';
END;
$seed$;

CREATE TEMP TABLE _advance AS
SELECT public.atina_v2_next_room_challenge(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host)
) AS value;

SELECT is((SELECT value->>'status' FROM _advance),'next',
  'the first simulated participant advances the shared room');
SELECT is((SELECT value->'state'->>'active_team' FROM _advance),'Equipa B',
  'the active turn rotates to the second simulated participant');

CREATE TEMP TABLE _correct_b AS
SELECT public.atina_v2_submit_room_answer(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _guest),
  (SELECT c.answer FROM private.atina_challenges c
    JOIN private.atina_v2_room_game_state g
      ON c.challenge_id=g.challenge_queue[g.position]
   WHERE g.room_id=(SELECT (value->>'room_id')::uuid FROM _host))
) AS value;

SELECT is((SELECT value->>'status' FROM _correct_b),'correct',
  'the second simulated participant answers through the same server RPC');

SELECT is((SELECT value->>'status' FROM (
  SELECT public.atina_v2_next_room_challenge(
    (SELECT (value->>'room_id')::uuid FROM _host),
    (SELECT value->>'token' FROM _guest)
  ) AS value
) q),'completed',
  'the second simulated participant completes the room');

SELECT * FROM finish();
ROLLBACK;
