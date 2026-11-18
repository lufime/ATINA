-- Ensure the legacy site-presence relation exists on clean installations.
-- Existing installations keep their rows and constraints; this is a no-op there.
CREATE TABLE IF NOT EXISTS private.atina_site_presence (
  session_id uuid PRIMARY KEY,
  last_seen_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  nickname text,
  account_player_id uuid
);

-- Count unique human identities and bot profiles from one server-side snapshot.
ALTER TABLE private.atina_site_presence
  ADD COLUMN IF NOT EXISTS account_player_id uuid;

CREATE INDEX IF NOT EXISTS atina_site_presence_last_seen_idx
  ON private.atina_site_presence (last_seen_at DESC);
CREATE INDEX IF NOT EXISTS atina_site_presence_account_active_idx
  ON private.atina_site_presence (account_player_id, last_seen_at DESC)
  WHERE account_player_id IS NOT NULL;

-- Replace the legacy overloads so PostgREST has one unambiguous heartbeat RPC.
DROP FUNCTION IF EXISTS public.atina_site_presence_heartbeat(uuid, text);
DROP FUNCTION IF EXISTS public.atina_site_presence_heartbeat(uuid);

CREATE FUNCTION public.atina_site_presence_heartbeat(
  p_session_id uuid,
  p_nickname text DEFAULT NULL,
  p_session_token text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_account_player_id uuid;
  v_account_nickname text;
  v_nickname text;
BEGIN
  IF p_session_id IS NULL THEN
    RAISE EXCEPTION 'Sessão de presença inválida.' USING errcode = '22023';
  END IF;

  IF p_session_token IS NOT NULL AND p_session_token ~ '^[0-9a-f]{64}$' THEN
    SELECT a.player_id, a.nickname
      INTO v_account_player_id, v_account_nickname
      FROM private.atina_player_accounts a
     WHERE a.session_token_hash = extensions.digest(convert_to(p_session_token, 'UTF8'), 'sha256')
       AND a.session_expires_at > statement_timestamp()
     LIMIT 1;
  END IF;

  v_nickname := CASE
    WHEN v_account_player_id IS NOT NULL THEN v_account_nickname
    ELSE nullif(left(btrim(coalesce(p_nickname, '')), 40), '')
  END;

  INSERT INTO private.atina_site_presence
    (session_id, last_seen_at, nickname, account_player_id)
  VALUES
    (p_session_id, statement_timestamp(), v_nickname, v_account_player_id)
  ON CONFLICT (session_id) DO UPDATE
    SET last_seen_at = EXCLUDED.last_seen_at,
        nickname = CASE
          WHEN EXCLUDED.account_player_id IS NOT NULL THEN EXCLUDED.nickname
          ELSE coalesce(private.atina_site_presence.nickname, EXCLUDED.nickname)
        END,
        account_player_id = coalesce(EXCLUDED.account_player_id, private.atina_site_presence.account_player_id);

  DELETE FROM private.atina_site_presence
   WHERE last_seen_at < statement_timestamp() - interval '30 days';

  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_site_presence_heartbeat(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_site_presence_heartbeat(uuid, text, text) TO anon, authenticated;

-- This private function is the single source of truth for both counters and the directory.
CREATE OR REPLACE FUNCTION private.atina_online_snapshot()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  WITH human_candidates AS (
    SELECT
      coalesce('account:' || p.account_player_id::text, 'guest:' || p.session_id::text) AS identity,
      coalesce(nullif(btrim(p.nickname), ''), 'Visitante') AS nickname,
      p.last_seen_at
    FROM private.atina_site_presence p
    WHERE p.last_seen_at >= statement_timestamp() - interval '60 seconds'

    -- Room membership uses a room-scoped token and does not carry a verified
    -- account_player_id. Do not infer account identity from nickname or room id:
    -- site presence is the authoritative, account-deduplicated human heartbeat.
  ),
  unique_humans AS (
    SELECT DISTINCT ON (identity) identity, nickname
    FROM human_candidates
    ORDER BY identity, last_seen_at DESC
  ),
  bot_candidates AS (
    SELECT b.id AS bot_id, b.nickname
    FROM private.atina_v2_bot_profiles b
    WHERE b.active
      AND private.atina_v2_bot_is_available(b)

    UNION ALL

    -- Keep a bot visible while its live room session is active, even if its
    -- simulated site-presence window has just expired.
    SELECT b.id AS bot_id, b.nickname
    FROM private.atina_v2_bot_matches m
    JOIN private.atina_v2_bot_profiles b ON b.id = m.bot_profile_id
    JOIN public.atina_v2_rooms r ON r.id = m.room_id
    JOIN public.atina_v2_room_players rp ON rp.id = m.bot_player_id
    WHERE r.status IN ('waiting', 'playing')
      AND rp.is_bot IS TRUE
      AND rp.last_seen_at >= statement_timestamp() - interval '90 seconds'
  ),
  unique_bots AS (
    SELECT DISTINCT ON (bot_id) bot_id, nickname
    FROM bot_candidates
    ORDER BY bot_id
  ),
  human_result AS (
    SELECT
      coalesce(jsonb_agg(
        jsonb_build_object('id', 'human:' || encode(extensions.digest(convert_to(identity, 'UTF8'), 'sha256'), 'hex'), 'type', 'human', 'nickname', nickname, 'online', true)
        ORDER BY nickname, identity
      ), '[]'::jsonb) AS players,
      count(*)::integer AS total
    FROM unique_humans
  ),
  bot_result AS (
    SELECT
      coalesce(jsonb_agg(
        jsonb_build_object('id', 'bot:' || encode(extensions.digest(convert_to(bot_id::text, 'UTF8'), 'sha256'), 'hex'), 'type', 'bot', 'nickname', nickname, 'online', true)
        ORDER BY nickname, bot_id
      ), '[]'::jsonb) AS players,
      count(*)::integer AS total
    FROM unique_bots
  )
  SELECT jsonb_build_object(
    'humans', human_result.players,
    'bots', bot_result.players,
    'counts', jsonb_build_object(
      'humans', human_result.total,
      'bots', bot_result.total,
      'total', human_result.total + bot_result.total
    )
  )
  FROM human_result CROSS JOIN bot_result;
$function$;

REVOKE ALL ON FUNCTION private.atina_online_snapshot() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.atina_online_player_stats()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT private.atina_online_snapshot();
$function$;

CREATE OR REPLACE FUNCTION public.atina_online_player_count()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT (private.atina_online_snapshot()->'counts'->>'total')::integer;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_online_players()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT coalesce(snapshot->'humans', '[]'::jsonb)
       || coalesce(snapshot->'bots', '[]'::jsonb)
  FROM (SELECT private.atina_online_snapshot() AS snapshot) AS current_snapshot;
$function$;

REVOKE ALL ON FUNCTION public.atina_online_player_stats() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.atina_online_player_count() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.atina_v2_online_players() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_online_player_stats() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atina_online_player_count() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_online_players() TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
