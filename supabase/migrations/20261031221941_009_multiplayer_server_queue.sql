-- Server-authoritative multiplayer challenge queue and sanitized public state.
CREATE TABLE IF NOT EXISTS private.atina_room_game_state (
  room_id uuid PRIMARY KEY REFERENCES public.atina_rooms(id) ON DELETE CASCADE,
  challenge_queue integer[] NOT NULL CHECK (cardinality(challenge_queue) > 0),
  position integer NOT NULL DEFAULT 1 CHECK (position >= 1),
  difficulty text NOT NULL CHECK (difficulty IN ('easy','medium','hard')),
  category text,
  timed_mode_seconds integer NOT NULL CHECK (timed_mode_seconds BETWEEN 0 AND 3600),
  revealed_clues integer NOT NULL DEFAULT 1 CHECK (revealed_clues BETWEEN 1 AND 6),
  deadline_at timestamptz,
  round_locked boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','abandoned')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.atina_room_game_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.atina_room_game_state FROM public, anon, authenticated;
COMMENT ON TABLE private.atina_room_game_state IS 'Authoritative private multiplayer queue and round clock; never exposed through the Data API.';

CREATE OR REPLACE FUNCTION public.atina_start_room_challenges(
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
  v_host public.atina_room_players%rowtype;
  v_room public.atina_rooms%rowtype;
  v_queue integer[];
  v_now timestamptz;
  v_deadline timestamptz;
  v_challenge private.atina_challenges%rowtype;
  v_state jsonb;
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
  FROM public.atina_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND OR NOT v_host.is_host THEN
    RAISE EXCEPTION 'Só o anfitrião pode iniciar os desafios.';
  END IF;

  SELECT * INTO v_room FROM public.atina_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status <> 'playing' OR v_room.game_state->>'mode' <> 'pending' THEN
    RAISE EXCEPTION 'A sala não está preparada para iniciar os desafios.';
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

  v_now := clock_timestamp();
  v_deadline := CASE WHEN p_duration_seconds=0 THEN NULL
                     ELSE v_now + make_interval(secs => p_duration_seconds) END;

  INSERT INTO private.atina_room_game_state(
    room_id,challenge_queue,position,difficulty,category,timed_mode_seconds,
    revealed_clues,deadline_at,round_locked,status,created_at,updated_at
  ) VALUES (
    p_room_id,v_queue,1,p_difficulty,p_category,p_duration_seconds,
    1,v_deadline,false,'active',v_now,v_now
  );

  SELECT * INTO v_challenge
  FROM private.atina_challenges
  WHERE challenge_id=v_queue[1] AND active;

  v_state := jsonb_build_object(
    'mode','challenges',
    'protocol_version',1,
    'challenge_id',v_challenge.challenge_id,
    'category',v_challenge.category,
    'emoji',v_challenge.emoji,
    'clues',jsonb_build_array(v_challenge.clues->0),
    'image_url',v_challenge.image_url,
    'pos',0,
    'queue_length',cardinality(v_queue),
    'revealed',1,
    'timedMode',p_duration_seconds,
    'deadline',CASE WHEN v_deadline IS NULL THEN 0 ELSE extract(epoch FROM v_deadline)*1000 END,
    'locked',false,
    'revision',v_room.state_version+1
  );

  UPDATE public.atina_rooms
  SET game_state=v_state,state_version=state_version+1,updated_at=v_now
  WHERE id=p_room_id;

  RETURN jsonb_build_object(
    'status','started',
    'queue_length',cardinality(v_queue),
    'state',v_state
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_start_room_challenges(uuid,text,text,integer,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_start_room_challenges(uuid,text,text,integer,text) TO anon,authenticated;
