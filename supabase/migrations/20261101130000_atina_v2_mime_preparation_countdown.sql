-- Start multiplayer Mímicas rounds only after a shared draw animation and preparation countdown.
-- The host starts the server-side round clock through atina_v2_publish_game_state.
CREATE OR REPLACE FUNCTION public.atina_v2_start_mime_round(
 p_room_id uuid,p_token text,p_round_number integer,p_representative_id uuid,p_duration_seconds integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_host public.atina_v2_room_players%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_rep public.atina_v2_room_players%rowtype;
 v_card private.atina_mime_cards%rowtype;
 v_prev private.atina_v2_mime_rounds%rowtype;
 v_now timestamptz;
 v_deadline timestamptz;
 v_state jsonb;
 v_total integer;
BEGIN
 SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A sala não está ativa.'; END IF;
 SELECT * INTO v_host FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND OR NOT v_host.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode preparar uma ronda de Mímicas.'; END IF;
 IF p_duration_seconds IS NULL OR p_duration_seconds NOT IN (0,60,90) THEN RAISE EXCEPTION 'Duração inválida.'; END IF;
 SELECT * INTO v_rep FROM public.atina_v2_room_players WHERE id=p_representative_id AND room_id=p_room_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Representante inválido.'; END IF;
 SELECT count(*) INTO v_total FROM private.atina_mime_cards;
 IF p_round_number IS NULL OR p_round_number<0 OR p_round_number>=v_total THEN RAISE EXCEPTION 'Não existem mais rondas.'; END IF;
 IF p_round_number=0 THEN
  IF EXISTS(SELECT 1 FROM private.atina_v2_mime_rounds WHERE room_id=p_room_id) THEN
   RAISE EXCEPTION 'A partida de Mímicas já começou.';
  END IF;
 ELSE
  SELECT * INTO v_prev FROM private.atina_v2_mime_rounds
  WHERE room_id=p_room_id AND round_number=p_round_number-1 FOR UPDATE;
  IF NOT FOUND OR NOT v_prev.locked THEN RAISE EXCEPTION 'A ronda anterior ainda não terminou.'; END IF;
 END IF;
 SELECT * INTO v_card FROM private.atina_mime_cards c
 WHERE NOT EXISTS(SELECT 1 FROM private.atina_v2_mime_rounds r WHERE r.room_id=p_room_id AND r.card_id=c.id)
 ORDER BY random() LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'Não existem mais cartões inéditos nesta partida.'; END IF;
 v_now:=clock_timestamp();
 v_deadline:=CASE WHEN p_duration_seconds=0 THEN NULL ELSE v_now+make_interval(secs=>p_duration_seconds) END;
 INSERT INTO private.atina_v2_mime_rounds(room_id,round_number,card_id,representative_id,started_at,deadline_at,duration_seconds)
 VALUES(p_room_id,p_round_number,v_card.id,v_rep.id,NULL,NULL,p_duration_seconds);
 v_state:=jsonb_build_object(
  'mode','mimicas','round',p_round_number,'total_rounds',v_total,
  'representative_id',v_rep.id,'representative_name',v_rep.nickname,
  'team_label',v_rep.team_label,'category',v_card.category,
  'clues',jsonb_build_array(v_card.clues->0),'clue_index',0,
  'duration_seconds',p_duration_seconds,'started',false,'locked',false,
  'deadline',0,
  'draw_until',floor(extract(epoch FROM (v_now+interval '2 seconds'))*1000)::bigint,
  'prepare_until',floor(extract(epoch FROM (v_now+interval '12 seconds'))*1000)::bigint,
  'revision',coalesce((v_room.game_state->>'revision')::integer,0)+1
 );
 UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
 RETURN v_state;
END;
$function$;
