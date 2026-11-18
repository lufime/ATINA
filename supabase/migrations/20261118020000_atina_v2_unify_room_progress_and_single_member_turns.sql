-- Align V2 room turns and account progression with the established server rules.
-- Additive only. This migration is source-controlled; it is not applied remotely.

create table if not exists private.atina_room_progress_events (
  id bigint generated always as identity primary key,
  player_id uuid not null references private.atina_players(id) on delete cascade,
  room_id uuid not null references public.atina_v2_rooms(id) on delete cascade,
  challenge_position integer not null check (challenge_position > 0),
  xp integer not null check (xp = 10),
  created_at timestamptz not null default clock_timestamp(),
  constraint atina_room_progress_events_once
    unique (player_id, room_id, challenge_position)
);

alter table private.atina_room_progress_events enable row level security;
revoke all on table private.atina_room_progress_events from public, anon, authenticated;
create index if not exists atina_room_progress_events_player_created_idx
  on private.atina_room_progress_events(player_id, created_at desc);

-- The V2 turn-control RPCs require these fields on the authoritative room state.
alter table private.atina_v2_room_game_state
  add column if not exists team_order text[] not null default '{}',
  add column if not exists active_team_index integer not null default 1,
  add column if not exists team_turn_advanced boolean not null default false;

