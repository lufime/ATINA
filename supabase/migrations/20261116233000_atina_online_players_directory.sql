CREATE OR REPLACE FUNCTION public.atina_v2_online_players()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
 WITH visible_players AS (
   SELECT p.nickname
   FROM public.atina_v2_room_players p
   WHERE NOT coalesce(p.is_bot,false)
     AND p.last_seen_at>clock_timestamp()-interval '90 seconds'
   UNION
   SELECT b.nickname
   FROM private.atina_v2_bot_profiles b
   WHERE private.atina_v2_bot_is_available(b)
     AND mod(b.id*37,100) < floor(b.online_probability*100)::integer
   UNION
   SELECT b.nickname
   FROM private.atina_v2_bot_matches m
   JOIN private.atina_v2_bot_profiles b ON b.id=m.bot_profile_id
   JOIN public.atina_v2_rooms r ON r.id=m.room_id
   JOIN public.atina_v2_room_players p ON p.id=m.bot_player_id
   WHERE r.status IN ('waiting','playing')
     AND p.last_seen_at>clock_timestamp()-interval '90 seconds'
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object('nickname',nickname,'online',true) ORDER BY nickname),'[]'::jsonb)
 FROM (SELECT DISTINCT nickname FROM visible_players WHERE nickname IS NOT NULL AND btrim(nickname)<>'') v;
$$;
REVOKE ALL ON FUNCTION public.atina_v2_online_players() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_v2_online_players() TO anon,authenticated;