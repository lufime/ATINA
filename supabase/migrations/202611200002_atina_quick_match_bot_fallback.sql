-- Safe human-first fallback to an ATINA bot after a short wait.
-- Matchmaking and fallback share the advisory lock to prevent duplicate rooms.
CREATE OR REPLACE FUNCTION public.atina_v2_matchmake_bot_fallback(
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
  v_entry private.atina_v2_matchmaking_queue%rowtype;
  v_account private.atina_player_accounts%rowtype;
  v_count integer;
  v_result jsonb;
BEGIN
  IF p_ticket IS NULL OR p_ticket !~ '^[0-9a-f]{64}$'
     OR p_session_token IS NULL OR p_session_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Pedido de partida rápida inválido.';
  END IF;
  SELECT * INTO v_account FROM private.atina_player_accounts
  WHERE session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
    AND session_expires_at>clock_timestamp();
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão expirada. Inicia sessão novamente.' USING errcode='28000'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('atina-v2-quick-match',0));
  v_hash:=extensions.digest(p_ticket,'sha256');
  SELECT * INTO v_entry FROM private.atina_v2_matchmaking_queue
    WHERE ticket_hash=v_hash FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','cancelled'); END IF;
  -- Check ownership before returning any room bearer token, even for matched tickets.
  IF v_entry.account_player_id IS DISTINCT FROM v_account.player_id THEN
    RAISE EXCEPTION 'Este pedido não pertence à tua sessão.';
  END IF;
  IF v_entry.status='matched' THEN
    RETURN jsonb_build_object('status','matched','room_id',v_entry.room_id,'token',v_entry.token);
  END IF;
  IF v_entry.created_at>clock_timestamp()-interval '8 seconds' THEN
    RETURN jsonb_build_object('status','waiting');
  END IF;

  PERFORM 1 FROM public.atina_v2_rooms WHERE id=v_entry.room_id FOR UPDATE;
  SELECT count(*) INTO v_count FROM public.atina_v2_room_players WHERE room_id=v_entry.room_id;
  IF v_count<>1 THEN
    RETURN jsonb_build_object('status','waiting');
  END IF;
  DELETE FROM private.atina_v2_matchmaking_queue WHERE ticket_hash=v_hash;
  DELETE FROM public.atina_v2_room_players WHERE room_id=v_entry.room_id AND id=v_entry.player_id;
  DELETE FROM public.atina_v2_rooms WHERE id=v_entry.room_id;

  v_result:=public.atina_v2_create_bot_match(p_session_token);
  RETURN jsonb_build_object('status','bot_matched','room_id',v_result->'room_id',
    'token',v_result->'token','code',v_result->'code','player_id',v_result->'player_id');
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_matchmake_bot_fallback(text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_matchmake_bot_fallback(text,text) TO anon, authenticated;

-- Disable the legacy RPC signature which bypasses account-identity checks.
DROP FUNCTION IF EXISTS public.atina_v2_matchmake(text,text);
