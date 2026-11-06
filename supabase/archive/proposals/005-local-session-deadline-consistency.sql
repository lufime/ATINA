-- PROPOSTA (não aplicar diretamente): deadline consistente nas RPCs de sessão local.
-- Aplicada e verificada apenas em atina-development (qvvlqrgbtjujsejvenld).
-- Não executar em produção sem revisão, testes de concorrência e aprovação.

create or replace function public.atina_local_game_state(p_session_id uuid, p_token text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_session private.atina_local_sessions;
  v_now timestamptz;
begin
  select * into v_session from private.atina_local_sessions
  where id=p_session_id
    and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
  for update;
  if not found then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  v_now := clock_timestamp();
  if v_session.expires_at <= v_now then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  if v_session.status='active' and not v_session.round_locked
     and v_session.deadline_at is not null and v_session.deadline_at <= v_now then
    v_session.scores[v_session.current_player] := v_session.scores[v_session.current_player]-10;
    v_session.streaks[v_session.current_player] := 0;
    v_session.round_locked := true;
    v_session.answered_count := v_session.answered_count+1;
    v_session.last_result := jsonb_build_object('outcome','timeout','penalty',10);
    update private.atina_local_sessions
      set scores=v_session.scores, streaks=v_session.streaks, round_locked=true,
          answered_count=v_session.answered_count, last_result=v_session.last_result,
          updated_at=v_now
      where id=v_session.id returning * into v_session;
  end if;
  return private.atina_local_public_state(v_session);
end;
$$;

create or replace function public.atina_local_reveal_clue(p_session_id uuid, p_token text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_session private.atina_local_sessions;
  v_total integer;
  v_now timestamptz;
begin
  select * into v_session from private.atina_local_sessions
  where id=p_session_id
    and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
  for update;
  if not found then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  v_now := clock_timestamp();
  if v_session.expires_at <= v_now then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  if v_session.status <> 'active' or v_session.round_locked then
    raise exception 'A ronda não está ativa.' using errcode='55000';
  end if;
  if v_session.deadline_at is not null and v_session.deadline_at <= v_now then
    v_session.scores[v_session.current_player] := v_session.scores[v_session.current_player]-10;
    v_session.streaks[v_session.current_player] := 0;
    v_session.round_locked := true;
    v_session.answered_count := v_session.answered_count+1;
    v_session.last_result := jsonb_build_object('outcome','timeout','penalty',10);
    update private.atina_local_sessions
      set scores=v_session.scores, streaks=v_session.streaks, round_locked=true,
          answered_count=v_session.answered_count, last_result=v_session.last_result,
          updated_at=v_now
      where id=v_session.id returning * into v_session;
    return private.atina_local_public_state(v_session);
  end if;
  select jsonb_array_length(clues) into v_total
  from private.atina_challenges
  where challenge_id=v_session.challenge_queue[v_session.position] and active;
  if v_session.revealed_clues >= v_total then
    return private.atina_local_public_state(v_session);
  end if;
  update private.atina_local_sessions
    set revealed_clues=revealed_clues+1, updated_at=v_now
    where id=v_session.id returning * into v_session;
  return private.atina_local_public_state(v_session);
end;
$$;

create or replace function public.atina_local_pass_challenge(p_session_id uuid, p_token text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_session private.atina_local_sessions;
  v_now timestamptz;
begin
  select * into v_session from private.atina_local_sessions
  where id=p_session_id
    and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
  for update;
  if not found then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
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
  else
    v_session.streaks[v_session.current_player] := 0;
    v_session.round_locked := true;
    v_session.answered_count := v_session.answered_count+1;
    v_session.last_result := jsonb_build_object('outcome','pass');
  end if;
  update private.atina_local_sessions
    set scores=v_session.scores, streaks=v_session.streaks, round_locked=true,
        answered_count=v_session.answered_count, last_result=v_session.last_result,
        updated_at=v_now
    where id=v_session.id returning * into v_session;
  return private.atina_local_public_state(v_session);
end;
$$;
