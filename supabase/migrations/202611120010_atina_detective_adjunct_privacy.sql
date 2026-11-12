CREATE OR REPLACE FUNCTION public.atina_detective_adjunct(p_room_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE v_player public.atina_v2_room_players%rowtype; v_session private.atina_detective_sessions%rowtype;
 v_facts jsonb; v_suggestions jsonb; v_contradictions jsonb;
BEGIN
 IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 SELECT * INTO v_player FROM public.atina_v2_room_players WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256');
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão inválida.' USING errcode='28000'; END IF;
 SELECT * INTO v_session FROM private.atina_detective_sessions WHERE room_id=p_room_id AND status='active';
 IF NOT FOUND OR v_session.detective_player_id<>v_player.id THEN RAISE EXCEPTION 'O adjunto só está disponível ao detetive.' USING errcode='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('key',e.evidence_key,'title',e.title,'description',e.evidence_payload->>'description') ORDER BY d.discovered_at),'[]'::jsonb),
  coalesce(jsonb_agg(to_jsonb(e.evidence_payload->>'suggestedQuestion')) FILTER(WHERE nullif(e.evidence_payload->>'suggestedQuestion','') IS NOT NULL),'[]'::jsonb)
 INTO v_facts,v_suggestions
 FROM private.atina_detective_discoveries d JOIN private.atina_detective_evidence e ON e.id=d.evidence_id
 WHERE d.session_id=v_session.id;
 SELECT coalesce(jsonb_agg(jsonb_build_object('evidence',e.evidence_key,'contradicts',e2.evidence_key)),'[]'::jsonb)
 INTO v_contradictions
 FROM private.atina_detective_discoveries d
 JOIN private.atina_detective_evidence e ON e.id=d.evidence_id
 CROSS JOIN LATERAL jsonb_array_elements_text(coalesce(e.evidence_payload->'contradicts','[]'::jsonb)) c(value)
 JOIN private.atina_detective_evidence e2 ON e2.session_id=d.session_id AND e2.evidence_key=c.value
 JOIN private.atina_detective_discoveries d2 ON d2.session_id=d.session_id AND d2.evidence_id=e2.id;
 RETURN jsonb_build_object('facts',v_facts,'suggested_questions',v_suggestions,'contradictions',v_contradictions,
  'note','O adjunto analisa apenas provas já descobertas. Não identifica o culpado nem revela segredos.');
END; $$;