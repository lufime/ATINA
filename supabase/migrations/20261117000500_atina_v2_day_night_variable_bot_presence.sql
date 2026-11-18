-- Vary simulated-player presence by each profile's local time.
-- Daytime activity is higher; nighttime activity is lower. Individual sessions remain 20-90 minutes.
create or replace function private.atina_v2_bot_refresh_presence()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_started integer := 0;
  v_stopped integer := 0;
begin
  insert into private.atina_v2_bot_presence_windows(bot_profile_id,next_online_at)
  select b.id, clock_timestamp() + make_interval(mins => 1 + floor(random()*30)::integer)
  from private.atina_v2_bot_profiles b
  on conflict (bot_profile_id) do nothing;

  update private.atina_v2_bot_presence_windows w
     set online_since = null,
         online_until = null,
         next_online_at = clock_timestamp() + make_interval(mins => 5 + floor(random()*41)::integer)
    from private.atina_v2_bot_profiles b
   where b.id = w.bot_profile_id
     and (not b.active or (w.online_until is not null and w.online_until <= clock_timestamp()));
  get diagnostics v_stopped = row_count;

  with due as (
    select b.id,
           case
             when extract(hour from (clock_timestamp() at time zone b.timezone_name)) between 0 and 5 then 0.06
             when extract(hour from (clock_timestamp() at time zone b.timezone_name)) between 6 and 7 then 0.14
             when extract(hour from (clock_timestamp() at time zone b.timezone_name)) between 8 and 11 then 0.27
             when extract(hour from (clock_timestamp() at time zone b.timezone_name)) between 12 and 17 then 0.36
             when extract(hour from (clock_timestamp() at time zone b.timezone_name)) between 18 and 21 then 0.30
             else 0.14
           end
           * case when extract(isodow from (clock_timestamp() at time zone b.timezone_name)) in (6,7) then 1.08 else 1.0 end
           as activity_chance
      from private.atina_v2_bot_profiles b
      join private.atina_v2_bot_presence_windows w on w.bot_profile_id=b.id
     where b.active and w.online_since is null and w.next_online_at <= clock_timestamp()
  ),
  decisions as (
    select id, activity_chance, random() as roll from due
  )
  update private.atina_v2_bot_presence_windows w
     set online_since = clock_timestamp(),
         online_until = clock_timestamp() + make_interval(mins => 20 + floor(random()*71)::integer),
         next_online_at = clock_timestamp() + make_interval(mins => 20 + floor(random()*71)::integer)
    from decisions d
   where w.bot_profile_id=d.id and d.roll < d.activity_chance;
  get diagnostics v_started = row_count;

  update private.atina_v2_bot_presence_windows w
     set next_online_at = clock_timestamp() + make_interval(mins => 8 + floor(random()*38)::integer)
    from private.atina_v2_bot_profiles b
   where b.id=w.bot_profile_id and b.active
     and w.online_since is null and w.next_online_at <= clock_timestamp();

  return v_started;
end;
$function$;

create or replace function public.atina_v2_online_players()
returns jsonb language sql stable security definer set search_path to ''
as $function$
  with bot_presence as (
    select b.nickname from private.atina_v2_bot_profiles b
    where private.atina_v2_bot_is_available(b)
  ),
  visible_players as (
    select p.nickname from public.atina_v2_room_players p
    where not coalesce(p.is_bot,false)
      and p.last_seen_at > clock_timestamp() - interval '90 seconds'
    union select nickname from bot_presence
    union
    select b.nickname
    from private.atina_v2_bot_matches m
    join private.atina_v2_bot_profiles b on b.id=m.bot_profile_id
    join public.atina_v2_rooms r on r.id=m.room_id
    join public.atina_v2_room_players p on p.id=m.bot_player_id
    where r.status in ('waiting','playing')
      and p.last_seen_at > clock_timestamp() - interval '90 seconds'
  )
  select coalesce(jsonb_agg(jsonb_build_object('nickname',nickname,'online',true) order by nickname),'[]'::jsonb)
  from (select distinct nickname from visible_players where nickname is not null and btrim(nickname)<>'') v;
$function$;

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
  if to_regclass('private.atina_site_presence') is not null then
    execute
      'select count(*)::integer
         from private.atina_site_presence
        where last_seen_at >= clock_timestamp() - interval ''60 seconds'''
      into v_humans;
  end if;

  select count(*)::integer
    into v_simulated
    from private.atina_v2_bot_profiles b
   where b.active
     and private.atina_v2_bot_is_available(b);

  return coalesce(v_humans, 0) + coalesce(v_simulated, 0);
end;
$function$;

select private.atina_v2_bot_refresh_presence();
