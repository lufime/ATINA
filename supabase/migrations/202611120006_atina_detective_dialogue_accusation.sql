CREATE OR REPLACE FUNCTION public.atina_detective_interrogate(
 p_room_id uuid,p_token text,p_character_key text,p_topic text DEFAULT 'general',p_presented_evidence_key text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_player public.atina_room_players%rowtype; v_session private.atina_detective_sessions%rowtype;
 v_character private.atina_detective_characters%rowtype; v_persona jsonb; v_discovered text[]; v_presented uuid;
 v_text text; v_reaction text; v_count integer;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 IF p_topic NOT IN ('whereabouts','timeline','relationships','object','motive','general') THEN RAISE EXCEPTION 'Tema inválido.' USING errcode='22023'; END IF;
 SELECT * INTO v_player FROM public.atina_room_players WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256');
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 SELECT * INTO v_session FROM private.atina_detective_sessions WHERE room_id=p_room_id AND status='active' FOR UPDATE;
 IF NOT FOUND OR v_session.detective_player_id<>v_player.id THEN RAISE EXCEPTION 'Só o detetive pode interrogar.' USING errcode='42501'; END IF;
 SELECT * INTO v_character FROM private.atina_detective_characters
 WHERE session_id=v_session.id AND character_key=p_character_key AND role_kind<>'detective';
 IF NOT FOUND THEN RAISE EXCEPTION 'Personagem desconhecida.' USING errcode='22023'; END IF;
 SELECT coalesce(array_agg(e.evidence_key),'{}'::text[]) INTO v_discovered
 FROM private.atina_detective_discoveries d JOIN private.atina_detective_evidence e ON e.id=d.evidence_id
 WHERE d.session_id=v_session.id;
 IF p_presented_evidence_key IS NOT NULL THEN
   SELECT e.id INTO v_presented FROM private.atina_detective_evidence e
   JOIN private.atina_detective_discoveries d ON d.evidence_id=e.id AND d.session_id=e.session_id
   WHERE e.session_id=v_session.id AND e.evidence_key=p_presented_evidence_key;
   IF NOT FOUND THEN RAISE EXCEPTION 'Não podes apresentar uma prova que ainda não descobriste.' USING errcode='42501'; END IF;
 END IF;
 SELECT count(*) INTO v_count FROM private.atina_detective_interactions
 WHERE session_id=v_session.id AND character_id=v_character.id;
 v_persona:=v_character.persona_state;
 IF p_presented_evidence_key IS NOT NULL AND v_persona->'evidenceResponses' ? p_presented_evidence_key THEN
   v_text:=v_persona->'evidenceResponses'->>p_presented_evidence_key; v_reaction:='evidence';
 ELSE
   v_text:=coalesce(
     CASE WHEN v_character.role_kind='culprit' THEN v_persona->'lies'->>p_topic END,
     v_persona->'statements'->>p_topic,
     v_persona->'statements'->>'general',
     'Não tenho mais nada a acrescentar neste momento.'
   );
   v_reaction:=CASE WHEN v_character.role_kind='culprit' THEN 'guarded' ELSE 'cooperative' END;
 END IF;
 INSERT INTO private.atina_detective_interactions(session_id,character_id,player_id,topic,presented_evidence_id,response_text,reaction)
 VALUES(v_session.id,v_character.id,v_player.id,p_topic,v_presented,v_text,v_reaction);
 UPDATE private.atina_detective_sessions SET turn_number=turn_number+1,updated_at=clock_timestamp() WHERE id=v_session.id;
 RETURN jsonb_build_object('character',v_character.display_name,'topic',p_topic,'text',v_text,'reaction',v_reaction,'question_number',v_count+1);
END; $$;

CREATE OR REPLACE FUNCTION public.atina_detective_adjunct(p_room_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_player public.atina_room_players%rowtype; v_session private.atina_detective_sessions%rowtype;
 v_facts jsonb; v_suggestions jsonb; v_contradictions jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 SELECT * INTO v_player FROM public.atina_room_players WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256');
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 SELECT * INTO v_session FROM private.atina_detective_sessions WHERE room_id=p_room_id AND status='active';
 IF NOT FOUND OR v_session.detective_player_id<>v_player.id THEN RAISE EXCEPTION 'O adjunto só está disponível ao detetive.' USING errcode='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('key',e.evidence_key,'title',e.title,'description',e.evidence_payload->>'description') ORDER BY d.discovered_at),'[]'::jsonb),
        coalesce(jsonb_agg(to_jsonb(e.evidence_payload->>'suggestedQuestion')) FILTER(WHERE nullif(e.evidence_payload->>'suggestedQuestion','') IS NOT NULL),'[]'::jsonb)
 INTO v_facts,v_suggestions
 FROM private.atina_detective_discoveries d JOIN private.atina_detective_evidence e ON e.id=d.evidence_id
 WHERE d.session_id=v_session.id;
 SELECT coalesce(jsonb_agg(jsonb_build_object('evidence',e.evidence_key,'contradicts',c.value)), '[]'::jsonb)
 INTO v_contradictions
 FROM private.atina_detective_discoveries d
 JOIN private.atina_detective_evidence e ON e.id=d.evidence_id
 CROSS JOIN LATERAL jsonb_array_elements_text(coalesce(e.evidence_payload->'contradicts','[]'::jsonb)) c(value)
 WHERE d.session_id=v_session.id;
 RETURN jsonb_build_object('facts',v_facts,'suggested_questions',v_suggestions,'contradictions',v_contradictions,
 'note','O adjunto analisa apenas provas já descobertas. Não identifica o culpado nem revela segredos.');
END; $$;

CREATE OR REPLACE FUNCTION public.atina_detective_accuse(p_room_id uuid,p_token text,p_character_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_player public.atina_room_players%rowtype; v_session private.atina_detective_sessions%rowtype;
 v_target private.atina_detective_characters%rowtype; v_solution jsonb; v_correct boolean;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 SELECT * INTO v_player FROM public.atina_room_players WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256');
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 SELECT * INTO v_session FROM private.atina_detective_sessions WHERE room_id=p_room_id AND status='active' FOR UPDATE;
 IF NOT FOUND OR v_session.detective_player_id<>v_player.id THEN RAISE EXCEPTION 'Só o detetive pode apresentar a acusação.' USING errcode='42501'; END IF;
 SELECT * INTO v_target FROM private.atina_detective_characters WHERE session_id=v_session.id AND character_key=p_character_key AND role_kind<>'detective';
 IF NOT FOUND THEN RAISE EXCEPTION 'Suspeito desconhecido.' USING errcode='22023'; END IF;
 SELECT case_payload->'solution' INTO v_solution FROM private.atina_detective_case_templates WHERE case_id=v_session.case_id;
 v_correct:=v_target.role_kind='culprit';
 UPDATE private.atina_detective_sessions SET status='completed',winner=CASE WHEN v_correct THEN 'detective' ELSE 'culprit' END,
 accusation=jsonb_build_object('character_key',p_character_key,'correct',v_correct),
 public_state=jsonb_set(public_state,'{status}','"completed"'::jsonb,true),
 completed_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=v_session.id;
 UPDATE public.atina_rooms SET status='completed',state_version=state_version+1,updated_at=clock_timestamp() WHERE id=p_room_id;
 RETURN jsonb_build_object('correct',v_correct,'winner',CASE WHEN v_correct THEN 'detective' ELSE 'culprit' END,
 'accused',v_target.display_name,'solution',v_solution);
END; $$;

REVOKE ALL ON FUNCTION public.atina_detective_interrogate(uuid,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.atina_detective_adjunct(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.atina_detective_accuse(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_detective_interrogate(uuid,text,text,text,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_detective_adjunct(uuid,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_detective_accuse(uuid,text,text) TO anon,authenticated;
