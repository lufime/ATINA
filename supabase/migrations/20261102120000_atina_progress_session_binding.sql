-- Bind pseudonymous XP to the player selected when an individual game session starts.
-- ATINA pseudonym cloud progression with session-time player binding.
-- Installs the cloud progression RPCs and binds Solo/Mix sessions at creation.
-- The client never sends XP or points.
--
-- Pré-requisitos:
--   * private.atina_v2_local_sessions já existe.
--   * extensions.digest (pgcrypto) está disponível.
--   * As funções são propriedade de um role confiável com acesso às tabelas privadas.

create table if not exists private.atina_players (
  id uuid primary key default gen_random_uuid(),
  device_token_hash bytea not null unique,
  nickname text not null check (char_length(btrim(nickname)) between 1 and 20),
  total_xp integer not null default 0 check (total_xp >= 0),
  total_challenges integer not null default 0 check (total_challenges >= 0),
  daily_date date,
  daily_count integer not null default 0 check (daily_count between 0 and 3),
  daily_reward_date date,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table if not exists private.atina_xp_events (
  id bigint generated always as identity primary key,
  player_id uuid not null references private.atina_players(id) on delete cascade,
  session_id uuid not null,
  challenge_position integer not null check (challenge_position > 0),
  xp integer not null check (xp = 10),
  created_at timestamptz not null default clock_timestamp(),
  constraint atina_xp_events_once_per_challenge
    unique (player_id, session_id, challenge_position)
);

-- A local game session is attributed to one pseudonymous profile only.
-- This prevents a second device identity from claiming the same session's XP.
create table if not exists private.atina_xp_session_owners (
  session_id uuid primary key,
  player_id uuid not null references private.atina_players(id) on delete cascade,
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists atina_players_leaderboard_idx
  on private.atina_players (total_xp desc, total_challenges desc, created_at asc);

alter table private.atina_players enable row level security;
alter table private.atina_xp_events enable row level security;
alter table private.atina_xp_session_owners enable row level security;

-- Restrict only these tables. Do not revoke USAGE on schema private globally.
revoke all on table
  private.atina_players,
  private.atina_xp_events,
  private.atina_xp_session_owners
from public, anon, authenticated;

create or replace function public.atina_progress_register(
  p_nickname text,
  p_device_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player private.atina_players;
  v_hash bytea;
begin
  if p_nickname is null
     or char_length(btrim(p_nickname)) not between 1 and 20
     or p_nickname !~ '^[[:alnum:]À-ÿ _.-]{1,20}$' then
    raise exception 'Pseudónimo inválido (1 a 20 caracteres).'
      using errcode = '22023';
  end if;

  if p_device_token is null
     or p_device_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Identificador de dispositivo inválido.'
      using errcode = '22023';
  end if;

  v_hash := extensions.digest(convert_to(p_device_token, 'UTF8'), 'sha256');

  insert into private.atina_players (device_token_hash, nickname)
  values (v_hash, btrim(p_nickname))
  on conflict (device_token_hash) do update
    set nickname = excluded.nickname,
        updated_at = clock_timestamp()
  returning * into v_player;

  return jsonb_build_object(
    'player_id', v_player.id,
    'nickname', v_player.nickname,
    'xp', v_player.total_xp,
    'level', floor(v_player.total_xp / 250.0)::integer + 1,
    'total_challenges', v_player.total_challenges,
    'daily_count',
      case when v_player.daily_date = current_date
        then v_player.daily_count else 0 end
  );
end;
$$;

create or replace function public.atina_progress_claim_local(
  p_device_token text,
  p_session_id uuid,
  p_session_token text,
  p_position integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player private.atina_players;
  v_session private.atina_v2_local_sessions;
  v_owner private.atina_xp_session_owners;
  v_inserted bigint;
  v_today date := current_date;
  v_daily_count integer;
  v_daily_bonus integer := 0;
begin
  if p_device_token is null
     or p_device_token !~ '^[0-9a-f]{64}$'
     or p_session_id is null
     or p_session_token is null
     or p_session_token !~ '^[0-9a-f]{64}$'
     or p_position is null
     or p_position < 1 then
    raise exception 'Pedido de progressão inválido.'
      using errcode = '22023';
  end if;

  -- Serialize simultaneous claims for the same pseudonymous player.
  select *
    into v_player
    from private.atina_players
   where device_token_hash =
     extensions.digest(convert_to(p_device_token, 'UTF8'), 'sha256')
   for update;

  if not found then
    raise exception 'Regista primeiro o teu pseudónimo.'
      using errcode = '28000';
  end if;

  -- Lock the session while checking its authoritative final-round state.
  select *
    into v_session
    from private.atina_v2_local_sessions
   where id = p_session_id
     and token_hash =
       extensions.digest(convert_to(p_session_token, 'UTF8'), 'sha256')
   for update;

  if not found
     or v_session.position <> p_position
     or not v_session.round_locked
     or v_session.last_result ->> 'outcome' is distinct from 'correct'
     or v_session.expires_at <= clock_timestamp() then
    raise exception 'O servidor ainda não confirmou este desafio como concluído.'
      using errcode = '55000';
  end if;

  -- Ownership was fixed by the server when the individual session started.
  select *
    into v_owner
    from private.atina_xp_session_owners
   where session_id = p_session_id
   for update;

  if not found or v_owner.player_id <> v_player.id then
    raise exception 'Esta sessão não está associada a este perfil.'
      using errcode = '42501';
  end if;

  insert into private.atina_xp_events (
    player_id, session_id, challenge_position, xp
  )
  values (v_player.id, p_session_id, p_position, 10)
  on conflict (player_id, session_id, challenge_position) do nothing
  returning id into v_inserted;

  if v_inserted is null then
    return jsonb_build_object(
      'awarded', false,
      'reason', 'already_claimed',
      'xp', v_player.total_xp,
      'level', floor(v_player.total_xp / 250.0)::integer + 1,
      'total_challenges', v_player.total_challenges,
      'daily_count',
        case when v_player.daily_date = v_today
          then v_player.daily_count else 0 end
    );
  end if;

  v_daily_count :=
    case when v_player.daily_date = v_today
      then v_player.daily_count + 1 else 1 end;

  if v_daily_count >= 3
     and v_player.daily_reward_date is distinct from v_today then
    v_daily_bonus := 50;
  end if;

  update private.atina_players
     set total_xp = total_xp + 10 + v_daily_bonus,
         total_challenges = total_challenges + 1,
         daily_date = v_today,
         daily_count = least(v_daily_count, 3),
         daily_reward_date =
           case when v_daily_bonus > 0 then v_today
                else daily_reward_date end,
         updated_at = clock_timestamp()
   where id = v_player.id
  returning * into v_player;

  return jsonb_build_object(
    'awarded', true,
    'challenge_xp', 10,
    'daily_bonus', v_daily_bonus,
    'xp', v_player.total_xp,
    'level', floor(v_player.total_xp / 250.0)::integer + 1,
    'total_challenges', v_player.total_challenges,
    'daily_count', v_player.daily_count
  );
end;
$$;

create or replace function public.atina_progress_leaderboard(
  p_limit integer default 50
)
returns table (
  nickname text,
  xp integer,
  level integer,
  challenges integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.nickname,
    p.total_xp,
    floor(p.total_xp / 250.0)::integer + 1,
    p.total_challenges
  from private.atina_players p
  order by p.total_xp desc, p.total_challenges desc, p.created_at asc
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$$;

-- SECURITY DEFINER functions are not executable by PUBLIC or authenticated.
revoke all on function public.atina_progress_register(text, text)
  from public, authenticated;
revoke all on function public.atina_progress_claim_local(text, uuid, text, integer)
  from public, authenticated;
revoke all on function public.atina_progress_leaderboard(integer)
  from public, authenticated;

grant execute on function public.atina_progress_register(text, text) to anon;
grant execute on function public.atina_progress_claim_local(text, uuid, text, integer) to anon;
grant execute on function public.atina_progress_leaderboard(integer) to anon;

comment on table private.atina_players is
  'Progressão ATINA por pseudónimo e token aleatório de dispositivo; sem conta Supabase Auth.';
comment on table private.atina_xp_events is
  'Eventos de XP idempotentes, apenas para rondas corretas confirmadas pelo servidor.';
comment on table private.atina_xp_session_owners is
  'Associa cada sessão local a um único perfil pseudónimo para impedir claims cruzados.';
comment on function public.atina_progress_claim_local(text, uuid, text, integer) is
  'Atribui 10 XP apenas após confirmar uma ronda correta, fechada e não expirada.';


drop function if exists public.atina_v2_start_local_game(text, text, text, integer);
drop function if exists public.atina_v2_start_local_game(text, text, text, integer, text);
create or replace function public.atina_v2_start_local_game(
  p_game_mode text,
  p_difficulty text,
  p_category text default null,
  p_timed_mode_seconds integer default 60,
  p_device_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_queue integer[];
  v_session private.atina_v2_local_sessions;
  v_player_id uuid;
begin
  if p_game_mode is null or p_game_mode not in ('solo','duel','mix','party') then
    raise exception 'Modo inválido.' using errcode='22023';
  end if;
  if p_difficulty is null or p_difficulty not in ('easy','medium','hard') then
    raise exception 'Dificuldade inválida.' using errcode='22023';
  end if;
  if p_timed_mode_seconds is null or p_timed_mode_seconds not between 0 and 3600 then
    raise exception 'Duração inválida.' using errcode='22023';
  end if;
  if p_category is not null and length(trim(p_category))=0 then
    raise exception 'Categoria inválida.' using errcode='22023';
  end if;

  if p_device_token is not null then
    if p_game_mode not in ('solo','mix') then
      raise exception 'A progressão individual só está disponível em Solo e Mix.'
        using errcode='22023';
    end if;
    if p_device_token !~ '^[0-9a-f]{64}$' then
      raise exception 'Identificador de dispositivo inválido.' using errcode='22023';
    end if;
    select id into v_player_id
      from private.atina_players
     where device_token_hash=extensions.digest(convert_to(p_device_token,'UTF8'),'sha256');
    if v_player_id is null then
      raise exception 'Regista primeiro o teu pseudónimo.' using errcode='28000';
    end if;
  end if;

  select array_agg(c.challenge_id order by random()) into v_queue
  from private.atina_challenges c
  where c.active and c.difficulty=p_difficulty
    and (p_category is null or c.category=p_category);
  if coalesce(cardinality(v_queue),0)=0 then
    raise exception 'Não existem desafios para estes critérios.' using errcode='22023';
  end if;
  if p_game_mode='party' then
    v_queue:=v_queue[1:least(10,cardinality(v_queue))];
  end if;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into private.atina_v2_local_sessions (
    token_hash,game_mode,difficulty,category,timed_mode_seconds,
    challenge_queue,position,revealed_clues,current_player,scores,streaks,
    round_context,deadline_at,expires_at,special_card
  ) values (
    extensions.digest(convert_to(v_token,'UTF8'),'sha256'),
    p_game_mode,p_difficulty,p_category,p_timed_mode_seconds,
    v_queue,1,1,1,array[0,0],array[0,0],'{}'::jsonb,
    case when p_timed_mode_seconds=0 then null
      else clock_timestamp()+make_interval(secs=>p_timed_mode_seconds) end,
    clock_timestamp()+interval '8 hours',null
  ) returning * into v_session;

  if v_player_id is not null then
    insert into private.atina_xp_session_owners(session_id,player_id)
    values(v_session.id,v_player_id);
  end if;

  return jsonb_build_object(
    'token',v_token,
    'state',private.atina_v2_local_public_state(v_session)
  );
end;
$$;

revoke all on function public.atina_v2_start_local_game(text, text, text, integer, text) from public;
grant execute on function public.atina_v2_start_local_game(text, text, text, integer, text) to anon, authenticated;
comment on function public.atina_v2_start_local_game(text, text, text, integer, text) is
  'Starts an authoritative game session and binds optional pseudonymous XP ownership at session creation.';
