-- Keep automated practice simulations separate from the real-player QI* sample.
-- This migration does not modify real player points, XP, scores, or performance events.

CREATE TABLE IF NOT EXISTS private.atina_qi_simulation_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  bot_profile_id integer NOT NULL REFERENCES private.atina_v2_bot_profiles(id) ON DELETE CASCADE,
  simulation_id uuid NOT NULL,
  challenge_position integer NOT NULL CHECK (challenge_position > 0),
  challenge_id integer NOT NULL,
  category text NOT NULL,
  difficulty text,
  outcome text NOT NULL CHECK (outcome IN ('correct', 'wrong')),
  response_ms integer NOT NULL CHECK (response_ms > 0),
  clues_used integer NOT NULL CHECK (clues_used >= 0),
  knowledge_level numeric(4,3) NOT NULL,
  mistake_rate numeric(4,3) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (bot_profile_id, simulation_id, challenge_position)
);

CREATE INDEX IF NOT EXISTS atina_qi_simulation_events_created_idx
  ON private.atina_qi_simulation_events (created_at DESC);
CREATE INDEX IF NOT EXISTS atina_qi_simulation_events_profile_idx
  ON private.atina_qi_simulation_events (bot_profile_id, created_at DESC);

REVOKE ALL ON private.atina_qi_simulation_events FROM PUBLIC, anon, authenticated;
ALTER TABLE private.atina_qi_simulation_events ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE private.atina_qi_simulation_events IS
  'Synthetic practice events for validating QI* calculations; never part of the real-player calibration sample.';

CREATE OR REPLACE FUNCTION private.atina_v2_simulate_bot_games()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_bot record;
  v_challenge record;
  v_game_id uuid;
  v_used integer[];
  v_challenge_count integer;
  v_clues integer;
  v_correct boolean;
  v_points integer;
  v_inserted integer;
  v_games integer := 0;
  v_interval integer;
  v_response_seconds integer;
  i integer;
BEGIN
  INSERT INTO private.atina_v2_bot_competition_stats (bot_profile_id, next_game_at)
  SELECT b.id, clock_timestamp() + make_interval(mins => 1 + floor(random()*3)::integer)
  FROM private.atina_v2_bot_profiles b
  ON CONFLICT (bot_profile_id) DO NOTHING;

  -- New online sessions start with a short, human-like delay.
  UPDATE private.atina_v2_bot_competition_stats s
     SET next_game_at = clock_timestamp() + make_interval(mins => 1 + floor(random()*3)::integer),
         updated_at = clock_timestamp()
    FROM private.atina_v2_bot_profiles b
    JOIN private.atina_v2_bot_presence_windows w ON w.bot_profile_id=b.id
   WHERE s.bot_profile_id=b.id
     AND b.active
     AND private.atina_v2_bot_is_available(b)
     AND w.online_since >= clock_timestamp() - interval '2 minutes'
     AND (s.last_game_at IS NULL OR s.last_game_at < w.online_since)
     AND s.next_game_at > clock_timestamp() + interval '3 minutes';

  FOR v_bot IN
    SELECT b.id, b.knowledge_level, b.mistake_rate,
           b.response_min_seconds, b.response_max_seconds, s.next_game_at
      FROM private.atina_v2_bot_profiles b
      JOIN private.atina_v2_bot_competition_stats s ON s.bot_profile_id=b.id
     WHERE b.active
       AND s.next_game_at <= clock_timestamp()
       AND private.atina_v2_bot_is_available(b)
       AND NOT EXISTS (
         SELECT 1
           FROM private.atina_v2_bot_matches m
           JOIN public.atina_v2_rooms r ON r.id=m.room_id
          WHERE m.bot_profile_id=b.id
            AND r.status IN ('waiting','playing')
       )
     ORDER BY s.next_game_at
     LIMIT 8
     FOR UPDATE OF s SKIP LOCKED
  LOOP
    v_game_id := extensions.gen_random_uuid();
    v_used := ARRAY[]::integer[];
    -- Different profiles have different play habits and match lengths.
    v_challenge_count := 2 + floor(random()*4)::integer;

    FOR i IN 1..v_challenge_count LOOP
      SELECT c.challenge_id, c.category, c.difficulty, c.image_url
        INTO v_challenge
        FROM private.atina_challenges c
       WHERE c.active AND NOT (c.challenge_id = ANY(v_used))
       ORDER BY random()
       LIMIT 1;

      IF NOT FOUND THEN
        EXIT;
      END IF;

      v_used := array_append(v_used, v_challenge.challenge_id);
      v_clues := CASE
        WHEN v_bot.knowledge_level >= 0.78 THEN 1
        WHEN v_bot.knowledge_level >= 0.55 THEN 2
        ELSE 3
      END;
      v_response_seconds := v_bot.response_min_seconds
        + floor(random() * (v_bot.response_max_seconds - v_bot.response_min_seconds + 1))::integer;
      v_correct := random() < greatest(0.03, least(0.98,
        v_bot.knowledge_level * (1 - v_bot.mistake_rate)));
      v_points := CASE
        WHEN NOT v_correct THEN 0
        WHEN v_clues=1 THEN 20
        WHEN v_clues=2 THEN 16
        ELSE 12
      END;

      INSERT INTO private.atina_v2_bot_competition_events
        (bot_profile_id, source, source_id, challenge_position, points, xp, is_correct)
      VALUES
        (v_bot.id, 'simulation', v_game_id, i, v_points, 10, v_correct)
      ON CONFLICT (bot_profile_id, source, source_id, challenge_position) DO NOTHING;

      GET DIAGNOSTICS v_inserted = ROW_COUNT;
      IF v_inserted=1 THEN
        UPDATE private.atina_v2_bot_competition_stats
           SET points=points+v_points,
               xp=xp+10,
               total_challenges=total_challenges+1,
               updated_at=clock_timestamp()
         WHERE bot_profile_id=v_bot.id;
      END IF;

      -- Synthetic QI* diagnostics are stored in their own private table.
      -- They are deliberately excluded from private.atina_performance_events.
      INSERT INTO private.atina_qi_simulation_events
        (bot_profile_id, simulation_id, challenge_position, challenge_id,
         category, difficulty, outcome, response_ms, clues_used,
         knowledge_level, mistake_rate)
      VALUES
        (v_bot.id, v_game_id, i, v_challenge.challenge_id,
         v_challenge.category, v_challenge.difficulty,
         CASE WHEN v_correct THEN 'correct' ELSE 'wrong' END,
         v_response_seconds * 1000, v_clues,
         v_bot.knowledge_level, v_bot.mistake_rate)
      ON CONFLICT (bot_profile_id, simulation_id, challenge_position) DO NOTHING;
    END LOOP;

    -- Preserve the existing profile-based activity cadence.
    v_interval := CASE
      WHEN mod(v_bot.id,10) IN (0,1) THEN 8 + floor(random()*8)::integer
      WHEN mod(v_bot.id,10) IN (2,3,4) THEN 15 + floor(random()*14)::integer
      WHEN mod(v_bot.id,10) IN (5,6,7) THEN 28 + floor(random()*23)::integer
      ELSE 50 + floor(random()*41)::integer
    END;

    UPDATE private.atina_v2_bot_competition_stats
       SET simulated_games=simulated_games+1,
           last_game_at=clock_timestamp(),
           next_game_at=clock_timestamp()+make_interval(mins=>v_interval),
           updated_at=clock_timestamp()
     WHERE bot_profile_id=v_bot.id;

    v_games := v_games+1;
  END LOOP;

  RETURN v_games;
END;
$function$;
