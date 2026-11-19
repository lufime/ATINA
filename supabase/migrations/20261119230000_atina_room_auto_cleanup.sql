-- Automatic lifecycle cleanup for rooms after use and abandoned sessions.
-- Keep completed results available for 15 minutes; clear stale waiting/playing rooms.
CREATE OR REPLACE FUNCTION private.atina_v2_cleanup_used_rooms()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE
  v_deleted integer := 0;
  v_rows integer := 0;
BEGIN
  -- Completed games remain available briefly so players can see final results.
  DELETE FROM public.atina_v2_rooms r
  WHERE r.status = 'completed'
    AND r.updated_at < clock_timestamp() - interval '15 minutes';
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_deleted := v_deleted + v_rows;

  -- Empty or abandoned lobbies are removed after two minutes without presence.
  DELETE FROM public.atina_v2_rooms r
  WHERE r.status = 'waiting'
    AND r.created_at < clock_timestamp() - interval '2 minutes'
    AND NOT EXISTS (
      SELECT 1 FROM public.atina_v2_room_players p
      WHERE p.room_id = r.id
        AND p.last_seen_at > clock_timestamp() - interval '2 minutes'
    );
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_deleted := v_deleted + v_rows;

  -- Active matches are preserved; only rooms with no recent player presence expire.
  DELETE FROM public.atina_v2_rooms r
  WHERE r.status = 'playing'
    AND NOT EXISTS (
      SELECT 1 FROM public.atina_v2_room_players p
      WHERE p.room_id = r.id
        AND p.last_seen_at > clock_timestamp() - interval '15 minutes'
    );
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  v_deleted := v_deleted + v_rows;

  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION private.atina_v2_cleanup_used_rooms() FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'atina-v2-room-auto-cleanup';

SELECT cron.schedule(
  'atina-v2-room-auto-cleanup',
  '*/5 * * * *',
  'SELECT private.atina_v2_cleanup_used_rooms();'
);
