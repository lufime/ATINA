-- Isolated ATINA social rooms, player identity and team RPCs.
create or replace function private.atina_social_player_id_for_token(p_room_id uuid,p_token text)
returns uuid language sql stable security definer set search_path = ''
as $$ select p.id from private.atina_social_players p where p.room_id=p_room_id and p.token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256') limit 1 $$;
revoke all on function private.atina_social_player_id_for_token(uuid,text) from public,anon,authenticated;

create or replace function public.atina_v2_create_room(p_nickname text,p_max_players integer default 12)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare v_room uuid:=gen_random_uuid(); v_player uuid:=gen_random_uuid(); v_token text:=encode(extensions.gen_random_bytes(32),'hex'); v_code text; v_alpha constant text:='ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; v_bytes bytea; v_try integer:=0;
begin
 if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 32 then raise exception using errcode='22023',message='INVALID_NICKNAME'; end if;
 if p_max_players is null or p_max_players not between 2 and 20 then raise exception using errcode='22023',message='INVALID_MAX_PLAYERS'; end if;
 loop
  v_try:=v_try+1; v_bytes:=extensions.gen_random_bytes(6); v_code:='';
  for i in 0..5 loop v_code:=v_code||substr(v_alpha,(get_byte(v_bytes,i)%length(v_alpha))+1,1); end loop;
  begin insert into private.atina_social_rooms(id,code,max_players) values(v_room,v_code,p_max_players); exit;
  exception when unique_violation then if v_try>=5 then raise exception using errcode='P0001',message='ROOM_CODE_GENERATION_FAILED'; end if; end;
 end loop;
 insert into private.atina_social_players(id,room_id,token_hash,nickname,is_host) values(v_player,v_room,extensions.digest(convert_to(v_token,'UTF8'),'sha256'),btrim(p_nickname),true);
 update private.atina_social_rooms set host_player_id=v_player where id=v_room;
 return jsonb_build_object('ok',true,'room_id',v_room,'player_id',v_player,'token',v_token,'code',v_code,'status','waiting','is_host',true,'max_players',p_max_players);
end $$;

create or replace function public.atina_v2_join_room(p_nickname text,p_code text)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare v_room private.atina_social_rooms%rowtype; v_player uuid:=gen_random_uuid(); v_token text:=encode(extensions.gen_random_bytes(32),'hex');
begin
 if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 32 then raise exception using errcode='22023',message='INVALID_NICKNAME'; end if;
 if p_code is null or p_code !~ '^[A-Za-z0-9]{6}$' then raise exception using errcode='22023',message='INVALID_ROOM_CODE'; end if;
 select * into v_room from private.atina_social_rooms r where r.code=upper(p_code) for update;
 if not found then raise exception using errcode='P0002',message='ROOM_NOT_FOUND'; end if;
 if v_room.status<>'waiting' then raise exception using errcode='P0001',message='ROOM_NOT_WAITING'; end if;
 if (select count(*) from private.atina_social_players p where p.room_id=v_room.id)>=v_room.max_players then raise exception using errcode='P0001',message='ROOM_FULL'; end if;
 insert into private.atina_social_players(id,room_id,token_hash,nickname) values(v_player,v_room.id,extensions.digest(convert_to(v_token,'UTF8'),'sha256'),btrim(p_nickname));
 return jsonb_build_object('ok',true,'room_id',v_room.id,'player_id',v_player,'token',v_token,'code',v_room.code,'status',v_room.status,'is_host',false,'max_players',v_room.max_players);
end $$;

