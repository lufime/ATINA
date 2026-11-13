-- Manual team setup RPCs for ATINA social games.
create or replace function public.atina_social_team_create(
 p_room_id uuid, p_token text, p_label text
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare v_actor uuid; v_room private.atina_social_rooms%rowtype; v_team uuid:=gen_random_uuid(); v_order integer;
begin
 v_actor:=private.atina_social_player_id_for_token(p_room_id,p_token);
 if v_actor is null then raise exception using errcode='28000',message='INVALID_TOKEN'; end if;
 select * into v_room from private.atina_social_rooms r where r.id=p_room_id for update;
 if not found then raise exception using errcode='P0002',message='ROOM_NOT_FOUND'; end if;
 if v_room.host_player_id<>v_actor then raise exception using errcode='42501',message='NOT_HOST'; end if;
 if v_room.status<>'waiting' then raise exception using errcode='P0001',message='ROOM_NOT_WAITING'; end if;
 if p_label is null or char_length(btrim(p_label)) not between 1 and 32 then raise exception using errcode='22023',message='INVALID_TEAM_LABEL'; end if;
 select coalesce(max(t.sort_order),0)+1 into v_order from private.atina_social_teams t where t.room_id=p_room_id;
 insert into private.atina_social_teams(id,room_id,label,sort_order) values(v_team,p_room_id,btrim(p_label),v_order);
 return jsonb_build_object('ok',true,'team_id',v_team,'label',btrim(p_label),'sort_order',v_order);
end $$;

create or replace function public.atina_social_team_assign_player(
 p_room_id uuid,p_token text,p_player_id uuid,p_team_id uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare v_actor uuid; v_room private.atina_social_rooms%rowtype;
begin
 v_actor:=private.atina_social_player_id_for_token(p_room_id,p_token);
 if v_actor is null then raise exception using errcode='28000',message='INVALID_TOKEN'; end if;
 select * into v_room from private.atina_social_rooms r where r.id=p_room_id for update;
 if not found then raise exception using errcode='P0002',message='ROOM_NOT_FOUND'; end if;
 if v_room.host_player_id<>v_actor then raise exception using errcode='42501',message='NOT_HOST'; end if;
 if v_room.status<>'waiting' then raise exception using errcode='P0001',message='ROOM_NOT_WAITING'; end if;
 if not exists(select 1 from private.atina_social_teams t where t.id=p_team_id and t.room_id=p_room_id) then raise exception using errcode='22023',message='TEAM_NOT_FOUND'; end if;
 update private.atina_social_players set team_id=p_team_id where id=p_player_id and room_id=p_room_id;
 if not found then raise exception using errcode='22023',message='PLAYER_NOT_FOUND'; end if;
 return jsonb_build_object('ok',true,'player_id',p_player_id,'team_id',p_team_id);
end $$;

revoke all on function public.atina_social_team_create(uuid,text,text) from public,anon,authenticated;
revoke all on function public.atina_social_team_assign_player(uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.atina_social_team_create(uuid,text,text) to anon,authenticated;
grant execute on function public.atina_social_team_assign_player(uuid,text,uuid,uuid) to anon,authenticated;
