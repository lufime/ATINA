-- Team proposals are text-only; the server validates correctness and awards points after unanimous consent.
ALTER TABLE public.atina_room_team_proposals
  ADD COLUMN IF NOT EXISTS resolution_reason text
  CHECK (resolution_reason IS NULL OR resolution_reason IN ('disagreement','incorrect_answer','correct_answer','timeout'));

CREATE UNIQUE INDEX IF NOT EXISTS atina_room_team_one_pending_proposal_idx
  ON public.atina_room_team_proposals(room_id,challenge_index,team_label)
  WHERE status='pending';

CREATE OR REPLACE FUNCTION public.atina_submit_team_proposal(
  p_room_id uuid,
  p_token text,
  p_challenge integer,
  p_answer text,
  p_correct boolean DEFAULT NULL,
  p_points integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_room public.atina_rooms%rowtype;
  v_player public.atina_room_players%rowtype;
  v_game private.atina_room_game_state%rowtype;
  v_proposal public.atina_room_team_proposals%rowtype;
  v_team_size integer;
  v_now timestamptz;
  v_state jsonb;
BEGIN
  IF p_answer IS NULL OR char_length(btrim(p_answer)) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Resposta vazia ou demasiado longa.';
  END IF;

  SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;

  SELECT * INTO v_player FROM public.atina_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
  IF v_player.team_label IS NULL THEN RAISE EXCEPTION 'O jogador não pertence a uma equipa.'; END IF;

  SELECT * INTO v_game FROM private.atina_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' OR v_game.round_locked THEN
    RAISE EXCEPTION 'A ronda não está ativa.';
  END IF;
  IF p_challenge IS DISTINCT FROM v_game.position-1 THEN
    RAISE EXCEPTION 'O desafio indicado já não é o desafio atual.';
  END IF;

  v_now:=clock_timestamp();
  IF v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
    v_state:=private.atina_room_public_state(p_room_id)
      || jsonb_build_object('feedback','Tempo esgotado.','locked',true);
    UPDATE public.atina_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now
    WHERE id=p_room_id;
    RETURN jsonb_build_object('status','locked','state',v_state);
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.atina_room_answers a
    JOIN public.atina_room_players p ON p.id=a.player_id
    WHERE a.room_id=p_room_id AND a.challenge_index=v_game.position-1
      AND a.is_correct AND p.team_label=v_player.team_label
  ) THEN
    RETURN jsonb_build_object('status','already_correct');
  END IF;

  SELECT count(*) INTO v_team_size FROM public.atina_room_players
  WHERE room_id=p_room_id AND team_label=v_player.team_label;
  IF v_team_size<2 THEN RAISE EXCEPTION 'A equipa precisa de pelo menos dois jogadores para votar.'; END IF;

  SELECT * INTO v_proposal FROM public.atina_room_team_proposals
  WHERE room_id=p_room_id AND challenge_index=v_game.position-1
    AND team_label=v_player.team_label AND status='pending'
  ORDER BY created_at DESC LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'A equipa já tem uma proposta pendente.'; END IF;

  INSERT INTO public.atina_room_team_proposals(
    room_id,challenge_index,team_label,proposer_id,answer_text,status
  ) VALUES (
    p_room_id,v_game.position-1,v_player.team_label,v_player.id,btrim(p_answer),'pending'
  ) RETURNING * INTO v_proposal;

  RETURN jsonb_build_object(
    'status','pending','proposal_id',v_proposal.id,
    'message','Proposta registada; aguarda os votos dos restantes membros.'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_vote_team_proposal(
  p_room_id uuid,
  p_token text,
  p_proposal_id uuid,
  p_agrees boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_room public.atina_rooms%rowtype;
  v_player public.atina_room_players%rowtype;
  v_proposal public.atina_room_team_proposals%rowtype;
  v_game private.atina_room_game_state%rowtype;
  v_now timestamptz;
  v_team_size integer;
  v_votes integer;
  v_disagrees integer;
  v_correct boolean;
  v_base integer;
  v_speed integer:=0;
  v_points integer:=0;
  v_state jsonb;
  v_scores jsonb;
BEGIN
  IF p_agrees IS NULL THEN RAISE EXCEPTION 'Voto inválido.'; END IF;

  SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;

  SELECT * INTO v_player FROM public.atina_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;

  SELECT * INTO v_proposal FROM public.atina_room_team_proposals
  WHERE id=p_proposal_id AND room_id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proposta não encontrada.'; END IF;
  IF v_proposal.status<>'pending' THEN
    RETURN jsonb_build_object('status',v_proposal.status,'reason',v_proposal.resolution_reason);
  END IF;
  IF v_player.team_label IS NULL OR v_player.team_label<>v_proposal.team_label THEN
    RAISE EXCEPTION 'Só os membros da equipa podem votar.';
  END IF;
  IF v_player.id=v_proposal.proposer_id THEN
    RAISE EXCEPTION 'Quem propõe a resposta não pode votar na própria proposta.';
  END IF;

  SELECT * INTO v_game FROM private.atina_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' OR v_game.round_locked
     OR v_game.position-1<>v_proposal.challenge_index THEN
    RAISE EXCEPTION 'A proposta já não pertence à ronda ativa.';
  END IF;

  v_now:=clock_timestamp();
  IF v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
    v_state:=private.atina_room_public_state(p_room_id)
      || jsonb_build_object('feedback','Tempo esgotado.','locked',true);
    UPDATE public.atina_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now
    WHERE id=p_room_id;
    UPDATE public.atina_room_team_proposals
    SET status='rejected',resolution_reason='timeout',resolved_at=v_now
    WHERE id=v_proposal.id;
    RETURN jsonb_build_object('status','locked','reason','timeout','state',v_state);
  END IF;

  INSERT INTO public.atina_room_team_votes(proposal_id,player_id,agrees)
  VALUES(v_proposal.id,v_player.id,p_agrees);

  SELECT count(*) INTO v_team_size FROM public.atina_room_players
  WHERE room_id=p_room_id AND team_label=v_proposal.team_label;
  SELECT count(*),count(*) FILTER(WHERE NOT agrees)
  INTO v_votes,v_disagrees
  FROM public.atina_room_team_votes WHERE proposal_id=v_proposal.id;

  IF v_disagrees>0 THEN
    UPDATE public.atina_room_team_proposals
    SET status='rejected',resolution_reason='disagreement',resolved_at=v_now
    WHERE id=v_proposal.id;
    RETURN jsonb_build_object('status','rejected','reason','disagreement','votes',v_votes);
  END IF;

  IF v_votes<v_team_size-1 THEN
    RETURN jsonb_build_object('status','pending','votes',v_votes,'required',v_team_size-1);
  END IF;

  v_correct:=private.atina_challenge_answer_matches(
    v_game.challenge_queue[v_game.position],v_proposal.answer_text
  );

  IF v_correct THEN
    SELECT CASE WHEN c.image_url IS NOT NULL
      THEN (ARRAY[20,16,12,8,6,5])[v_game.revealed_clues]
      ELSE (ARRAY[20,16,12,8,5])[v_game.revealed_clues] END
    INTO v_base
    FROM private.atina_challenges c
    WHERE c.challenge_id=v_game.challenge_queue[v_game.position] AND c.active;

    IF v_game.deadline_at IS NOT NULL THEN
      v_speed:=greatest(0,floor(ceil(extract(epoch FROM (v_game.deadline_at-v_now)))/10)::integer);
    END IF;
    v_points:=v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END;

    UPDATE public.atina_room_players
    SET score=score+v_points,last_seen_at=v_now
    WHERE room_id=p_room_id AND team_label=v_proposal.team_label;

    INSERT INTO public.atina_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
    SELECT p_room_id,p.id,v_game.position-1,true,v_points,v_now
    FROM public.atina_room_players p
    WHERE p.room_id=p_room_id AND p.team_label=v_proposal.team_label;

    UPDATE public.atina_room_team_proposals
    SET status='accepted',resolution_reason='correct_answer',resolved_at=v_now
    WHERE id=v_proposal.id;

    SELECT coalesce(jsonb_agg(jsonb_build_object('player_id',p.id,'score',p.score) ORDER BY p.created_at,p.id),'[]'::jsonb)
    INTO v_scores FROM public.atina_room_players p
    WHERE p.room_id=p_room_id AND p.team_label=v_proposal.team_label;

    RETURN jsonb_build_object(
      'status','accepted','correct',true,'points_per_player',v_points,
      'scores',v_scores,'votes',v_votes
    );
  END IF;

  UPDATE public.atina_room_players
  SET score=greatest(0,score-10),last_seen_at=v_now
  WHERE room_id=p_room_id AND team_label=v_proposal.team_label;

  INSERT INTO public.atina_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
  SELECT p_room_id,p.id,v_game.position-1,false,0,v_now
  FROM public.atina_room_players p
  WHERE p.room_id=p_room_id AND p.team_label=v_proposal.team_label;

  UPDATE public.atina_room_team_proposals
  SET status='rejected',resolution_reason='incorrect_answer',resolved_at=v_now
  WHERE id=v_proposal.id;

  SELECT coalesce(jsonb_agg(jsonb_build_object('player_id',p.id,'score',p.score) ORDER BY p.created_at,p.id),'[]'::jsonb)
  INTO v_scores FROM public.atina_room_players p
  WHERE p.room_id=p_room_id AND p.team_label=v_proposal.team_label;

  RETURN jsonb_build_object(
    'status','rejected','reason','incorrect_answer','correct',false,
    'penalty_per_player',10,'scores',v_scores,'votes',v_votes
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_submit_team_proposal(uuid,text,integer,text,boolean,integer) FROM public;
REVOKE ALL ON FUNCTION public.atina_vote_team_proposal(uuid,text,uuid,boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_submit_team_proposal(uuid,text,integer,text,boolean,integer) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_vote_team_proposal(uuid,text,uuid,boolean) TO anon,authenticated;
