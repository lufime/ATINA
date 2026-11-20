CREATE OR REPLACE FUNCTION public.atina_v2_create_bot_match(p_session_token text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_account private.atina_player_accounts%rowtype; v_bot private.atina_v2_bot_profiles%rowtype;
 v_room_result jsonb; v_room_id uuid; v_human_id uuid; v_bot_id uuid; v_bot_token text;
BEGIN
 IF p_session_token IS NULL OR p_session_token !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'Inicia sessão na tua conta ATINA para procurar adversários.' USING errcode='28000';
 END IF;
 SELECT * INTO v_account FROM private.atina_player_accounts
 WHERE session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
 AND session_expires_at>clock_timestamp() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão expirada. Inicia sessão novamente.' USING errcode='28000'; END IF;
 PERFORM private.atina_v2_cleanup_abandoned_bot_rooms();
 SELECT b.* INTO v_bot FROM private.atina_v2_bot_profiles b
 WHERE private.atina_v2_bot_is_available(b) AND random()<b.online_probability
 AND NOT EXISTS (SELECT 1 FROM private.atina_v2_bot_matches m JOIN public.atina_v2_rooms r ON r.id=m.room_id
 WHERE m.bot_profile_id=b.id AND r.status IN ('waiting','playing')) ORDER BY random() LIMIT 1;
 IF NOT FOUND THEN
  SELECT b.* INTO v_bot FROM private.atina_v2_bot_profiles b
  WHERE private.atina_v2_bot_is_available(b)
  AND NOT EXISTS (SELECT 1 FROM private.atina_v2_bot_matches m JOIN public.atina_v2_rooms r ON r.id=m.room_id
  WHERE m.bot_profile_id=b.id AND r.status IN ('waiting','playing')) ORDER BY random() LIMIT 1;
 END IF;
 IF NOT FOUND THEN RAISE EXCEPTION 'Neste momento não há adversários disponíveis. Tenta novamente daqui a pouco.'; END IF;
 v_room_result:=public.atina_v2_create_room(v_account.nickname,2);
 v_room_id:=(v_room_result->>'room_id')::uuid; v_human_id:=(v_room_result->>'player_id')::uuid;
 v_bot_id:=extensions.gen_random_uuid(); v_bot_token:=encode(extensions.gen_random_bytes(32),'hex');
 UPDATE public.atina_v2_room_players SET account_player_id=v_account.player_id,team_label='Equipa A',ready=false WHERE id=v_human_id AND room_id=v_room_id;
 INSERT INTO public.atina_v2_room_players(id,room_id,token_hash,nickname,is_host,ready,team_label,score,is_bot,last_seen_at)
 VALUES(v_bot_id,v_room_id,extensions.digest(v_bot_token,'sha256'),v_bot.nickname,false,false,'Equipa B',0,true,clock_timestamp());
 INSERT INTO private.atina_v2_bot_matches(room_id,bot_profile_id,bot_player_id,bot_token,next_action_at)
 VALUES(v_room_id,v_bot.id,v_bot_id,v_bot_token,clock_timestamp()+make_interval(secs=>2+floor(random()*9)::integer));
 RETURN jsonb_build_object('room_id',v_room_id,'token',v_room_result->>'token','code',v_room_result->>'code','player_id',v_human_id);
END;
$function$;