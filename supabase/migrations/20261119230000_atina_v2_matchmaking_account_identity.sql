-- Prevent quick matchmaking from matching two sessions owned by the same ATINA account.
-- The authenticated overload now performs matchmaking directly, with account identity
-- attached before the queue row can be selected by another request.
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
  v_account private.atina_player_accounts%rowtype;
  v_hash bytea;
  v_existing private.atina_v2_matchmaking_queue%rowtype;
  v_existing_account uuid;
  v_waiting private.atina_v2_matchmaking_queue%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_player public.atina_v2_room_players%rowtype;
  v_token text;
  v_code text;
  v_attempt integer := 0;
BEGIN
  IF p_session_token IS NULL OR p_session_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Inicia sessão na tua conta ATINA antes de procurar adversários.' USING errcode='28000';
  END IF;
  SELECT * INTO v_account FROM private.atina_player_accounts
   WHERE session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
     AND session_expires_at>clock_timestamp() FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão expirada. Inicia sessão novamente.' USING errcode='28000'; END IF;
  IF p_nickname IS NULL OR char_length(btrim(p_nickname)) NOT BETWEEN 1 AND 20 THEN
    RAISE EXCEPTION 'Escolhe um pseudónimo entre 1 e 20 caracteres.';
  END IF;
  IF p_ticket IS NULL OR p_ticket !~ '^[0-9a-f]{64}
    RAISE EXCEPTION 'Pedido de partida rápida inválido.';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('atina-v2-quick-match',0));
  v_hash:=extensions.digest(p_ticket,'sha256');
  SELECT * INTO v_existing FROM private.atina_v2_matchmaking_queue WHERE ticket_hash=v_hash;
  IF FOUND THEN
    SELECT account_player_id INTO v_existing_account
      FROM public.atina_v2_room_players
     WHERE id=v_existing.player_id AND room_id=v_existing.room_id;
    IF v_existing_account IS DISTINCT FROM v_account.player_id THEN
      RAISE EXCEPTION 'Pedido de partida rápida inválido para esta sessão.' USING errcode='28000';
    END IF;
    RETURN jsonb_build_object('status',CASE WHEN v_existing.status='matched' THEN 'matched' ELSE 'waiting' END,
      'room_id',CASE WHEN v_existing.status='matched' THEN v_existing.room_id ELSE NULL END,
      'token',CASE WHEN v_existing.status='matched' THEN v_existing.token ELSE NULL END);
  END IF;

  DELETE FROM public.atina_v2_rooms r
   WHERE r.status='waiting' AND r.id IN (
     SELECT q.room_id FROM private.atina_v2_matchmaking_queue q
     WHERE q.status='waiting' AND q.created_at<=clock_timestamp()-interval '90 seconds');

  SELECT q.* INTO v_waiting
  FROM private.atina_v2_matchmaking_queue q
  JOIN public.atina_v2_rooms r ON r.id=q.room_id
  JOIN public.atina_v2_room_players p ON p.id=q.player_id AND p.room_id=q.room_id
  WHERE q.status='waiting' AND r.status='waiting'
    AND p.account_player_id IS NOT NULL
    AND p.account_player_id<>v_account.player_id
    AND (SELECT count(*) FROM public.atina_v2_room_players rp WHERE rp.room_id=r.id)=1
    AND q.created_at>clock_timestamp()-interval '90 seconds'
  ORDER BY q.created_at LIMIT 1 FOR UPDATE OF q;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  IF FOUND THEN
    SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=v_waiting.room_id FOR UPDATE;
    INSERT INTO public.atina_v2_room_players(room_id,token_hash,nickname,is_host,ready,account_player_id)
    VALUES(v_room.id,extensions.digest(v_token,'sha256'),v_account.nickname,false,false,v_account.player_id)
    RETURNING * INTO v_player;
    INSERT INTO private.atina_v2_matchmaking_queue(ticket_hash,room_id,player_id,token,status)
    VALUES(v_hash,v_room.id,v_player.id,v_token,'matched');
    UPDATE private.atina_v2_matchmaking_queue SET status='matched' WHERE ticket_hash=v_waiting.ticket_hash;
    RETURN jsonb_build_object('status','matched','room_id',v_room.id,'token',v_token);
  END IF;

  LOOP
    v_code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
    BEGIN
      INSERT INTO public.atina_v2_rooms(code,max_players) VALUES(v_code,2) RETURNING * INTO v_room;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      v_attempt:=v_attempt+1;
      IF v_attempt>=8 THEN RAISE EXCEPTION 'Não foi possível criar uma partida. Tenta novamente.'; END IF;
    END;
  END LOOP;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  INSERT INTO public.atina_v2_room_players(room_id,token_hash,nickname,is_host,ready,account_player_id)
  VALUES(v_room.id,extensions.digest(v_token,'sha256'),v_account.nickname,true,false,v_account.player_id)
  RETURNING * INTO v_player;
  INSERT INTO private.atina_v2_matchmaking_queue(ticket_hash,room_id,player_id,token,status)
  VALUES(v_hash,v_room.id,v_player.id,v_token,'waiting');
  RETURN jsonb_build_object('status','waiting');
