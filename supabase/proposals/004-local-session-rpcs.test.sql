begin;
select plan(8);

insert into private.atina_challenges (
  challenge_id, category, emoji, clues, answer, accepted_answers, difficulty, active
) values (
  -990001, '__pgTAP_session_fixture__', '🧪',
  '["Pista inicial","Segunda pista","Terceira pista","Quarta pista","Quinta pista"]'::jsonb,
  'Coração de Leão', '["coracao de leao"]'::jsonb, 'easy', true
);

create temporary table _atina_test_session as
select
  (r->>'token') as token,
  ((r->'state')->>'session_id')::uuid as session_id
from (select public.atina_start_local_game(
  'solo', 'easy', '__pgTAP_session_fixture__', 0
) as r) started;

select ok(
  (public.atina_local_game_state(session_id, token)#>>'{challenge,answer}') is null,
  'o estado inicial não revela a resposta'
) from _atina_test_session;

select ok(
  jsonb_array_length(public.atina_local_game_state(session_id, token)#>'{challenge,clues}') = 1,
  'o estado inicial revela apenas a primeira pista'
) from _atina_test_session;

select ok(
  jsonb_array_length(public.atina_local_reveal_clue(session_id, token)#>'{challenge,clues}') = 2,
  'a RPC revela exatamente uma pista adicional'
) from _atina_test_session;

select ok(
  (public.atina_local_submit_answer(session_id, token, 'resposta errada')->>'round_locked') = 'false',
  'uma resposta errada não fecha a ronda'
) from _atina_test_session;

select ok(
  (public.atina_local_game_state(session_id, token)->'scores'->>0)::integer = -10,
  'uma resposta errada aplica a penalização no servidor'
) from _atina_test_session;

select ok(
  (public.atina_local_submit_answer(session_id, token, 'coracao de leao')->'challenge'->>'answer') = 'Coração de Leão',
  'a solução só é devolvida depois de uma resposta correta'
) from _atina_test_session;

select ok(
  (public.atina_local_game_state(session_id, token)->'scores'->>0)::integer = 0,
  'a pontuação correta é calculada no servidor após a penalização anterior'
) from _atina_test_session;

select throws_ok(
  format('select public.atina_local_game_state(%L::uuid, %L)', session_id, 'token-incorreto'),
  '28000',
  'Sessão inválida ou expirada.',
  'um token incorreto não obtém estado da sessão'
) from _atina_test_session;

select * from finish();
rollback;
