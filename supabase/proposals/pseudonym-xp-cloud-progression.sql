-- PROPOSTA ATINA: progressão na nuvem sem contas.
-- Não aplicar em produção sem aprovação específica. O cliente nunca envia valores de XP:
-- a RPC só credita XP após confirmar no servidor uma ronda correta e fechada.

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
  unique (player_id, session_id, challenge_position)
);

create index if not exists atina_players_leaderboard_idx
  on private.atina_players (total_xp desc, total_challenges desc, created_at asc);

alter table private.atina_players enable row level security;
alter table private.atina_xp_events enable row level security;
revoke all on schema private from public, anon, authenticated;
revoke all on table private.atina_players, private.atina_xp_events from public, anon, authenticated;

create or replace function public.atina_progress_register(p_nickname text, p_device_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player private.atina_players;
  v_hash bytea;
begin
  if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 20
     or p_nickname !~ '^[[:alnum:]À-ÿ _.-]{1,20}$' then
    raise exception 'Pseudónimo inválido (1 a 20 caracteres).' using errcode = '22023';
  end if;
  if p_device_token is null or p_device_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Identificador de dispositivo inválido.' using errcode = '22023';
  end if;

  v_hash := extensions.digest(convert_to(p_device_token, 'UTF8'), 'sha256');
  insert into private.atina_players (device_token_hash, nickname)
  values (v_hash, btrim(p_nickname))
  on conflict (device_token_hash) do update
    set nickname = excluded.nickname, updated_at = clock_timestamp()
  returning * into v_player;

  return jsonb_build_object(
    'player_id', v_player.id,
    'nickname', v_player.nickname,
    'xp', v_player.total_xp,
    'level', floor(v_player.total_xp / 250.0)::integer + 1,
    'total_challenges', v_player.total_challenges,
    'daily_count', case when v_player.daily_date = current_date then v_player.daily_count else 0 end
  );
end;
$$;

create or replace function public.atina_progress_claim_local(
  p_device_token text,
  p_session_id uuid,
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
  v_inserted bigint;
  v_today date := current_date;
  v_daily_count integer;
  v_daily_bonus integer := 0;
begin
  if p_device_token is null or p_device_token !~ '^[0-9a-f]{64}$'
     or p_session_id is null or p_position is null or p_position < 1 then
    raise exception 'Pedido de progressão inválido.' using errcode = '22023';
  end if;

  select * into v_player
  from private.atina_players
  where device_token_hash = extensions.digest(convert_to(p_device_token, 'UTF8'), 'sha256')
  for update;
  if not found then
    raise exception 'Regista primeiro o teu pseudónimo.' using errcode = '28000';
  end if;

  select * into v_session
  from private.atina_v2_local_sessions
  where id = p_session_id
    and position = p_position
    and round_locked
    and last_result ->> 'outcome' = 'correct'
    and expires_at > clock_timestamp();
  if not found then
    raise exception 'O servidor ainda não confirmou este desafio como concluído.' using errcode = '55000';
  end if;

  insert into private.atina_xp_events (player_id, session_id, challenge_position, xp)
  values (v_player.id, p_session_id, p_position, 10)
  on conflict (player_id, session_id, challenge_position) do nothing
  returning id into v_inserted;

  if v_inserted is null then
    return jsonb_build_object(
      'awarded', false, 'reason', 'already_claimed',
      'xp', v_player.total_xp,
      'level', floor(v_player.total_xp / 250.0)::integer + 1,
      'total_challenges', v_player.total_challenges
    );
  end if;

  v_daily_count := case when v_player.daily_date = v_today then v_player.daily_count + 1 else 1 end;
  if v_daily_count >= 3 and v_player.daily_reward_date is distinct from v_today then
    v_daily_bonus := 50;
  end if;

  update private.atina_players
  set total_xp = total_xp + 10 + v_daily_bonus,
      total_challenges = total_challenges + 1,
      daily_date = v_today,
      daily_count = least(v_daily_count, 3),
      daily_reward_date = case when v_daily_bonus > 0 then v_today else daily_reward_date end,
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

create or replace function public.atina_progress_leaderboard(p_limit integer default 50)
returns table(nickname text, xp integer, level integer, challenges integer)
language sql
stable
security definer
set search_path = ''
as $$
  select p.nickname, p.total_xp, floor(p.total_xp / 250.0)::integer + 1, p.total_challenges
  from private.atina_players p
  order by p.total_xp desc, p.total_challenges desc, p.created_at asc
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$$;

revoke all on function public.atina_progress_register(text, text) from public, authenticated;
revoke all on function public.atina_progress_claim_local(text, uuid, integer) from public, authenticated;
revoke all on function public.atina_progress_leaderboard(integer) from public, authenticated;
grant execute on function public.atina_progress_register(text, text) to anon;
grant execute on function public.atina_progress_claim_local(text, uuid, integer) to anon;
grant execute on function public.atina_progress_leaderboard(integer) to anon;

comment on table private.atina_players is
  'Progressão ATINA associada a pseudónimo e token aleatório de dispositivo; sem conta Supabase Auth.';
comment on table private.atina_xp_events is
  'Eventos de XP idempotentes, apenas para rondas corretas validadas pelo servidor.';
