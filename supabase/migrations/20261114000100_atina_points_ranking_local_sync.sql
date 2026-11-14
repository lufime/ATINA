-- Keep the global points ranking in source control and make local-game awards visible
-- in the same transaction that records XP. No historical/backfill awards are performed.

alter table private.atina_players
  add column if not exists total_points integer not null default 0;

create table if not exists private.atina_points_events (
  id bigint generated always as identity primary key,
  player_id uuid not null references private.atina_players(id) on delete cascade,
  source text not null check (source in ('local', 'room')),
  source_id uuid not null,
  challenge_position integer not null check (challenge_position > 0),
  points integer not null check (points > 0),
  created_at timestamptz not null default clock_timestamp(),
  constraint atina_points_events_once
    unique (player_id, source, source_id, challenge_position)
);

alter table private.atina_points_events enable row level security;
revoke all on table private.atina_points_events from public, anon, authenticated;

create index if not exists atina_points_events_player_created_idx
  on private.atina_points_events (player_id, created_at desc);

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
  v_inserted bigint;
  v_points_inserted bigint;
  v_today date := current_date;
  v_daily_count integer;
  v_award integer;
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
    raise exception 'Inicia sessão para guardar os pontos.' using errcode='28000';
  end if;

  select * into v_session from private.atina_v2_local_sessions
   where id=p_session_id
     and token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
   for update;

  if not found or v_session.position<>p_position or not v_session.round_locked
     or v_session.last_result->>'outcome' is distinct from 'correct'
     or v_session.expires_at<=clock_timestamp() then
    raise exception 'O servidor ainda não confirmou este desafio como concluído.' using errcode='55000';
  end if;

  select * into v_owner from private.atina_xp_session_owners
   where session_id=p_session_id for update;

  if not found or v_owner.player_id<>v_player.id then
    raise exception 'Esta sessão não está associada a esta conta.' using errcode='42501';
  end if;

  v_award:=coalesce((v_session.last_result->>'points')::integer,0);
  if v_award<=0 then
    raise exception 'Não foi possível confirmar os pontos deste desafio.' using errcode='55000';
  end if;

  insert into private.atina_xp_events(player_id,session_id,challenge_position,xp)
  values(v_player.id,p_session_id,p_position,v_award)
  on conflict(player_id,session_id,challenge_position) do nothing
  returning id into v_inserted;

  if v_inserted is null then
    return jsonb_build_object(
      'awarded',false,'reason','already_claimed',
      'xp',v_player.total_xp,'points',v_player.total_points,
      'level',floor(v_player.total_xp/250.0)::integer+1,
      'total_challenges',v_player.total_challenges,
      'daily_count',case when v_player.daily_date=v_today then v_player.daily_count else 0 end
    );
  end if;

  insert into private.atina_points_events(player_id,source,source_id,challenge_position,points)
  values(v_player.id,'local',p_session_id,p_position,v_award)
  on conflict(player_id,source,source_id,challenge_position) do nothing
  returning id into v_points_inserted;

  v_daily_count:=case when v_player.daily_date=v_today then v_player.daily_count+1 else 1 end;

  update private.atina_players
     set total_xp=total_xp+v_award,
         total_points=total_points+case when v_points_inserted is null then 0 else v_award end,
         total_challenges=total_challenges+1,
         daily_date=v_today,
         daily_count=least(v_daily_count,3),
         updated_at=clock_timestamp()
   where id=v_player.id
  returning * into v_player;

  return jsonb_build_object(
    'awarded',true,'challenge_xp',v_award,
    'challenge_points',case when v_points_inserted is null then 0 else v_award end,
    'daily_bonus',0,'xp',v_player.total_xp,'points',v_player.total_points,
    'level',floor(v_player.total_xp/250.0)::integer+1,
    'total_challenges',v_player.total_challenges,'daily_count',v_player.daily_count
  );
end;
$function$;

create or replace function public.atina_points_leaderboard(p_limit integer default 50)
returns table(nickname text, points integer, challenges integer)
language sql
stable
security definer
set search_path = ''
as $function$
  select p.nickname,p.total_points,p.total_challenges
    from private.atina_players p
   where p.total_points>0
   order by p.total_points desc,p.total_challenges desc,p.created_at asc
   limit least(greatest(coalesce(p_limit,50),1),100);
