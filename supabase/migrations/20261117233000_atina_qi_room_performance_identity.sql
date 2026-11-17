-- Ensure real room answers feed the QI* performance sample using stable account identity.
-- Only room participants linked to a verified account are included.
-- This does not modify points, XP, scores, or existing history.

DROP TRIGGER IF EXISTS atina_enrich_v2_room_answer ON public.atina_v2_room_answers;
CREATE TRIGGER atina_enrich_v2_room_answer
BEFORE INSERT ON public.atina_v2_room_answers
FOR EACH ROW
EXECUTE FUNCTION private.atina_enrich_room_answer();

CREATE OR REPLACE FUNCTION private.atina_log_room_performance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player public.atina_v2_room_players;
  v_actor_id uuid;
BEGIN
  SELECT * INTO v_player
    FROM public.atina_v2_room_players
   WHERE id = new.player_id
     AND room_id = new.room_id;

  IF NOT FOUND OR v_player.account_player_id IS NULL THEN
    RETURN new;
  END IF;

  v_actor_id := v_player.account_player_id;

  INSERT INTO private.atina_performance_events
    (actor_id, nickname, source, source_id, challenge_position,
     challenge_id, difficulty, outcome, response_ms, created_at)
  VALUES
    (v_actor_id, v_player.nickname, 'room', new.room_id,
     new.challenge_index + 1, new.challenge_id, new.difficulty,
     CASE WHEN new.is_correct THEN 'correct' ELSE 'wrong' END,
     new.response_ms, new.created_at)
  ON CONFLICT (source, source_id, actor_id, challenge_position)
  DO UPDATE SET
    outcome = excluded.outcome,
    difficulty = excluded.difficulty,
    response_ms = coalesce(excluded.response_ms, private.atina_performance_events.response_ms);

  RETURN new;
END;
$function$;

DROP TRIGGER IF EXISTS atina_log_v2_room_performance ON public.atina_v2_room_answers;
CREATE TRIGGER atina_log_v2_room_performance
AFTER INSERT ON public.atina_v2_room_answers
FOR EACH ROW
EXECUTE FUNCTION private.atina_log_room_performance();
