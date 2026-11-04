-- Keep the public global leaderboard in sync with both ATINA progression generations.
-- The client already renders this RPC in the "Progressão global ATINA" section.
create or replace function public.atina_progress_leaderboard(p_limit integer default 50)
returns table(nickname text, xp integer, level integer, challenges integer)
language sql
stable
security definer
set search_path to ''
as $function$
  with all_players as (
    select
      p.nickname,
      p.total_xp as xp,
      floor(p.total_xp / 250.0)::integer + 1 as level,
      p.total_challenges as challenges,
      p.created_at
    from private.atina_players p

    union all

    select
      p.nickname,
      p.xp,
      (p.xp / 250) + 1 as level,
      p.total_challenges as challenges,
      p.created_at
    from private.atina_v2_players p
  )
  select
    all_players.nickname,
    all_players.xp,
    all_players.level,
    all_players.challenges
  from all_players
  order by all_players.xp desc, all_players.challenges desc, all_players.created_at asc
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$function$;

-- The leaderboard contains public pseudonyms and aggregate progress only.
grant execute on function public.atina_progress_leaderboard(integer) to anon, service_role;
revoke execute on function public.atina_progress_leaderboard(integer) from authenticated;
