-- ATINA public quick matchmaking (two-player quick games).
-- Queue records and bearer credentials stay in the private schema.
CREATE TABLE IF NOT EXISTS private.atina_v2_matchmaking_queue (
  ticket_hash bytea PRIMARY KEY,
  room_id uuid NOT NULL REFERENCES public.atina_v2_rooms(id) ON DELETE CASCADE,
  player_id uuid NOT NULL,
  token text NOT NULL,
  status text NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting','matched')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT atina_v2_matchmaking_player_fk
    FOREIGN KEY (room_id, player_id)
    REFERENCES public.atina_v2_room_players(room_id, id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS atina_v2_matchmaking_waiting_idx
  ON private.atina_v2_matchmaking_queue(created_at)
  WHERE status = 'waiting';
ALTER TABLE private.atina_v2_matchmaking_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.atina_v2_matchmaking_queue FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.atina_v2_matchmake(
  p_nickname text,
  p_ticket text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_hash bytea;
  v_existing private.atina_v2_matchmaking_queue%rowtype;
  v_waiting private.atina_v2_matchmaking_queue%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_player public.atina_v2_room_players%rowtype;
  v_token text;
  v_code text;
  v_attempt integer := 0;
BEGIN
  IF p_nickname IS NULL OR char_length(btrim(p_nickname)) NOT BETWEEN 1 AND 20 THEN
    RAISE EXCEPTION 'Escolhe um pseudónimo entre 1 e 20 caracteres.';
  END IF;
  IF p_ticket IS NULL OR p_ticket !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Pedido de partida rápida inválido.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('atina-v2-quick-match', 0));
  v_hash := extensions.digest(p_ticket, 'sha256');

  SELECT * INTO v_existing
  FROM private.atina_v2_matchmaking_queue
  WHERE ticket_hash = v_hash;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'status', CASE WHEN v_existing.status = 'matched' THEN 'matched' ELSE 'waiting' END,
      'room_id', CASE WHEN v_existing.status = 'matched' THEN v_existing.room_id ELSE NULL END,
      'token', CASE WHEN v_existing.status = 'matched' THEN v_existing.token ELSE NULL END
    );
  END IF;

  SELECT q.* INTO v_waiting
  FROM private.atina_v2_matchmaking_queue q
  JOIN public.atina_v2_rooms r ON r.id = q.room_id
  WHERE q.status = 'waiting'
    AND r.status = 'waiting'
    AND (SELECT count(*) FROM public.atina_v2_room_players p WHERE p.room_id = r.id) = 1
    AND q.created_at > clock_timestamp() - interval '90 seconds'
  ORDER BY q.created_at
  LIMIT 1
  FOR UPDATE OF q;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  IF FOUND THEN
    SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id = v_waiting.room_id FOR UPDATE;
    INSERT INTO public.atina_v2_room_players(room_id, token_hash, nickname, is_host, ready)
    VALUES (v_room.id, extensions.digest(v_token, 'sha256'), btrim(p_nickname), false, false)
    RETURNING * INTO v_player;

    INSERT INTO private.atina_v2_matchmaking_queue(ticket_hash, room_id, player_id, token, status)
    VALUES (v_hash, v_room.id, v_player.id, v_token, 'matched');

    UPDATE private.atina_v2_matchmaking_queue
    SET status = 'matched'
    WHERE ticket_hash = v_waiting.ticket_hash;

    RETURN jsonb_build_object('status','matched','room_id',v_room.id,'token',v_token);
  END IF;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  LOOP
    v_code := upper(substr(replace(extensions.gen_random_uuid()::text, '-', ''), 1, 10));
    BEGIN
      INSERT INTO public.atina_v2_rooms(code, max_players)
      VALUES (v_code, 2)
      RETURNING * INTO v_room;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      v_attempt := v_attempt + 1;
      IF v_attempt >= 8 THEN
        RAISE EXCEPTION 'Não foi possível criar uma partida. Tenta novamente.';
      END IF;
    END;
  END LOOP;

  INSERT INTO public.atina_v2_room_players(room_id, token_hash, nickname, is_host, ready)
  VALUES (v_room.id, extensions.digest(v_token, 'sha256'), btrim(p_nickname), true, false)
  RETURNING * INTO v_player;

  INSERT INTO private.atina_v2_matchmaking_queue(ticket_hash, room_id, player_id, token, status)
  VALUES (v_hash, v_room.id, v_player.id, v_token, 'waiting');

  RETURN jsonb_build_object('status','waiting');
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_matchmake_status(p_ticket text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_entry private.atina_v2_matchmaking_queue%rowtype;
  v_count integer;
BEGIN
  IF p_ticket IS NULL OR p_ticket !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Pedido de partida rápida inválido.';
  END IF;
  SELECT * INTO v_entry
  FROM private.atina_v2_matchmaking_queue
  WHERE ticket_hash = extensions.digest(p_ticket, 'sha256');
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status','cancelled');
  END IF;
  SELECT count(*) INTO v_count
  FROM public.atina_v2_room_players
  WHERE room_id = v_entry.room_id;
  IF v_count >= 2 AND v_entry.status = 'matched' THEN
    RETURN jsonb_build_object('status','matched','room_id',v_entry.room_id,'token',v_entry.token);
  END IF;
  RETURN jsonb_build_object('status','waiting','players_waiting',1);
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_cancel_matchmake(p_ticket text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_entry private.atina_v2_matchmaking_queue%rowtype;
  v_count integer;
BEGIN
  IF p_ticket IS NULL OR p_ticket !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Pedido de partida rápida inválido.';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('atina-v2-quick-match', 0));
  SELECT * INTO v_entry
  FROM private.atina_v2_matchmaking_queue
  WHERE ticket_hash = extensions.digest(p_ticket, 'sha256')
  FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('cancelled', true); END IF;

  PERFORM 1 FROM public.atina_v2_rooms WHERE id = v_entry.room_id FOR UPDATE;
  DELETE FROM public.atina_v2_room_players
  WHERE room_id = v_entry.room_id AND id = v_entry.player_id;
  DELETE FROM private.atina_v2_matchmaking_queue WHERE ticket_hash = extensions.digest(p_ticket, 'sha256');

  SELECT count(*) INTO v_count
  FROM public.atina_v2_room_players WHERE room_id = v_entry.room_id;
  IF v_count = 0 THEN
    DELETE FROM public.atina_v2_rooms WHERE id = v_entry.room_id;
  ELSE
    UPDATE public.atina_v2_room_players
    SET is_host = true, ready = false
    WHERE id = (
      SELECT id FROM public.atina_v2_room_players
      WHERE room_id = v_entry.room_id ORDER BY created_at, id LIMIT 1
    );
    UPDATE private.atina_v2_matchmaking_queue
    SET status = 'waiting'
    WHERE room_id = v_entry.room_id;
  END IF;
  RETURN jsonb_build_object('cancelled', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_matchmake(text,text) FROM public;
REVOKE ALL ON FUNCTION public.atina_v2_matchmake_status(text) FROM public;
REVOKE ALL ON FUNCTION public.atina_v2_cancel_matchmake(text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_matchmake(text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_matchmake_status(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_cancel_matchmake(text) TO anon, authenticated;
