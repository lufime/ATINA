begin;
select plan(3);

delete from private.atina_v2_local_sessions where category='ATINA COUNT TEST';
delete from private.atina_challenges where category='ATINA COUNT TEST';
insert into private.atina_challenges(challenge_id,category,emoji,clues,answer,accepted_answers,image_url,active,difficulty)
select 990001+i,'ATINA COUNT TEST','🧪','["p1","p2","p3","p4","p5"]'::jsonb,'fixture '||i,jsonb_build_array('fixture '||i),null,true,'medium'
from generate_series(0,9) i;

select is(
  (public.atina_v2_start_local_game('solo','medium','ATINA COUNT TEST',0,1)->'state'->>'queue_size')::integer,
  1,
  'server queue respects configured count of one'
);
select is(
  (public.atina_v2_start_local_game('solo','medium','ATINA COUNT TEST',0,10)->'state'->>'queue_size')::integer,
  10,
  'server queue respects configured count of ten'
);
select throws_ok(
  $$select public.atina_v2_start_local_game('solo','medium','ATINA COUNT TEST',0,11)$$,
  '22023',
  null,
  'rejects requested count greater than available challenges'
);

delete from private.atina_v2_local_sessions where category='ATINA COUNT TEST';
delete from private.atina_challenges where category='ATINA COUNT TEST';
select * from finish();
rollback;
