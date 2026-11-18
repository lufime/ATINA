-- Restore the site-presence table created by the hosted baseline migration
-- that is missing from the repository's clean migration history.
create table if not exists private.atina_site_presence (
  session_id uuid primary key,
  last_seen_at timestamptz not null default clock_timestamp(),
  nickname text,
  account_player_id uuid
);

create index if not exists atina_site_presence_last_seen_idx
  on private.atina_site_presence (last_seen_at desc);

create index if not exists atina_site_presence_account_active_idx
  on private.atina_site_presence (account_player_id, last_seen_at desc)
  where account_player_id is not null;

alter table private.atina_site_presence enable row level security;
revoke all on table private.atina_site_presence from public, anon, authenticated;

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