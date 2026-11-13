begin;
do $$
declare h jsonb; g jsonb; s jsonb; rid uuid; ht text; gt text; pid uuid; t1 uuid; t2 uuid;
begin
 h:=public.atina_v2_create_room('Anfitriao manual',8); rid:=(h->>'room_id')::uuid; ht:=h->>'token';
 g:=public.atina_v2_join_room('Jogador dois',h->>'code'); gt:=g->>'token'; pid:=(g->>'player_id')::uuid;
 t1:=(public.atina_social_team_create(rid,ht,'Azul')->>'team_id')::uuid;
 t2:=(public.atina_social_team_create(rid,ht,'Vermelha')->>'team_id')::uuid;
 perform public.atina_social_team_assign_player(rid,ht,(h->>'player_id')::uuid,t1);
 perform public.atina_social_team_assign_player(rid,ht,pid,t2);
 s:=public.atina_v2_room_state(rid,ht);
 if (select count(*) from private.atina_social_players p where p.room_id=rid and p.team_id is not null)<>2 then raise exception 'Manual team assignment incomplete'; end if;
 if (select count(distinct p.team_id) from private.atina_social_players p where p.room_id=rid)<>2 then raise exception 'Manual assignment did not preserve selected teams'; end if;
 begin perform public.atina_social_team_create(rid,gt,'Não autorizado'); raise exception 'Non-host created a team';
 exception when insufficient_privilege then null; end;
 begin perform public.atina_social_team_assign_player(rid,ht,pid,gen_random_uuid()); raise exception 'Unknown team accepted';
 exception when sqlstate '22023' then null; end;
end $$;
rollback;
