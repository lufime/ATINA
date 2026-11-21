-- Track durable online time for each ATINA site-presence session.
ALTER TABLE private.atina_site_presence
  ADD COLUMN IF NOT EXISTS session_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS online_seconds_total bigint NOT NULL DEFAULT 0;

UPDATE private.atina_site_presence
SET session_started_at = last_seen_at
WHERE session_started_at IS NULL;

CREATE OR REPLACE FUNCTION public.atina_site_presence_heartbeat(
  p_session_id uuid,
  p_nickname text DEFAULT NULL,
  p_session_token text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_account_player_id uuid;
  v_account_nickname text;
  v_nickname text;
  v_now timestamptz := statement_timestamp();
BEGIN
  IF p_session_id IS NULL THEN
    RAISE EXCEPTION 'Sessão de presença inválida.' USING errcode = '22023';
  END IF;

  IF p_session_token IS NOT NULL AND p_session_token ~ '^[0-9a-f]{64}$' THEN
    SELECT a.player_id, a.nickname
      INTO v_account_player_id, v_account_nickname
      FROM private.atina_player_accounts a
     WHERE a.session_token_hash = extensions.digest(convert_to(p_session_token, 'UTF8'), 'sha256')
       AND a.session_expires_at > v_now
     LIMIT 1;
  END IF;

  v_nickname := CASE
    WHEN v_account_player_id IS NOT NULL THEN v_account_nickname
    ELSE nullif(left(btrim(coalesce(p_nickname, '')), 40), '')
  END;

  INSERT INTO private.atina_site_presence
    (session_id, last_seen_at, nickname, account_player_id, session_started_at, online_seconds_total)
  VALUES
    (p_session_id, v_now, v_nickname, v_account_player_id, v_now, 0)
  ON CONFLICT (session_id) DO UPDATE
    SET online_seconds_total = private.atina_site_presence.online_seconds_total
      + CASE
          WHEN private.atina_site_presence.last_seen_at >= v_now - interval '90 seconds'
          THEN least(30, greatest(0, floor(extract(epoch FROM (v_now - private.atina_site_presence.last_seen_at))::numeric)::bigint))
          ELSE 0
        END,
        session_started_at = CASE
          WHEN private.atina_site_presence.last_seen_at >= v_now - interval '90 seconds'
          THEN coalesce(private.atina_site_presence.session_started_at, private.atina_site_presence.last_seen_at)
          ELSE v_now
        END,
        last_seen_at = v_now,
        nickname = CASE
          WHEN EXCLUDED.account_player_id IS NOT NULL THEN EXCLUDED.nickname
          ELSE coalesce(private.atina_site_presence.nickname, EXCLUDED.nickname)
        END,
        account_player_id = coalesce(EXCLUDED.account_player_id, private.atina_site_presence.account_player_id);

  DELETE FROM private.atina_site_presence
   WHERE last_seen_at < v_now - interval '30 days';

  RETURN true;
END;
$;

CREATE OR REPLACE FUNCTION public.atina_player_online_time_stats()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH grouped AS (
    SELECT
      coalesce('account:' || account_player_id::text, 'session:' || session_id::text) AS identity_key,
      coalesce(max(nullif(btrim(nickname), '')), 'Visitante') AS nickname,
      max(last_seen_at) AS last_seen_at,
      sum(online_seconds_total)::bigint AS total_seconds,
      sum(CASE WHEN last_seen_at >= statement_timestamp() - interval '120 seconds'
        THEN greatest(0, floor(extract(epoch FROM (statement_timestamp() - coalesce(session_started_at, last_seen_at))))::bigint)
        ELSE 0 END)::bigint AS current_seconds,
      bool_or(last_seen_at >= statement_timestamp() - interval '60 seconds') AS online
    FROM private.atina_site_presence
    GROUP BY identity_key
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'nickname', nickname,
    'online', online,
    'last_seen_at', last_seen_at,
    'total_seconds', total_seconds,
    'current_seconds', current_seconds
  ) ORDER BY online DESC, last_seen_at DESC), '[]'::jsonb)
  FROM grouped;
$$;

REVOKE ALL ON FUNCTION public.atina_player_online_time_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_player_online_time_stats() TO authenticated;
