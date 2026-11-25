-- Testes de proposta; executar apenas depois de aplicar a proposta numa base local descartável.
BEGIN;
SELECT plan(9);

SELECT is(
  (SELECT count(*)::integer FROM cron.job
   WHERE active AND jobname IN (
     'atina-v2-bot-simulated-games',
     'atina-v2-bot-presence-refresh',
     'atina-v2-confirm-simulated-room-players'
   )),
  0,
  'não ficam rotinas automáticas agendadas'
);

SELECT ok(
  NOT (private.atina_online_snapshot() ? 'simulated'),
  'a resposta de presença não expõe uma lista simulada'
);

SELECT is(
  (private.atina_online_snapshot()->'counts'->>'total')::integer,
  jsonb_array_length(private.atina_online_snapshot()->'humans'),
  'o total online corresponde à lista de jogadores'
);

SELECT is(
  public.atina_v2_online_players(),
  private.atina_online_snapshot()->'humans',
  'a lista pública contém apenas jogadores reais'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.atina_v2_create_bot_match(text)', 'EXECUTE'),
  'a criação de partidas automáticas não é acessível publicamente'
);

SELECT ok(
  NOT has_function_privilege('authenticated', 'public.atina_v2_bot_tick(uuid,text)', 'EXECUTE'),
  'a rotina de avanço automático não é acessível a contas autenticadas'
);

SELECT ok(
  position('atina_v2_bot_competition' IN pg_get_functiondef('public.atina_points_leaderboard(integer)'::regprocedure)) = 0,
  'o ranking de pontos não consulta resultados automáticos'
);

SELECT ok(
  position('atina_v2_bot_competition' IN pg_get_functiondef('public.atina_progress_leaderboard(integer)'::regprocedure)) = 0,
  'o ranking de progressão não consulta resultados automáticos'
);

SELECT ok(
  position('atina_v2_bot_competition' IN pg_get_functiondef('public.atina_qi_leaderboard(integer)'::regprocedure)) = 0
  AND position('atina_v2_bot_competition' IN pg_get_functiondef('public.atina_qi_my_score(text)'::regprocedure)) = 0,
  'o QI e a pontuação individual usam apenas resultados de jogadores'
);

SELECT * FROM finish();
ROLLBACK;
