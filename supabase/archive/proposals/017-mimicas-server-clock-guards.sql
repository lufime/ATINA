-- Mímicas: the server clock starts only on the host's explicit start action.
CREATE OR REPLACE FUNCTION public.atina_start_mime_round(
 p_room_id uuid,p_token text,p_round_number integer,p_representative_id uuid,p_duration_seconds integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_host public.atina_room_players%rowtype;
 v_room public.atina_rooms%rowtype;
 v_rep public.atina_room_players%rowtype;
 v_card private.atina_mime_cards%rowtype;
 v_prev private.atina_mime_rounds%rowtype;
 v_now timestamptz;
 v_state jsonb;
 v_total integer;
BEGIN
 SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A sala não está ativa.'; END IF;
 SELECT * INTO v_host FROM public.atina_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND OR NOT v_host.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode preparar uma ronda de Mímicas.'; END IF;
 IF p_duration_seconds IS NULL OR p_duration_seconds NOT IN (0,60,90) THEN RAISE EXCEPTION 'Duração inválida.'; END IF;
 SELECT * INTO v_rep FROM public.atina_room_players WHERE id=p_representative_id AND room_id=p_room_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Representante inválido.'; END IF;
 SELECT count(*) INTO v_total FROM private.atina_mime_cards;
 IF p_round_number IS NULL OR p_round_number<0 OR p_round_number>=v_total THEN RAISE EXCEPTION 'Não existem mais rondas.'; END IF;
 IF p_round_number=0 THEN
  IF coalesce(v_room.game_state->>'mode','')<>'pending'
     OR EXISTS(SELECT 1 FROM private.atina_mime_rounds WHERE room_id=p_room_id) THEN
   RAISE EXCEPTION 'A partida não está preparada para iniciar Mímicas.';
  END IF;
 ELSE
  SELECT * INTO v_prev FROM private.atina_mime_rounds
  WHERE room_id=p_room_id AND round_number=p_round_number-1 FOR UPDATE;
  IF coalesce(v_room.game_state->>'mode','')<>'mimicas'
     OR coalesce((v_room.game_state->>'round')::integer,-1)<>p_round_number-1
     OR coalesce((v_room.game_state->>'locked')::boolean,false)=false
     OR NOT FOUND OR NOT v_prev.locked THEN
   RAISE EXCEPTION 'A ronda anterior ainda não terminou.';
  END IF;
 END IF;
 SELECT * INTO v_card FROM private.atina_mime_cards c
 WHERE NOT EXISTS(SELECT 1 FROM private.atina_mime_rounds r WHERE r.room_id=p_room_id AND r.card_id=c.id)
 ORDER BY random() LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'Não existem mais cartões inéditos nesta partida.'; END IF;
 v_now:=clock_timestamp();
 INSERT INTO private.atina_mime_rounds(room_id,round_number,card_id,representative_id,started_at,deadline_at,duration_seconds)
 VALUES(p_room_id,p_round_number,v_card.id,v_rep.id,NULL,NULL,p_duration_seconds);
 v_state:=jsonb_build_object(
  'mode','mimicas','round',p_round_number,'total_rounds',v_total,
  'representative_id',v_rep.id,'representative_name',v_rep.nickname,
  'team_label',v_rep.team_label,'category',v_card.category,
  'clues',jsonb_build_array(v_card.clues->0),'clue_index',0,
  'duration_seconds',p_duration_seconds,'started',false,'locked',false,
  'deadline',0,'revision',coalesce((v_room.game_state->>'revision')::integer,0)+1
 );
 UPDATE public.atina_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
 RETURN v_state;
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_publish_game_state(p_room_id uuid,p_token text,p_state jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_host public.atina_room_players%rowtype;
 v_room public.atina_rooms%rowtype;
 v_round private.atina_mime_rounds%rowtype;
 v_now timestamptz;
 v_state jsonb;
 v_requested_clue integer;
BEGIN
 SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A sala não está ativa.'; END IF;
 SELECT * INTO v_host FROM public.atina_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND OR NOT v_host.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode atualizar a ronda.'; END IF;
 IF coalesce(v_room.game_state->>'mode','')<>'mimicas' OR jsonb_typeof(p_state)<>'object' THEN
  RAISE EXCEPTION 'Publicação de estado arbitrário não é permitida.';
 END IF;
 SELECT * INTO v_round FROM private.atina_mime_rounds
 WHERE room_id=p_room_id ORDER BY round_number DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND OR v_round.locked THEN RAISE EXCEPTION 'A ronda já terminou.'; END IF;
 v_now:=clock_timestamp();
 IF v_round.deadline_at IS NOT NULL AND v_round.deadline_at<=v_now THEN
  RAISE EXCEPTION 'O tempo desta ronda terminou.';
 END IF;
 v_state:=v_room.game_state;
 v_requested_clue:=coalesce((p_state->>'clue_index')::integer,v_round.clue_index);
 IF coalesce((p_state->>'started')::boolean,false) AND v_round.started_at IS NULL THEN
  UPDATE private.atina_mime_rounds SET started_at=v_now,
    deadline_at=CASE WHEN duration_seconds=0 THEN NULL ELSE v_now+make_interval(secs=>duration_seconds) END,
    updated_at=v_now
  WHERE room_id=p_room_id AND round_number=v_round.round_number
  RETURNING * INTO v_round;
  v_state:=jsonb_set(v_state,'{started}','true'::jsonb,true);
  v_state:=jsonb_set(v_state,'{deadline}',to_jsonb(CASE WHEN v_round.deadline_at IS NULL THEN 0 ELSE floor(extract(epoch FROM v_round.deadline_at)*1000)::bigint END),true);
 ELSIF v_round.started_at IS NOT NULL AND v_requested_clue=v_round.clue_index+1 AND v_requested_clue BETWEEN 1 AND 4 THEN
  UPDATE private.atina_mime_rounds SET clue_index=v_requested_clue,updated_at=v_now
  WHERE room_id=p_room_id AND round_number=v_round.round_number
  RETURNING * INTO v_round;
  v_state:=jsonb_set(v_state,'{clue_index}',to_jsonb(v_round.clue_index),true);
  v_state:=jsonb_set(v_state,'{clues}',(
    SELECT jsonb_agg(c.clues->i ORDER BY i)
    FROM private.atina_mime_cards c
    CROSS JOIN generate_series(0,v_round.clue_index) i
    WHERE c.id=v_round.card_id
  ),true);
 ELSE
  RAISE EXCEPTION 'Transição de Mímicas inválida.';
 END IF;
 v_state:=jsonb_set(v_state,'{revision}',to_jsonb(coalesce((v_state->>'revision')::integer,0)+1),true);
 UPDATE public.atina_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
 RETURN v_state;
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_resolve_mime_round(
 p_room_id uuid,p_token text,p_correct boolean,p_points integer,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_host public.atina_room_players%rowtype;
 v_room public.atina_rooms%rowtype;
 v_round private.atina_mime_rounds%rowtype;
 v_card private.atina_mime_cards%rowtype;
 v_now timestamptz;
 v_correct boolean;
 v_reason text;
 v_points integer:=0;
 v_remaining integer:=0;
 v_state jsonb;
 v_team text;
 v_rep uuid;
BEGIN
 SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id AND status='playing' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
 SELECT * INTO v_host FROM public.atina_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND OR NOT v_host.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode terminar a ronda.'; END IF;
 SELECT * INTO v_round FROM private.atina_mime_rounds
 WHERE room_id=p_room_id ORDER BY round_number DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND OR v_round.locked THEN RAISE EXCEPTION 'A ronda já terminou.'; END IF;
 IF v_round.started_at IS NULL THEN RAISE EXCEPTION 'O cronómetro ainda não foi iniciado.'; END IF;
 v_now:=clock_timestamp();
 v_correct:=coalesce(p_correct,false);
 v_reason:=coalesce(p_reason,CASE WHEN v_correct THEN 'correct' ELSE 'pass' END);
 IF v_reason NOT IN ('correct','pass','timeout') THEN RAISE EXCEPTION 'Motivo inválido.'; END IF;
 IF v_round.deadline_at IS NOT NULL AND v_round.deadline_at<=v_now THEN
  v_correct:=false; v_reason:='timeout';
 END IF;
 IF v_correct AND v_reason<>'correct' THEN RAISE EXCEPTION 'Resultado inválido.'; END IF;
 IF v_reason='correct' AND NOT v_correct THEN RAISE EXCEPTION 'Resultado inválido.'; END IF;
 SELECT * INTO v_card FROM private.atina_mime_cards WHERE id=v_round.card_id;
 v_rep:=v_round.representative_id;
 SELECT team_label INTO v_team FROM public.atina_room_players WHERE id=v_rep AND room_id=p_room_id;
 IF v_correct THEN
  IF v_round.deadline_at IS NOT NULL THEN
   v_remaining:=greatest(0,ceil(extract(epoch FROM (v_round.deadline_at-v_now)))::integer);
  END IF;
  v_points:=(ARRAY[20,16,12,8,5])[v_round.clue_index+1]
    +CASE WHEN v_round.duration_seconds>0 THEN floor(v_remaining/10)::integer ELSE 0 END;
  IF v_team IS NOT NULL THEN
   UPDATE public.atina_room_players SET score=score+v_points
   WHERE room_id=p_room_id AND team_label=v_team;
   INSERT INTO public.atina_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
   SELECT p_room_id,id,v_round.round_number,true,v_points,v_now
   FROM public.atina_room_players WHERE room_id=p_room_id AND team_label=v_team;
  ELSE
   UPDATE public.atina_room_players SET score=score+v_points
   WHERE room_id=p_room_id AND id<>v_rep;
   INSERT INTO public.atina_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
   SELECT p_room_id,id,v_round.round_number,true,v_points,v_now
   FROM public.atina_room_players WHERE room_id=p_room_id AND id<>v_rep;
  END IF;
 END IF;
 UPDATE private.atina_mime_rounds SET locked=true,outcome=v_reason,points_awarded=v_points,updated_at=v_now
 WHERE room_id=p_room_id AND round_number=v_round.round_number;
 v_state:=v_room.game_state;
 v_state:=jsonb_set(v_state,'{locked}','true'::jsonb,true);
 v_state:=jsonb_set(v_state,'{deadline}','0'::jsonb,true);
 v_state:=jsonb_set(v_state,'{answer}',to_jsonb(v_card.word),true);
 v_state:=jsonb_set(v_state,'{correct}',to_jsonb(v_correct),true);
 v_state:=jsonb_set(v_state,'{points_awarded}',to_jsonb(v_points),true);
 v_state:=jsonb_set(v_state,'{feedback}',to_jsonb(CASE WHEN v_correct THEN 'Acertaram! +'||v_points||' pontos.' WHEN v_reason='timeout' THEN 'Tempo esgotado.' ELSE 'Palavra passada.' END),true);
 v_state:=jsonb_set(v_state,'{revision}',to_jsonb(coalesce((v_state->>'revision')::integer,0)+1),true);
 UPDATE public.atina_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
 RETURN v_state;
END;
$function$;
