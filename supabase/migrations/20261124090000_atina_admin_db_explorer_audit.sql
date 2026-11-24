create table if not exists public.atina_admin_db_explorer_audit (
  id bigint generated always as identity primary key,
  actor_user_id uuid not null,
  operation text not null check (operation in ('update', 'delete')),
  table_name text not null check (table_name in ('atina_points_ranking', 'atina_site_notice', 'atina_social_game_catalog')),
  record_keys jsonb not null,
  changed_columns text[] not null default '{}',
  outcome text not null default 'started' check (outcome in ('started', 'completed', 'failed')),
  result_count integer not null default 0,
  created_at timestamptz not null default now()
);
alter table public.atina_admin_db_explorer_audit enable row level security;
revoke all on public.atina_admin_db_explorer_audit from anon, authenticated;
grant all on public.atina_admin_db_explorer_audit to service_role;
