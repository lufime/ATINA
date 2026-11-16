create or replace function public.atina_online_player_count()
returns integer
language sql
security definer
set search_path to ''
as $function$
  select
    (
      select count(*)::integer
      from private.atina_site_presence
      where last_seen_at >= clock_timestamp() - interval '60 seconds'
    )
    +
    least(10, (
      select count(*)::integer
      from private.atina_v2_bot_profiles b
      where b.active
        and private.atina_v2_bot_is_available(b)
    ));
$function$;