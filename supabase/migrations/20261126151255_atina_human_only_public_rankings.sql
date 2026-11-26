-- Ensure every public ranking is based only on actual human player activity.

CREATE OR REPLACE FUNCTION public.atina_points_leaderboard(p_limit integer DEFAULT 50)
RETURNS TABLE(nickname text, points integer, challenges integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT p.nickname,
         p.total_points AS points,
         p.total_challenges AS challenges
  FROM private.atina_players p
  WHERE p.total_points > 0
  ORDER BY p.total_points DESC, p.total_challenges DESC, p.created_at ASC
  LIMIT least(greatest(coalesce(p_limit,50),1),100);
$function$;

CREATE OR REPLACE FUNCTION public.atina_progress_leaderboard(p_limit integer DEFAULT 50)
RETURNS TABLE(nickname text, xp integer, level integer, challenges integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH all_players AS (
    SELECT p.nickname, p.total_xp AS xp,
           private.atina_level_for_xp(p.total_xp) AS level,
           p.total_challenges AS challenges, p.created_at
    FROM private.atina_players p
    UNION ALL
    SELECT p.nickname, p.xp,
           private.atina_level_for_xp(p.xp) AS level,
           p.total_challenges AS challenges, p.created_at
    FROM private.atina_v2_players p
  )
  SELECT all_players.nickname, all_players.xp, all_players.level, all_players.challenges
  FROM all_players
  ORDER BY all_players.xp DESC, all_players.challenges DESC, all_players.created_at ASC
  LIMIT least(greatest(coalesce(p_limit,50),1),100);
$function$;

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
ranked AS (
  SELECT hp.*,
    CASE WHEN hp.avg_response_ms IS NULL THEN 0::numeric
      ELSE 1.0 - percent_rank() OVER (ORDER BY hp.avg_response_ms ASC NULLS LAST)
    END AS speed_rate
  FROM human_performance hp
),
components AS (
  SELECT r.*,
    greatest(0.0, least(1.0, coalesce(r.accuracy_rate, 0))) AS accuracy_part,
    greatest(0.0, least(1.0, coalesce(r.difficulty_rate, 0))) AS difficulty_part,
    greatest(0.0, least(1.0, coalesce(r.speed_rate, 0))) AS speed_part,
    greatest(0.0, least(1.0, 1.0 - 2.0 * coalesce(r.outcome_deviation, 0))) AS consistency_part
  FROM ranked r
)
SELECT c.player_name,
  round(200.0*(0.40*c.accuracy_part+0.25*c.difficulty_part+0.15*c.speed_part+0.20*c.consistency_part))::integer,
  c.attempts,
  round((c.accuracy_part*100)::numeric,1),
  round((c.difficulty_part*100)::numeric,1),
  round((c.speed_part*100)::numeric,1),
  round((c.consistency_part*100)::numeric,1)
FROM components c
ORDER BY 2 DESC,3 DESC,1 ASC
LIMIT least(greatest(coalesce(p_limit,15),1),100);
$function$;

CREATE OR REPLACE FUNCTION public.atina_qi_my_score(p_session_token text)
RETURNS TABLE(qi_score integer, challenges integer, accuracy numeric)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player_id uuid;
BEGIN
  IF p_session_token IS NULL OR p_session_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000';
  END IF;

  SELECT a.player_id INTO v_player_id
  FROM private.atina_player_accounts a
  WHERE a.session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
    AND a.session_expires_at>clock_timestamp();

  IF v_player_id IS NULL THEN
    RAISE EXCEPTION 'Sessão expirada. Inicia sessão novamente.' USING errcode='28000';
  END IF;

  RETURN QUERY
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
  ranked AS (
    SELECT hp.*,
      CASE WHEN hp.avg_response_ms IS NULL THEN 0::numeric
        ELSE 1.0 - percent_rank() OVER (ORDER BY hp.avg_response_ms ASC NULLS LAST)
      END AS speed_rate
    FROM human_performance hp
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
    round(200.0*(0.40*c.accuracy_part+0.25*c.difficulty_part+0.15*c.speed_part+0.20*c.consistency_part))::integer,
    c.attempts,
    round((c.accuracy_part*100)::numeric,1)
  FROM components c
  WHERE c.player_key=v_player_id::text;
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_online_players()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT coalesce(private.atina_online_snapshot()->'humans','[]'::jsonb);
$function$;
