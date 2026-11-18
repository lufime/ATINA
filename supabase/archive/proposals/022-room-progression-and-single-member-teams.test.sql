BEGIN;

INSERT INTO private.atina_challenges
  (challenge_id,category,emoji,clues,answer,accepted_answers,difficulty,active)
VALUES
  (-990022,'__ci_room_progress__','🧪',
   '["pista um","pista dois","pista três","pista quatro","pista cinco"]'::jsonb,
   'Resposta de teste 022','["resposta de teste 022"]'::jsonb,'medium',true),
  (-990023,'__ci_room_progress__','🧪',
   '["pista um","pista dois","pista três","pista quatro","pista cinco"]'::jsonb,
   'Resposta de teste 023','["resposta de teste 023"]'::jsonb,'medium',true),
  (-990024,'__ci_room_progress__','🧪',
   '["pista um","pista dois","pista três","pista quatro","pista cinco"]'::jsonb,
   'Resposta de teste 024','["resposta de teste 024"]'::jsonb,'medium',true);

SELECT plan(16);

CREATE TEMP TABLE _host AS
SELECT public.atina_v2_create_room('Host 022',2) AS value;

CREATE TEMP TABLE _guest AS
SELECT public.atina_v2_join_room(
  'Guest 022',(SELECT value->>'code' FROM _host)
) AS value;

CREATE TEMP TABLE _account AS
SELECT id FROM private.atina_players
WHERE false;

INSERT INTO private.atina_players(device_token_hash,nickname)
VALUES(extensions.gen_random_bytes(32),'Conta de teste 022');

UPDATE public.atina_v2_room_players
SET account_player_id=(
  SELECT id FROM private.atina_players WHERE nickname='Conta de teste 022'
)
WHERE id=(SELECT (value->>'player_id')::uuid FROM _host);

SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _host),
  'Equipa A'
);
SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _guest),
  'Equipa B'
);
SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),true
);
SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _guest),
  (SELECT value->>'token' FROM _guest),true
);
SELECT public.atina_v2_start_room(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host)
);
CREATE TEMP TABLE _started AS
SELECT public.atina_v2_start_room_challenges(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  'medium',60,'__ci_room_progress__'
) AS value;

SELECT is((SELECT value->'state'->>'active_team' FROM _started),'Equipa A',
  'the first assigned team is exposed as the active team');

CREATE TEMP TABLE _wrong AS
SELECT public.atina_v2_submit_room_answer(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  'resposta errada'
) AS value;

SELECT is((SELECT value->>'status' FROM _wrong),'wrong',
  'a single-member team can submit a wrong answer directly');
SELECT ok((SELECT NOT round_locked FROM private.atina_v2_room_game_state
  WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),
  'a wrong answer keeps the active team turn open');
SELECT ok((SELECT total_xp>=10 AND total_challenges=1 FROM private.atina_players
  WHERE nickname='Conta de teste 022'),
  'a completed wrong answer awards base XP once');

CREATE TEMP TABLE _correct AS
SELECT public.atina_v2_submit_room_answer(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT c.answer FROM private.atina_challenges c
    JOIN private.atina_v2_room_game_state g
      ON c.challenge_id=g.challenge_queue[g.position]
   WHERE g.room_id=(SELECT (value->>'room_id')::uuid FROM _host))
) AS value;

SELECT is((SELECT value->>'status' FROM _correct),'correct',
  'the same team can retry and submit the correct answer');
SELECT ok((SELECT round_locked FROM private.atina_v2_room_game_state
  WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),
  'a correct single-member team answer closes the turn');
SELECT ok((SELECT team_turn_advanced FROM private.atina_v2_room_game_state
  WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),
  'a correct answer marks the active team turn as completed');
SELECT ok((SELECT total_points>0 FROM private.atina_players
  WHERE nickname='Conta de teste 022'),
  'correct room points are added to the account ranking');
SELECT is((SELECT count(*)::integer FROM private.atina_room_progress_events
  WHERE player_id=(SELECT id FROM private.atina_players WHERE nickname='Conta de teste 022')),
  1,'room XP is counted once despite a wrong answer followed by a correct retry');
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

CREATE TEMP TABLE _advance_to_b AS
SELECT public.atina_v2_next_room_challenge(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host)
) AS value;

SELECT is((SELECT value->>'status' FROM _advance_to_b),'next',
  'the active team can advance after a correct answer');
SELECT is((SELECT value->'state'->>'active_team' FROM _advance_to_b),'Equipa B',
  'the next challenge rotates the turn to the other team');

SELECT is((SELECT public.atina_v2_submit_room_answer(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _guest),
  (SELECT c.answer FROM private.atina_challenges c
    JOIN private.atina_v2_room_game_state g
      ON c.challenge_id=g.challenge_queue[g.position]
   WHERE g.room_id=(SELECT (value->>'room_id')::uuid FROM _host))
)->>'status'),'correct',
  'the non-host active team can answer its own challenge');

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

CREATE TEMP TABLE _advance_to_a AS
SELECT public.atina_v2_next_room_challenge(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _guest)
) AS value;

SELECT is((SELECT value->>'status' FROM _advance_to_a),'next',
  'the active non-host team can advance after its correct answer');
SELECT is((SELECT value->'state'->>'active_team' FROM _advance_to_a),'Equipa A',
  'the turn rotates back to the first team');

SELECT is((SELECT public.atina_v2_submit_room_answer(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT c.answer FROM private.atina_challenges c
    JOIN private.atina_v2_room_game_state g
      ON c.challenge_id=g.challenge_queue[g.position]
   WHERE g.room_id=(SELECT (value->>'room_id')::uuid FROM _host))
)->>'status'),'correct',
  'the first team can play again after rotation');

SELECT is((SELECT value->>'status' FROM (
  SELECT public.atina_v2_next_room_challenge(
    (SELECT (value->>'room_id')::uuid FROM _host),
    (SELECT value->>'token' FROM _host)
  ) AS value
) q),'completed','the final active team can complete the room');

SELECT * FROM finish();
ROLLBACK;
