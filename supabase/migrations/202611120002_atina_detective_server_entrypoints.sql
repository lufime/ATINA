-- Server-authoritative entry points for the first Detective adventure slice.
-- All case solution/persona data remains in private tables.

INSERT INTO private.atina_detective_case_templates
  (case_id,title,version,case_payload,active)
VALUES
('o-ultimo-farol','O Último Farol',1,
'{
  "intro":"Durante uma tempestade, o faroleiro Duarte Vale foi encontrado morto no antigo farol da Ponta da Névoa. A porta principal estava trancada por dentro. Cinco pessoas estiveram no local nessa noite. Descobre o que aconteceu.",
  "starting_location":"hall",
  "locations":[
    {"key":"hall","name":"Átrio","description":"O átrio húmido do farol. Há marcas de água junto à escadaria."},
    {"key":"lantern","name":"Sala da Lanterna","description":"A luz do farol continua a rodar sobre o mar revolto."},
    {"key":"workshop","name":"Oficina","description":"Ferramentas, cabos e peças de metal cobrem a bancada."},
    {"key":"archive","name":"Arquivo","description":"Mapas náuticos e registos antigos ocupam as estantes."}
  ],
  "characters":[
    {"key":"ines","name":"Inês Moura","role":"suspect","persona":{"temperament":"nervous","statements":{"general":"Estou a tentar ajudar. Esta noite foi terrível.","whereabouts":"Estive no arquivo a organizar os registos.","timeline":"Ouvi o sino pouco depois das dez.","relationships":"O Duarte confiava em mim."},"lies":{"general":"Não sei de nada. Quero apenas ir embora.","whereabouts":"Não saí do arquivo em momento algum.","timeline":"Não me lembro das horas."}}},
    {"key":"raul","name":"Raul Faria","role":"culprit","persona":{"temperament":"defensive","hiddenRole":"culprit","statements":{"general":"O faroleiro tinha muitos inimigos.","whereabouts":"Estive na oficina a reparar uma dobradiça.","timeline":"A tempestade tornou impossível ouvir as horas.","relationships":"Discutíamos por causa da manutenção."},"lies":{"general":"Já expliquei tudo o que sei.","whereabouts":"Fiquei na oficina durante toda a noite.","timeline":"Não passei perto da sala da lanterna."}}},
    {"key":"celia","name":"Célia Nunes","role":"suspect","persona":{"temperament":"calm","statements":{"general":"Quero que a verdade venha ao de cima.","whereabouts":"Estive no átrio quando a luz falhou.","timeline":"A luz oscilou por volta das dez e meia.","relationships":"O Duarte era exigente, mas justo."}}},
    {"key":"tomás","name":"Tomás Reis","role":"suspect","persona":{"temperament":"proud","statements":{"general":"Não tenho razões para esconder nada.","whereabouts":"Estive junto à porta principal.","timeline":"Cheguei depois do primeiro toque do sino.","relationships":"O Duarte não gostava das minhas decisões."}}}
  ],
  "evidence":[
    {"key":"wet_bootprint","location":"hall","object":"floor","title":"Pegada molhada","payload":{"description":"Uma pegada de bota com um pequeno entalhe no calcanhar. A água salgada ainda não secou.","suggestedQuestion":"Quem entrou no átrio vindo diretamente do exterior?"},"requirements":{}},
    {"key":"cut_cable","location":"workshop","object":"bench","title":"Cabo cortado","payload":{"description":"Um cabo de segurança foi cortado com uma ferramenta afiada. O corte é recente.","suggestedQuestion":"Quem teve acesso às ferramentas da oficina?"},"requirements":{}},
    {"key":"maintenance_log","location":"archive","object":"shelf","title":"Registo de manutenção","payload":{"description":"O registo mostra que Raul requisitou uma lâmina de corte às 21:40 e não a devolveu.","contradicts":["raul_alibi"],"suggestedQuestion":"Porque precisaste de uma lâmina às 21:40?"},"requirements":{}},
    {"key":"lantern_oil","location":"lantern","object":"lamp","title":"Mancha de óleo","payload":{"description":"Há óleo fresco na manga de um casaco preso atrás da escada da lanterna.","suggestedQuestion":"Quem esteve junto ao mecanismo da lanterna?"},"requirements":{}}
  ],
  "solution":{"culprit":"raul","method":"O cabo de segurança foi cortado para provocar uma avaria e atrair Duarte à sala da lanterna. Raul aproveitou a confusão para o atacar e tentou encenar um acidente.","motive":"Duarte descobrira que Raul desviava material e iria denunciá-lo."}
}'::jsonb,true)
ON CONFLICT (case_id) DO UPDATE SET
  title=EXCLUDED.title,version=EXCLUDED.version,case_payload=EXCLUDED.case_payload,
  active=EXCLUDED.active,updated_at=clock_timestamp();

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
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(p_token,'sha256')
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

  v_chars := v_case.case_payload->'characters';
  v_evidence := v_case.case_payload->'evidence';
  v_locations := v_case.case_payload->'locations';
  IF jsonb_typeof(v_chars)<>'array' OR jsonb_array_length(v_chars)<v_count-1
     OR jsonb_typeof(v_evidence)<>'array' OR jsonb_typeof(v_locations)<>'array'
     OR (SELECT count(*) FROM jsonb_array_elements(v_chars) x WHERE x->>'role'='culprit')<>1 THEN
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

  v_seed := (('x' || substr(encode(extensions.gen_random_bytes(8),'hex'),1,15))::bit(60)::bigint);
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
  SELECT v_session.id,'detetive','Detetive', 'detective',v_detective,false,'{}'::jsonb;

  FOR v_player IN
    SELECT * FROM public.atina_room_players
    WHERE room_id=p_room_id AND id<>v_detective
    ORDER BY created_at,id
  LOOP
    v_index := v_index + 1;
    SELECT x INTO v_char FROM jsonb_array_elements(v_chars) WITH ORDINALITY AS a(x,n)
      WHERE n=v_index;
    INSERT INTO private.atina_detective_characters
      (session_id,character_key,display_name,role_kind,player_id,is_ai_controlled,persona_state)
    VALUES
      (v_session.id,v_char->>'key',v_char->>'name',
       CASE WHEN v_char->>'role'='culprit' THEN 'culprit' ELSE 'suspect' END,
       v_player.id,false,coalesce(v_char->'persona','{}'::jsonb));
  END LOOP;

  FOR v_index IN 1..jsonb_array_length(v_chars) LOOP
    SELECT x INTO v_char FROM jsonb_array_elements(v_chars) WITH ORDINALITY AS a(x,n)
      WHERE n=v_index;
    IF NOT EXISTS (SELECT 1 FROM private.atina_detective_characters
                   WHERE session_id=v_session.id AND character_key=v_char->>'key') THEN
      INSERT INTO private.atina_detective_characters
        (session_id,character_key,display_name,role_kind,is_ai_controlled,persona_state)
      VALUES
        (v_session.id,v_char->>'key',v_char->>'name',
         CASE WHEN v_char->>'role'='culprit' THEN 'culprit' ELSE 'suspect' END,
         true,coalesce(v_char->'persona','{}'::jsonb));
    END IF;
  END LOOP;

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_evidence)
  LOOP
    INSERT INTO private.atina_detective_evidence
      (session_id,evidence_key,location_key,object_key,title,evidence_payload,discovery_requirements)
    VALUES
      (v_session.id,v_item->>'key',v_item->>'location',v_item->>'object',
       v_item->>'title',coalesce(v_item->'payload','{}'::jsonb),
       coalesce(v_item->'requirements','{}'::jsonb));
  END LOOP;

  UPDATE public.atina_rooms
  SET status='playing',
      game_state=jsonb_build_object('mode','detetive_aventura','session_id',v_session.id),
      state_version=state_version+1,updated_at=clock_timestamp()
  WHERE id=p_room_id;

  RETURN jsonb_build_object('session_id',v_session.id,'status','active',
    'detective_player_id',v_detective,'state',v_session.public_state);
