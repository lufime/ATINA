BEGIN;

INSERT INTO private.atina_challenges
  (challenge_id,category,emoji,clues,answer,accepted_answers,difficulty,active)
VALUES
  (-990022,'__ci_room_progress__','🧪',
   '["pista um","pista dois","pista três"]'::jsonb,
   'Resposta de teste 022','["resposta de teste 022"]'::jsonb,'medium',true);

SELECT plan(9);

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
SELECT public.atina_v2_start_room_challenges(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  'medium',60,'__ci_room_progress__'
);

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
  'Resposta de teste 022'
) AS value;

SELECT is((SELECT value->>'status' FROM _correct),'correct',
  'the same team can retry and submit the correct answer');
SELECT ok((SELECT round_locked FROM private.atina_v2_room_game_state
  WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),
  'a correct single-member team answer closes the turn');
SELECT ok((SELECT total_points>0 FROM private.atina_players
  WHERE nickname='Conta de teste 022'),
  'correct room points are added to the account ranking');
SELECT is((SELECT count(*)::integer FROM private.atina_room_progress_events
  WHERE player_id=(SELECT id FROM private.atina_players WHERE nickname='Conta de teste 022')),
  1,'room XP is counted once despite a wrong answer followed by a correct retry');
SELECT is((SELECT value->>'status' FROM (
  SELECT public.atina_v2_next_room_challenge(
    (SELECT (value->>'room_id')::uuid FROM _host),
    (SELECT value->>'token' FROM _host)
  ) AS value
) q),'completed','the active team can advance after the correct answer');

SELECT * FROM finish();
ROLLBACK;
