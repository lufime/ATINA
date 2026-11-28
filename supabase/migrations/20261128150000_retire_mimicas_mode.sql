-- Retire Mímicas without deleting historical room or round data.
-- Reject transitions that would create a new Mímicas game in either room generation.
CREATE OR REPLACE FUNCTION public.atina_reject_new_mimicas_mode()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF coalesce(NEW.game_state->>'mode', '') = 'mimicas' THEN
    IF TG_OP = 'INSERT' THEN
      RAISE EXCEPTION 'O modo Mímicas foi removido do ATINA.'
        USING ERRCODE = 'feature_not_supported';
    ELSIF coalesce(OLD.game_state->>'mode', '') <> 'mimicas' THEN
      RAISE EXCEPTION 'O modo Mímicas foi removido do ATINA.'
        USING ERRCODE = 'feature_not_supported';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS atina_disable_new_mimicas_legacy_insert ON public.atina_rooms;
DROP TRIGGER IF EXISTS atina_disable_new_mimicas_legacy_update ON public.atina_rooms;
CREATE TRIGGER atina_disable_new_mimicas_legacy_insert
BEFORE INSERT ON public.atina_rooms
FOR EACH ROW EXECUTE FUNCTION public.atina_reject_new_mimicas_mode();
CREATE TRIGGER atina_disable_new_mimicas_legacy_update
BEFORE UPDATE OF game_state ON public.atina_rooms
FOR EACH ROW EXECUTE FUNCTION public.atina_reject_new_mimicas_mode();

DROP TRIGGER IF EXISTS atina_disable_new_mimicas_v2_insert ON public.atina_v2_rooms;
DROP TRIGGER IF EXISTS atina_disable_new_mimicas_v2_update ON public.atina_v2_rooms;
CREATE TRIGGER atina_disable_new_mimicas_v2_insert
BEFORE INSERT ON public.atina_v2_rooms
FOR EACH ROW EXECUTE FUNCTION public.atina_reject_new_mimicas_mode();
CREATE TRIGGER atina_disable_new_mimicas_v2_update
BEFORE UPDATE OF game_state ON public.atina_v2_rooms
FOR EACH ROW EXECUTE FUNCTION public.atina_reject_new_mimicas_mode();

REVOKE ALL ON FUNCTION public.atina_reject_new_mimicas_mode() FROM PUBLIC, anon, authenticated;
