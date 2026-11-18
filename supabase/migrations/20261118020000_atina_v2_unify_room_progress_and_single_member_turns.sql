-- Align V2 room turns and account progression with the established server rules.
-- Additive only. This migration is source-controlled; it is not applied remotely.

create table if not exists private.atina_room_progress_events (
  id bigint generated always as identity primary key,
  player_id uuid not null references private.atina_players(id) on delete cascade,
  room_id uuid not null references public.atina_v2_rooms(id) on delete cascade,
  challenge_position integer not null check (challenge_position > 0),
  xp integer not null check (xp = 10),
  created_at timestamptz not null default clock_timestamp(),
  constraint atina_room_progress_events_once
    unique (player_id, room_id, challenge_position)
);

alter table private.atina_room_progress_events enable row level security;
revoke all on table private.atina_room_progress_events from public, anon, authenticated;
create index if not exists atina_room_progress_events_player_created_idx
  on private.atina_room_progress_events(player_id, created_at desc);

-- The V2 turn-control RPCs require these fields on the authoritative room state.
alter table private.atina_v2_room_game_state
  add column if not exists team_order text[] not null default '{}',
  add column if not exists active_team_index integer not null default 1,
  add column if not exists team_turn_advanced boolean not null default false;

-- Initialize team order from the assigned room teams before the first challenge.
do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  v_def := pg_get_functiondef('public.atina_v2_start_room_challenges(uuid,text,text,integer,text)'::regprocedure);

  v_old := '  v_challenge private.atina_challenges%rowtype;'||chr(10)||
           '  v_state jsonb;';
  v_new := '  v_challenge private.atina_challenges%rowtype;'||chr(10)||
           '  v_state jsonb;'||chr(10)||
           '  v_team_order text[];';
  if position(v_old in v_def)=0 then
    raise exception 'Não foi possível localizar as variáveis de atina_v2_start_room_challenges.';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := '  v_now:=clock_timestamp();';
  v_new := '  SELECT array_agg(team_label ORDER BY team_label)'||chr(10)||
           '    INTO v_team_order'||chr(10)||
           '    FROM (SELECT DISTINCT team_label FROM public.atina_v2_room_players'||chr(10)||
           '           WHERE room_id=p_room_id AND team_label IS NOT NULL) assigned_teams;'||chr(10)||
           '  IF coalesce(cardinality(v_team_order),0)<2 THEN'||chr(10)||
           '    RAISE EXCEPTION ''A partida necessita de pelo menos duas equipas atribuídas.'';'||chr(10)||
           '  END IF;'||chr(10)||
           '  v_now := clock_timestamp();';
  if position(v_old in v_def)=0 then
    raise exception 'Não foi possível localizar o início do relógio em atina_v2_start_room_challenges.';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := $old$
    revealed_clues,deadline_at,round_locked,status,created_at,updated_at
  ) VALUES (
    p_room_id,v_queue,1,p_difficulty,p_category,p_duration_seconds,
    1,v_deadline,false,'active',v_now,v_now
  );
$old$;
  v_new := $new$
    revealed_clues,deadline_at,round_locked,status,created_at,updated_at,
    team_order,active_team_index,team_turn_advanced
  ) VALUES (
    p_room_id,v_queue,1,p_difficulty,p_category,p_duration_seconds,
    1,v_deadline,false,'active',v_now,v_now,
    v_team_order,1,false
  );
$new$;
  if position(v_old in v_def)=0 then
    raise exception 'Não foi possível inicializar as equipas em atina_v2_start_room_challenges.';
  end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end
$migration$;

-- Single-member teams use the same authoritative answer RPC as individual room play.
-- Larger teams must continue through proposal + unanimous voting.
do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  v_def := pg_get_functiondef('public.atina_v2_submit_room_answer(uuid,text,text)'::regprocedure);

  v_old := 'v_now:=clock_timestamp();';
  v_new := $new$
  IF v_player.team_label IS NOT NULL THEN
    IF (SELECT count(*) FROM public.atina_v2_room_players
         WHERE room_id=p_room_id AND team_label=v_player.team_label) <> 1 THEN
      RAISE EXCEPTION 'As respostas de equipas com vários membros exigem proposta e votação.';
    END IF;
    IF cardinality(v_game.team_order)=0
       OR v_player.team_label IS DISTINCT FROM v_game.team_order[v_game.active_team_index] THEN
      RAISE EXCEPTION 'Só a equipa que tem a vez pode responder.';
    END IF;
  END IF;

  v_now:=clock_timestamp();
