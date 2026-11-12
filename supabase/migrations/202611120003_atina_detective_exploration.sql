-- Restrict evidence visibility to the human detective and add validated exploration RPCs.

CREATE OR REPLACE FUNCTION public.atina_detective_state(p_room_id uuid,p_token text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_player public.atina_room_players%rowtype;
  v_session private.atina_detective_sessions%rowtype;
  v_discoveries jsonb := '[]'::jsonb;
  v_characters jsonb;
  v_my_character jsonb;
  v_is_detective boolean;
BEGIN
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Sessão da sala inválida.' USING errcode='28000';
  END IF;
  SELECT * INTO v_player FROM public.atina_room_players
  WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256');
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.' USING errcode='28000'; END IF;

  SELECT s.* INTO v_session FROM private.atina_detective_sessions s
  WHERE s.room_id=p_room_id AND s.status IN ('active','accused','completed');
  IF NOT FOUND THEN RAISE EXCEPTION 'Aventura não encontrada.' USING errcode='P0002'; END IF;

  v_is_detective := v_session.detective_player_id=v_player.id;

  IF v_is_detective THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'evidence_id',e.id,'key',e.evidence_key,'title',e.title,
      'location',e.location_key,'object',e.object_key,'details',e.evidence_payload
    ) ORDER BY d.discovered_at),'[]'::jsonb)
    INTO v_discoveries
    FROM private.atina_detective_discoveries d
    JOIN private.atina_detective_evidence e ON e.id=d.evidence_id
    WHERE d.session_id=v_session.id;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'key',c.character_key,'name',c.display_name,
    'is_ai',c.is_ai_controlled,'is_me',coalesce(c.player_id=v_player.id,false)
  ) ORDER BY c.display_name),'[]'::jsonb)
  INTO v_characters
  FROM private.atina_detective_characters c
  WHERE c.session_id=v_session.id;

  SELECT jsonb_build_object('name',c.display_name,'role',c.role_kind)
  INTO v_my_character
  FROM private.atina_detective_characters c
  WHERE c.session_id=v_session.id AND c.player_id=v_player.id;

  RETURN jsonb_build_object(
    'session_id',v_session.id,'status',v_session.status,
    'is_detective',v_is_detective,'my_character',v_my_character,
    'state',v_session.public_state,'characters',v_characters,
    'discoveries',v_discoveries,'turn',v_session.turn_number
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.atina_detective_move(
  p_room_id uuid,p_token text,p_location_key text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_player public.atina_room_players%rowtype;
  v_session private.atina_detective_sessions%rowtype;
  v_locations jsonb;
  v_location jsonb;
  v_state jsonb;
BEGIN
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Sessão da sala inválida.' USING errcode='28000';
  END IF;
  SELECT * INTO v_player FROM public.atina_room_players
  WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256');
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.' USING errcode='28000'; END IF;
  SELECT * INTO v_session FROM private.atina_detective_sessions
  WHERE room_id=p_room_id AND status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Aventura não está ativa.' USING errcode='55000'; END IF;
  IF v_session.detective_player_id<>v_player.id THEN
    RAISE EXCEPTION 'Só o detetive pode explorar o cenário.' USING errcode='42501';
  END IF;

  v_locations:=v_session.public_state->'locations';
  SELECT x.value INTO v_location
  FROM jsonb_array_elements(v_locations) AS x(value)
  WHERE x.value->>'key'=p_location_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'Localização desconhecida.' USING errcode='22023'; END IF;

  v_state:=jsonb_set(v_session.public_state,'{current_location}',to_jsonb(p_location_key),true);
  UPDATE private.atina_detective_sessions
  SET current_location=p_location_key,public_state=v_state,
      turn_number=turn_number+1,updated_at=clock_timestamp()
  WHERE id=v_session.id;

  RETURN jsonb_build_object('location',v_location,'state',v_state);
END;
$$;

CREATE OR REPLACE FUNCTION public.atina_detective_discover(
  p_room_id uuid,p_token text,p_evidence_key text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_player public.atina_room_players%rowtype;
  v_session private.atina_detective_sessions%rowtype;
  v_evidence private.atina_detective_evidence%rowtype;
  v_required text;
BEGIN
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Sessão da sala inválida.' USING errcode='28000';
  END IF;
  SELECT * INTO v_player FROM public.atina_room_players
  WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256');
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.' USING errcode='28000'; END IF;
  SELECT * INTO v_session FROM private.atina_detective_sessions
  WHERE room_id=p_room_id AND status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Aventura não está ativa.' USING errcode='55000'; END IF;
  IF v_session.detective_player_id<>v_player.id THEN
    RAISE EXCEPTION 'Só o detetive pode recolher provas.' USING errcode='42501';
  END IF;
  SELECT * INTO v_evidence FROM private.atina_detective_evidence
  WHERE session_id=v_session.id AND evidence_key=p_evidence_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'Objeto ou prova desconhecidos.' USING errcode='22023'; END IF;
  IF v_evidence.location_key<>v_session.current_location THEN
    RAISE EXCEPTION 'Tens de estar no local certo para examinar este objeto.' USING errcode='42501';
  END IF;

  IF jsonb_typeof(v_evidence.discovery_requirements->'requires')='array' THEN
    FOR v_required IN SELECT jsonb_array_elements_text(v_evidence.discovery_requirements->'requires')
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM private.atina_detective_evidence e
        JOIN private.atina_detective_discoveries d
          ON d.evidence_id=e.id AND d.session_id=e.session_id
        WHERE e.session_id=v_session.id AND e.evidence_key=v_required
      ) THEN
        RAISE EXCEPTION 'Ainda não encontraste todas as pistas necessárias.' USING errcode='55000';
      END IF;
    END LOOP;
  END IF;

  INSERT INTO private.atina_detective_discoveries(session_id,evidence_id,discovered_by_player_id)
  VALUES(v_session.id,v_evidence.id,v_player.id)
  ON CONFLICT(session_id,evidence_id) DO NOTHING;

  UPDATE private.atina_detective_sessions
  SET turn_number=turn_number+1,updated_at=clock_timestamp()
  WHERE id=v_session.id;

  RETURN jsonb_build_object(
    'discovered',true,'key',v_evidence.evidence_key,
    'title',v_evidence.title,'details',v_evidence.evidence_payload
  );
END;
$$;

REVOKE ALL ON FUNCTION public.atina_detective_move(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.atina_detective_discover(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_detective_move(uuid,text,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_detective_discover(uuid,text,text) TO anon,authenticated;
