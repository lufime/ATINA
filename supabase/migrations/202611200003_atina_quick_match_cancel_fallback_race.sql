-- Track bot fallback rooms by the originating quick-match ticket so a concurrent
-- cancel request can clean up a fallback that already committed.
CREATE TABLE IF NOT EXISTS private.atina_v2_quickmatch_bot_fallbacks (
  ticket_hash bytea PRIMARY KEY,
  room_id uuid NOT NULL REFERENCES public.atina_v2_rooms(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.atina_v2_quickmatch_bot_fallbacks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.atina_v2_quickmatch_bot_fallbacks FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.atina_v2_cancel_matchmake(p_ticket text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_hash bytea;
  v_entry private.atina_v2_matchmaking_queue%rowtype;
  v_bot_room uuid;
  v_count integer;
BEGIN
  IF p_ticket IS NULL OR p_ticket !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Pedido de partida rápida inválido.';
  END IF;
  v_hash:=extensions.digest(p_ticket,'sha256');
  PERFORM pg_advisory_xact_lock(hashtextextended('atina-v2-quick-match',0));

  -- If fallback won the lock race, remove its bot room as the cancellation
  -- request arrives. The tracking row is created in the same fallback txn.
  SELECT room_id INTO v_bot_room
  FROM private.atina_v2_quickmatch_bot_fallbacks
  WHERE ticket_hash=v_hash FOR UPDATE;
  IF FOUND THEN
    DELETE FROM public.atina_v2_rooms WHERE id=v_bot_room;
    DELETE FROM private.atina_v2_quickmatch_bot_fallbacks WHERE ticket_hash=v_hash;
    RETURN jsonb_build_object('cancelled',true,'bot_room_removed',true);
  END IF;

  SELECT * INTO v_entry FROM private.atina_v2_matchmaking_queue
  WHERE ticket_hash=v_hash FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('cancelled',true);
  END IF;

  PERFORM 1 FROM public.atina_v2_rooms WHERE id=v_entry.room_id FOR UPDATE;
  DELETE FROM public.atina_v2_room_players
  WHERE room_id=v_entry.room_id AND id=v_entry.player_id;
  DELETE FROM private.atina_v2_matchmaking_queue WHERE ticket_hash=v_hash;

  SELECT count(*) INTO v_count FROM public.atina_v2_room_players WHERE room_id=v_entry.room_id;
  IF v_count=0 THEN
    DELETE FROM public.atina_v2_rooms WHERE id=v_entry.room_id;
  ELSE
    UPDATE public.atina_v2_room_players SET is_host=true,ready=false
    WHERE id=(SELECT id FROM public.atina_v2_room_players
      WHERE room_id=v_entry.room_id ORDER BY created_at,id LIMIT 1);
    UPDATE private.atina_v2_matchmaking_queue SET status='waiting'
    WHERE room_id=v_entry.room_id;
  END IF;
  RETURN jsonb_build_object('cancelled',true);
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_cancel_matchmake(text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_cancel_matchmake(text) TO anon, authenticated;
