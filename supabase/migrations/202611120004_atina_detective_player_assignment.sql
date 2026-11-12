-- Expand the pilot case to all seven non-detective seats and randomize role assignment.
UPDATE private.atina_detective_case_templates
SET case_payload=jsonb_set(
  case_payload,
  '{characters}',
  (case_payload->'characters') || '[
    {"key":"marta","name":"Marta Lobo","role":"suspect","persona":{"temperament":"observant","statements":{"general":"Reparei em detalhes que talvez sejam importantes.","whereabouts":"Estive na arrecadação a verificar as caixas.","timeline":"Ouvi passos na escada pouco antes das onze.","relationships":"O Duarte pediu-me que não comentasse as contas."}}},
    {"key":"elias","name":"Elias Pires","role":"suspect","persona":{"temperament":"reserved","statements":{"general":"Prefiro falar apenas do que vi.","whereabouts":"Estive no cais a prender o barco.","timeline":"A maré estava a subir quando ouvi um estrondo.","relationships":"Conhecia o Duarte desde criança."}}},
    {"key":"bia","name":"Beatriz Vale","role":"suspect","persona":{"temperament":"direct","statements":{"general":"Não vou inventar uma história para agradar a ninguém.","whereabouts":"Estive na cozinha a preparar café.","timeline":"A luz apagou-se por alguns instantes depois das dez.","relationships":"O Duarte era meu tio."}}}
  ]'::jsonb
),
updated_at=clock_timestamp()
WHERE case_id='o-ultimo-farol'
  AND NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(case_payload->'characters') x
    WHERE x->>'key'='marta'
  );