$function$;

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
    'points',p.total_points,
    'level',floor(p.total_xp/250.0)::integer+1,
    'total_challenges',p.total_challenges,
    'daily_count',case when p.daily_date=current_date then p.daily_count else 0 end
  )
  into v_profile from private.atina_players p where p.id=v_account.player_id;

  return v_profile;
end;
$function$;

-- Include points in the profile returned immediately after password login.
create or replace function public.atina_account_login(p_nickname text,p_password text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account private.atina_player_accounts;
  v_failure private.atina_account_auth_failures;
  v_session_token text;
  v_profile jsonb;
  v_now timestamptz := clock_timestamp();
begin
  if p_password is null or octet_length(convert_to(p_password,'UTF8')) > 72 then
    return jsonb_build_object('ok',false,'message','Pseudónimo ou palavra-passe incorretos.');
  end if;

  select * into v_account from private.atina_player_accounts
   where nickname_normalized=lower(btrim(coalesce(p_nickname,''))) for update;

  if not found then
    return jsonb_build_object('ok',false,'message','Pseudónimo ou palavra-passe incorretos.');
  end if;

  select * into v_failure from private.atina_account_auth_failures
   where account_id=v_account.id for update;
  if found and v_failure.locked_until is not null and v_failure.locked_until>v_now then
    return jsonb_build_object('ok',false,'message','Não foi possível iniciar sessão. Aguarda 15 minutos e tenta novamente.');
  end if;

  if v_account.password_hash <> extensions.crypt(p_password,v_account.password_hash) then
    insert into private.atina_account_auth_failures(account_id,failed_attempts,window_started_at,locked_until,updated_at)
    values(v_account.id,1,v_now,null,v_now)
    on conflict(account_id) do update set
      failed_attempts=case when private.atina_account_auth_failures.window_started_at<=v_now-interval '15 minutes'
        then 1 else private.atina_account_auth_failures.failed_attempts+1 end,
      window_started_at=case when private.atina_account_auth_failures.window_started_at<=v_now-interval '15 minutes'
        then v_now else private.atina_account_auth_failures.window_started_at end,
      locked_until=case
        when (case when private.atina_account_auth_failures.window_started_at<=v_now-interval '15 minutes'
          then 1 else private.atina_account_auth_failures.failed_attempts+1 end)>=5
        then v_now+interval '15 minutes' else null end,
      updated_at=v_now;
    return jsonb_build_object('ok',false,'message','Pseudónimo ou palavra-passe incorretos.');
  end if;

  delete from private.atina_account_auth_failures where account_id=v_account.id;
  v_session_token := encode(extensions.gen_random_bytes(32),'hex');
  update private.atina_player_accounts set session_token_hash=extensions.digest(convert_to(v_session_token,'UTF8'),'sha256'),
    session_expires_at=v_now+interval '30 days',updated_at=v_now where id=v_account.id;

  select jsonb_build_object('player_id',p.id,'nickname',p.nickname,'xp',p.total_xp,
    'points',p.total_points,
    'level',floor(p.total_xp/250.0)::integer+1,'total_challenges',p.total_challenges,
    'daily_count',case when p.daily_date=current_date then p.daily_count else 0 end)
    into v_profile from private.atina_players p where p.id=v_account.player_id;

  return jsonb_build_object('ok',true,'session_token',v_session_token,'profile',v_profile);
end;
$function$;

revoke all on function public.atina_progress_claim_local(text,uuid,text,integer) from public;
grant execute on function public.atina_progress_claim_local(text,uuid,text,integer) to anon,authenticated;
revoke all on function public.atina_points_leaderboard(integer) from public;
grant execute on function public.atina_points_leaderboard(integer) to anon,authenticated;
revoke all on function public.atina_account_profile(text) from public;
grant execute on function public.atina_account_profile(text) to anon,authenticated;
revoke all on function public.atina_account_login(text,text) from public;
grant execute on function public.atina_account_login(text,text) to anon,authenticated;
