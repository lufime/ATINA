create or replace function public.atina_v2_bot_points_leaderboard(p_limit integer default 10)
returns table(nickname text, points integer, challenges integer, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $function$
  select b.nickname, s.points, s.total_challenges, s.created_at
    from private.atina_v2_bot_competition_stats s
    join private.atina_v2_bot_profiles b on b.id=s.bot_profile_id
   where s.points>0
   order by s.points desc, s.total_challenges desc, s.created_at asc
   limit least(greatest(coalesce(p_limit,10),1),100);
$function$;

revoke all on function public.atina_v2_bot_points_leaderboard(integer) from public;
grant execute on function public.atina_v2_bot_points_leaderboard(integer) to anon, authenticated;
