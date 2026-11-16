-- Make the opponent join the room as a normal online player and confirm readiness itself.
CREATE OR REPLACE FUNCTION public.atina_v2_create_bot_match(p_session_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
 v_account private.atina_player_accounts%rowtype; v_bot private.atina_v2_bot_profiles%rowtype;
 v_room_result jsonb; v_room_id uuid; v_human_id uuid; v_bot_id uuid; v_bot_token text;
BEGIN
 IF p_session_token IS NULL OR p_session_token !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'Inicia sessão na tua conta ATINA para procurar um adversário.' USING errcode='28000';
 END IF;
 SELECT * INTO v_account FROM private.atina_player_accounts
 WHERE session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
 AND session_expires_at>clock_timestamp() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão expirada. Inicia sessão novamente.' USING errcode='28000'; END IF;

 PERFORM private.atina_v2_cleanup_abandoned_bot_rooms();
 SELECT b.* INTO v_bot FROM private.atina_v2_bot_profiles b
 WHERE private.atina_v2_bot_is_available(b) AND random()<b.online_probability
 AND NOT EXISTS (SELECT 1 FROM private.atina_v2_bot_matches m
  JOIN public.atina_v2_rooms r ON r.id=m.room_id
  WHERE m.bot_profile_id=b.id AND r.status IN ('waiting','playing'))
 ORDER BY random() LIMIT 1;
 IF NOT FOUND THEN
  SELECT b.* INTO v_bot FROM private.atina_v2_bot_profiles b
  WHERE private.atina_v2_bot_is_available(b)
  AND NOT EXISTS (SELECT 1 FROM private.atina_v2_bot_matches m
   JOIN public.atina_v2_rooms r ON r.id=m.room_id
   WHERE m.bot_profile_id=b.id AND r.status IN ('waiting','playing'))
  ORDER BY random() LIMIT 1;
 END IF;
 IF NOT FOUND THEN RAISE EXCEPTION 'Neste momento não há adversários disponíveis. Tenta novamente daqui a pouco.'; END IF;

 v_room_result:=public.atina_v2_create_room(v_account.nickname,2);
 v_room_id:=(v_room_result->>'room_id')::uuid;
 v_human_id:=(v_room_result->>'player_id')::uuid;
 v_bot_id:=extensions.gen_random_uuid();
 v_bot_token:=encode(extensions.gen_random_bytes(32),'hex');
 UPDATE public.atina_v2_room_players SET account_player_id=v_account.player_id,
  team_label='Equipa A',ready=false WHERE id=v_human_id AND room_id=v_room_id;
 INSERT INTO public.atina_v2_room_players
  (id,room_id,token_hash,nickname,is_host,ready,team_label,score,is_bot,last_seen_at)
 VALUES(v_bot_id,v_room_id,extensions.digest(v_bot_token,'sha256'),
  v_bot.nickname,false,false,'Equipa B',0,true,clock_timestamp());
 INSERT INTO private.atina_v2_bot_matches(room_id,bot_profile_id,bot_player_id,bot_token,next_action_at)
 VALUES(v_room_id,v_bot.id,v_bot_id,v_bot_token,clock_timestamp()+make_interval(secs=>4+floor(random()*7)::integer));
 RETURN jsonb_build_object('room_id',v_room_id,'token',v_room_result->>'token',
  'code',v_room_result->>'code','player_id',v_human_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.atina_v2_bot_tick(p_room_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
 v_human public.atina_v2_room_players%rowtype;
 v_match private.atina_v2_bot_matches%rowtype;
 v_bot_player public.atina_v2_room_players%rowtype;
 v_bot private.atina_v2_bot_profiles%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_game private.atina_v2_room_game_state%rowtype;
 v_challenge private.atina_challenges%rowtype;
 v_result jsonb; v_wait integer; v_target_clues integer; v_answer text;
 v_now timestamptz:=clock_timestamp();
BEGIN
 SELECT * INTO v_human FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256');
 IF NOT FOUND OR v_human.is_bot THEN RAISE EXCEPTION 'Sessão de jogador inválida.'; END IF;
 SELECT * INTO v_match FROM private.atina_v2_bot_matches WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','no_opponent'); END IF;
 SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id;
 IF NOT FOUND OR v_room.status NOT IN ('waiting','playing') THEN RETURN jsonb_build_object('status','waiting'); END IF;
 SELECT * INTO v_bot FROM private.atina_v2_bot_profiles WHERE id=v_match.bot_profile_id;
 SELECT * INTO v_bot_player FROM public.atina_v2_room_players WHERE id=v_match.bot_player_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','left'); END IF;

 -- The opponent confirms its own place in the lobby after a human-like delay.
 IF v_room.status='waiting' THEN
  IF v_bot_player.ready THEN
   UPDATE public.atina_v2_room_players SET last_seen_at=v_now WHERE id=v_bot_player.id;
   RETURN jsonb_build_object('status','ready');
  END IF;
  IF v_match.next_action_at IS NOT NULL AND v_match.next_action_at>v_now THEN
   UPDATE public.atina_v2_room_players SET last_seen_at=v_now WHERE id=v_bot_player.id;
   RETURN jsonb_build_object('status','joining');
  END IF;
  UPDATE public.atina_v2_room_players SET ready=true,last_seen_at=v_now WHERE id=v_bot_player.id;
  UPDATE private.atina_v2_bot_matches SET next_action_at=NULL WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','ready');
 END IF;

 SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id;
 IF NOT FOUND OR v_game.status<>'active' THEN RETURN jsonb_build_object('status','waiting'); END IF;
 UPDATE public.atina_v2_room_players SET last_seen_at=v_now WHERE id=v_bot_player.id;
 IF cardinality(v_game.team_order)=0 OR v_bot_player.team_label IS DISTINCT FROM v_game.team_order[v_game.active_team_index] THEN
  RETURN jsonb_build_object('status','human_turn');
 END IF;
 IF coalesce((v_room.game_state->>'prepare_until')::bigint,0)>floor(extract(epoch FROM v_now)*1000)::bigint THEN
  RETURN jsonb_build_object('status','preparing');
 END IF;
 v_wait:=v_bot.response_min_seconds+
  floor(random()*(v_bot.response_max_seconds-v_bot.response_min_seconds+1))::integer;
 IF v_game.round_locked THEN
  IF v_match.next_action_at IS NULL THEN
   UPDATE private.atina_v2_bot_matches SET next_action_at=v_now+make_interval(secs=>least(v_wait,4)) WHERE room_id=p_room_id;
   RETURN jsonb_build_object('status','thinking');
  END IF;
  IF v_match.next_action_at>v_now THEN RETURN jsonb_build_object('status','thinking'); END IF;
  v_result:=public.atina_v2_next_room_challenge(p_room_id,v_match.bot_token);
  UPDATE private.atina_v2_bot_matches SET next_action_at=NULL,attempts=0,
   bot_turn_completed=false,current_challenge_id=NULL WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','advanced','result',v_result);
 END IF;
 SELECT * INTO v_challenge FROM private.atina_challenges
 WHERE challenge_id=v_game.challenge_queue[v_game.position] AND active;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','waiting'); END IF;
 IF v_match.current_challenge_id IS DISTINCT FROM v_challenge.challenge_id THEN
  UPDATE private.atina_v2_bot_matches SET current_challenge_id=v_challenge.challenge_id,
   attempts=0,next_action_at=v_now+make_interval(secs=>v_wait),bot_turn_completed=false
  WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','thinking');
 END IF;
 IF v_match.next_action_at IS NULL THEN
  UPDATE private.atina_v2_bot_matches SET next_action_at=v_now+make_interval(secs=>v_wait) WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','thinking');
 END IF;
 IF v_match.next_action_at>v_now THEN RETURN jsonb_build_object('status','thinking'); END IF;
 v_target_clues:=CASE WHEN v_bot.knowledge_level>=0.78 THEN 1
  WHEN v_bot.knowledge_level>=0.55 THEN 2 ELSE 3 END;
 IF v_game.revealed_clues<least(v_target_clues,jsonb_array_length(v_challenge.clues)) THEN
  v_result:=public.atina_v2_reveal_room_clue(p_room_id,v_match.bot_token);
  UPDATE private.atina_v2_bot_matches SET next_action_at=v_now+make_interval(secs=>v_wait) WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','clue_revealed','result',v_result);
 END IF;
 IF random()<greatest(0.01,v_bot.mistake_rate-(v_bot.knowledge_level*0.04)) THEN
  v_answer:=(ARRAY['Talvez seja uma montanha','Não tenho a certeza','Penso que é uma cidade','A minha primeira hipótese','Pode ser um animal'])[1+floor(random()*5)::integer];
 ELSE
  v_answer:=v_challenge.answer;
 END IF;
 v_result:=public.atina_v2_submit_team_proposal(p_room_id,v_match.bot_token,
  v_game.position-1,v_answer,NULL,NULL);
 IF v_result->>'status' IN ('accepted','already_correct') THEN
  UPDATE private.atina_v2_bot_matches SET bot_turn_completed=true,
   next_action_at=v_now+make_interval(secs=>least(v_wait,4)) WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','answered','result',v_result);
 END IF;
 UPDATE private.atina_v2_bot_matches SET attempts=attempts+1,
  next_action_at=v_now+make_interval(secs=>v_wait) WHERE room_id=p_room_id;
 RETURN jsonb_build_object('status','thinking','result',v_result);
END;
$$;