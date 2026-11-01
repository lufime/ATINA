-- Compatibility layer for atina-ranking's existing schema.
-- All local-session objects and RPCs are versioned; legacy RPC names are untouched.
-- This migration is additive and must be applied only after a separately tested
-- migration-history/baseline procedure. It does not run on any remote project here.

do $preflight$
begin
  if to_regclass('private.atina_challenges') is null then
    raise exception 'Missing private.atina_challenges; install/verify the private challenge catalogue first.';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema='private' and table_name='atina_challenges'
      and column_name='difficulty'
  ) then
    raise exception 'private.atina_challenges.difficulty is required; refusing implicit table alteration.';
  end if;
  if to_regclass('private.atina_v2_local_sessions') is not null then
    raise exception 'private.atina_v2_local_sessions already exists; inspect before applying.';
  end if;
end
$preflight$;

-- Private answer matching helpers (v2 namespace).
-- PROPOSTA (não aplicar diretamente): validação de respostas no servidor.
-- Requer a tabela private.atina_challenges criada pela proposta 001 e carregada
-- exclusivamente por um canal privado. Não expõe uma RPC que permita testar
-- respostas arbitrárias; estes helpers destinam-se apenas a outras RPCs SECURITY DEFINER.

create or replace function private.atina_v2_atina_normalize_answer(p_value text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select trim(regexp_replace(
    regexp_replace(
      regexp_replace(normalize(lower(p_value), NFD), '[̀-ͯ]', '', 'g'),
      '[^a-z0-9 ]+', '', 'g'
    ),
    '[[:space:]]+', ' ', 'g'
  ));
$$;
create or replace function private.atina_v2_atina_levenshtein_bounded(p_left text, p_right text)
returns integer
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  v_left_len integer := char_length(p_left);
  v_right_len integer := char_length(p_right);
  v_prev integer[];
  v_curr integer[];
  v_cost integer;
  v_row_min integer;
begin
  if abs(v_left_len - v_right_len) > 2 then return 3; end if;
  v_prev := array_fill(0, array[v_right_len + 1]);
  for j in 1..v_right_len loop v_prev[j + 1] := j; end loop;
  for i in 1..v_left_len loop
    v_curr := array_fill(0, array[v_right_len + 1]);
    v_curr[1] := i;
    v_row_min := i;
    for j in 1..v_right_len loop
      v_cost := case when substr(p_left, i, 1) = substr(p_right, j, 1) then 0 else 1 end;
      v_curr[j + 1] := least(v_curr[j] + 1, v_prev[j + 1] + 1, v_prev[j] + v_cost);
      v_row_min := least(v_row_min, v_curr[j + 1]);
    end loop;
    if v_row_min > 2 then return 3; end if;
    v_prev := v_curr;
  end loop;
  return v_prev[v_right_len + 1];
end;
$$;

create or replace function private.atina_v2_atina_answer_matches(p_expected text, p_actual text)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  v_expected text := private.atina_v2_atina_normalize_answer(p_expected);
  v_actual text := private.atina_v2_atina_normalize_answer(p_actual);
  v_words_expected text[];
  v_words_actual text[];
  v_used boolean[];
  v_best integer;
  v_best_distance integer;
  v_distance integer;
  v_allowed integer;
begin
  if v_expected = '' or v_actual = '' then return false; end if;
  if v_expected = v_actual then return true; end if;
  v_words_expected := string_to_array(v_expected, ' ');
  v_words_actual := string_to_array(v_actual, ' ');
  if cardinality(v_words_expected) <> cardinality(v_words_actual) then return false; end if;
  v_used := array_fill(false, array[cardinality(v_words_actual)]);
  for i in 1..cardinality(v_words_expected) loop
    v_best := 0;
    v_best_distance := 3;
    for j in 1..cardinality(v_words_actual) loop
      if not v_used[j] then
        v_distance := private.atina_v2_atina_levenshtein_bounded(v_words_expected[i], v_words_actual[j]);
        if v_distance < v_best_distance then
          v_best_distance := v_distance;
          v_best := j;
        end if;
      end if;
    end loop;
    v_allowed := case
      when char_length(v_words_expected[i]) >= 8 then 2
      when char_length(v_words_expected[i]) >= 4 then 1
      else 0
    end;
    if v_best = 0 or v_best_distance > v_allowed then return false; end if;
    v_used[v_best] := true;
  end loop;
  return true;
end;
$$;

create or replace function private.atina_v2_atina_challenge_answer_matches(p_challenge_id integer, p_answer text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.atina_challenges c
    where c.challenge_id = p_challenge_id
      and c.active
      and (
        private.atina_v2_atina_answer_matches(c.answer, p_answer)
        or exists (
          select 1
          from jsonb_array_elements_text(c.accepted_answers) accepted(answer)
          where private.atina_v2_atina_answer_matches(accepted.answer, p_answer)
        )
      )
  );
$$;

revoke all on function private.atina_v2_atina_normalize_answer(text) from public, anon, authenticated;
revoke all on function private.atina_v2_atina_levenshtein_bounded(text, text) from public, anon, authenticated;
revoke all on function private.atina_v2_atina_answer_matches(text, text) from public, anon, authenticated;
revoke all on function private.atina_v2_atina_challenge_answer_matches(integer, text) from public, anon, authenticated;

comment on function private.atina_v2_atina_challenge_answer_matches(integer, text) is
  'Internal-only answer check for authoritative game RPCs; never grant EXECUTE to API roles.';

-- New isolated local-session store (v2 namespace).
-- PROPOSTA (não aplicar diretamente): sessões autoritativas para modos locais online.
-- A tabela guarda apenas estado de jogo e IDs; nunca devolver a chave privada de respostas.
-- A implementação das RPCs e os testes transacionais serão adicionados após revisão.

create table if not exists private.atina_v2_local_sessions (
  id uuid primary key default gen_random_uuid(),
  token_hash bytea not null unique,
  game_mode text not null
    check (game_mode in ('solo', 'duel', 'mix', 'party')),
  difficulty text not null
    check (difficulty in ('easy', 'medium', 'hard')),
  category text,
  timed_mode_seconds integer not null default 60
    check (timed_mode_seconds between 0 and 3600),
  challenge_queue integer[] not null
    check (cardinality(challenge_queue) > 0),
  position integer not null default 1
    check (position >= 1),
  revealed_clues integer not null default 1
    check (revealed_clues between 1 and 6),
  current_player smallint not null default 1
    check (current_player in (1, 2)),
  scores integer[] not null default array[0, 0]::integer[],
  streaks integer[] not null default array[0, 0]::integer[],
  round_context jsonb not null default '{}'::jsonb,
  deadline_at timestamptz,
  status text not null default 'active'
    check (status in ('active', 'completed', 'abandoned', 'expired')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  check (position <= cardinality(challenge_queue)),
  check (cardinality(scores) = 2),
  check (cardinality(streaks) = 2)
);

create index if not exists atina_v2_local_sessions_expiry_idx
  on private.atina_v2_local_sessions (expires_at)
  where status = 'active';

alter table private.atina_v2_local_sessions enable row level security;
revoke all on table private.atina_v2_local_sessions from public, anon, authenticated;

comment on table private.atina_v2_local_sessions is
  'Authoritative state for online solo, duel, mix and party games; never expose through the Data API.';

-- RPCs planeadas (todas validam token_hash, estado e deadline no servidor):
-- atina_v2_start_local_game(...) -> session_id, token, estado público do desafio atual
-- atina_v2_local_game_state(session_id, token) -> estado persistido + pistas públicas
-- atina_v2_local_reveal_clue(session_id, token) -> avança uma pista
-- atina_v2_local_submit_answer(session_id, token, answer) -> valida, calcula e grava pontuação
-- atina_v2_local_pass_challenge(session_id, token) -> fecha ronda e só então revela solução
-- atina_v2_local_next_challenge(session_id, token) -> avança ou conclui a sessão
-- A implementação deve ainda validar os bónus atuais, a meta de 250 pontos e as regras de cada modo.

-- New token-authenticated local-game RPCs (v2 namespace).
-- PROPOSTA (não aplicar diretamente): sessões online autoritativas para Individual e Duelo.
-- Requer 001-private-challenges-table.sql e 003-server-answer-matching.sql.
-- A coluna difficulty tem de ser preenchida no carregamento privado dos desafios.
-- Não executar em produção. Testes e validação em Supabase de desenvolvimento são obrigatórios.

alter table private.atina_v2_local_sessions
  add column if not exists round_locked boolean not null default false,
  add column if not exists answered_count integer not null default 0,
  add column if not exists special_card jsonb,
  add column if not exists last_result jsonb not null default '{}'::jsonb;

create index if not exists atina_v2_challenges_local_selection_idx
  on private.atina_challenges (difficulty, category, challenge_id)
  where active;

-- Payload público: só devolve pistas já reveladas. Nunca inclui answer/accepted_answers.
create or replace function private.atina_v2_local_public_state(p_session private.atina_v2_local_sessions)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'session_id', p_session.id,
    'mode', p_session.game_mode,
    'difficulty', p_session.difficulty,
    'category_filter', p_session.category,
    'scores', to_jsonb(p_session.scores),
    'streaks', to_jsonb(p_session.streaks),
    'current_player', p_session.current_player,
    'position', p_session.position,
    'queue_size', cardinality(p_session.challenge_queue),
    'answered_count', p_session.answered_count,
    'round_locked', p_session.round_locked,
    'status', p_session.status,
    'deadline_at', p_session.deadline_at,
    'special_card', p_session.special_card,
    'last_result', p_session.last_result,
    'challenge', (
      select jsonb_build_object(
        'id', c.challenge_id,
        'category', c.category,
        'emoji', c.emoji,
        'image_url', c.image_url,
        'total_clues', jsonb_array_length(c.clues),
        'clues', (
          select coalesce(jsonb_agg(cl.value order by cl.ordinality), '[]'::jsonb)
          from jsonb_array_elements(c.clues) with ordinality cl(value, ordinality)
          where cl.ordinality <= p_session.revealed_clues
        ),
        'answer', case when p_session.round_locked then c.answer else null end
      )
      from private.atina_challenges c
      where c.challenge_id = p_session.challenge_queue[p_session.position]
        and c.active
    )
  );
$$;

-- Inicia Individual, Duelo ou Mix. No Mix, categoria NULL seleciona desafios de todas as modalidades.
create or replace function public.atina_v2_start_local_game(
  p_game_mode text,
  p_difficulty text,
  p_category text default null,
  p_timed_mode_seconds integer default 60
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
  v_card jsonb;
begin
  if p_game_mode is null or p_game_mode not in ('solo', 'duel', 'mix') then
    raise exception 'Modo inválido nesta versão.' using errcode = '22023';
  end if;
  if p_difficulty is null or p_difficulty not in ('easy', 'medium', 'hard') then
    raise exception 'Dificuldade inválida.' using errcode = '22023';
  end if;
  if p_timed_mode_seconds is null or p_timed_mode_seconds not between 0 and 3600 then
    raise exception 'Duração inválida.' using errcode = '22023';
  end if;
  if p_category is not null and length(trim(p_category)) = 0 then
    raise exception 'Categoria inválida.' using errcode = '22023';
  end if;

  select array_agg(c.challenge_id order by random())
    into v_queue
  from private.atina_challenges c
  where c.active
    and c.difficulty = p_difficulty
    and (p_category is null or c.category = p_category);

  if coalesce(cardinality(v_queue), 0) = 0 then
    raise exception 'Não existem desafios para estes critérios.' using errcode = '22023';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_card := null; -- O primeiro desafio não recebe carta especial (compatível com pos % 3 = 2 no cliente).

  insert into private.atina_v2_local_sessions (
    token_hash, game_mode, difficulty, category, timed_mode_seconds,
    challenge_queue, position, revealed_clues, current_player, scores, streaks,
    round_context, deadline_at, expires_at, special_card
  ) values (
    extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'),
    p_game_mode, p_difficulty, p_category, p_timed_mode_seconds,
    v_queue, 1, 1, 1, array[0,0], array[0,0],
    '{}'::jsonb,
    case when p_timed_mode_seconds = 0 then null
      else clock_timestamp() + make_interval(secs => p_timed_mode_seconds) end,
    clock_timestamp() + interval '8 hours',
    v_card
  )
  returning * into v_session;

  return jsonb_build_object('token', v_token, 'state', private.atina_v2_local_public_state(v_session));
end;
$$;

create or replace function public.atina_v2_local_game_state(p_session_id uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_session private.atina_v2_local_sessions;
begin
  select * into v_session
  from private.atina_v2_local_sessions
  where id = p_session_id
    and token_hash = extensions.digest(convert_to(p_token, 'UTF8'), 'sha256')
  for update;

  if not found or v_session.expires_at <= clock_timestamp() then
    raise exception 'Sessão inválida ou expirada.' using errcode = '28000';
  end if;
  if v_session.status = 'active' and not v_session.round_locked
     and v_session.deadline_at is not null and v_session.deadline_at <= clock_timestamp() then
    v_session.scores[v_session.current_player] := v_session.scores[v_session.current_player] - 10;
    v_session.streaks[v_session.current_player] := 0;
    v_session.round_locked := true;
    v_session.answered_count := v_session.answered_count + 1;
    v_session.last_result := jsonb_build_object('outcome','timeout','penalty',10);
    update private.atina_v2_local_sessions
      set scores=v_session.scores, streaks=v_session.streaks, round_locked=true,
          answered_count=v_session.answered_count, last_result=v_session.last_result,
          updated_at=clock_timestamp()
      where id=v_session.id
      returning * into v_session;
  end if;
  return private.atina_v2_local_public_state(v_session);
end;
$$;

create or replace function public.atina_v2_local_reveal_clue(p_session_id uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_session private.atina_v2_local_sessions; v_total integer;
begin
  select * into v_session from private.atina_v2_local_sessions
  where id=p_session_id
    and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
  for update;
  if not found or v_session.expires_at <= clock_timestamp() then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  if v_session.status <> 'active' or v_session.round_locked then
    raise exception 'A ronda não está ativa.' using errcode='55000';
  end if;
  if v_session.deadline_at is not null and v_session.deadline_at <= clock_timestamp() then
    raise exception 'Tempo esgotado; atualiza o estado da sessão.' using errcode='55000';
  end if;
  select jsonb_array_length(clues) into v_total
  from private.atina_challenges
  where challenge_id=v_session.challenge_queue[v_session.position] and active;
  if v_session.revealed_clues >= v_total then
    return private.atina_v2_local_public_state(v_session);
  end if;
  update private.atina_v2_local_sessions
    set revealed_clues=revealed_clues+1, updated_at=clock_timestamp()
    where id=v_session.id
    returning * into v_session;
  return private.atina_v2_local_public_state(v_session);
end;
$$;

create or replace function public.atina_v2_local_submit_answer(
  p_session_id uuid, p_token text, p_answer text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session private.atina_v2_local_sessions;
  v_correct boolean;
  v_now timestamptz;
  v_base integer;
  v_speed integer := 0;
  v_streak integer;
  v_streak_bonus integer := 0;
  v_multiplier integer := 1;
  v_bonus integer := 0;
  v_points integer;
  v_winner integer := null;
begin
  if p_answer is null or length(trim(p_answer))=0 or length(p_answer)>300 then
    raise exception 'Resposta vazia ou demasiado longa.' using errcode='22023';
  end if;
  select * into v_session from private.atina_v2_local_sessions
  where id=p_session_id
    and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
  for update;
  if not found then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  -- Obter a hora depois do FOR UPDATE: evita aceitar uma resposta com deadline
  -- já expirado enquanto a chamada aguardava pelo lock da sessão.
  v_now := clock_timestamp();
  if v_session.expires_at <= v_now then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  if v_session.status <> 'active' or v_session.round_locked then
    raise exception 'A ronda já foi fechada.' using errcode='55000';
  end if;
  if v_session.deadline_at is not null and v_session.deadline_at <= v_now then
    v_session.scores[v_session.current_player] := v_session.scores[v_session.current_player]-10;
    v_session.streaks[v_session.current_player] := 0;
    v_session.round_locked := true;
    v_session.answered_count := v_session.answered_count+1;
    v_session.last_result := jsonb_build_object('outcome','timeout','penalty',10);
    update private.atina_v2_local_sessions set scores=v_session.scores, streaks=v_session.streaks,
      round_locked=true, answered_count=v_session.answered_count, last_result=v_session.last_result,
      updated_at=v_now where id=v_session.id returning * into v_session;
    return private.atina_v2_local_public_state(v_session);
  end if;

  v_correct := private.atina_v2_atina_challenge_answer_matches(
    v_session.challenge_queue[v_session.position], p_answer
  );
  if not v_correct then
    v_session.scores[v_session.current_player] := v_session.scores[v_session.current_player]-10;
    v_session.streaks[v_session.current_player] := 0;
    v_session.last_result := jsonb_build_object('outcome','wrong','penalty',10);
    update private.atina_v2_local_sessions set scores=v_session.scores, streaks=v_session.streaks,
      last_result=v_session.last_result, updated_at=v_now
      where id=v_session.id returning * into v_session;
    return private.atina_v2_local_public_state(v_session);
  end if;

  v_base := case v_session.difficulty when 'easy' then 10 when 'hard' then 20 else 15 end;
  if v_session.deadline_at is not null then
    -- O frontend original aplica ceil() aos segundos restantes antes de floor(segundos/10).
    v_speed := greatest(0, floor(ceil(extract(epoch from (v_session.deadline_at-v_now)))/10)::integer);
  end if;
  v_streak := v_session.streaks[v_session.current_player]+1;
  if v_streak >= 2 then v_streak_bonus := least(15,(v_streak-1)*5); end if;
  if v_session.special_card is not null then
    v_multiplier := coalesce((v_session.special_card->>'multiplier')::integer,1);
    v_bonus := coalesce((v_session.special_card->>'bonus')::integer,0);
  end if;
  v_points := (v_base+v_speed+v_streak_bonus)*v_multiplier+v_bonus;
  v_session.scores[v_session.current_player] := v_session.scores[v_session.current_player]+v_points;
  v_session.streaks[v_session.current_player] := v_streak;
  v_session.round_locked := true;
  v_session.answered_count := v_session.answered_count+1;
  if v_session.scores[v_session.current_player] >= 250 then
    v_session.status := 'completed';
    v_winner := v_session.current_player;
  end if;
  v_session.last_result := jsonb_build_object(
    'outcome','correct','base_points',v_base,'speed_bonus',v_speed,
    'streak_bonus',v_streak_bonus,'special_multiplier',v_multiplier,
    'special_bonus',v_bonus,'points',v_points,'winner',v_winner
  );
  update private.atina_v2_local_sessions set scores=v_session.scores, streaks=v_session.streaks,
    round_locked=true, answered_count=v_session.answered_count, status=v_session.status,
    last_result=v_session.last_result, updated_at=v_now
    where id=v_session.id returning * into v_session;
  return private.atina_v2_local_public_state(v_session);
end;
$$;

create or replace function public.atina_v2_local_pass_challenge(p_session_id uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_session private.atina_v2_local_sessions;
begin
  select * into v_session from private.atina_v2_local_sessions
  where id=p_session_id
    and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
  for update;
  if not found or v_session.expires_at <= clock_timestamp() then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  if v_session.status <> 'active' or v_session.round_locked then
    raise exception 'A ronda já foi fechada.' using errcode='55000';
  end if;
  if v_session.deadline_at is not null and v_session.deadline_at <= clock_timestamp() then
    v_session.scores[v_session.current_player] := v_session.scores[v_session.current_player]-10;
    v_session.streaks[v_session.current_player] := 0;
    v_session.round_locked := true;
    v_session.answered_count := v_session.answered_count+1;
    v_session.last_result := jsonb_build_object('outcome','timeout','penalty',10);
    update private.atina_v2_local_sessions set scores=v_session.scores, streaks=v_session.streaks,
      round_locked=true, answered_count=v_session.answered_count, last_result=v_session.last_result,
      updated_at=clock_timestamp() where id=v_session.id returning * into v_session;
    return private.atina_v2_local_public_state(v_session);
  end if;
  v_session.streaks[v_session.current_player] := 0;
  v_session.round_locked := true;
  v_session.answered_count := v_session.answered_count+1;
  v_session.last_result := jsonb_build_object('outcome','pass');
  update private.atina_v2_local_sessions set streaks=v_session.streaks, round_locked=true,
    answered_count=v_session.answered_count, last_result=v_session.last_result,
    updated_at=clock_timestamp() where id=v_session.id returning * into v_session;
  return private.atina_v2_local_public_state(v_session);
end;
$$;

create or replace function public.atina_v2_local_next_challenge(p_session_id uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session private.atina_v2_local_sessions;
  v_queue integer[];
  v_next_position integer;
  v_card jsonb;
  v_now timestamptz;
begin
  select * into v_session from private.atina_v2_local_sessions
  where id=p_session_id
    and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
  for update;
  if not found then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  -- A hora é capturada depois do lock para não prolongar artificialmente a sessão.
  v_now := clock_timestamp();
  if v_session.expires_at <= v_now then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  if v_session.status <> 'active' or not v_session.round_locked then
    raise exception 'Fecha a ronda antes de avançar.' using errcode='55000';
  end if;

  v_next_position := v_session.position+1;
  if v_next_position > cardinality(v_session.challenge_queue) then
    select array_agg(q.challenge_id order by random()) into v_queue
    from unnest(v_session.challenge_queue) as q(challenge_id);
    v_next_position := 1;
  else
    v_queue := v_session.challenge_queue;
  end if;
  if v_session.game_mode='duel' then
    v_session.current_player := 3-v_session.current_player;
  else
    v_session.current_player := 1;
  end if;
  v_card := null;
  if mod(v_next_position-1,3)=2 then
    v_card := case floor(random()*3)::integer
      when 0 then jsonb_build_object('name','PONTOS A DOBRAR','icon','💎','multiplier',2,'bonus',0)
      when 1 then jsonb_build_object('name','BÓNUS SURPRESA','icon','🎁','multiplier',1,'bonus',15)
      else jsonb_build_object('name','PASSE VIP','icon','🃏','multiplier',1,'bonus',10)
    end;
  end if;
  update private.atina_v2_local_sessions set challenge_queue=v_queue, position=v_next_position,
    current_player=v_session.current_player, revealed_clues=1, round_locked=false,
    deadline_at=case when timed_mode_seconds=0 then null
      else v_now+make_interval(secs=>timed_mode_seconds) end,
    special_card=v_card, last_result='{}'::jsonb, updated_at=v_now
    where id=v_session.id returning * into v_session;
  return private.atina_v2_local_public_state(v_session);
end;
$$;

-- API roles só podem chamar as RPCs de sessão. Os helpers privados não são executáveis
-- diretamente por anon/authenticated. O token é uma credencial bearer e não deve ir para URLs/logs.
revoke all on function private.atina_v2_local_public_state(private.atina_v2_local_sessions) from public, anon, authenticated;
revoke all on function public.atina_v2_start_local_game(text,text,text,integer) from public;
revoke all on function public.atina_v2_local_game_state(uuid,text) from public;
revoke all on function public.atina_v2_local_reveal_clue(uuid,text) from public;
revoke all on function public.atina_v2_local_submit_answer(uuid,text,text) from public;
revoke all on function public.atina_v2_local_pass_challenge(uuid,text) from public;
revoke all on function public.atina_v2_local_next_challenge(uuid,text) from public;
grant execute on function public.atina_v2_start_local_game(text,text,text,integer) to anon, authenticated;
grant execute on function public.atina_v2_local_game_state(uuid,text) to anon, authenticated;
grant execute on function public.atina_v2_local_reveal_clue(uuid,text) to anon, authenticated;
grant execute on function public.atina_v2_local_submit_answer(uuid,text,text) to anon, authenticated;
grant execute on function public.atina_v2_local_pass_challenge(uuid,text) to anon, authenticated;
grant execute on function public.atina_v2_local_next_challenge(uuid,text) to anon, authenticated;

comment on function public.atina_v2_local_submit_answer(uuid,text,text) is
  'Recebe apenas a resposta textual; correção, deadline e pontuação são calculados no servidor.';


-- Latest Party-mode overrides, kept in the isolated v2 RPC namespace.
-- PROPOSTA (não aplicar diretamente): suporte do modo Party nas sessões locais.
-- Aplicada apenas em atina-development (qvvlqrgbtjujsejvenld).
-- Preserva as regras observadas no frontend: máximo de 10 desafios e pontos a dobrar
-- na última ronda. Não executar em produção sem revisão e autorização.

create or replace function public.atina_v2_start_local_game(
  p_game_mode text, p_difficulty text, p_category text default null,
  p_timed_mode_seconds integer default 60
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_token text; v_queue integer[]; v_session private.atina_v2_local_sessions;
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
  return jsonb_build_object('token',v_token,'state',private.atina_v2_local_public_state(v_session));
end;
$$;

create or replace function public.atina_v2_local_submit_answer(
  p_session_id uuid,p_token text,p_answer text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_session private.atina_v2_local_sessions;
  v_correct boolean; v_now timestamptz; v_base integer;
  v_speed integer:=0; v_streak integer; v_streak_bonus integer:=0;
  v_multiplier integer:=1; v_bonus integer:=0; v_points integer; v_winner integer:=null;
begin
  if p_answer is null or length(trim(p_answer))=0 or length(p_answer)>300 then
    raise exception 'Resposta vazia ou demasiado longa.' using errcode='22023';
  end if;
  select * into v_session from private.atina_v2_local_sessions
  where id=p_session_id and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
  for update;
  if not found then raise exception 'Sessão inválida ou expirada.' using errcode='28000'; end if;
  v_now:=clock_timestamp();
  if v_session.expires_at<=v_now then raise exception 'Sessão inválida ou expirada.' using errcode='28000'; end if;
  if v_session.status<>'active' or v_session.round_locked then
    raise exception 'A ronda já foi fechada.' using errcode='55000';
  end if;
  if v_session.deadline_at is not null and v_session.deadline_at<=v_now then
    v_session.scores[v_session.current_player]:=v_session.scores[v_session.current_player]-10;
    v_session.streaks[v_session.current_player]:=0; v_session.round_locked:=true;
    v_session.answered_count:=v_session.answered_count+1;
    v_session.last_result:=jsonb_build_object('outcome','timeout','penalty',10);
    update private.atina_v2_local_sessions set scores=v_session.scores,streaks=v_session.streaks,
      round_locked=true,answered_count=v_session.answered_count,last_result=v_session.last_result,
      updated_at=v_now where id=v_session.id returning * into v_session;
    return private.atina_v2_local_public_state(v_session);
  end if;
  v_correct:=private.atina_challenge_answer_matches(v_session.challenge_queue[v_session.position],p_answer);
  if not v_correct then
    v_session.scores[v_session.current_player]:=v_session.scores[v_session.current_player]-10;
    v_session.streaks[v_session.current_player]:=0;
    v_session.last_result:=jsonb_build_object('outcome','wrong','penalty',10);
    update private.atina_v2_local_sessions set scores=v_session.scores,streaks=v_session.streaks,
      last_result=v_session.last_result,updated_at=v_now where id=v_session.id returning * into v_session;
    return private.atina_v2_local_public_state(v_session);
  end if;
  v_base:=case v_session.difficulty when 'easy' then 10 when 'hard' then 20 else 15 end;
  if v_session.deadline_at is not null then
    v_speed:=greatest(0,floor(ceil(extract(epoch from (v_session.deadline_at-v_now)))/10)::integer);
  end if;
  v_streak:=v_session.streaks[v_session.current_player]+1;
  if v_streak>=2 then v_streak_bonus:=least(15,(v_streak-1)*5); end if;
  if v_session.special_card is not null then
    v_multiplier:=coalesce((v_session.special_card->>'multiplier')::integer,1);
    v_bonus:=coalesce((v_session.special_card->>'bonus')::integer,0);
  end if;
  v_points:=(v_base+v_speed+v_streak_bonus)*v_multiplier+v_bonus;
  if v_session.game_mode='party' and v_session.position=cardinality(v_session.challenge_queue) then
    v_points:=v_points*2;
  end if;
  v_session.scores[v_session.current_player]:=v_session.scores[v_session.current_player]+v_points;
  v_session.streaks[v_session.current_player]:=v_streak;
  v_session.round_locked:=true; v_session.answered_count:=v_session.answered_count+1;
  if v_session.scores[v_session.current_player]>=250 then
    v_session.status:='completed'; v_winner:=v_session.current_player;
  end if;
  v_session.last_result:=jsonb_build_object(
    'outcome','correct','base_points',v_base,'speed_bonus',v_speed,
    'streak_bonus',v_streak_bonus,'special_multiplier',v_multiplier,
    'special_bonus',v_bonus,'points',v_points,'winner',v_winner,
    'party_final_round_bonus',v_session.game_mode='party'
      and v_session.position=cardinality(v_session.challenge_queue)
  );
  update private.atina_v2_local_sessions set scores=v_session.scores,streaks=v_session.streaks,
    round_locked=true,answered_count=v_session.answered_count,status=v_session.status,
    last_result=v_session.last_result,updated_at=v_now where id=v_session.id returning * into v_session;
  return private.atina_v2_local_public_state(v_session);
end;
$$;


-- Party alterna as duas equipas, tal como Duelo.
create or replace function public.atina_v2_local_next_challenge(p_session_id uuid,p_token text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_session private.atina_v2_local_sessions;
  v_queue integer[];
  v_next_position integer;
  v_card jsonb;
  v_now timestamptz;
begin
  select * into v_session from private.atina_v2_local_sessions
  where id=p_session_id and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
  for update;
  if not found then raise exception 'Sessão inválida ou expirada.' using errcode='28000'; end if;
  v_now:=clock_timestamp();
  if v_session.expires_at<=v_now then raise exception 'Sessão inválida ou expirada.' using errcode='28000'; end if;
  if v_session.status<>'active' or not v_session.round_locked then
    raise exception 'Fecha a ronda antes de avançar.' using errcode='55000';
  end if;
  v_next_position:=v_session.position+1;
  if v_next_position>cardinality(v_session.challenge_queue) then
    select array_agg(q.challenge_id order by random()) into v_queue
    from unnest(v_session.challenge_queue) as q(challenge_id);
    v_next_position:=1;
  else
    v_queue:=v_session.challenge_queue;
  end if;
  if v_session.game_mode in ('duel','party') then
    v_session.current_player:=3-v_session.current_player;
  else
    v_session.current_player:=1;
  end if;
  v_card:=null;
  if mod(v_next_position-1,3)=2 then
    v_card:=case floor(random()*3)::integer
      when 0 then jsonb_build_object('name','PONTOS A DOBRAR','icon','💎','multiplier',2,'bonus',0)
      when 1 then jsonb_build_object('name','BÓNUS SURPRESA','icon','🎁','multiplier',1,'bonus',15)
      else jsonb_build_object('name','PASSE VIP','icon','🃏','multiplier',1,'bonus',10)
    end;
  end if;
  update private.atina_v2_local_sessions set challenge_queue=v_queue,position=v_next_position,
    current_player=v_session.current_player,revealed_clues=1,round_locked=false,
    deadline_at=case when timed_mode_seconds=0 then null
      else v_now+make_interval(secs=>timed_mode_seconds) end,
    special_card=v_card,last_result='{}'::jsonb,updated_at=v_now
    where id=v_session.id returning * into v_session;
  return private.atina_v2_local_public_state(v_session);
end;
$$;
