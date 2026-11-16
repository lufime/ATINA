create table if not exists private.atina_v2_bot_presence_windows (
  bot_profile_id integer primary key references private.atina_v2_bot_profiles(id) on delete cascade,
  online_since timestamptz,
  online_until timestamptz,
  next_online_at timestamptz not null default clock_timestamp()
);
revoke all on private.atina_v2_bot_presence_windows from public, anon, authenticated;

insert into private.atina_v2_bot_presence_windows(bot_profile_id,online_since,online_until,next_online_at)
select b.id,
       clock_timestamp() - make_interval(mins => floor(random()*20)::integer),
       clock_timestamp() + make_interval(mins => 20 + floor(random()*41)::integer),
       clock_timestamp() + make_interval(mins => 20 + floor(random()*41)::integer)
from private.atina_v2_bot_profiles b
on conflict (bot_profile_id) do nothing;

create or replace function private.atina_v2_bot_refresh_presence()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare v_started integer;
begin
  insert into private.atina_v2_bot_presence_windows(bot_profile_id,next_online_at)
  select b.id, clock_timestamp() + make_interval(mins => floor(random()*30)::integer)
  from private.atina_v2_bot_profiles b
  on conflict (bot_profile_id) do nothing;

  update private.atina_v2_bot_presence_windows w
  set online_since = clock_timestamp(),
      online_until = clock_timestamp() + make_interval(mins => 20 + floor(random()*71)::integer),
      next_online_at = clock_timestamp() + make_interval(mins => 20 + floor(random()*71)::integer)
  from private.atina_v2_bot_profiles b
  where b.id = w.bot_profile_id
    and b.active
    and (w.online_until is null or w.online_until <= clock_timestamp())
    and w.next_online_at <= clock_timestamp();
  get diagnostics v_started = row_count;

  update private.atina_v2_bot_presence_windows w
  set online_since = null, online_until = null
  from private.atina_v2_bot_profiles b
  where b.id = w.bot_profile_id
    and not b.active
    and (w.online_since is not null or w.online_until is not null);

  return v_started;
end;
$function$;

create or replace function private.atina_v2_bot_is_available(p_bot private.atina_v2_bot_profiles)
returns boolean
language sql
stable
set search_path to ''
as $function$
  select coalesce(p_bot.active,false)
    and exists (
      select 1 from private.atina_v2_bot_presence_windows w
      where w.bot_profile_id = p_bot.id
        and w.online_since is not null
        and w.online_until > clock_timestamp()
        and w.online_since <= clock_timestamp()
    );
$function$;

select cron.unschedule('atina-v2-bot-presence-refresh')
where exists (select 1 from cron.job where jobname='atina-v2-bot-presence-refresh');
select cron.schedule('atina-v2-bot-presence-refresh','* * * * *','select private.atina_v2_bot_refresh_presence();');
select private.atina_v2_bot_refresh_presence();
