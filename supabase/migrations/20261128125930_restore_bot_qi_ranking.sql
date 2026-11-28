-- Restore simulated participants to the public QI ranking.
-- Bot performance is derived from recorded competition events; no synthetic
-- leaderboard rows are inserted or modified by this function.
CREATE OR REPLACE FUNCTION public.atina_qi_leaderboard(p_limit integer DEFAULT 15)
RETURNS TABLE(
  nickname text,
  qi_score integer,
  challenges integer,
  accuracy numeric,
  difficulty_score numeric,
  speed_score numeric,
  consistency_score numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
WITH human_performance AS (
  SELECT
    e.actor_id::text AS player_key,
    coalesce(max(a.nickname), max(p.nickname), max(e.nickname), 'Jogador') AS player_name,
    count(*)::integer AS attempts,
    avg(CASE WHEN e.outcome = 'correct' THEN 1.0 ELSE 0.0 END) AS accuracy_rate,
    avg(CASE lower(coalesce(e.difficulty, ''))
      WHEN 'easy' THEN 1.0 WHEN 'facil' THEN 1.0 WHEN 'fácil' THEN 1.0
      WHEN 'medium' THEN 2.0 WHEN 'medio' THEN 2.0 WHEN 'médio' THEN 2.0
      WHEN 'hard' THEN 3.0 WHEN 'dificil' THEN 3.0 WHEN 'difícil' THEN 3.0
      ELSE null END) / 3.0 AS difficulty_rate,
    avg(e.response_ms)::numeric AS avg_response_ms,
    stddev_pop(CASE WHEN e.outcome = 'correct' THEN 1.0 ELSE 0.0 END) AS outcome_deviation
  FROM private.atina_performance_events e
  JOIN private.atina_player_accounts a ON a.player_id = e.actor_id
  LEFT JOIN private.atina_players p ON p.id = e.actor_id
  WHERE e.outcome IN ('correct', 'wrong', 'timeout', 'pass')
  GROUP BY e.actor_id
  HAVING count(*) FILTER (WHERE e.outcome IN ('correct','wrong')) > 10
),
bot_performance AS (
  SELECT
    'profile:' || b.id::text AS player_key,
    '🤖 ' || b.nickname AS player_name,
    count(*)::integer AS attempts,
    avg(CASE WHEN e.is_correct THEN 1.0 ELSE 0.0 END) AS accuracy_rate,
    coalesce(
      avg(CASE WHEN e.is_correct THEN greatest(0, least(20, coalesce(e.points, 0))) / 20.0 END),
      0.0
    ) AS difficulty_rate,
    ((b.response_min_seconds + b.response_max_seconds) / 2.0 * 1000.0)::numeric AS avg_response_ms,
    stddev_pop(CASE WHEN e.is_correct THEN 1.0 ELSE 0.0 END) AS outcome_deviation
  FROM private.atina_v2_bot_competition_events e
  JOIN private.atina_v2_bot_profiles b ON b.id = e.bot_profile_id
  WHERE e.source IN ('simulation', 'room')
    AND b.active
  GROUP BY b.id, b.nickname, b.response_min_seconds, b.response_max_seconds
  HAVING count(*) >= 1
),
per_player AS (
  SELECT * FROM human_performance
  UNION ALL
  SELECT * FROM bot_performance
),
ranked AS (
  SELECT pp.*,
    CASE WHEN pp.avg_response_ms IS NULL THEN 0::numeric
      ELSE 1.0 - percent_rank() OVER (ORDER BY pp.avg_response_ms ASC NULLS LAST)
    END AS speed_rate
  FROM per_player pp
),
components AS (
  SELECT r.*,
    greatest(0.0, least(1.0, coalesce(r.accuracy_rate, 0))) AS accuracy_part,
    greatest(0.0, least(1.0, coalesce(r.difficulty_rate, 0))) AS difficulty_part,
    greatest(0.0, least(1.0, coalesce(r.speed_rate, 0))) AS speed_part,
    greatest(0.0, least(1.0, 1.0 - 2.0 * coalesce(r.outcome_deviation, 0))) AS consistency_part
  FROM ranked r
)
SELECT
  c.player_name,
  round(200.0 * (
    0.40 * c.accuracy_part +
    0.25 * c.difficulty_part +
    0.15 * c.speed_part +
    0.20 * c.consistency_part
  ))::integer,
  c.attempts,
  round((c.accuracy_part * 100)::numeric, 1),
  round((c.difficulty_part * 100)::numeric, 1),
  round((c.speed_part * 100)::numeric, 1),
  round((c.consistency_part * 100)::numeric, 1)
FROM components c
ORDER BY 2 DESC, 3 DESC, 1 ASC
LIMIT least(greatest(coalesce(p_limit, 15), 1), 100);
$function$;
