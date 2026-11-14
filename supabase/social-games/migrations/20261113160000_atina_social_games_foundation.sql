-- ATINA social games v2: isolated foundation for the five new social games.
-- Scope: schema only. RPCs and content import are intentionally separate migrations.
-- Do not apply to production.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.atina_social_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{6}$'),
  status text not null default 'waiting'
    check (status in ('waiting','playing','completed')),
  max_players integer not null default 12 check (max_players between 2 and 20),
  host_player_id uuid,
  game_code text check (game_code in (
    'quanto_achas','associacao_palavras','isto_ou_aquilo',
    'misterio_impossivel','palavra_proibida'
  )),
  play_mode text check (play_mode in ('individual','teams')),
  difficulty text check (difficulty in ('easy','medium','hard','mixed')),
  total_rounds integer check (total_rounds between 1 and 50),
  current_round integer not null default 0 check (current_round >= 0),
  phase text not null default 'lobby'
    check (phase in ('lobby','answer','justify','vote','resolve','completed')),
  deadline_at timestamptz,
  state_version bigint not null default 0 check (state_version >= 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (
    (status = 'waiting' and phase = 'lobby')
    or status <> 'waiting'
  )
);

create table private.atina_social_players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references private.atina_social_rooms(id) on delete cascade,
  token_hash bytea not null unique check (octet_length(token_hash) = 32),
  nickname text not null check (char_length(btrim(nickname)) between 1 and 32),
  is_host boolean not null default false,
  team_id uuid,
  ready boolean not null default false,
  score integer not null default 0 check (score >= 0),
  last_seen_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  unique (room_id,id)
);

alter table private.atina_social_rooms
  add constraint atina_social_rooms_host_player_fk
  foreign key (id,host_player_id)
  references private.atina_social_players(room_id,id)
  deferrable initially deferred;

create unique index atina_social_players_one_host_idx
  on private.atina_social_players(room_id) where is_host;
create index atina_social_players_room_idx
  on private.atina_social_players(room_id,created_at,id);

create table private.atina_social_teams (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references private.atina_social_rooms(id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 1 and 32),
  sort_order integer not null check (sort_order > 0),
  created_at timestamptz not null default clock_timestamp(),
  unique (room_id,id),
  unique (room_id,sort_order),
  unique (room_id,label)
);

alter table private.atina_social_players
  add constraint atina_social_players_team_fk
  foreign key (room_id,team_id)
  references private.atina_social_teams(room_id,id);

create table private.atina_social_content (
  id bigint generated always as identity primary key,
  game_code text not null check (game_code in (
    'quanto_achas','associacao_palavras','isto_ou_aquilo',
    'misterio_impossivel','palavra_proibida'
  )),
  difficulty text not null check (difficulty in ('easy','medium','hard')),
  content_version integer not null default 1 check (content_version > 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  unique (id,game_code,difficulty)
);
create index atina_social_content_selection_idx
  on private.atina_social_content(game_code,difficulty,id) where active;

create table private.atina_social_rounds (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references private.atina_social_rooms(id) on delete cascade,
  round_number integer not null check (round_number > 0),
  content_id bigint not null,
  game_code text not null,
  difficulty text not null,
  phase text not null default 'answer'
    check (phase in ('answer','justify','vote','resolve','completed')),
  prompt_public jsonb not null default '{}'::jsonb
    check (jsonb_typeof(prompt_public) = 'object'),
  secret_payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(secret_payload) = 'object'),
  started_at timestamptz not null default clock_timestamp(),
  deadline_at timestamptz,
  resolved_at timestamptz,
  unique (room_id,round_number),
  unique (id,room_id),
  foreign key (content_id,game_code,difficulty)
    references private.atina_social_content(id,game_code,difficulty)
);
create index atina_social_rounds_room_idx
  on private.atina_social_rounds(room_id,round_number);

