-- Include every active ATINA participant in public online presence and global progress rankings.
-- Preserve existing player data; no rows are inserted, updated, or deleted.

CREATE OR REPLACE FUNCTION public.atina_points_leaderboard(p_limit integer DEFAULT 50)
RETURNS TABLE(nickname text, points integer, challenges integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  WITH all_players AS (
    SELECT p.nickname, p.total_points AS points,
           p.total_challenges AS challenges, p.created_at
    FROM private.atina_players p
    WHERE p.total_points > 0
    UNION ALL
    SELECT b.nickname, s.points,
           s.total_challenges AS challenges, b.created_at
    FROM private.atina_v2_bot_profiles b
    JOIN private.atina_v2_bot_competition_stats s ON s.bot_profile_id=b.id
    WHERE b.active AND s.points > 0
  )
  SELECT all_players.nickname, all_players.points, all_players.challenges
  FROM all_players
  ORDER BY all_players.points DESC, all_players.challenges DESC, all_players.created_at ASC
  LIMIT least(greatest(coalesce(p_limit,50),1),100);
$function$;

CREATE OR REPLACE FUNCTION public.atina_progress_leaderboard(p_limit integer DEFAULT 50)
RETURNS TABLE(nickname text, xp integer, level integer, challenges integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
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
    UNION ALL
    SELECT b.nickname, s.xp,
           private.atina_level_for_xp(s.xp) AS level,
           s.total_challenges AS challenges, b.created_at
    FROM private.atina_v2_bot_profiles b
    JOIN private.atina_v2_bot_competition_stats s ON s.bot_profile_id=b.id
    WHERE b.active AND s.xp > 0
  )
  SELECT all_players.nickname, all_players.xp, all_players.level, all_players.challenges
  FROM all_players
  ORDER BY all_players.xp DESC, all_players.challenges DESC, all_players.created_at ASC
  LIMIT least(greatest(coalesce(p_limit,50),1),100);
$function$;

CREATE OR REPLACE FUNCTION private.atina_online_snapshot()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
WITH human_candidates AS (
  SELECT coalesce('account:' || p.account_player_id::text,'guest:' || p.session_id::text) AS identity,
         coalesce(nullif(btrim(p.nickname),''),'Visitante') AS nickname,
         p.last_seen_at
  FROM private.atina_site_presence p
  WHERE p.last_seen_at >= statement_timestamp()-interval '60 seconds'
  UNION ALL
  SELECT 'account:' || rp.account_player_id::text,
         coalesce(nullif(btrim(rp.nickname),''),'Jogador'),
         rp.last_seen_at
  FROM public.atina_v2_room_players rp
  JOIN public.atina_v2_rooms r ON r.id=rp.room_id
  WHERE rp.account_player_id IS NOT NULL
    AND NOT coalesce(rp.is_bot,false)
    AND r.status IN ('waiting','playing')
    AND rp.last_seen_at >= statement_timestamp()-interval '90 seconds'
),
profile_candidates AS (
  SELECT 'profile:' || b.id::text AS identity,
         coalesce(nullif(btrim(b.nickname),''),'Jogador') AS nickname,
         w.online_since AS last_seen_at
  FROM private.atina_v2_bot_profiles b
  JOIN private.atina_v2_bot_presence_windows w ON w.bot_profile_id=b.id
  WHERE b.active AND w.online_since IS NOT NULL
    AND w.online_until > statement_timestamp()
  UNION ALL
  SELECT 'profile:' || b.id::text,
         coalesce(nullif(btrim(b.nickname),''),'Jogador'),
         rp.last_seen_at
  FROM private.atina_v2_bot_matches m
  JOIN private.atina_v2_bot_profiles b ON b.id=m.bot_profile_id
  JOIN public.atina_v2_room_players rp ON rp.id=m.bot_player_id AND rp.room_id=m.room_id
  JOIN public.atina_v2_rooms r ON r.id=m.room_id
  WHERE r.status IN ('waiting','playing')
    AND rp.last_seen_at >= statement_timestamp()-interval '90 seconds'
),
all_candidates AS (
  SELECT * FROM human_candidates
  UNION ALL
  SELECT * FROM profile_candidates
),
unique_players AS (
  SELECT DISTINCT ON(identity) identity,nickname
  FROM all_candidates
  ORDER BY identity,last_seen_at DESC
),
player_result AS (
  SELECT coalesce(
    jsonb_agg(jsonb_build_object(
      'id','player:'||encode(extensions.digest(convert_to(identity,'UTF8'),'sha256'),'hex'),
      'type','player','nickname',nickname,'online',true
    ) ORDER BY nickname,identity),'[]'::jsonb
  ) AS players,
  count(*)::integer AS total,
  count(*) FILTER (WHERE identity LIKE 'account:%' OR identity LIKE 'guest:%')::integer AS human_total
  FROM unique_players
)
SELECT jsonb_build_object(
  'players',player_result.players,
  'humans',player_result.players,
  'counts',jsonb_build_object('players',player_result.total,'humans',player_result.human_total,'total',player_result.total)
)
FROM player_result;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_online_players()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT coalesce(private.atina_online_snapshot()->'players','[]'::jsonb);
$function$;

DO $schedule$
DECLARE existing_job record;
BEGIN
  FOR existing_job IN SELECT jobid FROM cron.job WHERE jobname='atina-v2-presence-refresh'
  LOOP
    PERFORM cron.unschedule(existing_job.jobid);
  END LOOP;
  PERFORM cron.schedule(
    'atina-v2-presence-refresh',
    '* * * * *',
    'SELECT private.atina_v2_bot_refresh_presence();'
  );
END;
$schedule$;
