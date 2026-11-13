-- pgTAP wrapper: execute the assertions as one reported test.
begin;
select plan(1);
select lives_ok($atina_test$\ndo $$
declare h jsonb; g jsonb; sh jsonb; sg jsonb; teams jsonb; rid uuid; ht text; gt text;
begin
 h:=public.atina_v2_create_room('Anfitriao',6); rid:=(h->>'room_id')::uuid; ht:=h->>'token';
 if h->>'ok'<>'true' or length(ht)<32 or h->>'is_host'<>'true' then raise exception 'Invalid host creation payload'; end if;
 g:=public.atina_v2_join_room('Convidado',h->>'code'); gt:=g->>'token';
 if g->>'ok'<>'true' or g->>'is_host'<>'false' then raise exception 'Invalid guest join payload'; end if;
 sh:=public.atina_v2_room_state(rid,ht); sg:=public.atina_v2_room_state(rid,gt);
 if sh->>'is_host'<>'true' or sg->>'is_host'<>'false' then raise exception 'Incorrect host identity'; end if;
 if jsonb_array_length(sh->'players')<>2 then raise exception 'Both players not returned'; end if;
 if (sh->'players'->0 ? 'token') or (sh->'players'->1 ? 'token') then raise exception 'Bearer token leaked'; end if;
 teams:=public.atina_social_team_auto_assign(rid,ht,2);
 if teams->>'ok'<>'true' or (teams->>'team_count')::integer<>2 then raise exception 'Auto team assignment failed'; end if;
 if (select count(distinct p.team_id) from private.atina_social_players p where p.room_id=rid)<>2 then raise exception 'Players not distributed'; end if;
 begin perform public.atina_v2_room_state(rid,'invalid-token-that-is-long-enough-123456'); raise exception 'Invalid token accepted';
 exception when sqlstate '28000' then null; end;
 begin perform public.atina_social_team_auto_assign(rid,gt,2); raise exception 'Non-host changed teams';
 exception when insufficient_privilege then null; end;
end $$;\n$atina_test$, '20261113161000_atina_social_games_rooms_teams: all assertions execute without error');
select * from finish();
rollback;
