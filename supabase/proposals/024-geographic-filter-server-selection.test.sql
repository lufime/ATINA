begin;
select plan(4);

delete from private.atina_v2_local_sessions where category='ATINA GEO TEST';
delete from private.atina_challenges where category='ATINA GEO TEST';
insert into private.atina_challenges
  (challenge_id,category,emoji,clues,answer,accepted_answers,image_url,active,difficulty,geographic_scope)
values
  (990101,'ATINA GEO TEST','🧭','["p1","p2","p3","p4","p5"]'::jsonb,'Portugal fixture','["Portugal fixture"]'::jsonb,null,true,'medium','Portugal'),
  (990102,'ATINA GEO TEST','🧭','["p1","p2","p3","p4","p5"]'::jsonb,'Portugal fixture 2','["Portugal fixture 2"]'::jsonb,null,true,'medium','Portugal'),
  (990103,'ATINA GEO TEST','🧭','["p1","p2","p3","p4","p5"]'::jsonb,'International fixture','["International fixture"]'::jsonb,null,true,'medium','Internacional');

create temporary table atina_geo_test_session as
select (public.atina_v2_start_local_game(
  p_game_mode=>'mix',
  p_difficulty=>'mixed',
  p_challenge_count=>2,
  p_geographic_scope=>'Portugal',
  p_category=>'ATINA GEO TEST',
  p_timed_mode_seconds=>0,
  p_device_token=>null
)->'state'->>'session_id')::uuid as session_id;

select is(
  (select cardinality(s.challenge_queue) from private.atina_v2_local_sessions s join atina_geo_test_session t on t.session_id=s.id),
  2,
  'server returns the requested number of challenges inside the selected scope'
);

select ok(
  (select bool_and(c.geographic_scope='Portugal')
     from private.atina_v2_local_sessions s
     join atina_geo_test_session t on t.session_id=s.id
     cross join lateral unnest(s.challenge_queue) q(challenge_id)
     join private.atina_challenges c on c.challenge_id=q.challenge_id),
  'every challenge in the server queue matches Portugal'
);

select throws_ok(
  $$select public.atina_v2_start_local_game('mix','mixed',1,'Atlantis','ATINA GEO TEST',0,null)$$,
  '22023',
  'Âmbito geográfico inválido.',
  'rejects unknown geographic scopes'
);

select is(
  (select count(*)::integer from private.atina_challenges where challenge_id in (990101,990102,990103)),
  3,
  'geographic fixtures remain isolated for cleanup'
);

delete from private.atina_v2_local_sessions where category='ATINA GEO TEST';
delete from private.atina_challenges where category='ATINA GEO TEST';
select * from finish();
rollback;
