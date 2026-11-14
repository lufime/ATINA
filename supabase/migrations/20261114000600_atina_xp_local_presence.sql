-- Extend account-backed XP to local Duel/Team sessions and reward a clue-assisted pass.
-- Local multiplayer uses one authenticated device/account; online rooms need per-player ownership
-- and are handled separately. Points logic is intentionally unchanged.

create or replace function public.atina_v2_start_local_game(
  p_game_mode text,
  p_difficulty text,
  p_category text default null,
  p_timed_mode_seconds integer default 60,
  p_device_token text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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

  if p_game_mode in ('solo','mix') and p_device_token is null then
    raise exception 'Inicia sessão na tua conta ATINA para garantir desafios sem repetição.' using errcode='28000';
  end if;

  if p_device_token is not null then
    -- One account owns the local session, including local Duel and Team modes.
    if p_device_token !~ '^[0-9a-f]{64}$' then
      raise exception 'Identificador de sessão inválido.' using errcode='22023';
    end if;
    select coalesce(
      (select a.player_id from private.atina_player_accounts a
        where a.session_token_hash=extensions.digest(convert_to(p_device_token,'UTF8'),'sha256')
          and a.session_expires_at>clock_timestamp()),
      (select p.id from private.atina_players p
        where p.device_token_hash=extensions.digest(convert_to(p_device_token,'UTF8'),'sha256'))
    ) into v_player_id;
    if v_player_id is null then
      raise exception 'Sessão expirada. Inicia sessão novamente.' using errcode='28000';
    end if;
  end if;

  if p_game_mode='mix' or p_difficulty='mixed' then
    with category_order as (
      select categories.category,
             row_number() over (order by random()) as category_number,
             count(*) over () as category_count
        from (
          select distinct c.category
            from private.atina_challenges c
           where c.active and (p_category is null or c.category=p_category)
        ) categories
    ),
    selected as (
      select coalesce(
        (select c.challenge_id
           from private.atina_challenges c
          where c.active and c.category=ordered.category
            and c.difficulty=case
              when ordered.category_number <= floor(ordered.category_count::numeric/3) then 'easy'
              when ordered.category_number <= floor(2*ordered.category_count::numeric/3) then 'medium'
              else 'hard' end
            and not exists (
              select 1 from private.atina_challenge_exposures e
               where e.scope_type='player' and e.scope_key=v_player_id::text
                 and e.challenge_id=c.challenge_id
            )
          order by random() limit 1),
        (select c.challenge_id
           from private.atina_challenges c
          where c.active and c.category=ordered.category
            and not exists (
              select 1 from private.atina_challenge_exposures e
               where e.scope_type='player' and e.scope_key=v_player_id::text
                 and e.challenge_id=c.challenge_id
            )
          order by random() limit 1)
      ) as challenge_id
      from category_order ordered
    )
    select array_agg(selected.challenge_id order by random()) into v_queue
      from selected where selected.challenge_id is not null;
  else
    select array_agg(c.challenge_id order by random()) into v_queue
      from private.atina_challenges c
     where c.active and c.difficulty=p_difficulty
       and (p_category is null or c.category=p_category)
       and not exists (
         select 1 from private.atina_challenge_exposures e
          where e.scope_type='player' and e.scope_key=v_player_id::text
            and e.challenge_id=c.challenge_id
       );
  end if;

  if coalesce(cardinality(v_queue),0)=0 then
    raise exception 'Já viste todos os desafios disponíveis para estes critérios. Experimenta outra categoria ou dificuldade.';
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

    insert into private.atina_challenge_exposures(scope_type,scope_key,challenge_id)
    values('player',v_player_id::text,v_queue[1])
    on conflict(scope_type,scope_key,challenge_id) do nothing;
  end if;

  select * into v_session from private.atina_v2_local_sessions where id=v_session.id;
  return jsonb_build_object('token',v_token,'state',private.atina_v2_local_public_state(v_session));
end;
$function$;

create or replace function public.atina_progress_claim_local(
  p_device_token text,
  p_session_id uuid,
  p_session_token text,
  p_position integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player private.atina_players;
  v_session private.atina_v2_local_sessions;
  v_owner private.atina_xp_session_owners;
  v_challenge private.atina_challenges;
  v_inserted bigint;
  v_points_inserted bigint;
  v_bonus_inserted bigint;
  v_today date := current_date;
  v_daily_count integer;
  v_streak integer;
  v_xp integer := 10;
  v_points integer := 0;
  v_daily_bonus integer := 0;
  v_mission_bonus integer := 0;
  v_streak_bonus integer := 0;
  v_category_bonus integer := 0;
  v_hard_bonus integer := 0;
  v_milestone_bonus integer := 0;
  v_outcome text;
  v_challenge_id text;
begin
  if p_device_token is null or p_device_token !~ '^[0-9a-f]{64}$'
     or p_session_id is null or p_session_token is null
     or p_session_token !~ '^[0-9a-f]{64}$'
     or p_position is null or p_position < 1 then
    raise exception 'Pedido de progressão inválido.' using errcode='22023';
  end if;

  select * into v_player
    from private.atina_players
   where id = (
     select a.player_id from private.atina_player_accounts a
      where a.session_token_hash=extensions.digest(convert_to(p_device_token,'UTF8'),'sha256')
        and a.session_expires_at>clock_timestamp()
      limit 1
   )
   for update;

  if not found then
    raise exception 'Inicia sessão para guardar o XP.' using errcode='28000';
  end if;

  select * into v_session from private.atina_v2_local_sessions
   where id=p_session_id
     and token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
   for update;

  v_outcome := v_session.last_result->>'outcome';
  if not found or v_session.position<>p_position or not v_session.round_locked
     or v_outcome not in ('correct','wrong','incorrect','pass')
     or (v_outcome='pass' and coalesce(v_session.revealed_clues,1)<=1)
     or v_session.expires_at<=clock_timestamp() then
    raise exception 'O servidor ainda não confirmou este desafio como concluído.' using errcode='55000';
  end if;

  select * into v_owner from private.atina_xp_session_owners
   where session_id=p_session_id for update;
  if not found or v_owner.player_id<>v_player.id then
    raise exception 'Esta sessão não está associada a esta conta.' using errcode='42501';
  end if;

  if v_outcome='pass' then v_xp:=5; end if;

  v_challenge_id := v_session.challenge_queue[v_session.position];
  select * into v_challenge
    from private.atina_challenges
   where challenge_id=v_challenge_id and active;
  if not found then
    raise exception 'Não foi possível confirmar o desafio concluído.' using errcode='55000';
  end if;

  insert into private.atina_xp_events(player_id,session_id,challenge_position,xp)
  values(v_player.id,p_session_id,p_position,v_xp)
  on conflict(player_id,session_id,challenge_position) do nothing
  returning id into v_inserted;

  if v_inserted is null then
    return jsonb_build_object(
      'awarded',false,'reason','already_claimed',
      'xp',v_player.total_xp,'points',v_player.total_points,
      'level',floor(v_player.total_xp/250.0)::integer+1,
      'total_challenges',v_player.total_challenges,
      'daily_count',case when v_player.daily_date=v_today then v_player.daily_count else 0 end,
      'active_streak',v_player.active_streak
    );
  end if;

  -- Existing Points logic is unchanged: only correct answers award the server-calculated value.
  if v_outcome='correct' then
    v_points:=greatest(coalesce((v_session.last_result->>'points')::integer,0),0);
    if v_points>0 then
      insert into private.atina_points_events(player_id,source,source_id,challenge_position,points)
      values(v_player.id,'local',p_session_id,p_position,v_points)
      on conflict(player_id,source,source_id,challenge_position) do nothing
      returning id into v_points_inserted;
    end if;
  end if;

  v_daily_count:=case when v_player.daily_date=v_today then v_player.daily_count+1 else 1 end;
  if v_daily_count>=3 and v_player.daily_mission_reward_date is distinct from v_today then
    insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
    values(v_player.id,'daily_mission',v_today::text,25)
    on conflict(player_id,event_type,event_key) do nothing
    returning id into v_bonus_inserted;
    if v_bonus_inserted is not null then v_mission_bonus:=25; end if;
  end if;

  if v_daily_count>=5 and v_player.daily_reward_date is distinct from v_today then
    insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
    values(v_player.id,'daily_five',v_today::text,20)
    on conflict(player_id,event_type,event_key) do nothing
    returning id into v_bonus_inserted;
    if v_bonus_inserted is not null then v_daily_bonus:=20; end if;
  end if;

  -- A day counts once, regardless of how many challenges are completed that day.
  v_streak:=case
    when v_player.last_active_date=v_today then greatest(v_player.active_streak,1)
    when v_player.last_active_date=v_today-1 then greatest(v_player.active_streak,0)+1
    else 1
  end;
  if v_streak>=7 and v_streak%7=0 and v_player.last_active_date is distinct from v_today then
    insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
    values(v_player.id,'streak_seven',v_today::text,50)
    on conflict(player_id,event_type,event_key) do nothing
    returning id into v_bonus_inserted;
    if v_bonus_inserted is not null then v_streak_bonus:=50; end if;
  end if;

  if v_outcome<>'pass' and nullif(btrim(v_challenge.category),'') is not null then
    insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
    values(v_player.id,'new_category',v_challenge.category,15)
    on conflict(player_id,event_type,event_key) do nothing
    returning id into v_bonus_inserted;
    if v_bonus_inserted is not null then v_category_bonus:=15; end if;
  end if;

  if v_outcome<>'pass' and lower(coalesce(v_challenge.difficulty,''))='hard' then
    insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
    values(v_player.id,'hard_challenge',v_challenge_id,20)
    on conflict(player_id,event_type,event_key) do nothing
    returning id into v_bonus_inserted;
    if v_bonus_inserted is not null then v_hard_bonus:=20; end if;
  end if;

  if v_player.total_challenges+1>=100 then
    insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
    values(v_player.id,'challenge_milestone','100',100)
    on conflict(player_id,event_type,event_key) do nothing
    returning id into v_bonus_inserted;
    if v_bonus_inserted is not null then v_milestone_bonus:=100; end if;
  end if;

  update private.atina_players
     set total_xp=total_xp+v_xp+v_daily_bonus+v_mission_bonus+v_streak_bonus+
                  v_category_bonus+v_hard_bonus+v_milestone_bonus,
         total_points=total_points+case when v_points_inserted is null then 0 else v_points end,
         total_challenges=total_challenges+1,
         daily_date=v_today,
         daily_count=least(v_daily_count,5),
         daily_reward_date=case when v_daily_bonus>0 then v_today else daily_reward_date end,
         daily_mission_reward_date=case when v_mission_bonus>0 then v_today else daily_mission_reward_date end,
         last_active_date=v_today,
         active_streak=v_streak,
         updated_at=clock_timestamp()
   where id=v_player.id
  returning * into v_player;

  return jsonb_build_object(
    'awarded',true,'challenge_xp',v_xp,
    'challenge_points',case when v_points_inserted is null then 0 else v_points end,
    'daily_bonus',v_daily_bonus,'daily_mission_bonus',v_mission_bonus,
    'streak_bonus',v_streak_bonus,'category_bonus',v_category_bonus,
    'hard_bonus',v_hard_bonus,'milestone_bonus',v_milestone_bonus,
    'bonus_total',v_daily_bonus+v_mission_bonus+v_streak_bonus+v_category_bonus+v_hard_bonus+v_milestone_bonus,
    'xp',v_player.total_xp,'points',v_player.total_points,
    'level',floor(v_player.total_xp/250.0)::integer+1,
    'total_challenges',v_player.total_challenges,'daily_count',v_player.daily_count,
    'active_streak',v_player.active_streak
  );
end;
$function$;
