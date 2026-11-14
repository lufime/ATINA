-- ATINA XP phase 2: daily mission, activity streak, category, hard challenge and 100-challenge milestone.
-- Points are deliberately untouched. All bonuses are server-side and idempotent.

alter table private.atina_players
  add column if not exists last_active_date date,
  add column if not exists active_streak integer not null default 0,
  add column if not exists daily_mission_reward_date date;

create table if not exists private.atina_xp_bonus_events (
  id bigint generated always as identity primary key,
  player_id uuid not null references private.atina_players(id) on delete cascade,
  event_type text not null check (event_type in (
    'daily_mission','daily_five','streak_seven','new_category','hard_challenge','challenge_milestone'
  )),
  event_key text not null,
  xp integer not null check (xp > 0),
  created_at timestamptz not null default clock_timestamp(),
  constraint atina_xp_bonus_events_once unique (player_id,event_type,event_key)
);

alter table private.atina_xp_bonus_events enable row level security;
revoke all on table private.atina_xp_bonus_events from public, anon, authenticated;
create index if not exists atina_xp_bonus_events_player_created_idx
  on private.atina_xp_bonus_events (player_id, created_at desc);

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
     or v_outcome not in ('correct','wrong','incorrect')
     or v_session.expires_at<=clock_timestamp() then
    raise exception 'O servidor ainda não confirmou este desafio como concluído.' using errcode='55000';
  end if;

  select * into v_owner from private.atina_xp_session_owners
   where session_id=p_session_id for update;
  if not found or v_owner.player_id<>v_player.id then
    raise exception 'Esta sessão não está associada a esta conta.' using errcode='42501';
  end if;

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
    values(v_player.id,'streak_seven',v_streak::text,50)
    on conflict(player_id,event_type,event_key) do nothing
    returning id into v_bonus_inserted;
    if v_bonus_inserted is not null then v_streak_bonus:=50; end if;
  end if;

  if nullif(btrim(v_challenge.category),'') is not null then
    insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
    values(v_player.id,'new_category',v_challenge.category,15)
    on conflict(player_id,event_type,event_key) do nothing
    returning id into v_bonus_inserted;
    if v_bonus_inserted is not null then v_category_bonus:=15; end if;
  end if;

  if lower(coalesce(v_challenge.difficulty,''))='hard' then
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

revoke all on function public.atina_progress_claim_local(text,uuid,text,integer) from public;
grant execute on function public.atina_progress_claim_local(text,uuid,text,integer) to anon,authenticated;

-- Include streak data in account profiles so the UI can display server-authoritative progress.
create or replace function public.atina_account_profile(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account private.atina_player_accounts;
  v_profile jsonb;
begin
  if p_session_token is null or p_session_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Sessão inválida.' using errcode='28000';
  end if;

  select * into v_account from private.atina_player_accounts
   where session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
     and session_expires_at>clock_timestamp();
  if not found then
    raise exception 'Sessão expirada. Inicia sessão novamente.' using errcode='28000';
  end if;

  select jsonb_build_object(
    'player_id',p.id,'nickname',p.nickname,'xp',p.total_xp,
    'points',p.total_points,'level',floor(p.total_xp/250.0)::integer+1,
    'total_challenges',p.total_challenges,
    'daily_count',case when p.daily_date=current_date then p.daily_count else 0 end,
    'active_streak',p.active_streak,
    'last_active_date',p.last_active_date
  )
  into v_profile from private.atina_players p where p.id=v_account.player_id;
  return v_profile;
end;
$function$;

revoke all on function public.atina_account_profile(text) from public;
grant execute on function public.atina_account_profile(text) to anon,authenticated;