END;
$function$;

-- The legacy identity-less overload cannot safely be used for online matchmaking.
REVOKE ALL ON FUNCTION public.atina_v2_matchmake(text,text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.atina_v2_matchmake(text,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_matchmake(text,text,text) TO anon, authenticated;
 THEN
    RAISE EXCEPTION 'Pedido de partida rápida inválido.';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('atina-v2-quick-match',0));
  v_hash:=extensions.digest(p_ticket,'sha256');
  SELECT * INTO v_existing FROM private.atina_v2_matchmaking_queue WHERE ticket_hash=v_hash;
  IF FOUND THEN
    RETURN jsonb_build_object('status',CASE WHEN v_existing.status='matched' THEN 'matched' ELSE 'waiting' END,
      'room_id',CASE WHEN v_existing.status='matched' THEN v_existing.room_id ELSE NULL END,
      'token',CASE WHEN v_existing.status='matched' THEN v_existing.token ELSE NULL END);
  END IF;

  DELETE FROM public.atina_v2_rooms r
   WHERE r.status='waiting' AND r.id IN (
     SELECT q.room_id FROM private.atina_v2_matchmaking_queue q
     WHERE q.status='waiting' AND q.created_at<=clock_timestamp()-interval '90 seconds');

  SELECT q.* INTO v_waiting
  FROM private.atina_v2_matchmaking_queue q
  JOIN public.atina_v2_rooms r ON r.id=q.room_id
  JOIN public.atina_v2_room_players p ON p.id=q.player_id AND p.room_id=q.room_id
  WHERE q.status='waiting' AND r.status='waiting'
    AND p.account_player_id IS NOT NULL
    AND p.account_player_id<>v_account.player_id
    AND (SELECT count(*) FROM public.atina_v2_room_players rp WHERE rp.room_id=r.id)=1
    AND q.created_at>clock_timestamp()-interval '90 seconds'
  ORDER BY q.created_at LIMIT 1 FOR UPDATE OF q;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  IF FOUND THEN
    SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=v_waiting.room_id FOR UPDATE;
    INSERT INTO public.atina_v2_room_players(room_id,token_hash,nickname,is_host,ready,account_player_id)
    VALUES(v_room.id,extensions.digest(v_token,'sha256'),v_account.nickname,false,false,v_account.player_id)
    RETURNING * INTO v_player;
    INSERT INTO private.atina_v2_matchmaking_queue(ticket_hash,room_id,player_id,token,status)
    VALUES(v_hash,v_room.id,v_player.id,v_token,'matched');
    UPDATE private.atina_v2_matchmaking_queue SET status='matched' WHERE ticket_hash=v_waiting.ticket_hash;
    RETURN jsonb_build_object('status','matched','room_id',v_room.id,'token',v_token);
  END IF;

  LOOP
    v_code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
    BEGIN
      INSERT INTO public.atina_v2_rooms(code,max_players) VALUES(v_code,2) RETURNING * INTO v_room;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      v_attempt:=v_attempt+1;
      IF v_attempt>=8 THEN RAISE EXCEPTION 'Não foi possível criar uma partida. Tenta novamente.'; END IF;
    END;
  END LOOP;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  INSERT INTO public.atina_v2_room_players(room_id,token_hash,nickname,is_host,ready,account_player_id)
  VALUES(v_room.id,extensions.digest(v_token,'sha256'),v_account.nickname,true,false,v_account.player_id)
  RETURNING * INTO v_player;
  INSERT INTO private.atina_v2_matchmaking_queue(ticket_hash,room_id,player_id,token,status)
  VALUES(v_hash,v_room.id,v_player.id,v_token,'waiting');
  RETURN jsonb_build_object('status','waiting');
END;
$function$;

-- The legacy identity-less overload cannot safely be used for online matchmaking.
REVOKE ALL ON FUNCTION public.atina_v2_matchmake(text,text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.atina_v2_matchmake(text,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_matchmake(text,text,text) TO anon, authenticated;
