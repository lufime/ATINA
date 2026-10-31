-- ATINA multiplayer lobby RPCs. All room access is token-authenticated.
-- SECURITY DEFINER is required because direct table privileges are revoked.
-- Every function uses an empty search_path and schema-qualified references.
CREATE OR REPLACE FUNCTION public.atina_create_room(p_nickname text, p_max_players integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$;
declare
 v_room public.atina_rooms%rowtype; v_player public.atina_room_players%rowtype;
 v_token text; v_code text; v_attempt integer:=0;
begin
 if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 32 then raise exception 'Pseudónimo inválido.'; end if;
 if p_max_players is null or p_max_players not between 2 and 20 then raise exception 'Número de jogadores inválido.'; end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 loop
  v_code:=upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,6));
  begin
   insert into public.atina_rooms(code,max_players) values(v_code,p_max_players) returning * into v_room;
   exit;
  exception when unique_violation then
   v_attempt:=v_attempt+1;
   if v_attempt>=8 then raise exception 'Não foi possível gerar um código de sala. Tenta novamente.'; end if;
  end;
 end loop;
 insert into public.atina_room_players(room_id,token_hash,nickname,is_host,ready)
 values(v_room.id,extensions.digest(v_token,'sha256'),btrim(p_nickname),true,true)
 returning * into v_player;
 return jsonb_build_object('room_id',v_room.id,'token',v_token,'code',v_room.code,'player_id',v_player.id);
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_join_room(p_nickname text, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$;
declare
 v_room public.atina_rooms%rowtype; v_player public.atina_room_players%rowtype;
 v_token text;
begin
 if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 32 then raise exception 'Pseudónimo inválido.'; end if;
 if p_code is null or p_code !~ '^[A-Za-z0-9]{6}$' then raise exception 'Código de sala inválido.'; end if;
 select * into v_room from public.atina_rooms where code=upper(p_code) for update;
 if not found or v_room.status<>'waiting' then raise exception 'Sala não encontrada ou já iniciada.'; end if;
 if (select count(*) from public.atina_room_players where room_id=v_room.id)>=v_room.max_players then raise exception 'A sala está cheia.'; end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.atina_room_players(room_id,token_hash,nickname,is_host,ready)
 values(v_room.id,extensions.digest(v_token,'sha256'),btrim(p_nickname),false,false)
 returning * into v_player;
 return jsonb_build_object('room_id',v_room.id,'token',v_token,'code',v_room.code,'player_id',v_player.id);
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_leave_room(p_room_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$;
declare v_player public.atina_room_players%rowtype; v_count integer;
begin
 select * into v_player from public.atina_room_players
 where room_id=p_room_id and token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
 if not found then return jsonb_build_object('left',true); end if;
 perform 1 from public.atina_rooms where id=p_room_id for update;
 delete from public.atina_room_players where id=v_player.id;
 select count(*) into v_count from public.atina_room_players where room_id=p_room_id;
 if v_count=0 then
  delete from public.atina_rooms where id=p_room_id;
 else
  if v_player.is_host then
   update public.atina_room_players set is_host=true,ready=true
   where id=(select id from public.atina_room_players where room_id=p_room_id order by created_at,id limit 1);
  end if;
 end if;
 return jsonb_build_object('left',true);
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_room_state(p_room_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$;
declare v_me public.atina_room_players%rowtype; v_room public.atina_rooms%rowtype;
declare v_players jsonb; v_team_proposal jsonb; v_team text;
begin
 select * into v_me from public.atina_room_players
 where room_id=p_room_id and token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
 if not found then raise exception 'Sessão da sala inválida.'; end if;
 select * into v_room from public.atina_rooms where id=p_room_id;
 if not found then raise exception 'Sala não encontrada.'; end if;
 update public.atina_room_players set last_seen_at=clock_timestamp() where id=v_me.id;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'nickname',p.nickname,'is_host',p.is_host,'ready',p.ready,
  'team',p.team_label,'score',p.score
 ) order by p.created_at,p.id),'[]'::jsonb)
 into v_players from public.atina_room_players p where p.room_id=p_room_id;
 v_team:=v_me.team_label;
 if v_team is not null then
  select jsonb_build_object(
   'id',pr.id,'team',pr.team_label,'proposer_id',pr.proposer_id,
   'proposer',pp.nickname,'answer',pr.answer_text,'status',pr.status,
   'votes',coalesce((select jsonb_agg(jsonb_build_object('player_id',v.player_id,'agrees',v.agrees) order by v.created_at)
    from public.atina_room_team_votes v where v.proposal_id=pr.id),'[]'::jsonb)
  ) into v_team_proposal
  from public.atina_room_team_proposals pr
  join public.atina_room_players pp on pp.id=pr.proposer_id
  where pr.room_id=p_room_id and pr.team_label=v_team
    and pr.challenge_index=coalesce((v_room.game_state->>'pos')::integer,-1)
  order by pr.created_at desc limit 1;
 end if;
 return jsonb_build_object(
  'room_id',v_room.id,'code',v_room.code,'status',v_room.status,
  'max_players',v_room.max_players,'is_host',v_me.is_host,
  'player_id',v_me.id,'ready',v_me.ready,'team',v_team,
  'my_score',v_me.score,'players',v_players,
  'game_state',v_room.game_state,
  'team_proposal',v_team_proposal,
  'timeouts',jsonb_build_object(
   'player_remaining_seconds',v_me.player_timeout_seconds,
   'team_remaining_seconds',case when v_team is null then 0 else 3600 end
  )
 );
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_set_room_ready(p_room_id uuid, p_token text, p_ready boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$;
declare v_player public.atina_room_players%rowtype; v_room public.atina_rooms%rowtype;
begin
 if p_ready is null then raise exception 'Estado de prontidão inválido.'; end if;
 select * into v_player from public.atina_room_players
 where room_id=p_room_id and token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
 if not found then raise exception 'Sessão da sala inválida.'; end if;
 select * into v_room from public.atina_rooms where id=p_room_id for update;
 if v_room.status<>'waiting' then raise exception 'A sala já foi iniciada.'; end if;
 update public.atina_room_players set ready=p_ready,last_seen_at=clock_timestamp() where id=v_player.id;
 return jsonb_build_object('ready',p_ready);
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_set_room_team(p_room_id uuid, p_token text, p_player_id uuid, p_team text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$;
declare v_host public.atina_room_players%rowtype; v_room public.atina_rooms%rowtype;
begin
 select * into v_host from public.atina_room_players
 where room_id=p_room_id and token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
 if not found or not v_host.is_host then raise exception 'Só o anfitrião pode atribuir equipas.'; end if;
 select * into v_room from public.atina_rooms where id=p_room_id for update;
 if v_room.status<>'waiting' then raise exception 'As equipas já não podem ser alteradas.'; end if;
 if p_team is null or btrim(p_team)='' then
  update public.atina_room_players set team_label=null where room_id=p_room_id and id=p_player_id;
 else
  if char_length(btrim(p_team))>32 then raise exception 'Nome de equipa demasiado longo.'; end if;
  update public.atina_room_players set team_label=btrim(p_team) where room_id=p_room_id and id=p_player_id;
 end if;
 if not found then raise exception 'Jogador não encontrado nesta sala.'; end if;
 return jsonb_build_object('player_id',p_player_id,'team',nullif(btrim(coalesce(p_team,'')),''));
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_start_room(p_room_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$;
declare v_host public.atina_room_players%rowtype; v_room public.atina_rooms%rowtype;
declare v_count integer; v_unready integer;
begin
 select * into v_host from public.atina_room_players
 where room_id=p_room_id and token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
 if not found or not v_host.is_host then raise exception 'Só o anfitrião pode iniciar a sala.'; end if;
 select * into v_room from public.atina_rooms where id=p_room_id for update;
 if v_room.status<>'waiting' then raise exception 'A sala já foi iniciada.'; end if;
 select count(*),count(*) filter(where not ready) into v_count,v_unready
 from public.atina_room_players where room_id=p_room_id;
 if v_count<2 then raise exception 'São necessários pelo menos dois jogadores.'; end if;
 if v_unready>0 then raise exception 'Todos os jogadores têm de confirmar que estão prontos.'; end if;
 update public.atina_rooms set status='playing',updated_at=clock_timestamp(),
  game_state=jsonb_build_object('mode','pending','started_at',clock_timestamp())
 where id=p_room_id;
 return jsonb_build_object('status','playing','players',v_count);
end;
$function$;


revoke all on function public.atina_create_room(text,integer) from public;
revoke all on function public.atina_join_room(text,text) from public;
revoke all on function public.atina_set_room_ready(uuid,text,boolean) from public;
revoke all on function public.atina_set_room_team(uuid,text,uuid,text) from public;
revoke all on function public.atina_start_room(uuid,text) from public;
revoke all on function public.atina_room_state(uuid,text) from public;
revoke all on function public.atina_leave_room(uuid,text) from public;
grant execute on function public.atina_create_room(text,integer) to anon,authenticated;
grant execute on function public.atina_join_room(text,text) to anon,authenticated;
grant execute on function public.atina_set_room_ready(uuid,text,boolean) to anon,authenticated;
grant execute on function public.atina_set_room_team(uuid,text,uuid,text) to anon,authenticated;
grant execute on function public.atina_start_room(uuid,text) to anon,authenticated;
grant execute on function public.atina_room_state(uuid,text) to anon,authenticated;
grant execute on function public.atina_leave_room(uuid,text) to anon,authenticated;
