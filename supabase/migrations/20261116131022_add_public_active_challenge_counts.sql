-- Exposes only aggregate counts of active challenges for the public game menu.
create or replace function public.atina_public_active_challenge_counts()
returns table(category text, active_count integer)
language sql
stable
security definer
set search_path = ''
as $$
  select c.category, count(*)::integer
  from private.atina_challenges as c
  where c.active is true
  group by c.category
  order by c.category;
$$;

revoke all on function public.atina_public_active_challenge_counts() from public;
grant execute on function public.atina_public_active_challenge_counts() to anon, authenticated;