CREATE OR REPLACE FUNCTION public.atina_detective_start(
  p_room_id uuid,
  p_token text,
  p_case_id text DEFAULT 'o-ultimo-farol',
  p_selection text DEFAULT 'random',
  p_detective_player_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_room public.atina_rooms%rowtype;
  v_host public.atina_room_players%rowtype;
  v_case private.atina_detective_case_templates%rowtype;
  v_session private.atina_detective_sessions%rowtype;
  v_player public.atina_room_players%rowtype;
  v_char jsonb;
  v_item jsonb;
  v_detective uuid;
  v_count integer;
  v_index integer := 0;
  v_seed bigint;
  v_chars jsonb;
  v_evidence jsonb;
  v_locations jsonb;
BEGIN
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Sessão da sala inválida.' USING errcode='28000';
  END IF;
  IF p_selection NOT IN ('manual','random') THEN
    RAISE EXCEPTION 'Seleção de detetive inválida.' USING errcode='22023';
  END IF;
  SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status <> 'waiting' THEN
    RAISE EXCEPTION 'A sala não está disponível para iniciar.' USING errcode='55000';
  END IF;
  SELECT * INTO v_host FROM public.atina_room_players
  WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256')
  FOR UPDATE;
  IF NOT FOUND OR NOT v_host.is_host THEN
    RAISE EXCEPTION 'Só o anfitrião pode iniciar a aventura.' USING errcode='42501';
  END IF;
  SELECT count(*) INTO v_count FROM public.atina_room_players WHERE room_id=p_room_id;
  IF v_count < 1 OR v_count > 8 THEN
    RAISE EXCEPTION 'A aventura aceita entre 1 e 8 participantes humanos.' USING errcode='22023';
  END IF;
  SELECT * INTO v_case FROM private.atina_detective_case_templates
  WHERE case_id=p_case_id AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Caso indisponível.' USING errcode='22023'; END IF;

  -- Shuffle all suspect roles before assigning any human players. The culprit
  -- is therefore not predictably assigned to a particular seat.
  SELECT coalesce(jsonb_agg(x.value ORDER BY random()),'[]'::jsonb)
  INTO v_chars FROM jsonb_array_elements(v_case.case_payload->'characters') AS x(value);
  v_evidence:=v_case.case_payload->'evidence';
  v_locations:=v_case.case_payload->'locations';
  IF jsonb_typeof(v_chars)<>'array' OR jsonb_array_length(v_chars)<v_count-1
     OR jsonb_typeof(v_evidence)<>'array' OR jsonb_typeof(v_locations)<>'array'
     OR (SELECT count(*) FROM jsonb_array_elements(v_chars) AS x(value)
         WHERE value->>'role'='culprit')<>1 THEN
    RAISE EXCEPTION 'O caso não tem personagens, culpado ou provas suficientes.' USING errcode='22023';
  END IF;

  IF p_selection='manual' THEN
    SELECT id INTO v_detective FROM public.atina_room_players
    WHERE room_id=p_room_id AND id=p_detective_player_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'O detetive escolhido não pertence à sala.' USING errcode='22023'; END IF;
  ELSE
    SELECT id INTO v_detective FROM public.atina_room_players
    WHERE room_id=p_room_id ORDER BY random() LIMIT 1;
  END IF;

  v_seed := (('x'||substr(encode(extensions.gen_random_bytes(8),'hex'),1,15))::bit(60)::bigint);
  INSERT INTO private.atina_detective_sessions
    (room_id,case_id,status,detective_player_id,detective_selection,seed,
     current_location,world_state,public_state,secret_state,started_at)
  VALUES
    (p_room_id,p_case_id,'active',v_detective,p_selection,v_seed,
     v_case.case_payload->>'starting_location',
     jsonb_build_object('locations',v_locations,'turn',0),
     jsonb_build_object('title',v_case.title,'intro',v_case.case_payload->>'intro',
       'locations',v_locations,'current_location',v_case.case_payload->>'starting_location',
       'status','active'),
     jsonb_build_object('solution',v_case.case_payload->'solution'),
     clock_timestamp())
  RETURNING * INTO v_session;

  INSERT INTO private.atina_detective_characters
    (session_id,character_key,display_name,role_kind,player_id,is_ai_controlled,persona_state)
  VALUES(v_session.id,'detetive','Detetive','detective',v_detective,false,'{}'::jsonb);

  FOR v_player IN
    SELECT * FROM public.atina_room_players
    WHERE room_id=p_room_id AND id<>v_detective
    ORDER BY created_at,id
  LOOP
    v_index:=v_index+1;
    SELECT x.value INTO v_char FROM jsonb_array_elements(v_chars)
      WITH ORDINALITY AS x(value,n) WHERE x.n=v_index;
    INSERT INTO private.atina_detective_characters
      (session_id,character_key,display_name,role_kind,player_id,is_ai_controlled,persona_state)
    VALUES(v_session.id,v_char->>'key',v_char->>'name',
      CASE WHEN v_char->>'role'='culprit' THEN 'culprit' ELSE 'suspect' END,
      v_player.id,false,coalesce(v_char->'persona','{}'::jsonb));
  END LOOP;

  FOR v_index IN 1..jsonb_array_length(v_chars) LOOP
    SELECT x.value INTO v_char FROM jsonb_array_elements(v_chars)
      WITH ORDINALITY AS x(value,n) WHERE x.n=v_index;
    IF NOT EXISTS (SELECT 1 FROM private.atina_detective_characters
      WHERE session_id=v_session.id AND character_key=v_char->>'key') THEN
      INSERT INTO private.atina_detective_characters
        (session_id,character_key,display_name,role_kind,is_ai_controlled,persona_state)
      VALUES(v_session.id,v_char->>'key',v_char->>'name',
        CASE WHEN v_char->>'role'='culprit' THEN 'culprit' ELSE 'suspect' END,
        true,coalesce(v_char->'persona','{}'::jsonb));
    END IF;
  END LOOP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_evidence)
  LOOP
    INSERT INTO private.atina_detective_evidence
      (session_id,evidence_key,location_key,object_key,title,evidence_payload,discovery_requirements)
    VALUES(v_session.id,v_item->>'key',v_item->>'location',v_item->>'object',
      v_item->>'title',coalesce(v_item->'payload','{}'::jsonb),
      coalesce(v_item->'requirements','{}'::jsonb));
  END LOOP;

  UPDATE public.atina_rooms
  SET status='playing',game_state=jsonb_build_object('mode','detetive_aventura','session_id',v_session.id),
      state_version=state_version+1,updated_at=clock_timestamp()
  WHERE id=p_room_id;

  RETURN jsonb_build_object('session_id',v_session.id,'status','active',
    'detective_player_id',v_detective,'state',v_session.public_state);
END;
$$;