create or replace function public.atina_v2_room_state(p_room_id uuid,p_token text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_player uuid; v_room private.atina_social_rooms%rowtype; v_players jsonb; v_teams jsonb; v_game jsonb;
begin
 if p_room_id is null or p_token is null or length(p_token)<32 then raise exception using errcode='28000',message='INVALID_TOKEN'; end if;
 v_player:=private.atina_social_player_id_for_token(p_room_id,p_token);
 if v_player is null then raise exception using errcode='28000',message='INVALID_TOKEN'; end if;
 select * into v_room from private.atina_social_rooms r where r.id=p_room_id;
 if not found then raise exception using errcode='P0002',message='ROOM_NOT_FOUND'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'nickname',p.nickname,'is_host',p.is_host,'ready',p.ready,'score',p.score,'team_id',p.team_id) order by p.created_at,p.id),'[]'::jsonb) into v_players from private.atina_social_players p where p.room_id=p_room_id;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'label',t.label,'sort_order',t.sort_order) order by t.sort_order),'[]'::jsonb) into v_teams from private.atina_social_teams t where t.room_id=p_room_id;
 v_game:=case when v_room.status='waiting' then null else jsonb_build_object('mode','social_game','status',v_room.status,'game_code',v_room.game_code,'play_mode',v_room.play_mode,'difficulty',v_room.difficulty,'round',v_room.current_round,'total_rounds',v_room.total_rounds,'phase',v_room.phase,'deadline_at',v_room.deadline_at) end;
 return jsonb_build_object('room_id',v_room.id,'code',v_room.code,'status',v_room.status,'max_players',v_room.max_players,'is_host',(v_room.host_player_id=v_player),'player_id',v_player,'players',v_players,'teams',v_teams,'game_state',v_game);
end $$;

create or replace function public.atina_social_team_auto_assign(p_room_id uuid,p_token text,p_team_count integer)
returns jsonb language plpgsql volatile security definer set search_path = ''
as $$
declare v_actor uuid; v_room private.atina_social_rooms%rowtype; v_count integer; v_ids uuid[];
begin
 v_actor:=private.atina_social_player_id_for_token(p_room_id,p_token);
 if v_actor is null then raise exception using errcode='28000',message='INVALID_TOKEN'; end if;
 select * into v_room from private.atina_social_rooms r where r.id=p_room_id for update;
 if not found then raise exception using errcode='P0002',message='ROOM_NOT_FOUND'; end if;
 if v_room.host_player_id<>v_actor then raise exception using errcode='42501',message='NOT_HOST'; end if;
 if v_room.status<>'waiting' then raise exception using errcode='P0001',message='ROOM_NOT_WAITING'; end if;
 select count(*) into v_count from private.atina_social_players p where p.room_id=p_room_id;
 if p_team_count is null or p_team_count<2 or p_team_count>v_count then raise exception using errcode='22023',message='INVALID_TEAM_COUNT'; end if;
 update private.atina_social_players set team_id=null where room_id=p_room_id;
 delete from private.atina_social_teams where room_id=p_room_id;
 insert into private.atina_social_teams(room_id,label,sort_order) select p_room_id,'Equipa '||n::text,n from generate_series(1,p_team_count) n order by n;
 select array_agg(t.id order by t.sort_order) into v_ids from private.atina_social_teams t where t.room_id=p_room_id;
 with ranked as (select p.id,row_number() over(order by p.created_at,p.id) rn from private.atina_social_players p where p.room_id=p_room_id)
 update private.atina_social_players p set team_id=v_ids[((ranked.rn-1)%p_team_count)::integer+1] from ranked where p.id=ranked.id;
 return jsonb_build_object('ok',true,'team_count',p_team_count,'player_count',v_count,'teams',(select jsonb_agg(jsonb_build_object('id',t.id,'label',t.label,'sort_order',t.sort_order) order by t.sort_order) from private.atina_social_teams t where t.room_id=p_room_id));
end $$;

revoke all on function public.atina_v2_create_room(text,integer) from public,anon,authenticated;
revoke all on function public.atina_v2_join_room(text,text) from public,anon,authenticated;
revoke all on function public.atina_v2_room_state(uuid,text) from public,anon,authenticated;
revoke all on function public.atina_social_team_auto_assign(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.atina_v2_create_room(text,integer) to anon,authenticated;
grant execute on function public.atina_v2_join_room(text,text) to anon,authenticated;
grant execute on function public.atina_v2_room_state(uuid,text) to anon,authenticated;
grant execute on function public.atina_social_team_auto_assign(uuid,text,integer) to anon,authenticated;