END;
$$;

CREATE OR REPLACE FUNCTION public.atina_detective_state(
  p_room_id uuid,
  p_token text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_player public.atina_room_players%rowtype;
  v_session private.atina_detective_sessions%rowtype;
  v_discoveries jsonb;
  v_characters jsonb;
  v_my_character jsonb;
BEGIN
  IF p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Sessão da sala inválida.' USING errcode='28000';
  END IF;
  SELECT * INTO v_player FROM public.atina_room_players
  WHERE room_id=p_room_id AND token_hash=extensions.digest(p_token,'sha256');
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.' USING errcode='28000'; END IF;

  SELECT s.* INTO v_session
  FROM private.atina_detective_sessions s
  WHERE s.room_id=p_room_id AND s.status IN ('active','accused','completed');
  IF NOT FOUND THEN RAISE EXCEPTION 'Aventura não encontrada.' USING errcode='P0002'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'evidence_id',e.id,'key',e.evidence_key,'title',e.title,
    'location',e.location_key,'object',e.object_key,'details',e.evidence_payload
  ) ORDER BY d.discovered_at),'[]'::jsonb)
  INTO v_discoveries
  FROM private.atina_detective_discoveries d
  JOIN private.atina_detective_evidence e ON e.id=d.evidence_id
  WHERE d.session_id=v_session.id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'key',c.character_key,'name',c.display_name,
    'is_ai',c.is_ai_controlled,'is_me',c.player_id=v_player.id
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
    'is_detective',v_session.detective_player_id=v_player.id,
    'my_character',v_my_character,
    'state',v_session.public_state,
    'characters',v_characters,
    'discoveries',v_discoveries,
    'turn',v_session.turn_number
  );
END;
$$;

REVOKE ALL ON FUNCTION public.atina_detective_start(uuid,text,text,text,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.atina_detective_state(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_detective_start(uuid,text,text,text,uuid) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_detective_state(uuid,text) TO anon,authenticated;