$new$;
  if position(v_old in v_def)=0 then
    raise exception 'Não foi possível localizar o início da validação em atina_v2_submit_room_answer.';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := $old$
  INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
  VALUES(p_room_id,v_player.id,v_game.position-1,v_correct,v_points,v_now);

  RETURN jsonb_build_object(
$old$;
  v_new := $new$
  INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
  VALUES(p_room_id,v_player.id,v_game.position-1,v_correct,v_points,v_now);

  IF v_correct AND v_player.team_label IS NOT NULL THEN
    UPDATE private.atina_v2_room_game_state
       SET round_locked=true,updated_at=v_now
     WHERE room_id=p_room_id;
    v_state:=private.atina_v2_room_public_state(p_room_id);
    UPDATE public.atina_v2_rooms
       SET game_state=v_state,state_version=state_version+1,updated_at=v_now
     WHERE id=p_room_id;
  END IF;

  RETURN jsonb_build_object(
$new$;
  if position(v_old in v_def)=0 then
    raise exception 'Não foi possível localizar o registo da resposta em atina_v2_submit_room_answer.';
  end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end
$migration$;

-- Apply online special-card multipliers and protections to team-vote scoring too.
do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  v_def := pg_get_functiondef('public.atina_v2_vote_team_proposal(uuid,text,uuid,boolean)'::regprocedure);

  v_old := '  v_speed integer:=0;' ;
  v_new := '  v_speed integer:=0;'||chr(10)||
           '  v_multiplier integer:=1;'||chr(10)||
           '  v_bonus integer:=0;'||chr(10)||
           '  v_penalty integer:=10;';
  if position(v_old in v_def)=0 then
    raise exception 'Não foi possível localizar as variáveis de pontuação em atina_v2_vote_team_proposal.';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := '    v_points:=v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END;';
  v_new := '    v_multiplier:=coalesce((v_game.special_card->>''multiplier'')::integer,1);'||chr(10)||
           '    v_bonus:=coalesce((v_game.special_card->>''bonus'')::integer,0);'||chr(10)||
           '    v_points:=(v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END)*v_multiplier+v_bonus;';
  if position(v_old in v_def)=0 then
    raise exception 'Não foi possível localizar o cálculo de pontos em atina_v2_vote_team_proposal.';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := '  UPDATE public.atina_v2_room_players'||chr(10)||
           '  SET score=greatest(0,score-10),last_seen_at=v_now';
  v_new := '  v_penalty:=case v_game.special_card->>''id'' when ''shield'' then 0 when ''reduced_penalty'' then 5 else 10 end;'||chr(10)||
           '  UPDATE public.atina_v2_room_players'||chr(10)||
           '  SET score=greatest(0,score-v_penalty),last_seen_at=v_now';
  if position(v_old in v_def)=0 then
    raise exception 'Não foi possível localizar a penalização em atina_v2_vote_team_proposal.';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_def := replace(v_def, '''penalty_per_player'',10', '''penalty_per_player'',v_penalty');
  execute v_def;
end
$migration$;

-- Route the automated opponent through the same server answer validation and scoring
-- used by a single-member team. A correct answer closes that team's turn above.
do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  v_def := pg_get_functiondef('public.atina_v2_bot_tick(uuid,text)'::regprocedure);

  v_old := $old$
 v_result:=public.atina_v2_submit_team_proposal(p_room_id,v_match.bot_token,
  v_game.position-1,v_answer,NULL,NULL);
 IF v_result->>'status' IN ('accepted','already_correct') THEN
$old$;
  v_new := $new$
 v_result:=public.atina_v2_submit_room_answer(p_room_id,v_match.bot_token,v_answer);
 IF v_result->>'status' IN ('correct','already_correct') THEN
$new$;
  if position(v_old in v_def)=0 then
    raise exception 'Não foi possível localizar a submissão de resposta em atina_v2_bot_tick.';
  end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end
$migration$;

-- Every completed room challenge awards the same base 10 XP to a registered
-- human account, regardless of correctness. Correct answers award points once.
create or replace function private.atina_v2_award_room_player_progress()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player_id uuid;
  v_player private.atina_players%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_challenge private.atina_challenges%rowtype;
  v_xp_event bigint;
  v_points_event bigint;
  v_today date := current_date;
  v_daily_count integer;
  v_streak integer;
  v_daily_bonus integer := 0;
  v_mission_bonus integer := 0;
  v_streak_bonus integer := 0;
  v_category_bonus integer := 0;
  v_hard_bonus integer := 0;
  v_milestone_bonus integer := 0;
  v_bonus_event bigint;
  v_points integer := greatest(coalesce(new.points,0),0);
begin
  select rp.account_player_id into v_player_id
    from public.atina_v2_room_players rp
   where rp.id=new.player_id and rp.room_id=new.room_id;

  if v_player_id is null then
    return new;
  end if;

  select * into v_player
    from private.atina_players
   where id=v_player_id
   for update;
  if not found then
    return new;
  end if;

  select * into v_game
    from private.atina_v2_room_game_state
   where room_id=new.room_id;
  if not found or new.challenge_index < 0
     or new.challenge_index+1 > cardinality(v_game.challenge_queue) then
    raise exception 'Não foi possível confirmar o desafio da progressão da sala.';
  end if;

  select * into v_challenge
    from private.atina_challenges
   where challenge_id=v_game.challenge_queue[new.challenge_index+1];
  if not found then
    raise exception 'O desafio da progressão da sala já não existe.';
  end if;

  insert into private.atina_room_progress_events(player_id,room_id,challenge_position,xp)
  values(v_player_id,new.room_id,new.challenge_index+1,10)
  on conflict(player_id,room_id,challenge_position) do nothing
  returning id into v_xp_event;

  if new.is_correct and v_points>0 then
    insert into private.atina_points_events(player_id,source,source_id,challenge_position,points)
    values(v_player_id,'room',new.room_id,new.challenge_index+1,v_points)
    on conflict(player_id,source,source_id,challenge_position) do nothing
    returning id into v_points_event;
  end if;

  if v_xp_event is not null then
    v_daily_count:=case when v_player.daily_date=v_today then v_player.daily_count+1 else 1 end;

    if v_daily_count>=3 and v_player.daily_mission_reward_date is distinct from v_today then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'daily_mission',v_today::text,25)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_mission_bonus:=25; end if;
    end if;

    if v_daily_count>=5 and v_player.daily_reward_date is distinct from v_today then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'daily_five',v_today::text,20)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_daily_bonus:=20; end if;
    end if;

    v_streak:=case
      when v_player.last_active_date=v_today then greatest(v_player.active_streak,1)
      when v_player.last_active_date=v_today-1 then greatest(v_player.active_streak,0)+1
      else 1
    end;
    if v_streak>=7 and v_streak%7=0 and v_player.last_active_date is distinct from v_today then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'streak_seven',v_today::text,50)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_streak_bonus:=50; end if;
    end if;

    if nullif(btrim(v_challenge.category),'') is not null then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'new_category',v_challenge.category,15)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_category_bonus:=15; end if;
    end if;

    if lower(coalesce(v_challenge.difficulty,''))='hard' then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'hard_challenge',v_game.challenge_queue[new.challenge_index+1]::text,20)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_hard_bonus:=20; end if;
    end if;

    if v_player.total_challenges+1>=100 then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'challenge_milestone','100',100)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_milestone_bonus:=100; end if;
    end if;
  end if;

  update private.atina_players
     set total_xp=total_xp+case when v_xp_event is null then 0 else
           10+v_daily_bonus+v_mission_bonus+v_streak_bonus+v_category_bonus+v_hard_bonus+v_milestone_bonus end,
         total_points=total_points+case when v_points_event is null then 0 else v_points end,
         total_challenges=total_challenges+case when v_xp_event is null then 0 else 1 end,
         daily_date=case when v_xp_event is null then daily_date else v_today end,
         daily_count=case when v_xp_event is null then daily_count else least(v_daily_count,5) end,
         daily_reward_date=case when v_daily_bonus>0 then v_today else daily_reward_date end,
         daily_mission_reward_date=case when v_mission_bonus>0 then v_today else daily_mission_reward_date end,
         last_active_date=case when v_xp_event is null then last_active_date else v_today end,
         active_streak=case when v_xp_event is null then active_streak else v_streak end,
         updated_at=clock_timestamp()
   where id=v_player_id;

  return new;
