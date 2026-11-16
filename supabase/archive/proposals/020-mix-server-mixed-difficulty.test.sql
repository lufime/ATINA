BEGIN;
SELECT plan(12);

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

-- Register a disposable test profile and mark three cards as already exposed.
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

SELECT is(
  (SELECT player_id::text
     FROM private.atina_xp_session_owners
    WHERE session_id=(SELECT (result->'state'->>'session_id')::uuid FROM atina_mix_test_seed)),
  (SELECT id::text FROM atina_mix_test_player),
  'The device token is bound to the local session owner'
);

INSERT INTO private.atina_challenge_exposures (scope_type,scope_key,challenge_id)
SELECT
  'player',
  player.id::text,
  recent.challenge_id
FROM atina_mix_test_player player
CROSS JOIN (VALUES
  (-991002),
  (-991005),
  (-991008)
) AS recent(challenge_id)
ON CONFLICT (scope_type,scope_key,challenge_id) DO NOTHING;

-- Check level distribution in a separate registered disposable session so
-- the recent-history fixture cannot force a category to use its fallback.
INSERT INTO private.atina_players (device_token_hash,nickname)
VALUES (
  extensions.digest(convert_to(repeat('b',64),'UTF8'),'sha256'),
  'mix-dist-test'
);

CREATE TEMP TABLE atina_mix_distribution_run AS
SELECT public.atina_v2_start_local_game(
  'mix','medium',NULL,0,repeat('b',64)
) AS result;

CREATE TEMP TABLE atina_mix_test_run AS
SELECT public.atina_v2_start_local_game(
  'mix','medium',NULL,0,repeat('a',64)
) AS result;

CREATE TEMP TABLE atina_solo_test_run AS
SELECT public.atina_v2_start_local_game(
  'solo','medium',NULL,0,repeat('a',64)
) AS result;

SELECT is(
  (SELECT player_id::text
     FROM private.atina_xp_session_owners
    WHERE session_id=(SELECT (result->'state'->>'session_id')::uuid FROM atina_mix_test_run)),
  (SELECT id::text FROM atina_mix_test_player),
  'The second Mix session is bound to the same test player'
);

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
     JOIN atina_mix_distribution_run run ON session.id=(run.result->'state'->>'session_id')::uuid
     CROSS JOIN LATERAL unnest(session.challenge_queue) q(challenge_id)
     JOIN private.atina_challenges challenge ON challenge.challenge_id=q.challenge_id),
  3,
  'Mix contains easy, medium and hard challenges'
);

SELECT diag(
  'Mix player='||(SELECT id::text FROM atina_mix_test_player)||
  ' token_lookup='||coalesce((SELECT id::text FROM private.atina_players
    WHERE device_token_hash=extensions.digest(convert_to(repeat('a',64),'UTF8'),'sha256')),'null')||
  ' queue='||(SELECT array_to_string(session.challenge_queue,',')
               FROM private.atina_v2_local_sessions session
               JOIN atina_mix_test_run run ON session.id=(run.result->'state'->>'session_id')::uuid)||
  ' exposures='||(SELECT string_agg(challenge_id::text,',')
                 FROM private.atina_challenge_exposures
                WHERE scope_type='player' AND scope_key=(SELECT id::text FROM atina_mix_test_player))||
  ' solo_queue='||(SELECT array_to_string(session.challenge_queue,',')
               FROM private.atina_v2_local_sessions session
               JOIN atina_solo_test_run run ON session.id=(run.result->'state'->>'session_id')::uuid)||
  ' exposure_filter='||position('private.atina_challenge_exposures' in
    pg_get_functiondef('public.atina_v2_start_local_game(text,text,text,integer,text)'::regprocedure))||
  ' difficulty_history_filter='||position('private.atina_difficulty_history' in
    pg_get_functiondef('public.atina_v2_start_local_game(text,text,text,integer,text)'::regprocedure))
);

SELECT is(
  (SELECT count(*)::integer
     FROM private.atina_v2_local_sessions session
     JOIN atina_mix_test_run run ON session.id=(run.result->'state'->>'session_id')::uuid
     CROSS JOIN LATERAL unnest(session.challenge_queue) q(challenge_id)
     WHERE q.challenge_id IN (-991002,-991005,-991008)),
  0,
  'Mix avoids the player previously exposed challenges'
);

SELECT is(
  (SELECT count(*)::integer
     FROM private.atina_v2_local_sessions session
     JOIN atina_solo_test_run run ON session.id=(run.result->'state'->>'session_id')::uuid
     CROSS JOIN LATERAL unnest(session.challenge_queue) q(challenge_id)
     WHERE q.challenge_id IN (-991002,-991005,-991008)),
  0,
  'Solo avoids the player previously exposed challenges'
);

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
  position('private.atina_challenge_exposures' in pg_get_functiondef('private.atina_apply_adaptive_difficulty()'::regprocedure)) > 0,
  'Adaptive Solo difficulty respects the no-repeat exposure ledger'
);

SELECT ok(
  position('c.difficulty' in pg_get_functiondef('private.atina_record_difficulty_result()'::regprocedure)) > 0,
  'Difficulty history records the actual challenge level'
);

SELECT * FROM finish();
ROLLBACK;
