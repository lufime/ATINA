CREATE OR REPLACE FUNCTION private.atina_online_snapshot()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path=''
AS $$
  WITH human_candidates AS (
    SELECT
      coalesce('account:' || p.account_player_id::text, 'guest:' || p.session_id::text) AS identity,
      coalesce(nullif(btrim(p.nickname), ''), 'Visitante') AS nickname,
      p.last_seen_at
    FROM private.atina_site_presence p
    WHERE p.last_seen_at >= statement_timestamp() - interval '60 seconds'
    UNION ALL
    SELECT
      'account:' || rp.account_player_id::text AS identity,
      coalesce(nullif(btrim(rp.nickname), ''), 'Jogador') AS nickname,
      rp.last_seen_at
    FROM public.atina_v2_room_players rp
    JOIN public.atina_v2_rooms r ON r.id = rp.room_id
    WHERE rp.account_player_id IS NOT NULL
      AND r.status IN ('waiting', 'playing')
      AND rp.last_seen_at >= statement_timestamp() - interval '90 seconds'
  ),
  unique_humans AS (
    SELECT DISTINCT ON (identity) identity, nickname
    FROM human_candidates
    ORDER BY identity, last_seen_at DESC
  ),
  result AS (
    SELECT
      coalesce(jsonb_agg(
        jsonb_build_object(
          'id', 'human:' || encode(extensions.digest(convert_to(identity, 'UTF8'), 'sha256'), 'hex'),
          'type', 'human',
          'nickname', nickname,
          'online', true
        ) ORDER BY nickname, identity
      ), '[]'::jsonb) AS players,
      count(*)::integer AS total
    FROM unique_humans
  )
  SELECT jsonb_build_object(
    'humans', result.players,
    'counts', jsonb_build_object('humans', result.total, 'total', result.total)
  )
  FROM result;
$$;

CREATE OR REPLACE FUNCTION public.atina_online_player_stats()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT private.atina_online_snapshot();
$$;

CREATE OR REPLACE FUNCTION public.atina_v2_online_players()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT coalesce(private.atina_online_snapshot()->'humans', '[]'::jsonb);
$$;

REVOKE ALL ON FUNCTION public.atina_online_player_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_online_player_stats() TO anon, authenticated;
REVOKE ALL ON FUNCTION public.atina_v2_online_players() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_v2_online_players() TO anon, authenticated;
