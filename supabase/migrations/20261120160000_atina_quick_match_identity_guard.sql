-- Prevent quick matchmaking from pairing the same ATINA account with itself.
-- Identity is validated server-side using the account session token.
ALTER TABLE private.atina_v2_matchmaking_queue
  ADD COLUMN IF NOT EXISTS account_player_id uuid;

CREATE INDEX IF NOT EXISTS atina_v2_matchmaking_account_waiting_idx
  ON private.atina_v2_matchmaking_queue(account_player_id, created_at)
  WHERE status = 'waiting' AND account_player_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.atina_v2_matchmake(
  p_nickname text,
  p_ticket text,
  p_session_token text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_hash bytea;
  v_account_player_id uuid;
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
  IF p_session_token IS NULL OR p_session_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Inicia sessão na tua conta ATINA antes de procurar adversários.';
  END IF;

  SELECT a.player_id INTO v_account_player_id
  FROM private.atina_player_accounts a
  WHERE a.session_token_hash = extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
    AND a.session_expires_at > clock_timestamp();
  IF v_account_player_id IS NULL THEN
    RAISE EXCEPTION 'Sessão expirada. Inicia sessão novamente.';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('atina-v2-quick-match', 0));
  DELETE FROM public.atina_v2_rooms r
  WHERE r.status = 'waiting'
    AND r.id IN (
      SELECT q.room_id FROM private.atina_v2_matchmaking_queue q
      WHERE q.status = 'waiting' AND q.created_at <= clock_timestamp() - interval '90 seconds'
    );
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

  -- Do not allow multiple simultaneous tickets from one account.
  IF EXISTS (
    SELECT 1 FROM private.atina_v2_matchmaking_queue q
    JOIN public.atina_v2_rooms r ON r.id=q.room_id
    WHERE q.account_player_id=v_account_player_id
      AND q.status='waiting' AND r.status='waiting'
      AND q.created_at > clock_timestamp()-interval '90 seconds'
  ) THEN
    RAISE EXCEPTION 'Já estás à procura de adversário. Cancela a procura anterior antes de iniciar outra.';
  END IF;

  -- Only pair with a different verified account. Legacy entries without identity are ignored.
  SELECT q.* INTO v_waiting
  FROM private.atina_v2_matchmaking_queue q
  JOIN public.atina_v2_rooms r ON r.id = q.room_id
  WHERE q.status = 'waiting'
    AND q.account_player_id IS NOT NULL
    AND q.account_player_id <> v_account_player_id
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

    INSERT INTO private.atina_v2_matchmaking_queue(ticket_hash, room_id, player_id, token, status, account_player_id)
    VALUES (v_hash, v_room.id, v_player.id, v_token, 'matched', v_account_player_id);

    UPDATE private.atina_v2_matchmaking_queue
    SET status = 'matched'
    WHERE ticket_hash = v_waiting.ticket_hash;

    RETURN jsonb_build_object('status','matched','room_id',v_room.id,'token',v_token);
  END IF;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  LOOP
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
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

  INSERT INTO private.atina_v2_matchmaking_queue(ticket_hash, room_id, player_id, token, status, account_player_id)
  VALUES (v_hash, v_room.id, v_player.id, v_token, 'waiting', v_account_player_id);

  RETURN jsonb_build_object('status','waiting');
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_matchmake(text,text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.atina_v2_matchmake(text,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_matchmake(text,text,text) TO anon, authenticated;
