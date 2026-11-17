create or replace function public.atina_points_leaderboard(p_limit integer default 50)
returns table(nickname text, points integer, challenges integer)
language sql
stable
security definer
set search_path = ''
as $function$
  with all_players as (
    select p.nickname, p.total_points as points,
           p.total_challenges as challenges, p.created_at
      from private.atina_players p
     where p.total_points > 0
    union all
    select b.nickname, s.points,
           s.total_challenges as challenges, s.created_at
      from private.atina_v2_bot_competition_stats s
      join private.atina_v2_bot_profiles b on b.id=s.bot_profile_id
     where s.points > 0
  )
  select ap.nickname, ap.points, ap.challenges
    from all_players ap
   order by ap.points desc, ap.challenges desc, ap.created_at asc
   limit least(greatest(coalesce(p_limit, 50), 1), 100);
$function$;
