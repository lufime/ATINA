-- ATINA: 100 scheduled, server-controlled opponents
ALTER TABLE public.atina_v2_room_players
  ADD COLUMN IF NOT EXISTS is_bot boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS private.atina_v2_bot_profiles (
  id integer PRIMARY KEY,
  nickname text NOT NULL UNIQUE,
  age integer NOT NULL CHECK (age BETWEEN 18 AND 75),
  profession text NOT NULL,
  personality text NOT NULL,
  knowledge_level numeric(4,3) NOT NULL CHECK (knowledge_level BETWEEN 0 AND 1),
  mistake_rate numeric(4,3) NOT NULL CHECK (mistake_rate BETWEEN 0 AND 1),
  response_min_seconds integer NOT NULL,
  response_max_seconds integer NOT NULL,
  online_probability numeric(4,3) NOT NULL,
  timezone_name text NOT NULL DEFAULT 'Europe/Lisbon',
  sleep_start time NOT NULL,
  sleep_end time NOT NULL,
  work_start time NOT NULL,
  work_end time NOT NULL,
  breakfast_at time NOT NULL,
  lunch_at time NOT NULL,
  dinner_at time NOT NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS private.atina_v2_bot_matches (
  room_id uuid PRIMARY KEY REFERENCES public.atina_v2_rooms(id) ON DELETE CASCADE,
  bot_profile_id integer NOT NULL REFERENCES private.atina_v2_bot_profiles(id),
  bot_player_id uuid NOT NULL UNIQUE REFERENCES public.atina_v2_room_players(id) ON DELETE CASCADE,
  bot_token text NOT NULL,
  next_action_at timestamptz,
  current_challenge_id integer,
  attempts integer NOT NULL DEFAULT 0,
  bot_turn_completed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON private.atina_v2_bot_profiles FROM PUBLIC, anon, authenticated;
REVOKE ALL ON private.atina_v2_bot_matches FROM PUBLIC, anon, authenticated;
ALTER TABLE private.atina_v2_bot_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.atina_v2_bot_matches ENABLE ROW LEVEL SECURITY;

WITH names AS (
 SELECT ARRAY['Luna','Rui','Marta','Tiago','Inês','Diogo','Leonor','Miguel','Beatriz','Tomás','Carolina','Afonso','Matilde','Gonçalo','Sofia','André','Mariana','Pedro','Joana','Duarte','Clara','Francisco','Eva','Gabriel','Alice','Rodrigo','Laura','Daniel','Íris','Nuno','Catarina','Vasco','Ana','Bruno','Rita','David','Sara','Hugo','Filipa','Guilherme','Madalena','Fábio','Teresa','Samuel','Bárbara','Luís','Diana','Martim','Helena','Rafael'] a
), professions AS (
 SELECT ARRAY['professor/a','enfermeiro/a','cozinheiro/a','mecânico/a','estudante','programador/a','comerciante','designer','motorista','bibliotecário/a','técnico/a de saúde','jornalista','agricultor/a','contabilista','arquiteto/a','eletricista','veterinário/a','assistente social','gestor/a','reformado/a'] a
), personalities AS (
 SELECT ARRAY['curioso','calmo','competitivo','bem-disposto','analítico','descontraído','persistente','prudente','rápido','observador'] a
), zones AS (
 SELECT ARRAY['Europe/Lisbon','Europe/London','Atlantic/Azores','America/Sao_Paulo','Europe/Madrid'] a
)
INSERT INTO private.atina_v2_bot_profiles
(id,nickname,age,profession,personality,knowledge_level,mistake_rate,response_min_seconds,response_max_seconds,online_probability,timezone_name,sleep_start,sleep_end,work_start,work_end,breakfast_at,lunch_at,dinner_at)
SELECT g,
 (names.a[((g-1)%50)+1] || '_' || lpad(g::text,3,'0')),
 18+((g*7)%53),
 professions.a[((g-1)%20)+1],
 personalities.a[((g-1)%10)+1],
 (0.35+((g*13)%60)::numeric/100),
 (0.04+((g*11)%18)::numeric/100),
 4+((g*3)%9),12+((g*5)%15),
 (0.25+((g*17)%60)::numeric/100),
 zones.a[((g-1)%5)+1],
 (time '21:30'+(((g*19)%180)::text||' minutes')::interval)::time,
 (time '06:00'+(((g*23)%150)::text||' minutes')::interval)::time,
 (time '07:30'+(((g*7)%150)::text||' minutes')::interval)::time,
 (time '16:00'+(((g*11)%180)::text||' minutes')::interval)::time,
 (time '06:30'+(((g*5)%90)::text||' minutes')::interval)::time,
 (time '12:00'+(((g*7)%90)::text||' minutes')::interval)::time,
 (time '18:30'+(((g*9)%120)::text||' minutes')::interval)::time
FROM generate_series(1,100) g CROSS JOIN names CROSS JOIN professions CROSS JOIN personalities CROSS JOIN zones
ON CONFLICT (id) DO UPDATE SET nickname=excluded.nickname,age=excluded.age,
 profession=excluded.profession,personality=excluded.personality,
 knowledge_level=excluded.knowledge_level,mistake_rate=excluded.mistake_rate,
 response_min_seconds=excluded.response_min_seconds,response_max_seconds=excluded.response_max_seconds,
 online_probability=excluded.online_probability,timezone_name=excluded.timezone_name,
 sleep_start=excluded.sleep_start,sleep_end=excluded.sleep_end,work_start=excluded.work_start,
 work_end=excluded.work_end,breakfast_at=excluded.breakfast_at,lunch_at=excluded.lunch_at,dinner_at=excluded.dinner_at;

CREATE OR REPLACE FUNCTION private.atina_v2_bot_is_available(p_bot private.atina_v2_bot_profiles)
RETURNS boolean LANGUAGE plpgsql
SET search_path=''
AS $$
DECLARE v_local time; v_day integer; v_sleeping boolean; v_working boolean;
BEGIN
 v_local := (clock_timestamp() AT TIME ZONE p_bot.timezone_name)::time;
 v_day := extract(isodow FROM clock_timestamp() AT TIME ZONE p_bot.timezone_name)::integer;
 v_sleeping := CASE WHEN p_bot.sleep_start < p_bot.sleep_end
   THEN v_local >= p_bot.sleep_start AND v_local < p_bot.sleep_end
   ELSE v_local >= p_bot.sleep_start OR v_local < p_bot.sleep_end END;
 v_working := v_day <= 5 AND CASE WHEN p_bot.work_start < p_bot.work_end
   THEN v_local >= p_bot.work_start AND v_local < p_bot.work_end
   ELSE v_local >= p_bot.work_start OR v_local < p_bot.work_end END;
 RETURN p_bot.active AND NOT v_sleeping AND NOT v_working
   AND abs(extract(epoch FROM (v_local-p_bot.breakfast_at))) > 1200
   AND abs(extract(epoch FROM (v_local-p_bot.lunch_at))) > 1200
   AND abs(extract(epoch FROM (v_local-p_bot.dinner_at))) > 1200;
END;
$$;

CREATE OR REPLACE FUNCTION public.atina_v2_create_bot_match(p_session_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
 v_account private.atina_player_accounts%rowtype; v_bot private.atina_v2_bot_profiles%rowtype;
 v_room_result jsonb; v_room_id uuid; v_human_id uuid; v_bot_id uuid; v_bot_token text;
BEGIN
 IF p_session_token IS NULL OR p_session_token !~ '^[0-9a-f]{64}$' THEN
  RAISE EXCEPTION 'Inicia sessão na tua conta ATINA para jogar contra um bot.' USING errcode='28000';
 END IF;
 SELECT * INTO v_account FROM private.atina_player_accounts
 WHERE session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
 AND session_expires_at>clock_timestamp() FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão expirada. Inicia sessão novamente.' USING errcode='28000'; END IF;

 SELECT b.* INTO v_bot FROM private.atina_v2_bot_profiles b
 WHERE private.atina_v2_bot_is_available(b) AND random()<b.online_probability
 AND NOT EXISTS (SELECT 1 FROM private.atina_v2_bot_matches m
  JOIN public.atina_v2_rooms r ON r.id=m.room_id
  WHERE m.bot_profile_id=b.id AND r.status IN ('waiting','playing'))
 ORDER BY random() LIMIT 1;
 IF NOT FOUND THEN
  SELECT b.* INTO v_bot FROM private.atina_v2_bot_profiles b
  WHERE private.atina_v2_bot_is_available(b)
  AND NOT EXISTS (SELECT 1 FROM private.atina_v2_bot_matches m
   JOIN public.atina_v2_rooms r ON r.id=m.room_id
   WHERE m.bot_profile_id=b.id AND r.status IN ('waiting','playing'))
  ORDER BY random() LIMIT 1;
 END IF;
 IF NOT FOUND THEN RAISE EXCEPTION 'Neste momento todos os adversários estão a dormir, a trabalhar ou ocupados. Tenta novamente daqui a pouco.'; END IF;

 v_room_result:=public.atina_v2_create_room(v_account.nickname,2);
 v_room_id:=(v_room_result->>'room_id')::uuid;
 v_human_id:=(v_room_result->>'player_id')::uuid;
 v_bot_id:=extensions.gen_random_uuid();
 v_bot_token:=encode(extensions.gen_random_bytes(32),'hex');
 UPDATE public.atina_v2_room_players SET account_player_id=v_account.player_id,
  team_label='Equipa A',ready=true WHERE id=v_human_id AND room_id=v_room_id;
 INSERT INTO public.atina_v2_room_players
  (id,room_id,token_hash,nickname,is_host,ready,team_label,score,is_bot)
 VALUES(v_bot_id,v_room_id,extensions.digest(v_bot_token,'sha256'),
  v_bot.nickname,false,true,'Equipa B',0,true);
 INSERT INTO private.atina_v2_bot_matches(room_id,bot_profile_id,bot_player_id,bot_token)
 VALUES(v_room_id,v_bot.id,v_bot_id,v_bot_token);
 RETURN jsonb_build_object('room_id',v_room_id,'token',v_room_result->>'token',
  'code',v_room_result->>'code','player_id',v_human_id,
  'bot',jsonb_build_object('nickname',v_bot.nickname,'age',v_bot.age,
  'profession',v_bot.profession,'personality',v_bot.personality,
  'knowledge_level',v_bot.knowledge_level));
END;
$$;

CREATE OR REPLACE FUNCTION public.atina_v2_bot_tick(p_room_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
 v_human public.atina_v2_room_players%rowtype;
 v_match private.atina_v2_bot_matches%rowtype;
 v_bot_player public.atina_v2_room_players%rowtype;
 v_bot private.atina_v2_bot_profiles%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_game private.atina_v2_room_game_state%rowtype;
 v_challenge private.atina_challenges%rowtype;
 v_result jsonb; v_wait integer; v_target_clues integer; v_answer text;
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
 IF cardinality(v_game.team_order)=0 OR v_bot_player.team_label IS DISTINCT FROM v_game.team_order[v_game.active_team_index] THEN
  RETURN jsonb_build_object('status','human_turn');
 END IF;
 v_wait:=v_bot.response_min_seconds+
  floor(random()*(v_bot.response_max_seconds-v_bot.response_min_seconds+1))::integer;

 IF v_game.round_locked THEN
  IF v_match.next_action_at IS NULL THEN
   UPDATE private.atina_v2_bot_matches SET next_action_at=v_now+make_interval(secs=>least(v_wait,4)) WHERE room_id=p_room_id;
   RETURN jsonb_build_object('status','bot_thinking');
  END IF;
  IF v_match.next_action_at>v_now THEN RETURN jsonb_build_object('status','bot_thinking'); END IF;
  v_result:=public.atina_v2_next_room_challenge(p_room_id,v_match.bot_token);
  UPDATE private.atina_v2_bot_matches SET next_action_at=NULL,attempts=0,
   bot_turn_completed=false,current_challenge_id=NULL WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','advanced','result',v_result);
 END IF;

 SELECT * INTO v_challenge FROM private.atina_challenges
 WHERE challenge_id=v_game.challenge_queue[v_game.position] AND active;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','waiting'); END IF;
 IF v_match.current_challenge_id IS DISTINCT FROM v_challenge.challenge_id THEN
  UPDATE private.atina_v2_bot_matches SET current_challenge_id=v_challenge.challenge_id,
   attempts=0,next_action_at=v_now+make_interval(secs=>v_wait),bot_turn_completed=false
  WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','bot_thinking');
 END IF;
 IF v_match.next_action_at IS NULL THEN
  UPDATE private.atina_v2_bot_matches SET next_action_at=v_now+make_interval(secs=>v_wait) WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','bot_thinking');
 END IF;
 IF v_match.next_action_at>v_now THEN RETURN jsonb_build_object('status','bot_thinking'); END IF;

 v_target_clues:=CASE WHEN v_bot.knowledge_level>=0.78 THEN 1
  WHEN v_bot.knowledge_level>=0.55 THEN 2 ELSE 3 END;
 IF v_game.revealed_clues<least(v_target_clues,jsonb_array_length(v_challenge.clues)) THEN
  v_result:=public.atina_v2_reveal_room_clue(p_room_id,v_match.bot_token);
  UPDATE private.atina_v2_bot_matches SET next_action_at=v_now+make_interval(secs=>v_wait) WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','clue_revealed','result',v_result);
 END IF;
 IF random()<greatest(0.01,v_bot.mistake_rate-(v_bot.knowledge_level*0.04)) THEN
  v_answer:=(ARRAY['Talvez seja uma montanha','Não tenho a certeza','Penso que é uma cidade','A minha primeira hipótese','Pode ser um animal'])[1+floor(random()*5)::integer];
 ELSE
  v_answer:=v_challenge.answer;
 END IF;
 v_result:=public.atina_v2_submit_team_proposal(p_room_id,v_match.bot_token,
  v_game.position-1,v_answer,NULL,NULL);
 IF v_result->>'status' IN ('accepted','already_correct') THEN
  UPDATE private.atina_v2_bot_matches SET bot_turn_completed=true,
   next_action_at=v_now+make_interval(secs=>least(v_wait,4)) WHERE room_id=p_room_id;
  RETURN jsonb_build_object('status','answered','result',v_result);
 END IF;
 UPDATE private.atina_v2_bot_matches SET attempts=attempts+1,
  next_action_at=v_now+make_interval(secs=>v_wait) WHERE room_id=p_room_id;
 RETURN jsonb_build_object('status','thinking','result',v_result);
END;
$$;

REVOKE ALL ON FUNCTION public.atina_v2_create_bot_match(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.atina_v2_bot_tick(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_v2_create_bot_match(text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_bot_tick(uuid,text) TO anon,authenticated;