end;
$function$;

revoke all on function private.atina_v2_award_room_player_progress() from public, anon, authenticated;

drop trigger if exists atina_v2_award_room_player_progress_after_answer
  on public.atina_v2_room_answers;
create trigger atina_v2_award_room_player_progress_after_answer
after insert on public.atina_v2_room_answers
for each row execute function private.atina_v2_award_room_player_progress();

-- Synthetic competition progress follows the same base challenge XP rule:
-- 10 XP once per challenge, including an incorrect answer; points only on success.
create or replace function private.atina_v2_award_bot_competition_progress()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile_id integer;
  v_inserted integer;
  v_added_points integer := greatest(coalesce(new.points,0),0);
begin
  select m.bot_profile_id into v_profile_id
    from private.atina_v2_bot_matches m
   where m.room_id=new.room_id and m.bot_player_id=new.player_id;

  if v_profile_id is null then
    return new;
  end if;

  insert into private.atina_v2_bot_competition_events
    (bot_profile_id,source,source_id,challenge_position,points,xp,is_correct)
  values
    (v_profile_id,'room',new.room_id,new.challenge_index+1,
     case when new.is_correct then v_added_points else 0 end,10,new.is_correct)
  on conflict (bot_profile_id,source,source_id,challenge_position) do nothing;

  get diagnostics v_inserted = row_count;

  if v_inserted=1 then
    update private.atina_v2_bot_competition_stats
       set points=points+case when new.is_correct then v_added_points else 0 end,
           xp=xp+10,
           total_challenges=total_challenges+1,
           updated_at=clock_timestamp()
     where bot_profile_id=v_profile_id;
  elsif new.is_correct then
    update private.atina_v2_bot_competition_events
       set points=v_added_points,is_correct=true
     where bot_profile_id=v_profile_id and source='room'
       and source_id=new.room_id and challenge_position=new.challenge_index+1
       and is_correct=false;
    if found then
      update private.atina_v2_bot_competition_stats
         set points=points+v_added_points,updated_at=clock_timestamp()
       where bot_profile_id=v_profile_id;
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function private.atina_v2_award_bot_competition_progress() from public, anon, authenticated;

drop trigger if exists atina_v2_award_bot_competition_progress_after_answer
  on public.atina_v2_room_answers;
create trigger atina_v2_award_bot_competition_progress_after_answer
after insert on public.atina_v2_room_answers
for each row execute function private.atina_v2_award_bot_competition_progress();
