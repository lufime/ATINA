-- PROPOSTA (não aplicar diretamente): sessões online autoritativas para Individual e Duelo.
-- Requer 001-private-challenges-table.sql e 003-server-answer-matching.sql.
-- A coluna difficulty tem de ser preenchida no carregamento privado dos desafios.
-- Não executar em produção. Testes e validação em Supabase de desenvolvimento são obrigatórios.

alter table private.atina_challenges
  add column if not exists difficulty text
    check (difficulty in ('easy', 'medium', 'hard'));

alter table private.atina_local_sessions
  add column if not exists round_locked boolean not null default false,
  add column if not exists answered_count integer not null default 0,
  add column if not exists special_card jsonb,
  add column if not exists last_result jsonb not null default '{}'::jsonb;

create index if not exists atina_challenges_local_selection_idx
  on private.atina_challenges (difficulty, category, challenge_id)
  where active;

-- Payload público: só devolve pistas já reveladas. Nunca inclui answer/accepted_answers.
create or replace function private.atina_local_public_state(p_session private.atina_local_sessions)
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

-- Inicia apenas Individual ou Duelo. A fila é criada no servidor e não é escolhida pelo browser.
create or replace function public.atina_start_local_game(
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
  v_session private.atina_local_sessions;
  v_card jsonb;
begin
  if p_game_mode is null or p_game_mode not in ('solo', 'duel') then
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

  insert into private.atina_local_sessions (
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

  return jsonb_build_object('token', v_token, 'state', private.atina_local_public_state(v_session));
end;
$$;

create or replace function public.atina_local_game_state(p_session_id uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_session private.atina_local_sessions;
begin
  select * into v_session
  from private.atina_local_sessions
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
    update private.atina_local_sessions
      set scores=v_session.scores, streaks=v_session.streaks, round_locked=true,
          answered_count=v_session.answered_count, last_result=v_session.last_result,
          updated_at=clock_timestamp()
      where id=v_session.id
      returning * into v_session;
  end if;
  return private.atina_local_public_state(v_session);
end;
$$;

create or replace function public.atina_local_reveal_clue(p_session_id uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_session private.atina_local_sessions; v_total integer;
begin
  select * into v_session from private.atina_local_sessions
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
    return private.atina_local_public_state(v_session);
  end if;
  update private.atina_local_sessions
    set revealed_clues=revealed_clues+1, updated_at=clock_timestamp()
    where id=v_session.id
    returning * into v_session;
  return private.atina_local_public_state(v_session);
end;
$$;

create or replace function public.atina_local_submit_answer(
  p_session_id uuid, p_token text, p_answer text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session private.atina_local_sessions;
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
  select * into v_session from private.atina_local_sessions
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
    update private.atina_local_sessions set scores=v_session.scores, streaks=v_session.streaks,
      round_locked=true, answered_count=v_session.answered_count, last_result=v_session.last_result,
      updated_at=v_now where id=v_session.id returning * into v_session;
    return private.atina_local_public_state(v_session);
  end if;

  v_correct := private.atina_challenge_answer_matches(
    v_session.challenge_queue[v_session.position], p_answer
  );
  if not v_correct then
    v_session.scores[v_session.current_player] := v_session.scores[v_session.current_player]-10;
    v_session.streaks[v_session.current_player] := 0;
    v_session.last_result := jsonb_build_object('outcome','wrong','penalty',10);
    update private.atina_local_sessions set scores=v_session.scores, streaks=v_session.streaks,
      last_result=v_session.last_result, updated_at=v_now
      where id=v_session.id returning * into v_session;
    return private.atina_local_public_state(v_session);
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
  update private.atina_local_sessions set scores=v_session.scores, streaks=v_session.streaks,
    round_locked=true, answered_count=v_session.answered_count, status=v_session.status,
    last_result=v_session.last_result, updated_at=v_now
    where id=v_session.id returning * into v_session;
  return private.atina_local_public_state(v_session);
end;
$$;

create or replace function public.atina_local_pass_challenge(p_session_id uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_session private.atina_local_sessions;
begin
  select * into v_session from private.atina_local_sessions
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
    update private.atina_local_sessions set scores=v_session.scores, streaks=v_session.streaks,
      round_locked=true, answered_count=v_session.answered_count, last_result=v_session.last_result,
      updated_at=clock_timestamp() where id=v_session.id returning * into v_session;
    return private.atina_local_public_state(v_session);
  end if;
  v_session.streaks[v_session.current_player] := 0;
  v_session.round_locked := true;
  v_session.answered_count := v_session.answered_count+1;
  v_session.last_result := jsonb_build_object('outcome','pass');
  update private.atina_local_sessions set streaks=v_session.streaks, round_locked=true,
    answered_count=v_session.answered_count, last_result=v_session.last_result,
    updated_at=clock_timestamp() where id=v_session.id returning * into v_session;
  return private.atina_local_public_state(v_session);
end;
$$;

create or replace function public.atina_local_next_challenge(p_session_id uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session private.atina_local_sessions;
  v_queue integer[];
  v_next_position integer;
  v_card jsonb;
  v_now timestamptz;
begin
  select * into v_session from private.atina_local_sessions
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
  update private.atina_local_sessions set challenge_queue=v_queue, position=v_next_position,
    current_player=v_session.current_player, revealed_clues=1, round_locked=false,
    deadline_at=case when timed_mode_seconds=0 then null
      else v_now+make_interval(secs=>timed_mode_seconds) end,
    special_card=v_card, last_result='{}'::jsonb, updated_at=v_now
    where id=v_session.id returning * into v_session;
  return private.atina_local_public_state(v_session);
end;
$$;

-- API roles só podem chamar as RPCs de sessão. Os helpers privados não são executáveis
-- diretamente por anon/authenticated. O token é uma credencial bearer e não deve ir para URLs/logs.
revoke all on function private.atina_local_public_state(private.atina_local_sessions) from public, anon, authenticated;
revoke all on function public.atina_start_local_game(text,text,text,integer) from public;
revoke all on function public.atina_local_game_state(uuid,text) from public;
revoke all on function public.atina_local_reveal_clue(uuid,text) from public;
revoke all on function public.atina_local_submit_answer(uuid,text,text) from public;
revoke all on function public.atina_local_pass_challenge(uuid,text) from public;
revoke all on function public.atina_local_next_challenge(uuid,text) from public;
grant execute on function public.atina_start_local_game(text,text,text,integer) to anon, authenticated;
grant execute on function public.atina_local_game_state(uuid,text) to anon, authenticated;
grant execute on function public.atina_local_reveal_clue(uuid,text) to anon, authenticated;
grant execute on function public.atina_local_submit_answer(uuid,text,text) to anon, authenticated;
grant execute on function public.atina_local_pass_challenge(uuid,text) to anon, authenticated;
grant execute on function public.atina_local_next_challenge(uuid,text) to anon, authenticated;

comment on function public.atina_local_submit_answer(uuid,text,text) is
  'Recebe apenas a resposta textual; correção, deadline e pontuação são calculados no servidor.';
