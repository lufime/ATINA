BEGIN;
SELECT plan(12);

SELECT ok(private.atina_nickname_is_allowed('Ana'), 'Accepts a normal short nickname');
SELECT ok(private.atina_nickname_is_allowed('João Silva'), 'Accepts Portuguese accents and spaces');
SELECT ok(private.atina_nickname_is_allowed('Marta_2026'), 'Accepts ordinary digits and separators');
SELECT ok(NOT private.atina_nickname_is_allowed('Puta'), 'Rejects a prohibited Portuguese term');
SELECT ok(NOT private.atina_nickname_is_allowed('P.U.T.A'), 'Rejects punctuation-obfuscated terms');
SELECT ok(NOT private.atina_nickname_is_allowed('P0rra'), 'Rejects common number substitutions');
SELECT ok(NOT private.atina_nickname_is_allowed('Carálho'), 'Rejects accented variants');
SELECT ok(NOT private.atina_nickname_is_allowed('Filho da puta'), 'Rejects abusive multi-word phrases');
SELECT ok(NOT private.atina_nickname_is_allowed('MotherFucker'), 'Rejects English profanity');
SELECT ok(private.atina_nickname_is_allowed('Disputado'), 'Does not reject innocent words containing similar letter sequences');

SELECT throws_ok(
  $$ select public.atina_progress_register('P.U.T.A', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') $$,
  '22023',
  'Este pseudónimo não é permitido. Escolhe um nome respeitador e adequado a todos os públicos.',
  'The public guest registration RPC blocks offensive nicknames'
);

SELECT throws_ok(
  $$ select public.atina_account_register('P0rra', 'SenhaSegura123!') $$,
  '22023',
  'Este pseudónimo não é permitido. Escolhe um nome respeitador e adequado a todos os públicos.',
  'The account registration RPC blocks offensive nicknames'
);

SELECT * FROM finish();
ROLLBACK;