create table private.atina_social_submissions (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references private.atina_social_rounds(id) on delete cascade,
  player_id uuid not null references private.atina_social_players(id) on delete cascade,
  answer_payload jsonb not null check (jsonb_typeof(answer_payload) = 'object'),
  normalized_answer text,
  score_awarded integer not null default 0 check (score_awarded >= 0),
  created_at timestamptz not null default clock_timestamp(),
  unique (round_id,player_id)
);

create table private.atina_social_justifications (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references private.atina_social_rounds(id) on delete cascade,
  player_id uuid not null references private.atina_social_players(id) on delete cascade,
  text text not null check (char_length(btrim(text)) between 1 and 600),
  created_at timestamptz not null default clock_timestamp(),
  unique (round_id,player_id),
  unique (id,round_id)
);

create table private.atina_social_votes (
  round_id uuid not null references private.atina_social_rounds(id) on delete cascade,
  justification_id uuid not null,
  voter_player_id uuid not null references private.atina_social_players(id) on delete cascade,
  created_at timestamptz not null default clock_timestamp(),
  primary key (round_id,voter_player_id),
  foreign key (justification_id,round_id)
    references private.atina_social_justifications(id,round_id) on delete cascade
);

create table private.atina_social_mystery_events (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references private.atina_social_rounds(id) on delete cascade,
  player_id uuid not null references private.atina_social_players(id) on delete cascade,
  event_type text not null check (event_type in ('question','answer','guess')),
  question_text text check (question_text is null or char_length(btrim(question_text)) between 1 and 300),
  answer_code text check (answer_code in ('yes','no','irrelevant')),
  solution_guess text check (solution_guess is null or char_length(btrim(solution_guess)) between 1 and 300),
  accepted boolean,
  created_at timestamptz not null default clock_timestamp(),
  check (
    (event_type = 'question' and question_text is not null and answer_code is null and solution_guess is null)
    or (event_type = 'answer' and answer_code is not null and question_text is null and solution_guess is null)
    or (event_type = 'guess' and solution_guess is not null and question_text is null and answer_code is null)
  )
);
create index atina_social_mystery_events_round_idx
  on private.atina_social_mystery_events(round_id,created_at,id);

create table private.atina_social_taboo_turns (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references private.atina_social_rounds(id) on delete cascade,
  active_player_id uuid not null references private.atina_social_players(id) on delete cascade,
  content_id bigint not null references private.atina_social_content(id),
  status text not null default 'active'
    check (status in ('active','passed','completed','expired')),
  clue_text text check (clue_text is null or char_length(clue_text) <= 300),
  forbidden_violation boolean not null default false,
  score integer not null default 0 check (score >= 0),
  deadline_at timestamptz,
  created_at timestamptz not null default clock_timestamp()
);
create unique index atina_social_taboo_one_active_turn_idx
  on private.atina_social_taboo_turns(round_id) where status = 'active';

create table private.atina_social_action_log (
  id bigint generated always as identity primary key,
  room_id uuid not null references private.atina_social_rooms(id) on delete cascade,
  player_id uuid references private.atina_social_players(id) on delete set null,
  action_key text not null check (char_length(btrim(action_key)) between 1 and 80),
  request_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (room_id,player_id,action_key,request_id)
);
create index atina_social_action_log_room_idx
  on private.atina_social_action_log(room_id,created_at);

-- Defence in depth: no direct browser access to private game state.
do $$
declare
  t text;
begin
  foreach t in array array[
    'atina_social_rooms','atina_social_players','atina_social_teams',
    'atina_social_content','atina_social_rounds','atina_social_submissions',
    'atina_social_justifications','atina_social_votes',
    'atina_social_mystery_events','atina_social_taboo_turns',
    'atina_social_action_log'
  ] loop
    execute format('alter table private.%I enable row level security', t);
    execute format('revoke all on table private.%I from public, anon, authenticated', t);
  end loop;
end
$$;

revoke all on all sequences in schema private from public, anon, authenticated;
comment on schema private is
  'Private ATINA social-games v2 state. Access only through reviewed RPCs.';
