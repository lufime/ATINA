-- Keep the public progress leaderboard limited to real player records.
-- Simulation/competition stats remain internal and are not part of this public RPC.
CREATE OR REPLACE FUNCTION public.atina_progress_leaderboard(p_limit integer DEFAULT 50)
 RETURNS TABLE(nickname text, xp integer, level integer, challenges integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with all_players as (
    select p.nickname, p.total_xp as xp,
           private.atina_level_for_xp(p.total_xp) as level,
           p.total_challenges as challenges, p.created_at
      from private.atina_players p
    union all
    select p.nickname, p.xp,
           private.atina_level_for_xp(p.xp) as level,
           p.total_challenges as challenges, p.created_at
      from private.atina_v2_players p
  )
  select all_players.nickname, all_players.xp, all_players.level, all_players.challenges
    from all_players
   order by all_players.xp desc, all_players.challenges desc, all_players.created_at asc
   limit least(greatest(coalesce(p_limit,50),1),100);
$function$;
