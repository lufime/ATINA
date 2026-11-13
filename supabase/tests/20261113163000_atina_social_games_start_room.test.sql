begin;
do $$
declare
 h jsonb; g jsonb; started jsonb; rid uuid; ht text; gt text;
 p1 uuid; p2 uuid; p3 uuid; t1 uuid; t2 uuid;
begin
 h:=public.atina_v2_create_room('Host start',8);
 rid:=(h->>'room_id')::uuid; ht:=h->>'token'; p1:=(h->>'player_id')::uuid;
 g:=public.atina_v2_join_room('Jogador dois',h->>'code'); gt:=g->>'token'; p2:=(g->>'player_id')::uuid;
 g:=public.atina_v2_join_room('Jogador tres',h->>'code'); p3:=(g->>'player_id')::uuid;
 insert into private.atina_social_content(game_code,difficulty,payload)
 values
 ('quanto_achas','easy','{"prompt":"Quanto pesa?","answer":"10"}'),
 ('quanto_achas','medium','{"prompt":"Quanto mede?","answer":"20"}'),
 ('quanto_achas','hard','{"prompt":"Quanto custa?","answer":"30"}');
 t1:=(public.atina_social_team_create(rid,ht,'Azul')->>'team_id')::uuid;
 t2:=(public.atina_social_team_create(rid,ht,'Vermelha')->>'team_id')::uuid;
 perform public.atina_social_team_assign_player(rid,ht,p1,t1);
 perform public.atina_social_team_assign_player(rid,ht,p2,t2);
 perform public.atina_social_team_assign_player(rid,ht,p3,t1);

 begin
  perform public.atina_social_game_start_room(rid,gt,'quanto_achas','teams','mixed',2,60);
  raise exception 'Non-host started game';
 exception when insufficient_privilege then null; end;

 started:=public.atina_social_game_start_room(rid,ht,'quanto_achas','teams','mixed',2,60);
 if started->>'ok'<>'true' or (started->>'round_duration_seconds')::integer<>60 then
  raise exception 'Start response or duration invalid';
 end if;
 if (select count(*) from private.atina_social_rounds where room_id=rid)<>2 then
  raise exception 'Expected exactly two rounds';
 end if;
 if (select count(distinct content_id) from private.atina_social_rounds where room_id=rid)<>2 then
  raise exception 'Repeated content selected';
 end if;
 if (select round_duration_seconds from private.atina_social_rooms where id=rid)<>60 then
  raise exception 'Room duration not stored';
 end if;
 if (select deadline_at from private.atina_social_rooms where id=rid)
    <= clock_timestamp() then raise exception 'Deadline is not in the future'; end if;
 if (select status from private.atina_social_rooms where id=rid)<>'playing' then
  raise exception 'Room did not enter playing state';
 end if;
end $$;

do $
declare h jsonb; rid uuid; token text;
begin
 h:=public.atina_v2_create_room('Sem catalogo',4);
 rid:=(h->>'room_id')::uuid; token:=h->>'token';
 begin
  perform public.atina_social_game_start_room(rid,token,'unknown','individual','easy',1,60);
  raise exception 'Invalid game accepted';
 exception when sqlstate '22023' then null; end;
 begin
  perform public.atina_social_game_start_room(rid,token,'misterio_impossivel','individual','easy',1,60);
  raise exception using errcode='XX000',message='Missing content accepted';
 exception when sqlstate 'P0001' then null; end;
end $$;
rollback;
