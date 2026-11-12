CREATE OR REPLACE FUNCTION public.atina_detective_state(p_room_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_player public.atina_v2_room_players%rowtype; v_session private.atina_detective_sessions%rowtype;
 v_discoveries jsonb:='[]'::jsonb; v_characters jsonb; v_my_character jsonb; v_is_detective boolean;
 v_pending jsonb; v_dialogue jsonb:='[]'::jsonb; v_result jsonb;
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
 IF v_session.status='completed' THEN
  SELECT jsonb_build_object('winner',v_session.winner,'correct',v_session.accusation->'correct',
   'accused',(SELECT c.display_name FROM private.atina_detective_characters c WHERE c.session_id=v_session.id AND c.character_key=v_session.accusation->>'character_key'))
  INTO v_result;
 END IF;
 RETURN jsonb_build_object('session_id',v_session.id,'status',v_session.status,'is_detective',v_is_detective,
  'my_character',v_my_character,'state',v_session.public_state,'characters',v_characters,
  'discoveries',v_discoveries,'dialogue',v_dialogue,'pending_question',v_pending,'turn',v_session.turn_number,'result',v_result);
END; $$;