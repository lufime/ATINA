-- Keep the human-only directory contract while exposing all online participants.
CREATE OR REPLACE FUNCTION private.atina_online_snapshot()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
WITH human_candidates AS (
  SELECT coalesce('account:' || p.account_player_id::text,'guest:' || p.session_id::text) AS identity,
         coalesce(nullif(btrim(p.nickname),''),'Visitante') AS nickname,
         p.last_seen_at
  FROM private.atina_site_presence p
  WHERE p.last_seen_at >= statement_timestamp()-interval '60 seconds'
  UNION ALL
  SELECT 'account:' || rp.account_player_id::text,
         coalesce(nullif(btrim(rp.nickname),''),'Jogador'),
         rp.last_seen_at
  FROM public.atina_v2_room_players rp
  JOIN public.atina_v2_rooms r ON r.id=rp.room_id
  WHERE rp.account_player_id IS NOT NULL
    AND NOT coalesce(rp.is_bot,false)
    AND r.status IN ('waiting','playing')
    AND rp.last_seen_at >= statement_timestamp()-interval '90 seconds'
),
profile_candidates AS (
  SELECT 'profile:' || b.id::text AS identity,
         coalesce(nullif(btrim(b.nickname),''),'Jogador') AS nickname,
         w.online_since AS last_seen_at
  FROM private.atina_v2_bot_profiles b
  JOIN private.atina_v2_bot_presence_windows w ON w.bot_profile_id=b.id
  WHERE b.active AND w.online_since IS NOT NULL
    AND w.online_until > statement_timestamp()
  UNION ALL
  SELECT 'profile:' || b.id::text,
         coalesce(nullif(btrim(b.nickname),''),'Jogador'),
         rp.last_seen_at
  FROM private.atina_v2_bot_matches m
  JOIN private.atina_v2_bot_profiles b ON b.id=m.bot_profile_id
  JOIN public.atina_v2_room_players rp ON rp.id=m.bot_player_id AND rp.room_id=m.room_id
  JOIN public.atina_v2_rooms r ON r.id=m.room_id
  WHERE r.status IN ('waiting','playing')
    AND rp.last_seen_at >= statement_timestamp()-interval '90 seconds'
),
unique_humans AS (
  SELECT DISTINCT ON(identity) identity,nickname
  FROM human_candidates
  ORDER BY identity,last_seen_at DESC
),
unique_profiles AS (
  SELECT DISTINCT ON(identity) identity,nickname
  FROM profile_candidates
  ORDER BY identity,last_seen_at DESC
),
all_players AS (
  SELECT identity,nickname,'human'::text AS player_type FROM unique_humans
  UNION ALL
  SELECT identity,nickname,'training'::text AS player_type FROM unique_profiles
),
player_result AS (
  SELECT
    coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id','player:'||encode(extensions.digest(convert_to(identity,'UTF8'),'sha256'),'hex'),
        'type','human','nickname',nickname,'online',true
      ) ORDER BY nickname,identity)
      FROM unique_humans
    ),'[]'::jsonb) AS humans,
    coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id','player:'||encode(extensions.digest(convert_to(identity,'UTF8'),'sha256'),'hex'),
        'type',player_type,'nickname',nickname,'online',true
      ) ORDER BY nickname,identity)
      FROM all_players
    ),'[]'::jsonb) AS players,
    (SELECT count(*)::integer FROM unique_humans) AS human_total,
    (SELECT count(*)::integer FROM all_players) AS total
)
SELECT jsonb_build_object(
  'players',player_result.players,
  'humans',player_result.humans,
  'counts',jsonb_build_object(
    'players',player_result.total,
    'humans',player_result.human_total,
    'total',player_result.total
  )
)
FROM player_result;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_online_players()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT coalesce(private.atina_online_snapshot()->'players','[]'::jsonb);
$function$;
