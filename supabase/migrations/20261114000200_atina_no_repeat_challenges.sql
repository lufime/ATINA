-- Permanent no-repeat history for ATINA challenges.
-- Player scope is tied to the authenticated ATINA player; team scope is tied to
-- the stable membership fingerprint of the room team (accounts or guest nicknames).

create table if not exists private.atina_challenge_exposures (
  id bigint generated always as identity primary key,
  scope_type text not null check (scope_type in ('player','team')),
  scope_key text not null,
  challenge_id integer not null,
  first_seen_at timestamptz not null default clock_timestamp(),
  unique (scope_type,scope_key,challenge_id)
);
alter table private.atina_challenge_exposures enable row level security;
revoke all on table private.atina_challenge_exposures from public,anon,authenticated;
create index if not exists atina_challenge_exposures_scope_idx
  on private.atina_challenge_exposures(scope_type,scope_key,first_seen_at desc);

-- One stable scope per team in a room. Registered players use their immutable
-- player UUID; guests use a normalized nickname hash. Membership changes form
-- a different team identity, while the same group can carry its history to a
-- later room.
create or replace function private.atina_room_challenge_scopes(p_room_id uuid)
returns table(scope_type text,scope_key text)
language sql
stable
security definer
set search_path = ''
as $function$
  with members as (
    select p.team_label,
           coalesce('account:'||a.player_id::text,
                    'guest:'||md5(lower(btrim(p.nickname)))) as member_key
      from public.atina_v2_room_players p
      left join private.atina_player_accounts a
        on a.nickname_normalized=lower(btrim(p.nickname))
     where p.room_id=p_room_id
  ),
  teams as (
    select md5(string_agg(member_key,'|' order by member_key)) as fingerprint
      from members
     where team_label is not null
     group by team_label
  ),
  unassigned as (
    select distinct member_key from members where team_label is null
  )
  select 'team'::text,'team:'||fingerprint from teams
  union all
  select 'player'::text,'player:'||member_key from unassigned;
$function$;

create or replace function private.atina_record_room_challenge_exposure(
  p_room_id uuid,p_challenge_id integer
) returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into private.atina_challenge_exposures(scope_type,scope_key,challenge_id)
  select s.scope_type,s.scope_key,p_challenge_id
    from private.atina_room_challenge_scopes(p_room_id) s
  on conflict(scope_type,scope_key,challenge_id) do nothing;
end;
$function$;

-- Local Solo/Mix selection excludes every challenge already presented to this
-- player, rather than only the most recent 30 attempts. A completed pool is
-- reported honestly instead of silently replaying old challenges.
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
    if p_game_mode not in ('solo','mix') then
      raise exception 'A progressão individual só está disponível em Solo e Mix.' using errcode='22023';
    end if;
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

