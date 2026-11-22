-- Challenge count with player-session progression binding.
drop function if exists public.atina_v2_start_local_game(text, text, text, integer);
drop function if exists public.atina_v2_start_local_game(text, text, text, integer, text);
drop function if exists public.atina_v2_start_local_game(text, text, text, integer, integer);

create or replace function public.atina_v2_start_local_game(
  p_game_mode text,
  p_difficulty text,
  p_category text default null,
  p_timed_mode_seconds integer default 60,
  p_device_token text default null,
  p_challenge_count integer default 10
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_token text;
  v_queue integer[];
  v_session private.atina_v2_local_sessions;
  v_card jsonb;
  v_available integer;
  v_player_id uuid;
begin
  if p_game_mode is null or p_game_mode not in ('solo','duel','mix') then raise exception 'Modo inválido nesta versão.' using errcode='22023'; end if;
  if p_difficulty is null or p_difficulty not in ('easy','medium','hard') then raise exception 'Dificuldade inválida.' using errcode='22023'; end if;
  if p_challenge_count is null or p_challenge_count not between 1 and 1000 then raise exception 'Quantidade de desafios inválida (1–1000).' using errcode='22023'; end if;
  if p_timed_mode_seconds is null or p_timed_mode_seconds not between 0 and 3600 then raise exception 'Duração inválida.' using errcode='22023'; end if;
  if p_category is not null and length(trim(p_category))=0 then raise exception 'Categoria inválida.' using errcode='22023'; end if;
  if p_device_token is not null then
    if p_game_mode not in ('solo','mix') then raise exception 'A progressão individual só está disponível em Solo e Mix.' using errcode='22023'; end if;
    if p_device_token !~ '^[0-9a-f]{64}$' then raise exception 'Identificador de dispositivo inválido.' using errcode='22023'; end if;
    select id into v_player_id from private.atina_players
     where device_token_hash=extensions.digest(convert_to(p_device_token,'UTF8'),'sha256');
    if v_player_id is null then raise exception 'Regista primeiro o teu pseudónimo.' using errcode='28000'; end if;
  end if;
  select count(*) into v_available from private.atina_challenges c
   where c.active and c.difficulty=p_difficulty and (p_category is null or c.category=p_category);
  if v_available < p_challenge_count then raise exception 'Esta seleção tem apenas % desafios disponíveis. Escolhe uma quantidade até % ou altera a categoria/dificuldade.',v_available,v_available using errcode='22023'; end if;
  select array_agg(selected.challenge_id) into v_queue from (
    select c.challenge_id from private.atina_challenges c
     where c.active and c.difficulty=p_difficulty and (p_category is null or c.category=p_category)
     order by random() limit p_challenge_count
  ) selected;
  if coalesce(cardinality(v_queue),0)=0 then raise exception 'Não existem desafios para estes critérios.' using errcode='22023'; end if;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_card:=null;
  insert into private.atina_v2_local_sessions (
    token_hash,game_mode,difficulty,category,timed_mode_seconds,challenge_queue,
    position,revealed_clues,current_player,scores,streaks,round_context,deadline_at,expires_at,special_card
  ) values (
    extensions.digest(convert_to(v_token,'UTF8'),'sha256'),p_game_mode,p_difficulty,p_category,p_timed_mode_seconds,
    v_queue,1,1,1,array[0,0],array[0,0],'{}'::jsonb,
    case when p_timed_mode_seconds=0 then null else clock_timestamp()+make_interval(secs=>p_timed_mode_seconds) end,
    clock_timestamp()+interval '8 hours',v_card
  ) returning * into v_session;
  if v_player_id is not null then
    insert into private.atina_xp_session_owners(session_id,player_id) values(v_session.id,v_player_id);
  end if;
  return jsonb_build_object('token',v_token,'state',private.atina_v2_local_public_state(v_session));
end; $$;

-- Compatibility wrapper: existing SQL tests/callers passing a challenge count as argument 5.
create or replace function public.atina_v2_start_local_game(
  p_game_mode text, p_difficulty text, p_category text,
  p_timed_mode_seconds integer, p_challenge_count integer
) returns jsonb language sql security definer set search_path = '' as $$
  select public.atina_v2_start_local_game(p_game_mode,p_difficulty,p_category,p_timed_mode_seconds,null,p_challenge_count);
$$;

revoke all on function public.atina_v2_start_local_game(text, text, text, integer, text, integer) from public;
grant execute on function public.atina_v2_start_local_game(text, text, text, integer, text, integer) to anon, authenticated;
revoke all on function public.atina_v2_start_local_game(text, text, text, integer, integer) from public;
grant execute on function public.atina_v2_start_local_game(text, text, text, integer, integer) to anon, authenticated;
comment on function public.atina_v2_start_local_game(text, text, text, integer, text, integer) is 'Starts a bounded local game and binds optional pseudonymous XP ownership.';
