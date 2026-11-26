-- ATINA: desativar a experiência de jogadores simulados sem apagar histórico.

-- Parar apenas as rotinas agendadas associadas à simulação.
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname IN (
  'atina-v2-bot-simulated-games',
  'atina-v2-bot-presence-refresh',
  'atina-v2-confirm-simulated-room-players'
);

-- Retirar os jogadores simulados da resposta pública de presença online.
CREATE OR REPLACE FUNCTION private.atina_online_snapshot()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
WITH human_candidates AS (
  SELECT coalesce('account:' || p.account_player_id::text, 'guest:' || p.session_id::text) identity,
         coalesce(nullif(btrim(p.nickname),''),'Visitante') nickname, p.last_seen_at
  FROM private.atina_site_presence p
  WHERE p.last_seen_at >= statement_timestamp()-interval '60 seconds'
  UNION ALL
  SELECT 'account:' || rp.account_player_id::text,
         coalesce(nullif(btrim(rp.nickname),''),'Jogador'), rp.last_seen_at
  FROM public.atina_v2_room_players rp
  JOIN public.atina_v2_rooms r ON r.id=rp.room_id
  WHERE rp.account_player_id IS NOT NULL AND NOT coalesce(rp.is_bot,false)
    AND r.status IN ('waiting','playing')
    AND rp.last_seen_at >= statement_timestamp()-interval '90 seconds'
),
unique_humans AS (
  SELECT DISTINCT ON(identity) identity,nickname
  FROM human_candidates
  ORDER BY identity,last_seen_at DESC
),
human_result AS (
  SELECT coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id','human:'||encode(extensions.digest(convert_to(identity,'UTF8'),'sha256'),'hex'),
               'type','human',
               'nickname',nickname,
               'online',true
             )
             ORDER BY nickname,identity
           ),
           '[]'::jsonb
         ) players,
         count(*)::integer total
  FROM unique_humans
)
SELECT jsonb_build_object(
  'humans',human_result.players,
  'counts',jsonb_build_object('humans',human_result.total,'total',human_result.total)
)
FROM human_result;
$function$;

-- Bloquear os pontos de entrada públicos para criação/execução de partidas simuladas.
REVOKE ALL ON FUNCTION public.atina_v2_create_bot_match(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.atina_v2_bot_tick(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.atina_v2_bot_points_leaderboard(integer) FROM PUBLIC, anon, authenticated;

-- Bloquear a execução direta das rotinas internas de simulação.
REVOKE ALL ON FUNCTION private.atina_v2_simulate_bot_games() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.atina_v2_bot_refresh_presence() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.atina_v2_bot_is_available(private.atina_v2_bot_profiles) FROM PUBLIC, anon, authenticated;
DO $migration$
BEGIN
  -- Esta rotina pode existir em instalações históricas, mas não é criada
  -- por nenhuma migration versionada. Revogar apenas quando estiver presente.
  IF to_regprocedure('private.atina_v2_confirm_simulated_room_players()') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON FUNCTION private.atina_v2_confirm_simulated_room_players() FROM PUBLIC, anon, authenticated';
  END IF;
END;
$migration$;
REVOKE ALL ON FUNCTION private.atina_v2_award_bot_competition_progress() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.atina_v2_remove_bot_when_human_leaves() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.atina_v2_cleanup_abandoned_bot_rooms() FROM PUBLIC, anon, authenticated;

-- Garantir que não ficam triggers ativos para automatismos associados a esses perfis.
DROP TRIGGER IF EXISTS atina_v2_award_bot_competition_progress_after_answer ON public.atina_v2_room_answers;
DROP TRIGGER IF EXISTS atina_v2_cleanup_bot_on_human_leave ON public.atina_v2_room_players;
