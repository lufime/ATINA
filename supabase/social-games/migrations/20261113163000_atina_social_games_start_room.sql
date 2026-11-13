-- ATINA social games: authoritative start of a five-game social session.
-- Isolated migration: never place in supabase/migrations or apply to production.
alter table private.atina_social_rooms
  add column round_duration_seconds integer
  check (round_duration_seconds is null or round_duration_seconds between 30 and 180);

create or replace function public.atina_social_game_start_room(
 p_room_id uuid,
 p_token text,
 p_game_code text,
 p_play_mode text,
 p_difficulty text,
 p_total_rounds integer,
 p_round_duration_seconds integer default 60
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
 v_actor uuid;
 v_room private.atina_social_rooms%rowtype;
 v_content private.atina_social_content%rowtype;
 v_selected bigint[] := array[]::bigint[];
 v_player_count integer;
 v_team_count integer;
 v_min_team integer;
 v_max_team integer;
 v_available integer;
 v_round integer;
 v_deadline timestamptz;
 v_public jsonb;
 v_secret jsonb;
begin
 if p_room_id is null or p_token is null or length(p_token)<32 then
  raise exception using errcode='28000',message='INVALID_TOKEN';
 end if;
 v_actor:=private.atina_social_player_id_for_token(p_room_id,p_token);
 if v_actor is null then raise exception using errcode='28000',message='INVALID_TOKEN'; end if;

 select * into v_room from private.atina_social_rooms r where r.id=p_room_id for update;
 if not found then raise exception using errcode='P0002',message='ROOM_NOT_FOUND'; end if;
 if v_room.host_player_id<>v_actor then raise exception using errcode='42501',message='NOT_HOST'; end if;
 if v_room.status<>'waiting' then raise exception using errcode='P0001',message='ROOM_NOT_WAITING'; end if;

 if p_game_code is null or p_game_code not in
  ('quanto_achas','associacao_palavras','isto_ou_aquilo','misterio_impossivel','palavra_proibida') then
  raise exception using errcode='22023',message='GAME_NOT_ALLOWED';
 end if;
 if p_play_mode is null or p_play_mode not in ('individual','teams') then
  raise exception using errcode='22023',message='INVALID_MODE';
 end if;
 if p_difficulty is null or p_difficulty not in ('easy','medium','hard','mixed') then
  raise exception using errcode='22023',message='INVALID_DIFFICULTY';
 end if;
 if p_total_rounds is null or p_total_rounds not between 1 and 50 then
  raise exception using errcode='22023',message='INVALID_ROUND_COUNT';
 end if;
 if p_round_duration_seconds is null or p_round_duration_seconds not between 30 and 180 then
  raise exception using errcode='22023',message='INVALID_ROUND_DURATION';
 end if;

 select count(*) into v_player_count from private.atina_social_players p where p.room_id=p_room_id;
 if v_player_count<1 then raise exception using errcode='P0001',message='NO_PLAYERS'; end if;
 if p_play_mode='teams' then
  select count(*),min(team_size),max(team_size)
   into v_team_count,v_min_team,v_max_team
   from (
    select t.id,count(p.id)::integer as team_size
    from private.atina_social_teams t
    left join private.atina_social_players p on p.team_id=t.id and p.room_id=t.room_id
    where t.room_id=p_room_id group by t.id
   ) sizes;
  if v_team_count<2 or v_min_team<1 then
   raise exception using errcode='22023',message='TEAMS_INCOMPLETE';
  end if;
  if exists(select 1 from private.atina_social_players p where p.room_id=p_room_id and p.team_id is null) then
   raise exception using errcode='22023',message='PLAYERS_UNASSIGNED';
  end if;
  if v_max_team-v_min_team>1 then
   raise exception using errcode='22023',message='TEAMS_UNBALANCED';
  end if;
 else
  if exists(select 1 from private.atina_social_players p where p.room_id=p_room_id and p.team_id is not null) then
   raise exception using errcode='22023',message='TEAMS_PRESENT_IN_INDIVIDUAL_MODE';
  end if;
 end if;

 select count(*) into v_available
 from private.atina_social_content c
 where c.active and c.game_code=p_game_code
   and (p_difficulty='mixed' or c.difficulty=p_difficulty);
 if v_available<p_total_rounds then
  raise exception using errcode='P0001',message='INSUFFICIENT_CONTENT';
 end if;

 v_deadline:=clock_timestamp()+make_interval(secs=>p_round_duration_seconds);
 for v_round in 1..p_total_rounds loop
  select c.* into v_content
  from private.atina_social_content c
  where c.active and c.game_code=p_game_code
    and (p_difficulty='mixed' or c.difficulty=p_difficulty)
    and not (c.id=any(v_selected))
  order by random()
  limit 1;
  if not found then
   raise exception using errcode='P0001',message='INSUFFICIENT_CONTENT';
  end if;
  v_selected:=array_append(v_selected,v_content.id);
  v_public:=v_content.payload-'solution'-'answer'-'secret'-'target'-'forbidden_words';
  v_secret:=jsonb_strip_nulls(jsonb_build_object(
   'solution',v_content.payload->'solution',
   'answer',v_content.payload->'answer',
   'secret',v_content.payload->'secret',
   'target',v_content.payload->'target',
   'forbidden_words',v_content.payload->'forbidden_words'
  ));
  insert into private.atina_social_rounds(
   room_id,round_number,content_id,game_code,difficulty,phase,
   prompt_public,secret_payload,started_at,deadline_at
  ) values(
   p_room_id,v_round,v_content.id,p_game_code,v_content.difficulty,'answer',
   v_public,v_secret,clock_timestamp(),
   case when v_round=1 then v_deadline else null end
  );
 end loop;

 update private.atina_social_rooms
 set status='playing',game_code=p_game_code,play_mode=p_play_mode,
     difficulty=p_difficulty,total_rounds=p_total_rounds,current_round=1,
     phase='answer',round_duration_seconds=p_round_duration_seconds,
     deadline_at=v_deadline,state_version=state_version+1,
     updated_at=clock_timestamp()
 where id=p_room_id;

 return jsonb_build_object(
  'ok',true,'room_id',p_room_id,'game_code',p_game_code,
  'play_mode',p_play_mode,'difficulty',p_difficulty,
  'total_rounds',p_total_rounds,'current_round',1,
  'round_duration_seconds',p_round_duration_seconds,
  'deadline_at',v_deadline,'selected_content_count',cardinality(v_selected)
 );
end
$$;

revoke all on function public.atina_social_game_start_room(uuid,text,text,text,text,integer,integer) from public,anon,authenticated;
grant execute on function public.atina_social_game_start_room(uuid,text,text,text,text,integer,integer) to anon,authenticated;