create or replace function public.atina_v2_local_next_challenge(
  p_session_id uuid,p_token text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_session private.atina_v2_local_sessions;
  v_next_position integer;
  v_card jsonb;
  v_now timestamptz;
  v_player_id uuid;
begin
  select * into v_session
    from private.atina_v2_local_sessions
   where id=p_session_id
     and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
   for update;
  if not found then raise exception 'Sessão inválida ou expirada.' using errcode='28000'; end if;
  v_now:=clock_timestamp();
  if v_session.expires_at<=v_now then raise exception 'Sessão inválida ou expirada.' using errcode='28000'; end if;
  if v_session.status<>'active' or not v_session.round_locked then
    raise exception 'Fecha a ronda antes de avançar.' using errcode='55000';
  end if;

  v_next_position:=v_session.position+1;
  if v_next_position>cardinality(v_session.challenge_queue) then
    update private.atina_v2_local_sessions
       set status='completed',round_locked=true,deadline_at=null,updated_at=v_now
     where id=v_session.id returning * into v_session;
    return private.atina_v2_local_public_state(v_session);
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

  update private.atina_v2_local_sessions
     set position=v_next_position,current_player=v_session.current_player,
         revealed_clues=1,round_locked=false,
         deadline_at=case when timed_mode_seconds=0 then null
           else v_now+make_interval(secs=>timed_mode_seconds) end,
         special_card=v_card,last_result='{}'::jsonb,updated_at=v_now
   where id=v_session.id returning * into v_session;

  select o.player_id into v_player_id
    from private.atina_xp_session_owners o where o.session_id=v_session.id;
  if v_player_id is not null then
    insert into private.atina_challenge_exposures(scope_type,scope_key,challenge_id)
    values('player',v_player_id::text,v_session.challenge_queue[v_next_position])
    on conflict(scope_type,scope_key,challenge_id) do nothing;
  end if;

  return private.atina_v2_local_public_state(v_session);
end;
$function$;

create or replace function public.atina_v2_start_room_challenges(
  p_room_id uuid,
  p_token text,
  p_difficulty text default 'medium',
  p_duration_seconds integer default 60,
  p_category text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_host public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_queue integer[];
  v_now timestamptz;
  v_deadline timestamptz;
  v_challenge private.atina_challenges%rowtype;
  v_state jsonb;
begin
  if p_difficulty is null or p_difficulty not in ('easy','medium','hard') then
    raise exception 'Dificuldade inválida.';
  end if;
  if p_duration_seconds is null or p_duration_seconds not between 0 and 3600 then
    raise exception 'Duração inválida.';
  end if;
  if p_category is not null and char_length(btrim(p_category)) not between 1 and 80 then
    raise exception 'Categoria inválida.';
  end if;

  select * into v_host from public.atina_v2_room_players
   where room_id=p_room_id
     and token_hash=extensions.digest(coalesce(p_token,''),'sha256')
   for update;
  if not found or not v_host.is_host then
    raise exception 'Só o anfitrião pode iniciar os desafios.';
  end if;

  select * into v_room from public.atina_v2_rooms where id=p_room_id for update;
  if not found or v_room.status<>'playing' or v_room.game_state->>'mode'<>'pending' then
    raise exception 'A sala não está preparada para iniciar os desafios.';
  end if;

  select array_agg(c.challenge_id order by random())
    into v_queue
    from private.atina_challenges c
   where c.active and c.difficulty=p_difficulty
     and (p_category is null or c.category=p_category)
     and not exists (
       select 1
         from private.atina_room_challenge_scopes(p_room_id) s
         join private.atina_challenge_exposures e
           on e.scope_type=s.scope_type and e.scope_key=s.scope_key
        where e.challenge_id=c.challenge_id
     );

  if coalesce(cardinality(v_queue),0)=0 then
    raise exception 'Esta equipa já viu todos os desafios disponíveis para estes critérios. Experimenta outra categoria ou dificuldade.';
  end if;

  v_now:=clock_timestamp();
  v_deadline:=case when p_duration_seconds=0 then null
    else v_now+make_interval(secs=>p_duration_seconds) end;

  insert into private.atina_v2_room_game_state(
    room_id,challenge_queue,position,difficulty,category,timed_mode_seconds,
    revealed_clues,deadline_at,round_locked,status,created_at,updated_at
  ) values (
    p_room_id,v_queue,1,p_difficulty,p_category,p_duration_seconds,
    1,v_deadline,false,'active',v_now,v_now
  );

  perform private.atina_record_room_challenge_exposure(p_room_id,v_queue[1]);

  select * into v_challenge from private.atina_challenges
   where challenge_id=v_queue[1] and active;

  v_state:=jsonb_build_object(
    'mode','challenges','protocol_version',1,
    'challenge_id',v_challenge.challenge_id,'category',v_challenge.category,
    'emoji',v_challenge.emoji,'clues',jsonb_build_array(v_challenge.clues->0),
    'image_url',v_challenge.image_url,'pos',0,'queue_length',cardinality(v_queue),
    'revealed',1,'timedMode',p_duration_seconds,
    'deadline',case when v_deadline is null then 0 else extract(epoch from v_deadline)*1000 end,
    'locked',false,'revision',v_room.state_version+1
  );

  update public.atina_v2_rooms
     set game_state=v_state,state_version=state_version+1,updated_at=v_now
   where id=p_room_id;

  return jsonb_build_object('status','started','queue_length',cardinality(v_queue),'state',v_state);
end;
$function$;

create or replace function public.atina_v2_next_room_challenge(
  p_room_id uuid,p_token text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_now timestamptz;
  v_state jsonb;
  v_results jsonb;
begin
  select * into v_player from public.atina_v2_room_players
   where room_id=p_room_id
     and token_hash=extensions.digest(coalesce(p_token,''),'sha256')
   for update;
  if not found or not v_player.is_host then
    raise exception 'Só o anfitrião pode avançar o desafio.';
  end if;
  select * into v_room from public.atina_v2_rooms where id=p_room_id for update;
  if not found or v_room.status<>'playing' then raise exception 'A partida não está ativa.'; end if;
  select * into v_game from private.atina_v2_room_game_state where room_id=p_room_id for update;
  if not found or v_game.status<>'active' then raise exception 'A ronda não está ativa.'; end if;
  v_now:=clock_timestamp();

  if v_game.position<cardinality(v_game.challenge_queue) then
    update private.atina_v2_room_game_state
       set position=position+1,revealed_clues=1,round_locked=false,
           deadline_at=case when timed_mode_seconds=0 then null
             else v_now+make_interval(secs=>timed_mode_seconds) end,
           updated_at=v_now
     where room_id=p_room_id;
    perform private.atina_record_room_challenge_exposure(
      p_room_id,v_game.challenge_queue[v_game.position+1]
    );
    v_state:=private.atina_v2_room_public_state(p_room_id);
    update public.atina_v2_rooms
       set game_state=v_state,state_version=state_version+1,updated_at=v_now
     where id=p_room_id;
    return jsonb_build_object('status','next','state',v_state);
  end if;

  update private.atina_v2_room_game_state
     set status='completed',round_locked=true,updated_at=v_now
   where room_id=p_room_id;

  insert into public.atina_v2_room_results(room_id,player_id,nickname,team_label,score,completed_at)
  select p.room_id,p.id,p.nickname,p.team_label,p.score,v_now
    from public.atina_v2_room_players p
   where p.room_id=p_room_id
  on conflict(room_id,player_id) do update
    set nickname=excluded.nickname,team_label=excluded.team_label,
        score=excluded.score,completed_at=excluded.completed_at;

  select coalesce(jsonb_agg(jsonb_build_object(
    'player_id',r.player_id,'nickname',r.nickname,'team',r.team_label,'score',r.score
  ) order by r.score desc,r.nickname),'[]'::jsonb)
    into v_results from public.atina_v2_room_results r where r.room_id=p_room_id;

  update public.atina_v2_rooms
     set status='completed',
         game_state=jsonb_build_object(
           'mode','completed','protocol_version',1,
           'pos',cardinality(v_game.challenge_queue),
           'queue_length',cardinality(v_game.challenge_queue),
           'locked',true,'revision',state_version+1
         ),
         state_version=state_version+1,updated_at=v_now
   where id=p_room_id;

  return jsonb_build_object('status','completed','results',v_results);
end;
$function$;

revoke all on function private.atina_room_challenge_scopes(uuid) from public,anon,authenticated;
revoke all on function private.atina_record_room_challenge_exposure(uuid,integer) from public,anon,authenticated;
revoke all on function public.atina_v2_start_local_game(text,text,text,integer,text) from public;
grant execute on function public.atina_v2_start_local_game(text,text,text,integer,text) to anon,authenticated;
revoke all on function public.atina_v2_local_next_challenge(uuid,text) from public;
grant execute on function public.atina_v2_local_next_challenge(uuid,text) to anon,authenticated;
revoke all on function public.atina_v2_start_room_challenges(uuid,text,text,integer,text) from public;
grant execute on function public.atina_v2_start_room_challenges(uuid,text,text,integer,text) to anon,authenticated;
revoke all on function public.atina_v2_next_room_challenge(uuid,text) from public;
grant execute on function public.atina_v2_next_room_challenge(uuid,text) to anon,authenticated;
