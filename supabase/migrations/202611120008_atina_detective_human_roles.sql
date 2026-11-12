ALTER TABLE private.atina_detective_interactions DROP CONSTRAINT atina_detective_interactions_reaction_check;
ALTER TABLE private.atina_detective_interactions ADD CONSTRAINT atina_detective_interactions_reaction_check
 CHECK (reaction IN ('neutral','cooperative','guarded','pressured','evidence','pending','human'));

CREATE OR REPLACE FUNCTION public.atina_detective_interrogate(
 p_room_id uuid,p_token text,p_character_key text,p_topic text DEFAULT 'general',p_presented_evidence_key text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_player public.atina_v2_room_players%rowtype; v_session private.atina_detective_sessions%rowtype;
 v_character private.atina_detective_characters%rowtype; v_persona jsonb; v_presented uuid;
 v_text text; v_reaction text; v_count integer; v_pending bigint;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 IF p_topic NOT IN ('whereabouts','timeline','relationships','object','motive','general') THEN RAISE EXCEPTION 'Tema inválido.' USING errcode='22023'; END IF;
 SELECT * INTO v_player FROM public.atina_v2_room_players WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256');
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 SELECT * INTO v_session FROM private.atina_detective_sessions WHERE room_id=p_room_id AND status='active' FOR UPDATE;
 IF NOT FOUND OR v_session.detective_player_id<>v_player.id THEN RAISE EXCEPTION 'Só o detetive pode interrogar.' USING errcode='42501'; END IF;
 SELECT * INTO v_character FROM private.atina_detective_characters WHERE session_id=v_session.id AND character_key=p_character_key AND role_kind<>'detective';
 IF NOT FOUND THEN RAISE EXCEPTION 'Personagem desconhecida.' USING errcode='22023'; END IF;
 IF p_presented_evidence_key IS NOT NULL THEN
  SELECT e.id INTO v_presented FROM private.atina_detective_evidence e
  JOIN private.atina_detective_discoveries d ON d.evidence_id=e.id AND d.session_id=e.session_id
  WHERE e.session_id=v_session.id AND e.evidence_key=p_presented_evidence_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'Não podes apresentar uma prova que ainda não descobriste.' USING errcode='42501'; END IF;
 END IF;
 SELECT count(*) INTO v_count FROM private.atina_detective_interactions WHERE session_id=v_session.id AND character_id=v_character.id;
 IF v_character.player_id IS NOT NULL THEN
  SELECT id INTO v_pending FROM private.atina_detective_interactions
  WHERE session_id=v_session.id AND character_id=v_character.id AND reaction='pending' ORDER BY created_at DESC LIMIT 1;
  IF v_pending IS NOT NULL THEN
   RETURN jsonb_build_object('character',v_character.display_name,'awaiting_player',true,'question_number',v_count);
  END IF;
  INSERT INTO private.atina_detective_interactions(session_id,character_id,player_id,topic,presented_evidence_id,response_text,reaction)
  VALUES(v_session.id,v_character.id,v_player.id,p_topic,v_presented,'A aguardar resposta do participante.','pending');
  UPDATE private.atina_detective_sessions SET turn_number=turn_number+1,updated_at=clock_timestamp() WHERE id=v_session.id;
  RETURN jsonb_build_object('character',v_character.display_name,'awaiting_player',true,'question_number',v_count+1);
 END IF;
 v_persona:=v_character.persona_state;
 IF p_presented_evidence_key IS NOT NULL AND coalesce(v_persona->'evidenceResponses','{}'::jsonb) ? p_presented_evidence_key THEN
  v_text:=v_persona->'evidenceResponses'->>p_presented_evidence_key; v_reaction:='evidence';
 ELSE
  v_text:=coalesce(CASE WHEN v_character.role_kind='culprit' THEN v_persona->'lies'->>p_topic END,
   v_persona->'statements'->>p_topic,v_persona->'statements'->>'general','Não tenho mais nada a acrescentar neste momento.');
  v_reaction:=CASE WHEN v_character.role_kind='culprit' THEN 'guarded' ELSE 'cooperative' END;
 END IF;
 INSERT INTO private.atina_detective_interactions(session_id,character_id,player_id,topic,presented_evidence_id,response_text,reaction)
 VALUES(v_session.id,v_character.id,v_player.id,p_topic,v_presented,v_text,v_reaction);
 UPDATE private.atina_detective_sessions SET turn_number=turn_number+1,updated_at=clock_timestamp() WHERE id=v_session.id;
 RETURN jsonb_build_object('character',v_character.display_name,'topic',p_topic,'text',v_text,'reaction',v_reaction,'question_number',v_count+1,'awaiting_player',false);
END; $$;

CREATE OR REPLACE FUNCTION public.atina_detective_character_reply(p_room_id uuid,p_token text,p_reply text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_player public.atina_v2_room_players%rowtype; v_session private.atina_detective_sessions%rowtype;
 v_character private.atina_detective_characters%rowtype; v_interaction bigint;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 IF p_reply IS NULL OR char_length(btrim(p_reply)) NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'A resposta deve ter entre 1 e 1000 caracteres.' USING errcode='22023'; END IF;
 SELECT * INTO v_player FROM public.atina_v2_room_players WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256');
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 SELECT * INTO v_session FROM private.atina_detective_sessions WHERE room_id=p_room_id AND status='active' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'A investigação já não está ativa.' USING errcode='55000'; END IF;
 SELECT * INTO v_character FROM private.atina_detective_characters
 WHERE session_id=v_session.id AND player_id=v_player.id AND role_kind<>'detective' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Não tens uma personagem nesta investigação.' USING errcode='42501'; END IF;
 SELECT id INTO v_interaction FROM private.atina_detective_interactions
 WHERE session_id=v_session.id AND character_id=v_character.id AND reaction='pending'
 ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Não tens nenhuma pergunta pendente.' USING errcode='55000'; END IF;
 UPDATE private.atina_detective_interactions SET response_text=btrim(p_reply),reaction='human'
 WHERE id=v_interaction;
 UPDATE private.atina_detective_sessions SET turn_number=turn_number+1,updated_at=clock_timestamp() WHERE id=v_session.id;
 RETURN jsonb_build_object('sent',true,'character',v_character.display_name);
END; $$;

CREATE OR REPLACE FUNCTION public.atina_detective_state(p_room_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_player public.atina_v2_room_players%rowtype; v_session private.atina_detective_sessions%rowtype;
 v_discoveries jsonb:='[]'::jsonb; v_characters jsonb; v_my_character jsonb; v_is_detective boolean;
 v_pending jsonb; v_dialogue jsonb:='[]'::jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 SELECT * INTO v_player FROM public.atina_v2_room_players WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256');
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 SELECT s.* INTO v_session FROM private.atina_detective_sessions s
 WHERE s.room_id=p_room_id AND s.status IN ('active','accused','completed');
 IF NOT FOUND THEN RAISE EXCEPTION 'Aventura não encontrada.' USING errcode='P0002'; END IF;
 v_is_detective:=v_session.detective_player_id=v_player.id;
 IF v_is_detective THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('evidence_id',e.id,'key',e.evidence_key,'title',e.title,'location',e.location_key,'object',e.object_key,'details',e.evidence_payload) ORDER BY d.discovered_at),'[]'::jsonb)
  INTO v_discoveries FROM private.atina_detective_discoveries d JOIN private.atina_detective_evidence e ON e.id=d.evidence_id WHERE d.session_id=v_session.id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('character',c.display_name,'topic',i.topic,'text',i.response_text,'reaction',i.reaction,'created_at',i.created_at) ORDER BY i.created_at),'[]'::jsonb)
  INTO v_dialogue FROM private.atina_detective_interactions i JOIN private.atina_detective_characters c ON c.id=i.character_id
  WHERE i.session_id=v_session.id AND i.reaction<>'pending';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('key',c.character_key,'name',c.display_name,'is_ai',c.is_ai_controlled,'is_me',coalesce(c.player_id=v_player.id,false)) ORDER BY c.display_name),'[]'::jsonb)
 INTO v_characters FROM private.atina_detective_characters c WHERE c.session_id=v_session.id;
 SELECT jsonb_build_object('name',c.display_name,'role',c.role_kind,'persona',c.persona_state,'knowledge',c.knowledge_state)
 INTO v_my_character FROM private.atina_detective_characters c WHERE c.session_id=v_session.id AND c.player_id=v_player.id;
 IF NOT v_is_detective THEN
  SELECT jsonb_build_object('character',c.display_name,'topic',i.topic,'question_number',i.id,'presented_evidence',
    CASE WHEN i.presented_evidence_id IS NULL THEN NULL ELSE (SELECT jsonb_build_object('title',e.title,'description',e.evidence_payload->>'description') FROM private.atina_detective_evidence e WHERE e.id=i.presented_evidence_id) END)
  INTO v_pending FROM private.atina_detective_interactions i JOIN private.atina_detective_characters c ON c.id=i.character_id
  WHERE i.session_id=v_session.id AND c.player_id=v_player.id AND i.reaction='pending'
  ORDER BY i.created_at DESC LIMIT 1;
 END IF;
 RETURN jsonb_build_object('session_id',v_session.id,'status',v_session.status,'is_detective',v_is_detective,
  'my_character',v_my_character,'state',v_session.public_state,'characters',v_characters,
  'discoveries',v_discoveries,'dialogue',v_dialogue,'pending_question',v_pending,'turn',v_session.turn_number);
END; $$;

REVOKE ALL ON FUNCTION public.atina_detective_character_reply(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_detective_character_reply(uuid,text,text) TO anon,authenticated;
