BEGIN;
SELECT plan(5);

INSERT INTO private.atina_challenges (
  challenge_id, category, emoji, clues, answer, accepted_answers, difficulty, active
) VALUES (
  -992001, '__xp_extra_test__', '🧪',
  '["Pista 1","Pista 2","Pista 3","Pista 4","Pista 5"]'::jsonb,
  'resposta de teste', '["resposta de teste"]'::jsonb, 'medium', true
);

INSERT INTO private.atina_players (device_token_hash,nickname)
VALUES (
  extensions.digest(convert_to(repeat('c',64),'UTF8'),'sha256'),
  'xp-extra-test'
);

INSERT INTO private.atina_player_accounts (
  player_id,nickname,password_hash,recovery_key_hash,session_token_hash,session_expires_at
)
SELECT
  player.id,
  'xp-extra-test',
  'test-password-hash',
  'test-recovery-hash',
  extensions.digest(convert_to(repeat('d',64),'UTF8'),'sha256'),
  clock_timestamp()+interval '1 hour'
FROM private.atina_players player
WHERE player.device_token_hash=extensions.digest(convert_to(repeat('c',64),'UTF8'),'sha256');

CREATE TEMP TABLE atina_xp_extra_session AS
SELECT public.atina_v2_start_local_game(
  'solo','medium','__xp_extra_test__',0,repeat('c',64)
) AS result;

UPDATE private.atina_v2_local_sessions
   SET special_card='{"id":"xp_extra"}'::jsonb,
       round_locked=true,
       answered_count=1,
       last_result='{"outcome":"correct","points":10}'::jsonb
 WHERE id=(SELECT (result->'state'->>'session_id')::uuid FROM atina_xp_extra_session);

CREATE TEMP TABLE atina_xp_extra_claim AS
SELECT public.atina_progress_claim_local(
  repeat('c',64),
  (result->'state'->>'session_id')::uuid,
  repeat('d',64),
  1
) AS result
FROM atina_xp_extra_session;

SELECT is(
  (SELECT (result->>'challenge_xp')::integer FROM atina_xp_extra_claim),
  10,
  'A resposta correta mantém os 10 XP base'
);
SELECT is(
  (SELECT (result->>'special_card_bonus')::integer FROM atina_xp_extra_claim),
  10,
  'A carta XP Extra acrescenta 10 XP'
);
SELECT is(
  (SELECT (result->>'bonus_total')::integer FROM atina_xp_extra_claim),
  25,
  'O total de bónus inclui a primeira categoria e XP Extra'
);
SELECT is(
  (SELECT (result->>'xp')::integer FROM atina_xp_extra_claim),
  35,
  'O total de XP persistido inclui base, categoria e carta especial'
);
SELECT ok(
  position('special_card_bonus' in pg_get_functiondef('public.atina_progress_claim_local(text,uuid,text,integer)'::regprocedure)) > 0,
  'A resposta da progressão expõe o bónus especial de XP'
);

SELECT * FROM finish();
ROLLBACK;
