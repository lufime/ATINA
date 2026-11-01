begin;
select plan(6);

insert into private.atina_challenges
(challenge_id,category,emoji,clues,answer,accepted_answers,difficulty,active)
values (-990011,'__deadline_fix__','🧪','["a","b","c","d","e"]'::jsonb,'Teste','["teste"]'::jsonb,'easy',true);

create temporary table _reveal_timeout as
select (x.r->>'token') token, ((x.r->'state')->>'session_id')::uuid sid
from (select public.atina_start_local_game('solo','easy','__deadline_fix__',60) r) x;
update private.atina_local_sessions set deadline_at=clock_timestamp()-interval '1 second'
where id=(select sid from _reveal_timeout);

select ok((public.atina_local_reveal_clue(sid,token)->>'round_locked')='true',
          'revelar pista após deadline fecha a ronda') from _reveal_timeout;
select ok((public.atina_local_game_state(sid,token)->'last_result'->>'outcome')='timeout',
          'revelar pista após deadline regista timeout') from _reveal_timeout;

create temporary table _pass_timeout as
select (x.r->>'token') token, ((x.r->'state')->>'session_id')::uuid sid
from (select public.atina_start_local_game('solo','easy','__deadline_fix__',60) r) x;
update private.atina_local_sessions set deadline_at=clock_timestamp()-interval '1 second'
where id=(select sid from _pass_timeout);

select ok((public.atina_local_pass_challenge(sid,token)->>'round_locked')='true',
          'passar após deadline fecha a ronda') from _pass_timeout;
select ok((public.atina_local_game_state(sid,token)->'scores'->>0)::int=-10,
          'passar após deadline aplica penalização') from _pass_timeout;
select ok((public.atina_local_game_state(sid,token)->'last_result'->>'outcome')='timeout',
          'passar após deadline regista timeout') from _pass_timeout;
select ok((select count(*)=3 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in
 ('atina_local_game_state','atina_local_reveal_clue','atina_local_pass_challenge')
 and p.prosecdef and p.proconfig @> array['search_path=""']),
 'as três RPCs mantêm SECURITY DEFINER com search_path vazio');

select * from finish();
rollback;
