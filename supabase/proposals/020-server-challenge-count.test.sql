begin;
select plan(4);

delete from private.atina_v2_local_sessions where category='ATINA COUNT TEST';
delete from private.atina_challenges where category='ATINA COUNT TEST';
insert into private.atina_challenges(challenge_id,category,emoji,clues,answer,accepted_answers,image_url,active,difficulty)
select 990001+i,'ATINA COUNT TEST','🧪','["p1","p2","p3","p4","p5"]'::jsonb,'fixture '||i,jsonb_build_array('fixture '||i),null,true,'medium'
from generate_series(0,9) i;

insert into private.atina_players(id,device_token_hash,nickname)
values('00000000-0000-0000-0000-000000009372',extensions.digest(convert_to('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','UTF8'),'sha256'),'ATINA COUNT TEST PLAYER');

select is(
  (public.atina_v2_start_local_game('solo','medium','ATINA COUNT TEST',0,null,1)->'state'->>'queue_size')::integer,
  1,
  'server queue respects configured count of one'
);
select is(
  (public.atina_v2_start_local_game('solo','medium','ATINA COUNT TEST',0,null,10)->'state'->>'queue_size')::integer,
  10,
  'server queue respects configured count of ten'
);
select throws_ok(
  $$select public.atina_v2_start_local_game('solo','medium','ATINA COUNT TEST',0,null,11)$$,
  '22023',
  null,
  'rejects requested count greater than available challenges'
);

select is(
  (select player_id::text from private.atina_xp_session_owners
   where session_id=(public.atina_v2_start_local_game('solo','medium','ATINA COUNT TEST',0,'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',1)->'state'->>'session_id')::uuid),
  '00000000-0000-0000-0000-000000009372',
  'start RPC preserves pseudonymous XP session binding while limiting challenge count'
);

delete from private.atina_v2_local_sessions where category='ATINA COUNT TEST';
delete from private.atina_xp_session_owners where player_id='00000000-0000-0000-0000-000000009372';
delete from private.atina_players where id='00000000-0000-0000-0000-000000009372';
delete from private.atina_challenges where category='ATINA COUNT TEST';
select * from finish();
rollback;
