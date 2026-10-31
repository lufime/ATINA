-- ATINA multiplayer room foundation.
-- Reconstructed from the existing browser RPC contract. No client table access;
-- all room operations must be exposed through token-authenticated RPCs.
create table if not exists public.atina_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{6}$'),
  max_players integer not null check (max_players between 2 and 20),
  status text not null default 'waiting'
    check (status in ('waiting','playing','completed','finished')),
  game_state jsonb not null default '{}'::jsonb
    check (jsonb_typeof(game_state) = 'object'),
  state_version bigint not null default 0 check (state_version >= 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.atina_room_players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.atina_rooms(id) on delete cascade,
  token_hash bytea not null,
  nickname text not null check (char_length(btrim(nickname)) between 1 and 32),
  is_host boolean not null default false,
  ready boolean not null default false,
  team_label text,
  score integer not null default 0 check (score >= 0),
  player_timeout_seconds integer not null default 3600
    check (player_timeout_seconds between 0 and 3600),
  created_at timestamptz not null default clock_timestamp(),
  last_seen_at timestamptz not null default clock_timestamp(),
  constraint atina_room_players_token_hash_unique unique (token_hash),
  constraint atina_room_players_room_id_id_unique unique (room_id,id)
);

create unique index if not exists atina_room_players_one_host_idx
  on public.atina_room_players(room_id) where is_host;
create index if not exists atina_room_players_room_created_idx
  on public.atina_room_players(room_id,created_at,id);

create table if not exists public.atina_room_answers (
  id bigint generated always as identity primary key,
  room_id uuid not null,
  player_id uuid not null,
  challenge_index integer not null check (challenge_index >= 0),
  is_correct boolean not null,
  points integer not null default 0 check (points >= 0),
  created_at timestamptz not null default clock_timestamp(),
  constraint atina_room_answers_player_fk
    foreign key (room_id,player_id)
    references public.atina_room_players(room_id,id) on delete cascade
);
create index if not exists atina_room_answers_room_challenge_idx
  on public.atina_room_answers(room_id,challenge_index,created_at);

create table if not exists public.atina_room_results (
  room_id uuid not null references public.atina_rooms(id) on delete cascade,
  player_id uuid not null,
  nickname text not null,
  team_label text,
  score integer not null check (score >= 0),
  completed_at timestamptz not null default clock_timestamp(),
  primary key (room_id,player_id),
  constraint atina_room_results_player_fk
    foreign key (room_id,player_id)
    references public.atina_room_players(room_id,id) on delete cascade
);

create table if not exists public.atina_room_team_proposals (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.atina_rooms(id) on delete cascade,
  challenge_index integer not null check (challenge_index >= 0),
  team_label text not null,
  proposer_id uuid not null,
  answer_text text not null check (char_length(btrim(answer_text)) between 1 and 200),
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  constraint atina_room_team_proposals_player_fk
    foreign key (room_id,proposer_id)
    references public.atina_room_players(room_id,id) on delete cascade
);
create index if not exists atina_room_team_proposals_pending_idx
  on public.atina_room_team_proposals(room_id,challenge_index,status);

create table if not exists public.atina_room_team_votes (
  proposal_id uuid not null references public.atina_room_team_proposals(id) on delete cascade,
  player_id uuid not null references public.atina_room_players(id) on delete cascade,
  agrees boolean not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (proposal_id,player_id)
);

alter table public.atina_rooms enable row level security;
alter table public.atina_room_players enable row level security;
alter table public.atina_room_answers enable row level security;
alter table public.atina_room_results enable row level security;
alter table public.atina_room_team_proposals enable row level security;
alter table public.atina_room_team_votes enable row level security;

revoke all on public.atina_rooms, public.atina_room_players,
  public.atina_room_answers, public.atina_room_results,
  public.atina_room_team_proposals, public.atina_room_team_votes
  from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;

comment on table public.atina_rooms is
  'ATINA multiplayer room metadata; direct client access revoked, use token-authenticated RPCs.';
comment on table public.atina_room_players is
  'ATINA room participants; token_hash is a SHA-256 digest of a random bearer token.';
comment on table public.atina_room_answers is
  'Server-recorded answer attempts and awarded points; clients must not write directly.';
comment on table public.atina_room_results is
  'Final server-calculated room leaderboard.';
comment on table public.atina_room_team_proposals is
  'Team answer proposals; correctness and points must be calculated server-side.';
comment on table public.atina_room_team_votes is
  'One vote per participant and proposal.';

-- Cover the player-side foreign keys flagged by the Supabase performance advisor.
create index if not exists atina_room_answers_room_player_idx
  on public.atina_room_answers(room_id,player_id);
create index if not exists atina_room_team_proposals_room_proposer_idx
  on public.atina_room_team_proposals(room_id,proposer_id);
create index if not exists atina_room_team_votes_player_idx
  on public.atina_room_team_votes(player_id);
