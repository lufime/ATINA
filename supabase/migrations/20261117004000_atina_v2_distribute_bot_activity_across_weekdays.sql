-- Vary bot activity by each bot's local day of week.
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
             when extract(hour from (clock_timestamp() at time zone b.timezone_name)) between 0 and 5 then 0.01
             when extract(hour from (clock_timestamp() at time zone b.timezone_name)) between 6 and 7 then 0.08
             when extract(hour from (clock_timestamp() at time zone b.timezone_name)) between 8 and 11 then 0.27
             when extract(hour from (clock_timestamp() at time zone b.timezone_name)) between 12 and 17 then 0.36
             when extract(hour from (clock_timestamp() at time zone b.timezone_name)) between 18 and 21 then 0.25
             else 0.04
           end
           * case extract(isodow from (clock_timestamp() at time zone b.timezone_name))
               when 1 then 0.82
               when 2 then 0.88
               when 3 then 0.92
               when 4 then 0.98
               when 5 then 1.05
               when 6 then 1.15
               when 7 then 0.95
             end as activity_chance
      from private.atina_v2_bot_profiles b
      join private.atina_v2_bot_presence_windows w on w.bot_profile_id=b.id
     where b.active
       and w.online_since is null
       and w.next_online_at <= clock_timestamp()
  ),
  decisions as (
    select id, activity_chance, random() as roll from due
  )
  update private.atina_v2_bot_presence_windows w
     set online_since = clock_timestamp(),
         online_until = clock_timestamp() + make_interval(mins => 20 + floor(random()*71)::integer),
         next_online_at = clock_timestamp() + make_interval(mins => 20 + floor(random()*71)::integer)
    from decisions d
   where w.bot_profile_id=d.id
     and d.roll < d.activity_chance;
  get diagnostics v_started = row_count;

  update private.atina_v2_bot_presence_windows w
     set next_online_at = clock_timestamp() + make_interval(mins => 8 + floor(random()*38)::integer)
    from private.atina_v2_bot_profiles b
   where b.id=w.bot_profile_id
     and b.active
     and w.online_since is null
     and w.next_online_at <= clock_timestamp();

  return v_started;
end;
$function$;
