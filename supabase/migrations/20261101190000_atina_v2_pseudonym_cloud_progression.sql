-- ATINA pseudonym-only cloud progression.
-- Proposal only: this migration is intentionally not applied to any Supabase project.
-- Players are identified by a random device recovery token + display pseudonym.
-- No Supabase Auth user, email, password, or client-supplied XP is involved.

do $preflight$
begin
  if to_regclass('private.atina_v2_local_sessions') is null then
    raise exception 'Missing private.atina_v2_local_sessions; install the authoritative local-session migration first.';
  end if;
  if to_regclass('private.atina_v2_players') is not null
     or to_regclass('private.atina_v2_progress_events') is not null then
    raise exception 'ATINA cloud progression objects already exist; inspect before applying.';
  end if;
end
$preflight$;

create table private.atina_v2_players (
  id uuid primary key default gen_random_uuid(),
  token_hash bytea not null unique,
  nickname text not null check (char_length(btrim(nickname)) between 1 and 20),
  xp integer not null default 0 check (xp >= 0),
  total_challenges integer not null default 0 check (total_challenges >= 0),
  daily_date date not null default (timezone('utc', now())::date),
  daily_count integer not null default 0 check (daily_count between 0 and 3),
  rewarded_date date,
  last_played_date date,
  current_streak integer not null default 0 check (current_streak >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table private.atina_v2_progress_events (
  id bigint generated always as identity primary key,
  player_id uuid not null references private.atina_v2_players(id) on delete cascade,
  session_id uuid not null,
  position integer not null check (position > 0),
  points integer not null check (points in (10, 60)),
  played_on date not null default (timezone('utc', now())::date),
  created_at timestamptz not null default now(),
  unique (player_id, session_id, position)
);

create index atina_v2_progress_events_player_date_idx
  on private.atina_v2_progress_events (player_id, played_on desc);

alter table private.atina_v2_players enable row level security;
alter table private.atina_v2_progress_events enable row level security;
revoke all on private.atina_v2_players from public, anon, authenticated;
revoke all on private.atina_v2_progress_events from public, anon, authenticated;

-- A device creates a 256-bit random token locally and keeps it in localStorage.
-- Only its SHA-256 digest is stored. Losing the token means losing access to that
-- pseudonym's cloud progress; there is deliberately no email/account recovery.
create or replace function public.atina_v2_player_profile(
  p_nickname text,
  p_player_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player private.atina_v2_players;
  v_hash bytea;
begin
  if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 20
     or p_player_token is null or p_player_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Pseudónimo ou chave de jogador inválidos.' using errcode='22023';
  end if;

  v_hash := extensions.digest(convert_to(p_player_token, 'UTF8'), 'sha256');
  insert into private.atina_v2_players(token_hash, nickname)
  values (v_hash, btrim(p_nickname))
  on conflict (token_hash) do update
    set nickname = excluded.nickname, updated_at = now()
  returning * into v_player;

  if v_player.daily_date <> timezone('utc', now())::date then
    update private.atina_v2_players
    set daily_date = timezone('utc', now())::date,
        daily_count = 0,
        updated_at = now()
    where id = v_player.id
    returning * into v_player;
  end if;

  return jsonb_build_object(
    'player_id', v_player.id,
    'nickname', v_player.nickname,
    'xp', v_player.xp,
    'level', (v_player.xp / 250) + 1,
    'total_challenges', v_player.total_challenges,
    'daily_count', v_player.daily_count,
    'streak', v_player.current_streak
  );
end;
$$;

-- XP is never accepted from the browser. The RPC verifies the server-issued game
-- bearer token and only rewards a locked, server-validated correct answer.
-- The unique event key prevents refresh/retry replay from awarding XP twice.
create or replace function public.atina_v2_record_local_progress(
  p_session_id uuid,
  p_session_token text,
  p_player_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session private.atina_v2_local_sessions;
  v_player private.atina_v2_players;
  v_today date := timezone('utc', now())::date;
  v_points integer := 10;
  v_inserted integer;
begin
  if p_session_token is null or p_player_token is null
     or p_session_token !~ '^[0-9a-f]{64}$'
     or p_player_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Credenciais inválidas.' using errcode='28000';
  end if;

  select * into v_session
  from private.atina_v2_local_sessions
  where id = p_session_id
    and token_hash = extensions.digest(convert_to(p_session_token, 'UTF8'), 'sha256')
  for update;
  if not found or v_session.expires_at <= now() then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  if not v_session.round_locked
     or v_session.last_result ->> 'outcome' <> 'correct' then
    raise exception 'Só os desafios respondidos corretamente dão XP.' using errcode='55000';
  end if;

  select * into v_player
  from private.atina_v2_players
  where token_hash = extensions.digest(convert_to(p_player_token, 'UTF8'), 'sha256')
  for update;
  if not found then
    raise exception 'Pseudónimo não registado neste dispositivo.' using errcode='28000';
  end if;

  if v_player.daily_date <> v_today then
    v_player.daily_date := v_today;
    v_player.daily_count := 0;
  end if;
  if v_player.last_played_date = v_today - 1 then
    v_player.current_streak := v_player.current_streak + 1;
  elsif v_player.last_played_date is distinct from v_today then
    v_player.current_streak := 1;
  end if;
  v_player.last_played_date := v_today;
  v_player.daily_count := least(3, v_player.daily_count + 1);
  if v_player.daily_count >= 3 and v_player.rewarded_date is distinct from v_today then
    v_points := 60;
    v_player.rewarded_date := v_today;
  end if;

  insert into private.atina_v2_progress_events(player_id, session_id, position, points, played_on)
  values (v_player.id, v_session.id, v_session.position, v_points, v_today)
  on conflict (player_id, session_id, position) do nothing;
  get diagnostics v_inserted = row_count;

  if v_inserted = 1 then
    v_player.xp := v_player.xp + v_points;
    v_player.total_challenges := v_player.total_challenges + 1;
    update private.atina_v2_players
    set xp = v_player.xp,
        total_challenges = v_player.total_challenges,
        daily_date = v_player.daily_date,
        daily_count = v_player.daily_count,
        rewarded_date = v_player.rewarded_date,
        last_played_date = v_player.last_played_date,
        current_streak = v_player.current_streak,
        updated_at = now()
    where id = v_player.id;
  else
    select * into v_player from private.atina_v2_players where id = v_player.id;
  end if;

  return jsonb_build_object(
    'player_id', v_player.id,
    'nickname', v_player.nickname,
    'xp', v_player.xp,
    'level', (v_player.xp / 250) + 1,
    'total_challenges', v_player.total_challenges,
    'daily_count', v_player.daily_count,
    'streak', v_player.current_streak,
    'awarded_xp', case when v_inserted = 1 then v_points else 0 end,
    'achievements', jsonb_build_array(
      v_player.total_challenges >= 1,
      v_player.total_challenges >= 10,
      v_player.total_challenges >= 25,
      v_player.total_challenges >= 50,
      v_player.total_challenges >= 100
    )
  );
end;
$$;

revoke all on function public.atina_v2_player_profile(text, text) from public;
revoke all on function public.atina_v2_record_local_progress(uuid, text, text) from public;
grant execute on function public.atina_v2_player_profile(text, text) to anon, authenticated;
grant execute on function public.atina_v2_record_local_progress(uuid, text, text) to anon, authenticated;

comment on function public.atina_v2_player_profile(text, text) is
  'Creates or reads pseudonym-only cloud progression using a random device token; no Auth account.';
comment on function public.atina_v2_record_local_progress(uuid, text, text) is
  'Awards XP only for a server-validated correct local challenge; idempotent per session position.';
