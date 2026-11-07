BEGIN;
SELECT plan(9);

-- The clean migration replay intentionally has no production challenge seed.
-- Build a deterministic, isolated fixture with six categories and all levels.
INSERT INTO private.atina_challenges (
  challenge_id, category, emoji, clues, answer, accepted_answers, difficulty, active
)
SELECT
  fixture.challenge_id,
  fixture.category,
  '🧪',
  '["Pista 1","Pista 2","Pista 3","Pista 4","Pista 5"]'::jsonb,
  'resposta de teste',
  '["resposta de teste"]'::jsonb,
  fixture.difficulty,
  true
FROM (VALUES
  (-991001, '__mix_test_a__', 'easy'),
  (-991002, '__mix_test_a__', 'medium'),
  (-991003, '__mix_test_a__', 'hard'),
  (-991004, '__mix_test_b__', 'easy'),
  (-991005, '__mix_test_b__', 'medium'),
  (-991006, '__mix_test_b__', 'hard'),
  (-991007, '__mix_test_c__', 'easy'),
  (-991008, '__mix_test_c__', 'medium'),
  (-991009, '__mix_test_c__', 'hard'),
  (-991010, '__mix_test_d__', 'easy'),
  (-991011, '__mix_test_d__', 'medium'),
  (-991012, '__mix_test_d__', 'hard'),
  (-991013, '__mix_test_e__', 'easy'),
  (-991014, '__mix_test_e__', 'medium'),
  (-991015, '__mix_test_e__', 'hard'),
  (-991016, '__mix_test_f__', 'easy'),
  (-991017, '__mix_test_f__', 'medium'),
  (-991018, '__mix_test_f__', 'hard')
) AS fixture(challenge_id, category, difficulty);

-- Register a disposable test profile and mark three medium cards as recently seen.
-- Both modes must avoid these IDs while other cards remain available.
CREATE TEMP TABLE atina_mix_test_player AS
WITH inserted AS (
  INSERT INTO private.atina_players (device_token_hash,nickname)
  VALUES (
    extensions.digest(convert_to(repeat('a',64),'UTF8'),'sha256'),
    'mix-rotation-test'
  )
  RETURNING id
)
SELECT id FROM inserted;

CREATE TEMP TABLE atina_mix_test_seed AS
SELECT public.atina_v2_start_local_game(
  'mix','medium',NULL,0,repeat('a',64)
) AS result;

INSERT INTO private.atina_difficulty_history
  (player_id,session_id,challenge_position,challenge_id,difficulty,outcome)
SELECT
  player.id,
  (seed.result->'state'->>'session_id')::uuid,
  recent.position,
  recent.challenge_id,
  'medium',
  'correct'
FROM atina_mix_test_player player
CROSS JOIN atina_mix_test_seed seed
CROSS JOIN (VALUES
  (1,-991002),
  (2,-991005),
  (3,-991008)
) AS recent(position,challenge_id);

CREATE TEMP TABLE atina_mix_test_run AS
SELECT public.atina_v2_start_local_game(
  'mix','medium',NULL,0,repeat('a',64)
) AS result;

CREATE TEMP TABLE atina_solo_test_run AS
SELECT public.atina_v2_start_local_game(
  'solo','medium',NULL,0,repeat('a',64)
) AS result;

CREATE TEMP TABLE atina_mix_test_answer AS
SELECT public.atina_v2_local_submit_answer(
  (run.result->'state'->>'session_id')::uuid,
  run.result->>'token',
  challenge.answer
) AS result
FROM atina_mix_test_run run
JOIN private.atina_v2_local_sessions session
  ON session.id=(run.result->'state'->>'session_id')::uuid
JOIN private.atina_challenges challenge
  ON challenge.challenge_id=session.challenge_queue[session.position];

SELECT is(
  (SELECT (result->'state'->>'queue_size')::integer FROM atina_mix_test_run),
  (SELECT count(DISTINCT category)::integer FROM private.atina_challenges WHERE active),
  'Mix serves one challenge for every active category'
);

SELECT is(
  (SELECT count(*)::integer
     FROM private.atina_v2_local_sessions session
     JOIN atina_mix_test_run run ON session.id=(run.result->'state'->>'session_id')::uuid
     CROSS JOIN LATERAL unnest(session.challenge_queue) q(challenge_id)),
  (SELECT count(DISTINCT category)::integer FROM private.atina_challenges WHERE active),
  'Mix queue does not duplicate categories'
);

SELECT is(
  (SELECT count(DISTINCT challenge.difficulty)::integer
     FROM private.atina_v2_local_sessions session
     JOIN atina_mix_test_run run ON session.id=(run.result->'state'->>'session_id')::uuid
     CROSS JOIN LATERAL unnest(session.challenge_queue) q(challenge_id)
     JOIN private.atina_challenges challenge ON challenge.challenge_id=q.challenge_id),
  3,
  'Mix contains easy, medium and hard challenges'
);

SELECT is(
  (SELECT count(*)::integer
     FROM private.atina_v2_local_sessions session
     JOIN atina_mix_test_run run ON session.id=(run.result->'state'->>'session_id')::uuid
     CROSS JOIN LATERAL unnest(session.challenge_queue) q(challenge_id)
     WHERE q.challenge_id IN (-991002,-991005,-991008)),
  0,
  'Mix avoids the player recent challenge history'
);

SELECT is(
  (SELECT count(*)::integer
     FROM private.atina_v2_local_sessions session
     JOIN atina_solo_test_run run ON session.id=(run.result->'state'->>'session_id')::uuid
     CROSS JOIN LATERAL unnest(session.challenge_queue) q(challenge_id)
     WHERE q.challenge_id IN (-991002,-991005,-991008)),
  0,
  'Solo avoids the player recent challenge history'
);

SELECT is(
  (SELECT result->'state'->>'difficulty' FROM atina_mix_test_run),
  (SELECT challenge.difficulty
     FROM private.atina_v2_local_sessions session
     JOIN atina_mix_test_run run ON session.id=(run.result->'state'->>'session_id')::uuid
     JOIN private.atina_challenges challenge
       ON challenge.challenge_id=session.challenge_queue[session.position]),
  'Public state reports the current challenge difficulty'
);

SELECT is(
  (SELECT (result->'last_result'->>'base_points')::integer FROM atina_mix_test_answer),
  (SELECT CASE challenge.difficulty WHEN 'easy' THEN 10 WHEN 'hard' THEN 20 ELSE 15 END
     FROM private.atina_v2_local_sessions session
     JOIN atina_mix_test_run run ON session.id=(run.result->'state'->>'session_id')::uuid
     JOIN private.atina_challenges challenge
       ON challenge.challenge_id=session.challenge_queue[session.position]),
  'Mix scoring uses the current challenge difficulty'
);

SELECT ok(
  position('v_session.game_mode <> ''solo''' in pg_get_functiondef('private.atina_apply_adaptive_difficulty()'::regprocedure)) > 0,
  'Adaptive difficulty does not replace a mixed Mix queue'
);

SELECT ok(
  position('c.difficulty' in pg_get_functiondef('private.atina_record_difficulty_result()'::regprocedure)) > 0,
  'Difficulty history records the actual challenge level'
);

SELECT * FROM finish();
ROLLBACK;
