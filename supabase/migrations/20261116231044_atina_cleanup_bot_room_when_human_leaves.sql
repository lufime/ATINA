CREATE OR REPLACE FUNCTION private.atina_v2_remove_bot_when_human_leaves()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
BEGIN
  IF NOT coalesce(OLD.is_bot,false)
     AND EXISTS (SELECT 1 FROM private.atina_v2_bot_matches m WHERE m.room_id=OLD.room_id) THEN
    DELETE FROM public.atina_v2_room_players
     WHERE room_id=OLD.room_id AND is_bot=true;
  END IF;
  RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS atina_v2_cleanup_bot_on_human_leave ON public.atina_v2_room_players;
CREATE TRIGGER atina_v2_cleanup_bot_on_human_leave
AFTER DELETE ON public.atina_v2_room_players
FOR EACH ROW EXECUTE FUNCTION private.atina_v2_remove_bot_when_human_leaves();