-- Liga cada participante à conta autenticada, sem confiar no pseudónimo enviado pelo cliente.
ALTER TABLE public.atina_v2_room_players
  ADD COLUMN IF NOT EXISTS account_player_id uuid
    REFERENCES private.atina_players(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.atina_v2_create_room(
  p_nickname text,p_max_players integer,p_session_token text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player_id uuid;
  v_result jsonb;
BEGIN
  IF p_session_token IS NULL OR p_session_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Inicia sessão na tua conta ATINA para criar uma sala.' USING errcode='28000';
  END IF;
  SELECT a.player_id INTO v_player_id
    FROM private.atina_player_accounts a
   WHERE a.session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
     AND a.session_expires_at>clock_timestamp()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sessão expirada. Inicia sessão novamente.' USING errcode='28000';
  END IF;
  v_result:=public.atina_v2_create_room(p_nickname,p_max_players);
  UPDATE public.atina_v2_room_players
     SET account_player_id=v_player_id
   WHERE id=(v_result->>'player_id')::uuid
     AND room_id=(v_result->>'room_id')::uuid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Não foi possível associar a conta à sala.'; END IF;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_join_room(
  p_nickname text,p_code text,p_session_token text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player_id uuid;
  v_result jsonb;
BEGIN
  IF p_session_token IS NULL OR p_session_token !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Inicia sessão na tua conta ATINA para entrar numa sala.' USING errcode='28000';
  END IF;
  SELECT a.player_id INTO v_player_id
    FROM private.atina_player_accounts a
   WHERE a.session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
     AND a.session_expires_at>clock_timestamp()
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sessão expirada. Inicia sessão novamente.' USING errcode='28000';
  END IF;
  v_result:=public.atina_v2_join_room(p_nickname,p_code);
  UPDATE public.atina_v2_room_players
     SET account_player_id=v_player_id
   WHERE id=(v_result->>'player_id')::uuid
     AND room_id=(v_result->>'room_id')::uuid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Não foi possível associar a conta à sala.'; END IF;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_create_room(text,integer,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.atina_v2_join_room(text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_v2_create_room(text,integer,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_join_room(text,text,text) TO anon,authenticated;

-- Definição completa da RPC: sem edição dinâmica de fragmentos de texto.
-- A ordem das equipas fica persistida no estado autoritativo da sala.
CREATE OR REPLACE FUNCTION public.atina_v2_start_room_challenges(
  p_room_id uuid,
  p_token text,
  p_difficulty text DEFAULT 'medium',
  p_duration_seconds integer DEFAULT 60,
  p_category text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_host public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_queue integer[];
  v_now timestamptz;
  v_deadline timestamptz;
  v_challenge private.atina_challenges%rowtype;
  v_state jsonb;
  v_team_order text[];
BEGIN
  IF p_difficulty IS NULL OR p_difficulty NOT IN ('easy','medium','hard') THEN
    RAISE EXCEPTION 'Dificuldade inválida.';
  END IF;
  IF p_duration_seconds IS NULL OR p_duration_seconds NOT BETWEEN 0 AND 3600 THEN
    RAISE EXCEPTION 'Duração inválida.';
  END IF;
  IF p_category IS NOT NULL AND char_length(btrim(p_category)) NOT BETWEEN 1 AND 80 THEN
    RAISE EXCEPTION 'Categoria inválida.';
  END IF;

  SELECT * INTO v_host
  FROM public.atina_v2_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND OR NOT v_host.is_host THEN
    RAISE EXCEPTION 'Só o anfitrião pode iniciar os desafios.';
  END IF;

  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status <> 'playing' OR v_room.game_state->>'mode' <> 'pending' THEN
    RAISE EXCEPTION 'A sala não está preparada para iniciar os desafios.';
  END IF;

  SELECT array_agg(team_label ORDER BY team_label)
  INTO v_team_order
  FROM (
    SELECT DISTINCT team_label
    FROM public.atina_v2_room_players
    WHERE room_id=p_room_id AND team_label IS NOT NULL
  ) assigned_teams;
  IF coalesce(cardinality(v_team_order),0)<2 THEN
    RAISE EXCEPTION 'A partida necessita de pelo menos duas equipas atribuídas.';
  END IF;

  SELECT array_agg(challenge_id ORDER BY random())
  INTO v_queue
  FROM private.atina_challenges
  WHERE active
    AND difficulty=p_difficulty
    AND (p_category IS NULL OR category=p_category);
  IF coalesce(cardinality(v_queue),0)=0 THEN
    RAISE EXCEPTION 'Não existem desafios disponíveis para estes critérios.';
  END IF;

  v_now:=clock_timestamp();
  v_deadline:=CASE WHEN p_duration_seconds=0 THEN NULL
                   ELSE v_now+make_interval(secs=>p_duration_seconds) END;

  INSERT INTO private.atina_v2_room_game_state(
    room_id,challenge_queue,position,difficulty,category,timed_mode_seconds,
    revealed_clues,deadline_at,round_locked,status,created_at,updated_at,
    team_order,active_team_index,team_turn_advanced
  ) VALUES (
    p_room_id,v_queue,1,p_difficulty,p_category,p_duration_seconds,
    1,v_deadline,false,'active',v_now,v_now,
    v_team_order,1,false
  );

  SELECT * INTO v_challenge
  FROM private.atina_challenges
  WHERE challenge_id=v_queue[1] AND active;

  v_state:=jsonb_build_object(
    'mode','challenges',
    'protocol_version',1,
    'challenge_id',v_challenge.challenge_id,
    'category',v_challenge.category,
    'emoji',v_challenge.emoji,
    'clues',jsonb_build_array(v_challenge.clues->0),
    'image_url',v_challenge.image_url,
    'pos',0,
    'queue_length',cardinality(v_queue),
    'active_team',v_team_order[1],
    'special_card',NULL,
    'revealed',1,
    'timedMode',p_duration_seconds,
    'deadline',CASE WHEN v_deadline IS NULL THEN 0 ELSE extract(epoch FROM v_deadline)*1000 END,
    'locked',false,
    'revision',v_room.state_version+1
  );

  UPDATE public.atina_v2_rooms
  SET game_state=v_state,state_version=state_version+1,updated_at=v_now
  WHERE id=p_room_id;

  RETURN jsonb_build_object('status','started','queue_length',cardinality(v_queue),'state',v_state);
END;
$function$;


-- Turnos, respostas e cartas especiais são definidos integralmente.
-- Cada desafio pertence à equipa ativa; erros permitem nova tentativa.
CREATE OR REPLACE FUNCTION private.atina_v2_room_public_state(p_room_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_game private.atina_v2_room_game_state%rowtype;
  v_challenge private.atina_challenges%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_clues jsonb;
BEGIN
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id;
  SELECT * INTO v_challenge FROM private.atina_challenges
   WHERE challenge_id=v_game.challenge_queue[v_game.position] AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Desafio atual indisponível.'; END IF;
  SELECT coalesce(jsonb_agg(cl.value ORDER BY cl.ordinality),'[]'::jsonb)
    INTO v_clues
    FROM jsonb_array_elements(v_challenge.clues) WITH ORDINALITY cl(value,ordinality)
   WHERE cl.ordinality<=v_game.revealed_clues;
  RETURN jsonb_build_object(
    'mode','challenges','protocol_version',1,
    'challenge_id',v_challenge.challenge_id,'category',v_challenge.category,
    'emoji',v_challenge.emoji,'clues',v_clues,'image_url',v_challenge.image_url,
    'answer',CASE WHEN v_game.round_locked THEN v_challenge.answer ELSE NULL END,
    'pos',v_game.position-1,'queue_length',cardinality(v_game.challenge_queue),
    'revealed',v_game.revealed_clues,'special_card',v_game.special_card,
    'active_team',CASE WHEN cardinality(v_game.team_order)>0
      THEN v_game.team_order[v_game.active_team_index] ELSE NULL END,
    'timedMode',v_game.timed_mode_seconds,
    'deadline',CASE WHEN v_game.deadline_at IS NULL THEN 0 ELSE extract(epoch FROM v_game.deadline_at)*1000 END,
    'locked',v_game.round_locked,'revision',v_room.state_version
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_submit_room_answer(
  p_room_id uuid,p_token text,p_answer text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_now timestamptz;
  v_correct boolean;
  v_base integer;
  v_speed integer:=0;
  v_points integer:=0;
  v_score integer;
  v_prior_correct boolean;
  v_state jsonb;
  v_team_size integer;
  v_multiplier integer:=1;
  v_bonus integer:=0;
  v_penalty integer:=10;
BEGIN
  IF p_answer IS NULL OR char_length(btrim(p_answer))=0 OR char_length(p_answer)>300 THEN
    RAISE EXCEPTION 'Resposta vazia ou demasiado longa.';
  END IF;

  SELECT * INTO v_player FROM public.atina_v2_room_players
   WHERE room_id=p_room_id
     AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;

  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' THEN RAISE EXCEPTION 'A partida não tem uma ronda ativa.'; END IF;

  IF v_player.team_label IS NOT NULL THEN
    SELECT count(*) INTO v_team_size FROM public.atina_v2_room_players
     WHERE room_id=p_room_id AND team_label=v_player.team_label;
    IF v_team_size<>1 THEN
      RAISE EXCEPTION 'As equipas com vários membros têm de usar proposta e votação.';
    END IF;
    IF cardinality(v_game.team_order)=0
       OR v_player.team_label IS DISTINCT FROM v_game.team_order[v_game.active_team_index] THEN
      RAISE EXCEPTION 'Só a equipa que tem a vez pode responder.';
    END IF;
  END IF;

  v_now:=clock_timestamp();
  IF v_game.round_locked OR (v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now) THEN
    IF NOT v_game.round_locked THEN
      UPDATE private.atina_v2_room_game_state
         SET round_locked=true,team_turn_advanced=false,updated_at=v_now
       WHERE room_id=p_room_id;
      v_state:=private.atina_v2_room_public_state(p_room_id)
        || jsonb_build_object('feedback','Tempo esgotado.','locked',true);
      UPDATE public.atina_v2_rooms
         SET game_state=v_state,state_version=state_version+1,updated_at=v_now
       WHERE id=p_room_id;
    END IF;
    RETURN jsonb_build_object('status','locked','score',v_player.score,
      'state',coalesce(v_state,private.atina_v2_room_public_state(p_room_id)));
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.atina_v2_room_answers
     WHERE room_id=p_room_id AND player_id=v_player.id
       AND challenge_index=v_game.position-1 AND is_correct
  ) INTO v_prior_correct;
  IF v_prior_correct THEN
    RETURN jsonb_build_object('status','already_correct','correct',true,'score',v_player.score,'points',0);
  END IF;

  v_correct:=private.atina_v2_challenge_answer_matches(
    v_game.challenge_queue[v_game.position],btrim(p_answer)
  );
  v_multiplier:=coalesce((v_game.special_card->>'multiplier')::integer,1);
  v_bonus:=coalesce((v_game.special_card->>'bonus')::integer,0);
  v_penalty:=CASE v_game.special_card->>'id'
    WHEN 'shield' THEN 0 WHEN 'reduced_penalty' THEN 5 ELSE 10 END;

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
    v_points:=(v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END)*v_multiplier+v_bonus;
    UPDATE public.atina_v2_room_players
       SET score=score+v_points,last_seen_at=v_now
     WHERE id=v_player.id RETURNING score INTO v_score;
  ELSE
    UPDATE public.atina_v2_room_players
       SET score=greatest(0,score-v_penalty),last_seen_at=v_now
     WHERE id=v_player.id RETURNING score INTO v_score;
  END IF;

  INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
  VALUES(p_room_id,v_player.id,v_game.position-1,v_correct,v_points,v_now);

  IF v_correct AND v_player.team_label IS NOT NULL THEN
    UPDATE private.atina_v2_room_game_state
       SET round_locked=true,team_turn_advanced=true,updated_at=v_now
     WHERE room_id=p_room_id;
    v_state:=private.atina_v2_room_public_state(p_room_id);
    UPDATE public.atina_v2_rooms
       SET game_state=v_state,state_version=state_version+1,updated_at=v_now
     WHERE id=p_room_id;
  ELSE
    v_state:=private.atina_v2_room_public_state(p_room_id);
  END IF;

  RETURN jsonb_build_object(
    'status',CASE WHEN v_correct THEN 'correct' ELSE 'wrong' END,
    'correct',v_correct,'points',v_points,'score',v_score,
    'penalty',CASE WHEN v_correct THEN 0 ELSE v_penalty END,'state',v_state
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_submit_team_proposal(
  p_room_id uuid,p_token text,p_challenge integer,p_answer text,
  p_correct boolean DEFAULT NULL,p_points integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_room public.atina_v2_rooms%rowtype;
  v_player public.atina_v2_room_players%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_proposal public.atina_v2_room_team_proposals%rowtype;
  v_team_size integer;
  v_now timestamptz;
BEGIN
  IF p_answer IS NULL OR char_length(btrim(p_answer)) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Resposta vazia ou demasiado longa.';
  END IF;
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
  SELECT * INTO v_player FROM public.atina_v2_room_players
   WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
  IF v_player.team_label IS NULL THEN RAISE EXCEPTION 'O jogador não pertence a uma equipa.'; END IF;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' OR v_game.round_locked THEN
    RAISE EXCEPTION 'A ronda não está ativa.';
  END IF;
  IF p_challenge IS DISTINCT FROM v_game.position-1 THEN
    RAISE EXCEPTION 'O desafio indicado já não é o desafio atual.';
  END IF;
  IF cardinality(v_game.team_order)=0
     OR v_player.team_label IS DISTINCT FROM v_game.team_order[v_game.active_team_index] THEN
    RAISE EXCEPTION 'Só a equipa que tem a vez pode propor uma resposta.';
  END IF;
  v_now:=clock_timestamp();
  IF v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_v2_room_game_state
       SET round_locked=true,team_turn_advanced=false,updated_at=v_now
     WHERE room_id=p_room_id;
    UPDATE public.atina_v2_rooms
       SET game_state=private.atina_v2_room_public_state(p_room_id)||jsonb_build_object('feedback','Tempo esgotado.','locked',true),
           state_version=state_version+1,updated_at=v_now
     WHERE id=p_room_id;
    RETURN jsonb_build_object('status','locked','state',private.atina_v2_room_public_state(p_room_id));
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.atina_v2_room_answers a
    JOIN public.atina_v2_room_players p ON p.id=a.player_id
     WHERE a.room_id=p_room_id AND a.challenge_index=v_game.position-1
       AND a.is_correct AND p.team_label=v_player.team_label
  ) THEN RETURN jsonb_build_object('status','already_correct'); END IF;
  SELECT count(*) INTO v_team_size FROM public.atina_v2_room_players
   WHERE room_id=p_room_id AND team_label=v_player.team_label;
  IF v_team_size<2 THEN RAISE EXCEPTION 'A equipa precisa de pelo menos dois jogadores para votar.'; END IF;
  SELECT * INTO v_proposal FROM public.atina_v2_room_team_proposals
   WHERE room_id=p_room_id AND challenge_index=v_game.position-1
     AND team_label=v_player.team_label AND status='pending'
   ORDER BY created_at DESC LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'A equipa já tem uma proposta pendente.'; END IF;
  INSERT INTO public.atina_v2_room_team_proposals(
    room_id,challenge_index,team_label,proposer_id,answer_text,status
  ) VALUES(p_room_id,v_game.position-1,v_player.team_label,v_player.id,btrim(p_answer),'pending')
  RETURNING * INTO v_proposal;
  RETURN jsonb_build_object('status','pending','proposal_id',v_proposal.id,
    'message','Proposta registada; aguarda os votos dos restantes membros.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_vote_team_proposal(
  p_room_id uuid,p_token text,p_proposal_id uuid,p_agrees boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_room public.atina_v2_rooms%rowtype;
  v_player public.atina_v2_room_players%rowtype;
  v_proposal public.atina_v2_room_team_proposals%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
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
  v_multiplier integer:=1;
  v_bonus integer:=0;
  v_penalty integer:=10;
BEGIN
  IF p_agrees IS NULL THEN RAISE EXCEPTION 'Voto inválido.'; END IF;
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
  SELECT * INTO v_player FROM public.atina_v2_room_players
   WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
  SELECT * INTO v_proposal FROM public.atina_v2_room_team_proposals
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
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' OR v_game.round_locked
     OR v_game.position-1<>v_proposal.challenge_index THEN
    RAISE EXCEPTION 'A proposta já não pertence à ronda ativa.';
  END IF;
  IF cardinality(v_game.team_order)=0
     OR v_proposal.team_label IS DISTINCT FROM v_game.team_order[v_game.active_team_index] THEN
    RAISE EXCEPTION 'A proposta já não pertence à equipa ativa.';
  END IF;
  v_now:=clock_timestamp();
  IF v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_v2_room_game_state
       SET round_locked=true,team_turn_advanced=false,updated_at=v_now
     WHERE room_id=p_room_id;
    v_state:=private.atina_v2_room_public_state(p_room_id)||jsonb_build_object('feedback','Tempo esgotado.','locked',true);
    UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now
     WHERE id=p_room_id;
    UPDATE public.atina_v2_room_team_proposals
       SET status='rejected',resolution_reason='timeout',resolved_at=v_now
     WHERE id=v_proposal.id;
    RETURN jsonb_build_object('status','locked','reason','timeout','state',v_state);
  END IF;
  INSERT INTO public.atina_v2_room_team_votes(proposal_id,player_id,agrees)
  VALUES(v_proposal.id,v_player.id,p_agrees);
  SELECT count(*) INTO v_team_size FROM public.atina_v2_room_players
   WHERE room_id=p_room_id AND team_label=v_proposal.team_label;
  SELECT count(*),count(*) FILTER(WHERE NOT agrees)
    INTO v_votes,v_disagrees FROM public.atina_v2_room_team_votes WHERE proposal_id=v_proposal.id;
  IF v_disagrees>0 THEN
    UPDATE public.atina_v2_room_team_proposals
       SET status='rejected',resolution_reason='disagreement',resolved_at=v_now
     WHERE id=v_proposal.id;
    RETURN jsonb_build_object('status','rejected','reason','disagreement','votes',v_votes);
  END IF;
  IF v_votes<v_team_size-1 THEN
    RETURN jsonb_build_object('status','pending','votes',v_votes,'required',v_team_size-1);
  END IF;

  v_correct:=private.atina_v2_challenge_answer_matches(
    v_game.challenge_queue[v_game.position],v_proposal.answer_text
  );
  v_multiplier:=coalesce((v_game.special_card->>'multiplier')::integer,1);
  v_bonus:=coalesce((v_game.special_card->>'bonus')::integer,0);
  v_penalty:=CASE v_game.special_card->>'id'
    WHEN 'shield' THEN 0 WHEN 'reduced_penalty' THEN 5 ELSE 10 END;

  IF v_correct THEN
    SELECT CASE WHEN c.image_url IS NOT NULL
      THEN (ARRAY[20,16,12,8,6,5])[v_game.revealed_clues]
      ELSE (ARRAY[20,16,12,8,5])[v_game.revealed_clues] END
      INTO v_base FROM private.atina_challenges c
     WHERE c.challenge_id=v_game.challenge_queue[v_game.position] AND c.active;
    IF v_game.deadline_at IS NOT NULL THEN
      v_speed:=greatest(0,floor(ceil(extract(epoch FROM (v_game.deadline_at-v_now)))/10)::integer);
    END IF;
    v_points:=(v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END)*v_multiplier+v_bonus;
    UPDATE public.atina_v2_room_players SET score=score+v_points,last_seen_at=v_now
     WHERE room_id=p_room_id AND team_label=v_proposal.team_label;
    INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
    SELECT p_room_id,p.id,v_game.position-1,true,v_points,v_now
      FROM public.atina_v2_room_players p
     WHERE p.room_id=p_room_id AND p.team_label=v_proposal.team_label;
    UPDATE public.atina_v2_room_team_proposals
       SET status='accepted',resolution_reason='correct_answer',resolved_at=v_now
     WHERE id=v_proposal.id;
    UPDATE private.atina_v2_room_game_state
       SET round_locked=true,team_turn_advanced=true,updated_at=v_now
     WHERE room_id=p_room_id;
    v_state:=private.atina_v2_room_public_state(p_room_id);
    UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now
     WHERE id=p_room_id;
    SELECT coalesce(jsonb_agg(jsonb_build_object('player_id',p.id,'score',p.score) ORDER BY p.created_at,p.id),'[]'::jsonb)
      INTO v_scores FROM public.atina_v2_room_players p
     WHERE p.room_id=p_room_id AND p.team_label=v_proposal.team_label;
    RETURN jsonb_build_object('status','accepted','correct',true,'points_per_player',v_points,
      'scores',v_scores,'votes',v_votes,'state',v_state);
  END IF;

  UPDATE public.atina_v2_room_players
     SET score=greatest(0,score-v_penalty),last_seen_at=v_now
   WHERE room_id=p_room_id AND team_label=v_proposal.team_label;
  INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
  SELECT p_room_id,p.id,v_game.position-1,false,0,v_now
    FROM public.atina_v2_room_players p
   WHERE p.room_id=p_room_id AND p.team_label=v_proposal.team_label;
  UPDATE public.atina_v2_room_team_proposals
     SET status='rejected',resolution_reason='incorrect_answer',resolved_at=v_now
   WHERE id=v_proposal.id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('player_id',p.id,'score',p.score) ORDER BY p.created_at,p.id),'[]'::jsonb)
    INTO v_scores FROM public.atina_v2_room_players p
   WHERE p.room_id=p_room_id AND p.team_label=v_proposal.team_label;
  RETURN jsonb_build_object('status','rejected','reason','incorrect_answer','correct',false,
    'penalty_per_player',v_penalty,'scores',v_scores,'votes',v_votes);
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_pass_room_challenge(p_room_id uuid,p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_now timestamptz;
  v_state jsonb;
  v_status text;
  v_active_team text;
  v_expired boolean;
BEGIN
  SELECT * INTO v_player FROM public.atina_v2_room_players
   WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' OR v_game.round_locked THEN RAISE EXCEPTION 'A ronda não está ativa.'; END IF;
  v_now:=clock_timestamp();
  v_active_team:=CASE WHEN cardinality(v_game.team_order)>0
    THEN v_game.team_order[v_game.active_team_index] ELSE NULL END;
  v_expired:=v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now;
  IF v_active_team IS NOT NULL AND v_player.team_label IS DISTINCT FROM v_active_team
     AND NOT (v_player.is_host AND v_expired) THEN
    RAISE EXCEPTION 'Só a equipa ativa pode passar o desafio.';
  END IF;
  IF v_active_team IS NULL AND NOT v_player.is_host THEN
    RAISE EXCEPTION 'Só o anfitrião pode passar o desafio.';
  END IF;
  v_status:=CASE WHEN v_expired THEN 'timeout' ELSE 'passed' END;
  UPDATE private.atina_v2_room_game_state
     SET round_locked=true,team_turn_advanced=true,updated_at=v_now
   WHERE room_id=p_room_id;
  v_state:=private.atina_v2_room_public_state(p_room_id)||jsonb_build_object(
    'feedback',CASE WHEN v_status='timeout' THEN 'Tempo esgotado.' ELSE 'Desafio passado.' END,'locked',true);
  UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now
   WHERE id=p_room_id;
  RETURN jsonb_build_object('status',v_status,'state',v_state);
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_next_room_challenge(p_room_id uuid,p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_now timestamptz;
  v_state jsonb;
  v_results jsonb;
  v_card jsonb;
  v_active_team text;
  v_expired boolean;
  v_next_team integer;
BEGIN
  SELECT * INTO v_player FROM public.atina_v2_room_players
   WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' THEN RAISE EXCEPTION 'A ronda não está ativa.'; END IF;

  v_now:=clock_timestamp();
  v_active_team:=CASE WHEN cardinality(v_game.team_order)>0
    THEN v_game.team_order[v_game.active_team_index] ELSE NULL END;
  v_expired:=v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now;

  IF v_active_team IS NOT NULL AND v_player.team_label IS DISTINCT FROM v_active_team
     AND NOT (v_player.is_host AND v_expired) THEN
    RAISE EXCEPTION 'Só a equipa ativa pode avançar o desafio.';
  END IF;
  IF NOT v_game.round_locked AND NOT v_expired THEN
    RAISE EXCEPTION 'A ronda ainda não terminou.';
  END IF;
  IF NOT v_game.team_turn_advanced AND NOT v_expired THEN
    RAISE EXCEPTION 'O turno ainda não foi concluído.';
  END IF;
  IF v_expired AND NOT v_game.round_locked THEN
    UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=v_now
     WHERE room_id=p_room_id;
  END IF;

  IF v_game.position<cardinality(v_game.challenge_queue) THEN
    v_next_team:=v_game.active_team_index;
    IF cardinality(v_game.team_order)>1 THEN
      v_next_team:=mod(v_game.active_team_index,cardinality(v_game.team_order))+1;
    END IF;

    v_card:=NULL;
    -- Sorteio independente por desafio: 20% de probabilidade de aparecer uma carta.
    IF random()<0.20 AND cardinality(v_game.team_order)>1 THEN
      CASE floor(random()*9)::integer
        WHEN 0 THEN v_card:=jsonb_build_object('id','double_points','name','PONTOS A DOBRAR','icon','💎','description','Multiplica por 3 os pontos deste desafio se acertares.','multiplier',3,'bonus',0);
        WHEN 1 THEN v_card:=jsonb_build_object('id','speed_bonus','name','BÓNUS DE VELOCIDADE','icon','⚡','description','Recebes mais 25 pontos se acertares.','multiplier',1,'bonus',25);
        WHEN 2 THEN v_card:=jsonb_build_object('id','correct_prize','name','PRÉMIO DE ACERTO','icon','🏆','description','Recebes 40 pontos extra se acertares.','multiplier',1,'bonus',40);
        WHEN 3 THEN v_card:=jsonb_build_object('id','shield','name','ESCUDO','icon','🛡️','description','Anula a penalização se errares.');
        WHEN 4 THEN v_card:=jsonb_build_object('id','reduced_penalty','name','PENALIZAÇÃO REDUZIDA','icon','➖','description','A penalização por erro passa de 10 para 5 pontos.');
        WHEN 5 THEN v_card:=jsonb_build_object('id','bonus_clue','name','PISTA BÓNUS','icon','💡','description','Recebes imediatamente mais uma pista.');
        WHEN 6 THEN v_card:=jsonb_build_object('id','extra_time','name','TEMPO EXTRA','icon','⏱️','description','Recebes mais 30 segundos neste desafio.');
        WHEN 7 THEN v_card:=jsonb_build_object('id','pass_team','name','PASSAR A EQUIPA','icon','⏭️','description','A equipa que recebe esta carta perde a vez; o desafio é saltado.');
        ELSE v_card:=jsonb_build_object('id','steal_turn','name','ROUBAR A VEZ','icon','🔄','description','A equipa seguinte assume imediatamente este desafio.');
      END CASE;
    END IF;
    IF v_card->>'id'='steal_turn' THEN
      v_next_team:=mod(v_next_team,cardinality(v_game.team_order))+1;
    END IF;

    UPDATE private.atina_v2_room_game_state
       SET position=position+1,
           active_team_index=v_next_team,
           team_turn_advanced=coalesce(v_card->>'id'='pass_team',false),
           revealed_clues=CASE WHEN v_card->>'id'='bonus_clue' THEN 2 ELSE 1 END,
           round_locked=coalesce(v_card->>'id'='pass_team',false),
           special_card=v_card,
           deadline_at=CASE WHEN timed_mode_seconds=0 OR v_card->>'id'='pass_team' THEN NULL
             ELSE v_now+make_interval(secs=>timed_mode_seconds+
               CASE WHEN v_card->>'id'='extra_time' THEN 30 ELSE 0 END) END,
           updated_at=v_now
     WHERE room_id=p_room_id;

    PERFORM private.atina_record_room_challenge_exposure(
      p_room_id,v_game.challenge_queue[v_game.position+1]
    );
    v_state:=private.atina_v2_room_public_state(p_room_id);
    IF v_card->>'id'='pass_team' THEN
      v_state:=v_state||jsonb_build_object(
        'feedback','A carta PASSAR A EQUIPA saltou este desafio.','locked',true
      );
    END IF;
    UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now
     WHERE id=p_room_id;
    RETURN jsonb_build_object('status','next','state',v_state);
  END IF;

  UPDATE private.atina_v2_room_game_state
     SET status='completed',round_locked=true,team_turn_advanced=true,updated_at=v_now
   WHERE room_id=p_room_id;
  INSERT INTO public.atina_v2_room_results(room_id,player_id,nickname,team_label,score,completed_at)
  SELECT p.room_id,p.id,p.nickname,p.team_label,p.score,v_now
    FROM public.atina_v2_room_players p WHERE p.room_id=p_room_id
  ON CONFLICT(room_id,player_id) DO UPDATE
    SET nickname=excluded.nickname,team_label=excluded.team_label,
        score=excluded.score,completed_at=excluded.completed_at;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'player_id',r.player_id,'nickname',r.nickname,'team',r.team_label,'score',r.score
  ) ORDER BY r.score DESC,r.nickname),'[]'::jsonb)
    INTO v_results FROM public.atina_v2_room_results r WHERE r.room_id=p_room_id;
  UPDATE public.atina_v2_rooms
     SET status='completed',
         game_state=jsonb_build_object('mode','completed','protocol_version',1,
           'pos',cardinality(v_game.challenge_queue),'queue_length',cardinality(v_game.challenge_queue),
           'locked',true,'revision',state_version+1),
         state_version=state_version+1,updated_at=v_now
   WHERE id=p_room_id;
  RETURN jsonb_build_object('status','completed','results',v_results);
END;
$function$;

-- A equipa ativa, incluindo uma sessão automatizada, pode revelar as suas pistas.
CREATE OR REPLACE FUNCTION public.atina_v2_reveal_room_clue(p_room_id uuid,p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_total integer;
  v_now timestamptz;
  v_state jsonb;
  v_active_team text;
BEGIN
  SELECT * INTO v_player FROM public.atina_v2_room_players
   WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' OR v_game.round_locked THEN
    RAISE EXCEPTION 'A ronda não está ativa.';
  END IF;
  v_active_team:=CASE WHEN cardinality(v_game.team_order)>0
    THEN v_game.team_order[v_game.active_team_index] ELSE NULL END;
  IF v_active_team IS NOT NULL THEN
    IF v_player.team_label IS DISTINCT FROM v_active_team THEN
      RAISE EXCEPTION 'Só a equipa que tem a vez pode revelar pistas.';
    END IF;
  ELSIF NOT v_player.is_host THEN
    RAISE EXCEPTION 'Só o anfitrião pode revelar pistas.';
  END IF;
  v_now:=clock_timestamp();
  IF v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_v2_room_game_state
       SET round_locked=true,team_turn_advanced=false,updated_at=v_now
     WHERE room_id=p_room_id;
    v_state:=private.atina_v2_room_public_state(p_room_id)
      ||jsonb_build_object('feedback','Tempo esgotado.','locked',true);
    UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now
     WHERE id=p_room_id;
    RETURN jsonb_build_object('status','timeout','state',v_state);
  END IF;
  SELECT jsonb_array_length(clues) INTO v_total
    FROM private.atina_challenges
   WHERE challenge_id=v_game.challenge_queue[v_game.position] AND active;
  IF v_game.revealed_clues>=v_total THEN
    RETURN jsonb_build_object('status','unchanged','state',private.atina_v2_room_public_state(p_room_id));
  END IF;
  UPDATE private.atina_v2_room_game_state
     SET revealed_clues=revealed_clues+1,updated_at=v_now
   WHERE room_id=p_room_id;
  v_state:=private.atina_v2_room_public_state(p_room_id);
  UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now
   WHERE id=p_room_id;
  RETURN jsonb_build_object('status','revealed','state',v_state);
END;
$function$;

-- A sessão da equipa ativa usa o mesmo motor de resposta e pode concluir o seu turno.
CREATE OR REPLACE FUNCTION public.atina_v2_bot_tick(p_room_id uuid,p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_human public.atina_v2_room_players%rowtype;
  v_match private.atina_v2_bot_matches%rowtype;
  v_bot_player public.atina_v2_room_players%rowtype;
  v_bot private.atina_v2_bot_profiles%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_challenge private.atina_challenges%rowtype;
  v_result jsonb;
  v_wait integer;
  v_target_clues integer;
  v_answer text;
  v_now timestamptz:=clock_timestamp();
BEGIN
  SELECT * INTO v_human FROM public.atina_v2_room_players
   WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256');
  IF NOT FOUND OR v_human.is_bot THEN RAISE EXCEPTION 'Sessão de jogador inválida.'; END IF;
  SELECT * INTO v_match FROM private.atina_v2_bot_matches WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','no_bot'); END IF;
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id;
  IF NOT FOUND OR v_room.status<>'playing' THEN RETURN jsonb_build_object('status','waiting'); END IF;
  SELECT * INTO v_bot FROM private.atina_v2_bot_profiles WHERE id=v_match.bot_profile_id;
  SELECT * INTO v_bot_player FROM public.atina_v2_room_players WHERE id=v_match.bot_player_id;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id;
  IF NOT FOUND OR v_game.status<>'active' THEN RETURN jsonb_build_object('status','waiting'); END IF;
  IF cardinality(v_game.team_order)=0
     OR v_bot_player.team_label IS DISTINCT FROM v_game.team_order[v_game.active_team_index] THEN
    RETURN jsonb_build_object('status','human_turn');
  END IF;
  v_wait:=v_bot.response_min_seconds+
    floor(random()*(v_bot.response_max_seconds-v_bot.response_min_seconds+1))::integer;

  IF v_game.round_locked THEN
    IF v_match.next_action_at IS NULL THEN
      UPDATE private.atina_v2_bot_matches
         SET next_action_at=v_now+make_interval(secs=>least(v_wait,4))
       WHERE room_id=p_room_id;
      RETURN jsonb_build_object('status','bot_thinking');
    END IF;
    IF v_match.next_action_at>v_now THEN RETURN jsonb_build_object('status','bot_thinking'); END IF;
    v_result:=public.atina_v2_next_room_challenge(p_room_id,v_match.bot_token);
    UPDATE private.atina_v2_bot_matches
       SET next_action_at=NULL,attempts=0,bot_turn_completed=false,current_challenge_id=NULL
     WHERE room_id=p_room_id;
    RETURN jsonb_build_object('status','advanced','result',v_result);
  END IF;

  SELECT * INTO v_challenge FROM private.atina_challenges
   WHERE challenge_id=v_game.challenge_queue[v_game.position] AND active;
  IF NOT FOUND THEN RETURN jsonb_build_object('status','waiting'); END IF;
  IF v_match.current_challenge_id IS DISTINCT FROM v_challenge.challenge_id THEN
    UPDATE private.atina_v2_bot_matches
       SET current_challenge_id=v_challenge.challenge_id,attempts=0,
           next_action_at=v_now+make_interval(secs=>v_wait),bot_turn_completed=false
     WHERE room_id=p_room_id;
    RETURN jsonb_build_object('status','bot_thinking');
  END IF;
  IF v_match.next_action_at IS NULL THEN
    UPDATE private.atina_v2_bot_matches
       SET next_action_at=v_now+make_interval(secs=>v_wait)
     WHERE room_id=p_room_id;
    RETURN jsonb_build_object('status','bot_thinking');
  END IF;
  IF v_match.next_action_at>v_now THEN RETURN jsonb_build_object('status','bot_thinking'); END IF;

  v_target_clues:=CASE WHEN v_bot.knowledge_level>=0.78 THEN 1
    WHEN v_bot.knowledge_level>=0.55 THEN 2 ELSE 3 END;
  IF v_game.revealed_clues<least(v_target_clues,jsonb_array_length(v_challenge.clues)) THEN
    v_result:=public.atina_v2_reveal_room_clue(p_room_id,v_match.bot_token);
    UPDATE private.atina_v2_bot_matches SET next_action_at=v_now+make_interval(secs=>v_wait)
     WHERE room_id=p_room_id;
    RETURN jsonb_build_object('status','clue_revealed','result',v_result);
  END IF;
  IF random()<greatest(0.01,v_bot.mistake_rate-(v_bot.knowledge_level*0.04)) THEN
    v_answer:=(ARRAY['Talvez seja uma montanha','Não tenho a certeza','Penso que é uma cidade','A minha primeira hipótese','Pode ser um animal'])[1+floor(random()*5)::integer];
  ELSE
    v_answer:=v_challenge.answer;
  END IF;
  v_result:=public.atina_v2_submit_room_answer(p_room_id,v_match.bot_token,v_answer);
  IF v_result->>'status' IN ('correct','already_correct') THEN
    UPDATE private.atina_v2_bot_matches
       SET bot_turn_completed=true,next_action_at=v_now+make_interval(secs=>least(v_wait,4))
     WHERE room_id=p_room_id;
    RETURN jsonb_build_object('status','answered','result',v_result);
  END IF;
  UPDATE private.atina_v2_bot_matches
     SET attempts=attempts+1,next_action_at=v_now+make_interval(secs=>v_wait)
   WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','thinking','result',v_result);
END;
$function$;

-- Every completed room challenge awards the same base 10 XP to a registered
-- human account, regardless of correctness. Correct answers award points once.
create or replace function private.atina_v2_award_room_player_progress()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player_id uuid;
  v_player private.atina_players%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_challenge private.atina_challenges%rowtype;
  v_xp_event bigint;
  v_points_event bigint;
  v_today date := current_date;
  v_daily_count integer;
  v_streak integer;
  v_daily_bonus integer := 0;
  v_mission_bonus integer := 0;
  v_streak_bonus integer := 0;
  v_category_bonus integer := 0;
  v_hard_bonus integer := 0;
  v_milestone_bonus integer := 0;
  v_bonus_event bigint;
  v_points integer := greatest(coalesce(new.points,0),0);
begin
  select rp.account_player_id into v_player_id
    from public.atina_v2_room_players rp
   where rp.id=new.player_id and rp.room_id=new.room_id;

  if v_player_id is null then
    return new;
  end if;

  select * into v_player
    from private.atina_players
   where id=v_player_id
   for update;
  if not found then
    return new;
  end if;

  select * into v_game
    from private.atina_v2_room_game_state
   where room_id=new.room_id;
  if not found or new.challenge_index < 0
     or new.challenge_index+1 > cardinality(v_game.challenge_queue) then
    raise exception 'Não foi possível confirmar o desafio da progressão da sala.';
  end if;

  select * into v_challenge
    from private.atina_challenges
   where challenge_id=v_game.challenge_queue[new.challenge_index+1];
  if not found then
    raise exception 'O desafio da progressão da sala já não existe.';
  end if;

  insert into private.atina_room_progress_events(player_id,room_id,challenge_position,xp)
  values(v_player_id,new.room_id,new.challenge_index+1,10)
  on conflict(player_id,room_id,challenge_position) do nothing
  returning id into v_xp_event;

  if new.is_correct and v_points>0 then
    insert into private.atina_points_events(player_id,source,source_id,challenge_position,points)
    values(v_player_id,'room',new.room_id,new.challenge_index+1,v_points)
    on conflict(player_id,source,source_id,challenge_position) do nothing
    returning id into v_points_event;
  end if;

  if v_xp_event is not null then
    v_daily_count:=case when v_player.daily_date=v_today then v_player.daily_count+1 else 1 end;

    if v_daily_count>=3 and v_player.daily_mission_reward_date is distinct from v_today then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'daily_mission',v_today::text,25)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_mission_bonus:=25; end if;
    end if;

    if v_daily_count>=5 and v_player.daily_reward_date is distinct from v_today then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'daily_five',v_today::text,20)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_daily_bonus:=20; end if;
    end if;

    v_streak:=case
      when v_player.last_active_date=v_today then greatest(v_player.active_streak,1)
      when v_player.last_active_date=v_today-1 then greatest(v_player.active_streak,0)+1
      else 1
    end;
    if v_streak>=7 and v_streak%7=0 and v_player.last_active_date is distinct from v_today then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'streak_seven',v_today::text,50)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_streak_bonus:=50; end if;
    end if;

    if nullif(btrim(v_challenge.category),'') is not null then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'new_category',v_challenge.category,15)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_category_bonus:=15; end if;
    end if;

    if lower(coalesce(v_challenge.difficulty,''))='hard' then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'hard_challenge',v_game.challenge_queue[new.challenge_index+1]::text,20)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_hard_bonus:=20; end if;
    end if;

    if v_player.total_challenges+1>=100 then
      insert into private.atina_xp_bonus_events(player_id,event_type,event_key,xp)
      values(v_player_id,'challenge_milestone','100',100)
      on conflict(player_id,event_type,event_key) do nothing
      returning id into v_bonus_event;
      if v_bonus_event is not null then v_milestone_bonus:=100; end if;
    end if;
  end if;

  update private.atina_players
     set total_xp=total_xp+case when v_xp_event is null then 0 else
           10+v_daily_bonus+v_mission_bonus+v_streak_bonus+v_category_bonus+v_hard_bonus+v_milestone_bonus end,
         total_points=total_points+case when v_points_event is null then 0 else v_points end,
         total_challenges=total_challenges+case when v_xp_event is null then 0 else 1 end,
         daily_date=case when v_xp_event is null then daily_date else v_today end,
         daily_count=case when v_xp_event is null then daily_count else least(v_daily_count,5) end,
         daily_reward_date=case when v_daily_bonus>0 then v_today else daily_reward_date end,
         daily_mission_reward_date=case when v_mission_bonus>0 then v_today else daily_mission_reward_date end,
         last_active_date=case when v_xp_event is null then last_active_date else v_today end,
         active_streak=case when v_xp_event is null then active_streak else v_streak end,
         updated_at=clock_timestamp()
   where id=v_player_id;

  return new;
end;
$function$;

revoke all on function private.atina_v2_award_room_player_progress() from public, anon, authenticated;

drop trigger if exists atina_v2_award_room_player_progress_after_answer
  on public.atina_v2_room_answers;
create trigger atina_v2_award_room_player_progress_after_answer
after insert on public.atina_v2_room_answers
for each row execute function private.atina_v2_award_room_player_progress();

-- Synthetic competition progress follows the same base challenge XP rule:
-- 10 XP once per challenge, including an incorrect answer; points only on success.
create or replace function private.atina_v2_award_bot_competition_progress()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile_id integer;
  v_inserted integer;
  v_added_points integer := greatest(coalesce(new.points,0),0);
begin
  select m.bot_profile_id into v_profile_id
    from private.atina_v2_bot_matches m
   where m.room_id=new.room_id and m.bot_player_id=new.player_id;

  if v_profile_id is null then
    return new;
  end if;

  insert into private.atina_v2_bot_competition_events
    (bot_profile_id,source,source_id,challenge_position,points,xp,is_correct)
  values
    (v_profile_id,'room',new.room_id,new.challenge_index+1,
     case when new.is_correct then v_added_points else 0 end,10,new.is_correct)
  on conflict (bot_profile_id,source,source_id,challenge_position) do nothing;

  get diagnostics v_inserted = row_count;

  if v_inserted=1 then
    update private.atina_v2_bot_competition_stats
       set points=points+case when new.is_correct then v_added_points else 0 end,
           xp=xp+10,
           total_challenges=total_challenges+1,
           updated_at=clock_timestamp()
     where bot_profile_id=v_profile_id;
  elsif new.is_correct then
    update private.atina_v2_bot_competition_events
       set points=v_added_points,is_correct=true
     where bot_profile_id=v_profile_id and source='room'
       and source_id=new.room_id and challenge_position=new.challenge_index+1
       and is_correct=false;
    if found then
      update private.atina_v2_bot_competition_stats
         set points=points+v_added_points,updated_at=clock_timestamp()
       where bot_profile_id=v_profile_id;
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function private.atina_v2_award_bot_competition_progress() from public, anon, authenticated;

drop trigger if exists atina_v2_award_bot_competition_progress_after_answer
  on public.atina_v2_room_answers;
create trigger atina_v2_award_bot_competition_progress_after_answer
after insert on public.atina_v2_room_answers
for each row execute function private.atina_v2_award_bot_competition_progress();
