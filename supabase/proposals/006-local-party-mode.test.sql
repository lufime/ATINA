begin;
select plan(4);
insert into private.atina_challenges
(challenge_id,category,emoji,clues,answer,accepted_answers,difficulty,active)
values (-990021,'__party_final__','🎉','["a","b","c","d","e"]'::jsonb,'Teste Festa','["teste festa"]'::jsonb,'easy',true);
create temporary table _party_all as
select (r->>'token') token, ((r->'state')->>'session_id')::uuid sid,
       (r->'state'->>'queue_size')::int queue_size
from (select public.atina_start_local_game('party','easy',null,0) r) x;
select ok((select queue_size=10 from _party_all),'Party limita a fila a dez desafios');
create temporary table _party_final as
select (r->>'token') token, ((r->'state')->>'session_id')::uuid sid
from (select public.atina_start_local_game('party','easy','__party_final__',0) r) x;
select ok((select (public.atina_local_game_state(sid,token)->>'mode')='party' from _party_final),
 'servidor inicia o modo Party');
select ok((select (public.atina_local_submit_answer(sid,token,'teste festa')->'last_result'->>'points')::int=20 from _party_final),
 'a última ronda Party duplica os pontos calculados');
select ok((select (public.atina_local_game_state(sid,token)->'last_result'->>'party_final_round_bonus')='true' from _party_final),
 'estado identifica o bónus da ronda final');
select * from finish();
rollback;
