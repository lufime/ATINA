-- Support true server-side random difficulty in Solo mode.
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
  if p_difficulty is null or p_difficulty not in ('easy','medium','hard','mixed') then
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

  if p_game_mode = 'mix' or p_difficulty = 'mixed' then
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
  if not found or v_session.game_mode <> 'solo' or v_session.difficulty = 'mixed' then
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

