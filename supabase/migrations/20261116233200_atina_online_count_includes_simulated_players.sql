create or replace function public.atina_online_player_count()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_humans integer := 0;
  v_simulated integer := 0;
begin
  -- The legacy presence table is optional on clean installations.
  -- Resolve it dynamically so the function can be created either way.
  if to_regclass('private.atina_site_presence') is not null then
    execute
      'select count(*)::integer
         from private.atina_site_presence
        where last_seen_at >= clock_timestamp() - interval ''60 seconds'''
      into v_humans;
  end if;

  select least(10, count(*)::integer)
    into v_simulated
    from private.atina_v2_bot_profiles b
   where b.active
     and private.atina_v2_bot_is_available(b);

  return coalesce(v_humans, 0) + coalesce(v_simulated, 0);
end;
$function$;
