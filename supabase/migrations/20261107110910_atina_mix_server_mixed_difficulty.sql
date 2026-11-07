-- Keep Mix faithful to its advertised contract: one challenge per category,
-- with easy, medium and hard levels represented across the queue.
-- Mix is intentionally not subject to adaptive queue replacement; that would
-- collapse its mixed-difficulty selection back to a single level.

create or replace function private.atina_v2_local_public_state(
  p_session private.atina_v2_local_sessions
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'session_id', p_session.id,
    'mode', p_session.game_mode,
    'difficulty', coalesce((
      select c.difficulty
        from private.atina_challenges c
       where c.challenge_id = p_session.challenge_queue[p_session.position]
         and c.active
    ), p_session.difficulty),
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

  if p_game_mode = 'mix' then
    -- Match the original Mix design: one random challenge per category.
    -- Categories are split as evenly as possible across the three levels;
    -- a category without the assigned level falls back to any active card.
    with category_order as (
      select categories.category,
             row_number() over (order by random()) as category_number,
             count(*) over () as category_count
        from (
          select distinct c.category
            from private.atina_challenges c
           where c.active
             and (p_category is null or c.category=p_category)
        ) categories
    ),
    selected as (
      select coalesce(
        (
          select c.challenge_id
            from private.atina_challenges c
           where c.active
             and c.category=ordered.category
             and c.difficulty=case
               when ordered.category_number <= floor(ordered.category_count::numeric/3) then 'easy'
               when ordered.category_number <= floor(2*ordered.category_count::numeric/3) then 'medium'
               else 'hard'
             end
             and (
               v_player_id is null or not exists (
                 select 1 from (
                   select h.challenge_id
                     from private.atina_difficulty_history h
                    where h.player_id=v_player_id
                    order by h.created_at desc,h.id desc
                    limit 30
                 ) recent
                 where recent.challenge_id=c.challenge_id
               )
             )
           order by random()
           limit 1
        ),
        (
          select c.challenge_id
            from private.atina_challenges c
           where c.active and c.category=ordered.category
             and (
               v_player_id is null or not exists (
                 select 1 from (
                   select h.challenge_id
                     from private.atina_difficulty_history h
                    where h.player_id=v_player_id
                    order by h.created_at desc,h.id desc
                    limit 30
                 ) recent
                 where recent.challenge_id=c.challenge_id
               )
             )
           order by random()
           limit 1
        ),
        (
          select c.challenge_id
            from private.atina_challenges c
           where c.active and c.category=ordered.category
           order by random()
           limit 1
        )
      ) as challenge_id
        from category_order ordered
    )
    select array_agg(selected.challenge_id order by random())
      into v_queue
      from selected
     where selected.challenge_id is not null;
  else
    -- Rotate the last 30 challenges for registered players in both Solo and Mix.
    -- If the available pool is exhausted, fall back gracefully rather than blocking a game.
    select array_agg(c.challenge_id order by random())
      into v_queue
      from private.atina_challenges c
     where c.active
       and c.difficulty=p_difficulty
       and (p_category is null or c.category=p_category)
       and (
         v_player_id is null or not exists (
           select 1 from (
             select h.challenge_id
               from private.atina_difficulty_history h
              where h.player_id=v_player_id
              order by h.created_at desc,h.id desc
              limit 30
           ) recent
           where recent.challenge_id=c.challenge_id
         )
       );
    if coalesce(cardinality(v_queue),0)=0 then
      select array_agg(c.challenge_id order by random())
        into v_queue
        from private.atina_challenges c
       where c.active
         and c.difficulty=p_difficulty
         and (p_category is null or c.category=p_category);
    end if;
  end if;

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

create or replace function public.atina_v2_local_submit_answer(
  p_session_id uuid,
  p_token text,
  p_answer text
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
  v_speed integer:=0;
  v_streak integer;
  v_streak_bonus integer:=0;
  v_multiplier integer:=1;
  v_bonus integer:=0;
  v_points integer;
  v_winner integer:=null;
begin
  if p_answer is null or length(trim(p_answer))=0 or length(p_answer)>300 then
    raise exception 'Resposta vazia ou demasiado longa.' using errcode='22023';
  end if;
  select * into v_session
    from private.atina_v2_local_sessions
   where id=p_session_id
     and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
   for update;
  if not found then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  v_now:=clock_timestamp();
  if v_session.expires_at<=v_now then
    raise exception 'Sessão inválida ou expirada.' using errcode='28000';
  end if;
  if v_session.status<>'active' or v_session.round_locked then
    raise exception 'A ronda já foi fechada.' using errcode='55000';
  end if;
  if v_session.deadline_at is not null and v_session.deadline_at<=v_now then
    v_session.scores[v_session.current_player]:=v_session.scores[v_session.current_player]-10;
    v_session.streaks[v_session.current_player]:=0;
    v_session.round_locked:=true;
    v_session.answered_count:=v_session.answered_count+1;
    v_session.last_result:=jsonb_build_object('outcome','timeout','penalty',10);
    update private.atina_v2_local_sessions
       set scores=v_session.scores,streaks=v_session.streaks,
           round_locked=true,answered_count=v_session.answered_count,
           last_result=v_session.last_result,updated_at=v_now
     where id=v_session.id returning * into v_session;
    return private.atina_v2_local_public_state(v_session);
  end if;

  v_correct:=private.atina_v2_challenge_answer_matches(
    v_session.challenge_queue[v_session.position],p_answer
  );
  if not v_correct then
    v_session.scores[v_session.current_player]:=v_session.scores[v_session.current_player]-10;
    v_session.streaks[v_session.current_player]:=0;
    v_session.last_result:=jsonb_build_object('outcome','wrong','penalty',10);
    update private.atina_v2_local_sessions
       set scores=v_session.scores,streaks=v_session.streaks,
           last_result=v_session.last_result,updated_at=v_now
     where id=v_session.id returning * into v_session;
    return private.atina_v2_local_public_state(v_session);
  end if;

  -- The Mix queue contains different levels, so score from the current card,
  -- never from the session's initial difficulty setting.
  select case c.difficulty when 'easy' then 10 when 'hard' then 20 else 15 end
    into v_base
    from private.atina_challenges c
   where c.challenge_id=v_session.challenge_queue[v_session.position]
     and c.active;
  if v_base is null then
    raise exception 'Desafio indisponível.' using errcode='55000';
  end if;

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
  v_session.round_locked:=true;
  v_session.answered_count:=v_session.answered_count+1;
  if v_session.scores[v_session.current_player]>=250 then
    v_session.status:='completed';
    v_winner:=v_session.current_player;
  end if;
  v_session.last_result:=jsonb_build_object(
    'outcome','correct','base_points',v_base,'speed_bonus',v_speed,
    'streak_bonus',v_streak_bonus,'special_multiplier',v_multiplier,
    'special_bonus',v_bonus,'points',v_points,'winner',v_winner,
    'party_final_round_bonus',v_session.game_mode='party'
      and v_session.position=cardinality(v_session.challenge_queue)
  );
  update private.atina_v2_local_sessions
     set scores=v_session.scores,streaks=v_session.streaks,
         round_locked=true,answered_count=v_session.answered_count,
         status=v_session.status,last_result=v_session.last_result,updated_at=v_now
   where id=v_session.id returning * into v_session;
  return private.atina_v2_local_public_state(v_session);
end;
$$;

-- Store the actual challenge level in history; Mix does not have one session-wide level.
create or replace function private.atina_record_difficulty_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player_id uuid;
  v_nickname text;
  v_difficulty text;
  v_outcome text;
begin
  v_outcome := new.last_result ->> 'outcome';
  if v_outcome is null or v_outcome not in ('wrong','timeout','pass','correct') then
    return new;
  end if;
  if v_outcome = 'wrong' and new.round_locked then
    return new;
  end if;
  if v_outcome <> 'wrong' and not new.round_locked then
    return new;
  end if;

  select o.player_id,p.nickname,c.difficulty
    into v_player_id,v_nickname,v_difficulty
    from private.atina_xp_session_owners o
    join private.atina_players p on p.id=o.player_id
    join private.atina_challenges c
      on c.challenge_id=new.challenge_queue[new.position]
   where o.session_id=new.id;

  if v_player_id is null or lower(btrim(coalesce(v_nickname,'')))='admin' then
    return new;
  end if;

  insert into private.atina_difficulty_history
    (player_id,session_id,challenge_position,challenge_id,difficulty,outcome)
  values
    (v_player_id,new.id,new.position,new.challenge_queue[new.position],
     v_difficulty,v_outcome);
  return new;
end;
$function$;

-- Adaptive difficulty remains available in Solo. Replacing a Mix queue here
-- would silently destroy its mixed-level guarantee immediately after profile binding.
create or replace function private.atina_apply_adaptive_difficulty()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player private.atina_players;
  v_session private.atina_v2_local_sessions;
  v_total integer:=0;
  v_errors integer:=0;
  v_difficulty text;
  v_queue integer[];
begin
  select * into v_player from private.atina_players where id=new.player_id;
  if not found or lower(btrim(v_player.nickname))='admin' then
    return new;
  end if;

  select * into v_session
    from private.atina_v2_local_sessions
   where id=new.session_id;
  if not found or v_session.game_mode <> 'solo' then
    return new;
  end if;

  select count(*),
         count(*) filter (where recent.outcome in ('wrong','timeout','pass'))
    into v_total,v_errors
    from (
      select h.outcome
        from private.atina_difficulty_history h
       where h.player_id=new.player_id
       order by h.created_at desc,h.id desc
       limit 20
    ) recent;

  v_difficulty:=v_session.difficulty;
  if v_total>=5 then
    if v_errors::numeric/v_total>=0.50 then
      v_difficulty:='hard';
    elsif v_errors::numeric/v_total<=0.20 then
      v_difficulty:='easy';
    else
      v_difficulty:='medium';
    end if;
  end if;

  select array_agg(c.challenge_id order by random())
    into v_queue
    from private.atina_challenges c
   where c.active
     and c.difficulty=v_difficulty
     and (v_session.category is null or c.category=v_session.category)
     and not exists (
       select 1
         from (
           select h.challenge_id
             from private.atina_difficulty_history h
            where h.player_id=new.player_id
            order by h.created_at desc,h.id desc
            limit 20
         ) recent
        where recent.challenge_id=c.challenge_id
     );

  if coalesce(cardinality(v_queue),0)=0 then
    select array_agg(c.challenge_id order by random())
      into v_queue
      from private.atina_challenges c
     where c.active
       and c.difficulty=v_difficulty
       and (v_session.category is null or c.category=v_session.category);
  end if;

  if coalesce(cardinality(v_queue),0)>0 then
    update private.atina_v2_local_sessions
       set difficulty=v_difficulty,
           challenge_queue=case
             when game_mode='party' then v_queue[1:least(10,cardinality(v_queue))]
             else v_queue
           end,
           position=1,
           updated_at=clock_timestamp()
     where id=v_session.id;
  end if;
  return new;
end;
$function$;
