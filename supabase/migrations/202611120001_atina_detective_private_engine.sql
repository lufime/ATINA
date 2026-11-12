-- ATINA Detective adventure: private, server-authoritative storage.
-- This migration is additive. It does not modify existing challenge or room data.
-- No client role receives privileges or RLS policies on these tables.

create table if not exists private.atina_detective_case_templates (
  case_id text primary key check (case_id ~ '^[a-z0-9][a-z0-9_-]{2,63}$'),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  version integer not null default 1 check (version > 0),
  case_payload jsonb not null check (jsonb_typeof(case_payload) = 'object'),
  active boolean not null default false,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table if not exists private.atina_detective_sessions (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null unique references public.atina_rooms(id) on delete cascade,
  case_id text not null references private.atina_detective_case_templates(case_id),
  status text not null default 'setup'
    check (status in ('setup','active','accused','completed','abandoned')),
  detective_player_id uuid references public.atina_room_players(id) on delete set null,
  detective_selection text not null default 'random'
    check (detective_selection in ('manual','random')),
  seed bigint not null,
  turn_number integer not null default 0 check (turn_number >= 0),
  current_location text,
  world_state jsonb not null default '{}'::jsonb
    check (jsonb_typeof(world_state) = 'object'),
  public_state jsonb not null default '{}'::jsonb
    check (jsonb_typeof(public_state) = 'object'),
  secret_state jsonb not null default '{}'::jsonb
    check (jsonb_typeof(secret_state) = 'object'),
  accusation jsonb,
  winner text check (winner is null or winner in ('detective','culprit','draw')),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create index if not exists atina_detective_sessions_status_idx
  on private.atina_detective_sessions(status, updated_at desc);

create table if not exists private.atina_detective_characters (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references private.atina_detective_sessions(id) on delete cascade,
  character_key text not null check (character_key ~ '^[a-z0-9][a-z0-9_-]{1,63}$'),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  role_kind text not null check (role_kind in ('detective','culprit','suspect')),
  player_id uuid references public.atina_room_players(id) on delete set null,
  is_ai_controlled boolean not null default true,
  persona_state jsonb not null default '{}'::jsonb
    check (jsonb_typeof(persona_state) = 'object'),
  knowledge_state jsonb not null default '{}'::jsonb
    check (jsonb_typeof(knowledge_state) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  unique (session_id, character_key)
);

create unique index if not exists atina_detective_one_culprit_idx
  on private.atina_detective_characters(session_id)
  where role_kind = 'culprit';

create unique index if not exists atina_detective_one_detective_idx
  on private.atina_detective_characters(session_id)
  where role_kind = 'detective';

create unique index if not exists atina_detective_character_player_idx
  on private.atina_detective_characters(session_id, player_id)
  where player_id is not null;

create table if not exists private.atina_detective_evidence (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references private.atina_detective_sessions(id) on delete cascade,
  evidence_key text not null check (evidence_key ~ '^[a-z0-9][a-z0-9_-]{1,63}$'),
  location_key text not null,
  object_key text,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  evidence_payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(evidence_payload) = 'object'),
  discovery_requirements jsonb not null default '{}'::jsonb
    check (jsonb_typeof(discovery_requirements) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  unique (session_id, evidence_key)
);

create index if not exists atina_detective_evidence_location_idx
  on private.atina_detective_evidence(session_id, location_key);

create table if not exists private.atina_detective_discoveries (
  id bigint generated always as identity primary key,
  session_id uuid not null references private.atina_detective_sessions(id) on delete cascade,
  evidence_id uuid not null references private.atina_detective_evidence(id) on delete cascade,
  discovered_by_player_id uuid references public.atina_room_players(id) on delete set null,
  discovered_at timestamptz not null default clock_timestamp(),
  unique (session_id, evidence_id)
);

create index if not exists atina_detective_discoveries_session_idx
  on private.atina_detective_discoveries(session_id, discovered_at);

create table if not exists private.atina_detective_interactions (
  id bigint generated always as identity primary key,
  session_id uuid not null references private.atina_detective_sessions(id) on delete cascade,
  character_id uuid not null references private.atina_detective_characters(id) on delete cascade,
  player_id uuid references public.atina_room_players(id) on delete set null,
  topic text not null check (topic in ('whereabouts','timeline','relationships','object','motive','general')),
  presented_evidence_id uuid references private.atina_detective_evidence(id) on delete set null,
  response_text text not null check (char_length(response_text) between 1 and 2000),
  reaction text not null default 'neutral'
    check (reaction in ('neutral','cooperative','guarded','pressured','evidence')),
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists atina_detective_interactions_session_idx
  on private.atina_detective_interactions(session_id, created_at);

alter table private.atina_detective_case_templates enable row level security;
alter table private.atina_detective_sessions enable row level security;
alter table private.atina_detective_characters enable row level security;
alter table private.atina_detective_evidence enable row level security;
alter table private.atina_detective_discoveries enable row level security;
alter table private.atina_detective_interactions enable row level security;

revoke all on private.atina_detective_case_templates from public, anon, authenticated;
revoke all on private.atina_detective_sessions from public, anon, authenticated;
revoke all on private.atina_detective_characters from public, anon, authenticated;
revoke all on private.atina_detective_evidence from public, anon, authenticated;
revoke all on private.atina_detective_discoveries from public, anon, authenticated;
revoke all on private.atina_detective_interactions from public, anon, authenticated;

comment on table private.atina_detective_case_templates is
  'Server-only Detective case templates; case_payload may contain the full solution and private NPC data.';
comment on table private.atina_detective_sessions is
  'Server-authoritative Detective session state. secret_state is never returned to a browser.';
comment on table private.atina_detective_characters is
  'Private Detective character assignments, roles, persona state and character knowledge.';
comment on table private.atina_detective_evidence is
  'Private evidence catalogue. Client visibility is granted only after a validated discovery.';
comment on table private.atina_detective_discoveries is
  'Server-recorded evidence discoveries for each Detective session.';
comment on table private.atina_detective_interactions is
  'Server-recorded NPC dialogue; responses are generated from deterministic rules.';
