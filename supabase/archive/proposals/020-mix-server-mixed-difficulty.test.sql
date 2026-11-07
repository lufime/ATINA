BEGIN;
SELECT plan(7);

-- The clean migration replay intentionally has no production challenge seed.
-- Build a deterministic, isolated fixture with three categories and all levels.
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
  (-991009, '__mix_test_c__', 'hard')
) AS fixture(challenge_id, category, difficulty);

CREATE TEMP TABLE atina_mix_test_run AS
SELECT public.atina_v2_start_local_game('mix','medium',NULL,0) AS result;

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
  (SELECT result->'state'->>'difficulty' FROM atina_mix_test_run),
  (SELECT challenge.difficulty
     FROM private.atina_v2_local_sessions session
     JOIN atina_mix_test_run run ON session.id=(run.result->'state'->>'session_id')::uuid
     JOIN private.atina_challenges challenge
       ON challenge.challenge_id=session.challenge_queue[session.position]),
  'Public state reports the current challenge difficulty'
);

SELECT is(
  (SELECT (result->'state'->'last_result'->>'base_points')::integer FROM atina_mix_test_answer),
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
