-- ATINA ranking compatibility: isolated multiplayer + Mímicas v2.
-- Additive-only candidate. Existing public.atina_* room tables, RPCs,
-- private.atina_mime_cards and private.atina_mime_secrets are not replaced.
-- This file is source-controlled only; do not apply remotely until baseline and
-- disposable legacy-upgrade tests are complete.

do $preflight$
begin
  if to_regclass('private.atina_challenges') is null then
    raise exception 'Missing private.atina_challenges catalogue.';
  end if;
  if to_regclass('private.atina_mime_cards') is null then
    raise exception 'Missing legacy private.atina_mime_cards catalogue.';
  end if;
  if (select count(*) from private.atina_mime_cards) <> 48 then
    raise exception 'Expected exactly 48 existing MIME cards.';
  end if;
  if to_regclass('public.atina_rooms') is null
     or to_regclass('public.atina_room_players') is null then
    raise exception 'Legacy room tables are required and will not be created/replaced by this migration.';
  end if;
  if to_regclass('public.atina_v2_rooms') is not null
     or to_regclass('public.atina_v2_room_players') is not null
     or to_regclass('private.atina_v2_mime_rounds') is not null then
    raise exception 'One or more v2 multiplayer objects already exist; inspect before applying.';
  end if;
end
$preflight$;



-- Source 20261031220702_007_multiplayer_room_foundation.sql, isolated in v2 namespace.
-- ATINA multiplayer room foundation.
-- Reconstructed from the existing browser RPC contract. No client table access;
-- all room operations must be exposed through token-authenticated RPCs.
create table if not exists public.atina_v2_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{6}$'),
  max_players integer not null check (max_players between 2 and 20),
  status text not null default 'waiting'
    check (status in ('waiting','playing','completed','finished')),
  game_state jsonb not null default '{}'::jsonb
    check (jsonb_typeof(game_state) = 'object'),
  state_version bigint not null default 0 check (state_version >= 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.atina_v2_room_players (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.atina_v2_rooms(id) on delete cascade,
  token_hash bytea not null,
  nickname text not null check (char_length(btrim(nickname)) between 1 and 32),
  is_host boolean not null default false,
  ready boolean not null default false,
  team_label text,
  score integer not null default 0 check (score >= 0),
  player_timeout_seconds integer not null default 3600
    check (player_timeout_seconds between 0 and 3600),
  created_at timestamptz not null default clock_timestamp(),
  last_seen_at timestamptz not null default clock_timestamp(),
  constraint atina_v2_room_players_token_hash_unique unique (token_hash),
  constraint atina_v2_room_players_room_id_id_unique unique (room_id,id)
);

create unique index if not exists atina_v2_room_players_one_host_idx
  on public.atina_v2_room_players(room_id) where is_host;
create index if not exists atina_v2_room_players_room_created_idx
  on public.atina_v2_room_players(room_id,created_at,id);

create table if not exists public.atina_v2_room_answers (
  id bigint generated always as identity primary key,
  room_id uuid not null,
  player_id uuid not null,
  challenge_index integer not null check (challenge_index >= 0),
  is_correct boolean not null,
  points integer not null default 0 check (points >= 0),
  created_at timestamptz not null default clock_timestamp(),
  constraint atina_v2_room_answers_player_fk
    foreign key (room_id,player_id)
    references public.atina_v2_room_players(room_id,id) on delete cascade
);
create index if not exists atina_v2_room_answers_room_challenge_idx
  on public.atina_v2_room_answers(room_id,challenge_index,created_at);

create table if not exists public.atina_v2_room_results (
  room_id uuid not null references public.atina_v2_rooms(id) on delete cascade,
  player_id uuid not null,
  nickname text not null,
  team_label text,
  score integer not null check (score >= 0),
  completed_at timestamptz not null default clock_timestamp(),
  primary key (room_id,player_id),
  constraint atina_v2_room_results_player_fk
    foreign key (room_id,player_id)
    references public.atina_v2_room_players(room_id,id) on delete cascade
);

create table if not exists public.atina_v2_room_team_proposals (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.atina_v2_rooms(id) on delete cascade,
  challenge_index integer not null check (challenge_index >= 0),
  team_label text not null,
  proposer_id uuid not null,
  answer_text text not null check (char_length(btrim(answer_text)) between 1 and 200),
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected')),
  created_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  constraint atina_v2_room_team_proposals_player_fk
    foreign key (room_id,proposer_id)
    references public.atina_v2_room_players(room_id,id) on delete cascade
);
create index if not exists atina_v2_room_team_proposals_pending_idx
  on public.atina_v2_room_team_proposals(room_id,challenge_index,status);

create table if not exists public.atina_v2_room_team_votes (
  proposal_id uuid not null references public.atina_v2_room_team_proposals(id) on delete cascade,
  player_id uuid not null references public.atina_v2_room_players(id) on delete cascade,
  agrees boolean not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (proposal_id,player_id)
);

alter table public.atina_v2_rooms enable row level security;
alter table public.atina_v2_room_players enable row level security;
alter table public.atina_v2_room_answers enable row level security;
alter table public.atina_v2_room_results enable row level security;
alter table public.atina_v2_room_team_proposals enable row level security;
alter table public.atina_v2_room_team_votes enable row level security;

revoke all on public.atina_v2_rooms, public.atina_v2_room_players,
  public.atina_v2_room_answers, public.atina_v2_room_results,
  public.atina_v2_room_team_proposals, public.atina_v2_room_team_votes
  from public, anon, authenticated;

comment on table public.atina_v2_rooms is
  'ATINA multiplayer room metadata; direct client access revoked, use token-authenticated RPCs.';
comment on table public.atina_v2_room_players is
  'ATINA room participants; token_hash is a SHA-256 digest of a random bearer token.';
comment on table public.atina_v2_room_answers is
  'Server-recorded answer attempts and awarded points; clients must not write directly.';
comment on table public.atina_v2_room_results is
  'Final server-calculated room leaderboard.';
comment on table public.atina_v2_room_team_proposals is
  'Team answer proposals; correctness and points must be calculated server-side.';
comment on table public.atina_v2_room_team_votes is
  'One vote per participant and proposal.';

-- Cover the player-side foreign keys flagged by the Supabase performance advisor.
create index if not exists atina_v2_room_answers_room_player_idx
  on public.atina_v2_room_answers(room_id,player_id);
create index if not exists atina_v2_room_team_proposals_room_proposer_idx
  on public.atina_v2_room_team_proposals(room_id,proposer_id);
create index if not exists atina_v2_room_team_votes_player_idx
  on public.atina_v2_room_team_votes(player_id);


-- Source 20261031220703_008_multiplayer_lobby_rpcs.sql, isolated in v2 namespace.
-- ATINA multiplayer lobby RPCs. All room access is token-authenticated.
-- SECURITY DEFINER is required because direct table privileges are revoked.
-- Every function uses an empty search_path and schema-qualified references.
CREATE OR REPLACE FUNCTION public.atina_v2_create_room(p_nickname text, p_max_players integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_room public.atina_v2_rooms%rowtype; v_player public.atina_v2_room_players%rowtype;
 v_token text; v_code text; v_attempt integer:=0;
begin
 if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 32 then raise exception 'Pseudónimo inválido.'; end if;
 if p_max_players is null or p_max_players not between 2 and 20 then raise exception 'Número de jogadores inválido.'; end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 loop
  v_code:=upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,6));
  begin
   insert into public.atina_v2_rooms(code,max_players) values(v_code,p_max_players) returning * into v_room;
   exit;
  exception when unique_violation then
   v_attempt:=v_attempt+1;
   if v_attempt>=8 then raise exception 'Não foi possível gerar um código de sala. Tenta novamente.'; end if;
  end;
 end loop;
 insert into public.atina_v2_room_players(room_id,token_hash,nickname,is_host,ready)
 values(v_room.id,extensions.digest(v_token,'sha256'),btrim(p_nickname),true,true)
 returning * into v_player;
 return jsonb_build_object('room_id',v_room.id,'token',v_token,'code',v_room.code,'player_id',v_player.id);
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_v2_join_room(p_nickname text, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_room public.atina_v2_rooms%rowtype; v_player public.atina_v2_room_players%rowtype;
 v_token text;
begin
 if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 32 then raise exception 'Pseudónimo inválido.'; end if;
 if p_code is null or p_code !~ '^[A-Za-z0-9]{6}$' then raise exception 'Código de sala inválido.'; end if;
 select * into v_room from public.atina_v2_rooms where code=upper(p_code) for update;
 if not found or v_room.status<>'waiting' then raise exception 'Sala não encontrada ou já iniciada.'; end if;
 if (select count(*) from public.atina_v2_room_players where room_id=v_room.id)>=v_room.max_players then raise exception 'A sala está cheia.'; end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.atina_v2_room_players(room_id,token_hash,nickname,is_host,ready)
 values(v_room.id,extensions.digest(v_token,'sha256'),btrim(p_nickname),false,false)
 returning * into v_player;
 return jsonb_build_object('room_id',v_room.id,'token',v_token,'code',v_room.code,'player_id',v_player.id);
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_v2_leave_room(p_room_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_player public.atina_v2_room_players%rowtype; v_count integer;
begin
 select * into v_player from public.atina_v2_room_players
 where room_id=p_room_id and token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
 if not found then return jsonb_build_object('left',true); end if;
 perform 1 from public.atina_v2_rooms where id=p_room_id for update;
 delete from public.atina_v2_room_players where id=v_player.id;
 select count(*) into v_count from public.atina_v2_room_players where room_id=p_room_id;
 if v_count=0 then
  delete from public.atina_v2_rooms where id=p_room_id;
 else
  if v_player.is_host then
   update public.atina_v2_room_players set is_host=true,ready=true
   where id=(select id from public.atina_v2_room_players where room_id=p_room_id order by created_at,id limit 1);
  end if;
 end if;
 return jsonb_build_object('left',true);
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_v2_room_state(p_room_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_me public.atina_v2_room_players%rowtype; v_room public.atina_v2_rooms%rowtype;
declare v_players jsonb; v_team_proposal jsonb; v_team text;
begin
 select * into v_me from public.atina_v2_room_players
 where room_id=p_room_id and token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
 if not found then raise exception 'Sessão da sala inválida.'; end if;
 select * into v_room from public.atina_v2_rooms where id=p_room_id;
 if not found then raise exception 'Sala não encontrada.'; end if;
 update public.atina_v2_room_players set last_seen_at=clock_timestamp() where id=v_me.id;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',p.id,'nickname',p.nickname,'is_host',p.is_host,'ready',p.ready,
  'team',p.team_label,'score',p.score
 ) order by p.created_at,p.id),'[]'::jsonb)
 into v_players from public.atina_v2_room_players p where p.room_id=p_room_id;
 v_team:=v_me.team_label;
 if v_team is not null then
  select jsonb_build_object(
   'id',pr.id,'team',pr.team_label,'proposer_id',pr.proposer_id,
   'proposer',pp.nickname,'answer',pr.answer_text,'status',pr.status,
   'votes',coalesce((select jsonb_agg(jsonb_build_object('player_id',v.player_id,'agrees',v.agrees) order by v.created_at)
    from public.atina_v2_room_team_votes v where v.proposal_id=pr.id),'[]'::jsonb)
  ) into v_team_proposal
  from public.atina_v2_room_team_proposals pr
  join public.atina_v2_room_players pp on pp.id=pr.proposer_id
  where pr.room_id=p_room_id and pr.team_label=v_team
    and pr.challenge_index=coalesce((v_room.game_state->>'pos')::integer,-1)
  order by pr.created_at desc limit 1;
 end if;
 return jsonb_build_object(
  'room_id',v_room.id,'code',v_room.code,'status',v_room.status,
  'max_players',v_room.max_players,'is_host',v_me.is_host,
  'player_id',v_me.id,'ready',v_me.ready,'team',v_team,
  'my_score',v_me.score,'players',v_players,
  'game_state',v_room.game_state,
  'team_proposal',v_team_proposal,
  'timeouts',jsonb_build_object(
   'player_remaining_seconds',v_me.player_timeout_seconds,
   'team_remaining_seconds',case when v_team is null then 0 else 3600 end
  )
 );
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_v2_set_room_ready(p_room_id uuid, p_token text, p_ready boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_player public.atina_v2_room_players%rowtype; v_room public.atina_v2_rooms%rowtype;
begin
 if p_ready is null then raise exception 'Estado de prontidão inválido.'; end if;
 select * into v_player from public.atina_v2_room_players
 where room_id=p_room_id and token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
 if not found then raise exception 'Sessão da sala inválida.'; end if;
 select * into v_room from public.atina_v2_rooms where id=p_room_id for update;
 if v_room.status<>'waiting' then raise exception 'A sala já foi iniciada.'; end if;
 update public.atina_v2_room_players set ready=p_ready,last_seen_at=clock_timestamp() where id=v_player.id;
 return jsonb_build_object('ready',p_ready);
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_v2_set_room_team(p_room_id uuid, p_token text, p_player_id uuid, p_team text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_host public.atina_v2_room_players%rowtype; v_room public.atina_v2_rooms%rowtype;
begin
 select * into v_host from public.atina_v2_room_players
 where room_id=p_room_id and token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
 if not found or not v_host.is_host then raise exception 'Só o anfitrião pode atribuir equipas.'; end if;
 select * into v_room from public.atina_v2_rooms where id=p_room_id for update;
 if v_room.status<>'waiting' then raise exception 'As equipas já não podem ser alteradas.'; end if;
 if p_team is null or btrim(p_team)='' then
  update public.atina_v2_room_players set team_label=null where room_id=p_room_id and id=p_player_id;
 else
  if char_length(btrim(p_team))>32 then raise exception 'Nome de equipa demasiado longo.'; end if;
  update public.atina_v2_room_players set team_label=btrim(p_team) where room_id=p_room_id and id=p_player_id;
 end if;
 if not found then raise exception 'Jogador não encontrado nesta sala.'; end if;
 return jsonb_build_object('player_id',p_player_id,'team',nullif(btrim(coalesce(p_team,'')),''));
end;
$function$;


CREATE OR REPLACE FUNCTION public.atina_v2_start_room(p_room_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_host public.atina_v2_room_players%rowtype; v_room public.atina_v2_rooms%rowtype;
declare v_count integer; v_unready integer;
begin
 select * into v_host from public.atina_v2_room_players
 where room_id=p_room_id and token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
 if not found or not v_host.is_host then raise exception 'Só o anfitrião pode iniciar a sala.'; end if;
 select * into v_room from public.atina_v2_rooms where id=p_room_id for update;
 if v_room.status<>'waiting' then raise exception 'A sala já foi iniciada.'; end if;
 select count(*),count(*) filter(where not ready) into v_count,v_unready
 from public.atina_v2_room_players where room_id=p_room_id;
 if v_count<2 then raise exception 'São necessários pelo menos dois jogadores.'; end if;
 if v_unready>0 then raise exception 'Todos os jogadores têm de confirmar que estão prontos.'; end if;
 update public.atina_v2_rooms set status='playing',updated_at=clock_timestamp(),
  game_state=jsonb_build_object('mode','pending','started_at',clock_timestamp())
 where id=p_room_id;
 return jsonb_build_object('status','playing','players',v_count);
end;
$function$;


revoke all on function public.atina_v2_create_room(text,integer) from public;
revoke all on function public.atina_v2_join_room(text,text) from public;
revoke all on function public.atina_v2_set_room_ready(uuid,text,boolean) from public;
revoke all on function public.atina_v2_set_room_team(uuid,text,uuid,text) from public;
revoke all on function public.atina_v2_start_room(uuid,text) from public;
revoke all on function public.atina_v2_room_state(uuid,text) from public;
revoke all on function public.atina_v2_leave_room(uuid,text) from public;
grant execute on function public.atina_v2_create_room(text,integer) to anon,authenticated;
grant execute on function public.atina_v2_join_room(text,text) to anon,authenticated;
grant execute on function public.atina_v2_set_room_ready(uuid,text,boolean) to anon,authenticated;
grant execute on function public.atina_v2_set_room_team(uuid,text,uuid,text) to anon,authenticated;
grant execute on function public.atina_v2_start_room(uuid,text) to anon,authenticated;
grant execute on function public.atina_v2_room_state(uuid,text) to anon,authenticated;
grant execute on function public.atina_v2_leave_room(uuid,text) to anon,authenticated;


-- Source 20261031221941_009_multiplayer_server_queue.sql, isolated in v2 namespace.
-- Server-authoritative multiplayer challenge queue and sanitized public state.
CREATE TABLE IF NOT EXISTS private.atina_v2_room_game_state (
  room_id uuid PRIMARY KEY REFERENCES public.atina_v2_rooms(id) ON DELETE CASCADE,
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
ALTER TABLE private.atina_v2_room_game_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.atina_v2_room_game_state FROM public, anon, authenticated;
COMMENT ON TABLE private.atina_v2_room_game_state IS 'Authoritative private multiplayer queue and round clock; never exposed through the Data API.';

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

  INSERT INTO private.atina_v2_room_game_state(
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

  UPDATE public.atina_v2_rooms
  SET game_state=v_state,state_version=state_version+1,updated_at=v_now
  WHERE id=p_room_id;

  RETURN jsonb_build_object(
    'status','started',
    'queue_length',cardinality(v_queue),
    'state',v_state
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_start_room_challenges(uuid,text,text,integer,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_start_room_challenges(uuid,text,text,integer,text) TO anon,authenticated;


-- Source 20261031222217_010_multiplayer_answer_and_clues.sql, isolated in v2 namespace.
-- Authoritative multiplayer answer submission and clue reveal.
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
  SELECT * INTO v_challenge
  FROM private.atina_challenges
  WHERE challenge_id=v_game.challenge_queue[v_game.position] AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Desafio atual indisponível.'; END IF;

  SELECT coalesce(jsonb_agg(cl.value ORDER BY cl.ordinality),'[]'::jsonb)
  INTO v_clues
  FROM jsonb_array_elements(v_challenge.clues) WITH ORDINALITY cl(value,ordinality)
  WHERE cl.ordinality <= v_game.revealed_clues;

  RETURN jsonb_build_object(
    'mode','challenges',
    'protocol_version',1,
    'challenge_id',v_challenge.challenge_id,
    'category',v_challenge.category,
    'emoji',v_challenge.emoji,
    'clues',v_clues,
    'image_url',v_challenge.image_url,
    'pos',v_game.position-1,
    'queue_length',cardinality(v_game.challenge_queue),
    'revealed',v_game.revealed_clues,
    'timedMode',v_game.timed_mode_seconds,
    'deadline',CASE WHEN v_game.deadline_at IS NULL THEN 0 ELSE extract(epoch FROM v_game.deadline_at)*1000 END,
    'locked',v_game.round_locked,
    'revision',v_room.state_version
  );
END;
$function$;
REVOKE ALL ON FUNCTION private.atina_v2_room_public_state(uuid) FROM public,anon,authenticated;

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
BEGIN
  SELECT * INTO v_player FROM public.atina_v2_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND OR NOT v_player.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode revelar pistas.'; END IF;

  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' OR v_game.round_locked THEN
    RAISE EXCEPTION 'A ronda não está ativa.';
  END IF;
  v_now:=clock_timestamp();
  IF v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
    UPDATE public.atina_v2_rooms SET game_state=coalesce(private.atina_v2_room_public_state(p_room_id),'{}'::jsonb) || jsonb_build_object('feedback','Tempo esgotado.','locked',true),
      state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
    RETURN jsonb_build_object('status','timeout','state',private.atina_v2_room_public_state(p_room_id));
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
  UPDATE public.atina_v2_rooms
  SET game_state=v_state,state_version=state_version+1,updated_at=v_now
  WHERE id=p_room_id;
  RETURN jsonb_build_object('status','revealed','state',v_state);
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_submit_room_answer(
  p_room_id uuid,
  p_token text,
  p_answer text
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

  v_now:=clock_timestamp();
  IF v_game.round_locked OR (v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now) THEN
    IF NOT v_game.round_locked THEN
      UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
      v_game.round_locked:=true;
      v_state:=private.atina_v2_room_public_state(p_room_id) || jsonb_build_object('feedback','Tempo esgotado.','locked',true);
      UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
    END IF;
    RETURN jsonb_build_object('status','locked','score',v_player.score,'state',coalesce(v_state,private.atina_v2_room_public_state(p_room_id)));
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

  IF v_correct THEN
    SELECT CASE
      WHEN v_game.revealed_clues>=jsonb_array_length(c.clues) THEN
        CASE WHEN c.image_url IS NOT NULL THEN (ARRAY[20,16,12,8,6,5])[v_game.revealed_clues]
             ELSE (ARRAY[20,16,12,8,5])[v_game.revealed_clues] END
      WHEN c.image_url IS NOT NULL THEN (ARRAY[20,16,12,8,6,5])[v_game.revealed_clues]
      ELSE (ARRAY[20,16,12,8,5])[v_game.revealed_clues]
    END
    INTO v_base
    FROM private.atina_challenges c
    WHERE c.challenge_id=v_game.challenge_queue[v_game.position] AND c.active;
    IF v_game.deadline_at IS NOT NULL THEN
      v_speed:=greatest(0,floor(ceil(extract(epoch FROM (v_game.deadline_at-v_now)))/10)::integer);
    END IF;
    v_points:=v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END;
    UPDATE public.atina_v2_room_players
    SET score=score+v_points,last_seen_at=v_now
    WHERE id=v_player.id RETURNING score INTO v_score;
  ELSE
    UPDATE public.atina_v2_room_players
    SET score=greatest(0,score-10),last_seen_at=v_now
    WHERE id=v_player.id RETURNING score INTO v_score;
  END IF;

  INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
  VALUES(p_room_id,v_player.id,v_game.position-1,v_correct,v_points,v_now);

  RETURN jsonb_build_object(
    'status',CASE WHEN v_correct THEN 'correct' ELSE 'wrong' END,
    'correct',v_correct,
    'points',v_points,
    'score',v_score,
    'penalty',CASE WHEN v_correct THEN 0 ELSE 10 END,
    'state',private.atina_v2_room_public_state(p_room_id)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_reveal_room_clue(uuid,text) FROM public;
REVOKE ALL ON FUNCTION public.atina_v2_submit_room_answer(uuid,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_reveal_room_clue(uuid,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_submit_room_answer(uuid,text,text) TO anon,authenticated;


-- Source 20261031222248_011_multiplayer_speed_bonus_rounding.sql, isolated in v2 namespace.
CREATE OR REPLACE FUNCTION public.atina_v2_submit_room_answer(
  p_room_id uuid,
  p_token text,
  p_answer text
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
BEGIN
  IF p_answer IS NULL OR char_length(btrim(p_answer))=0 OR char_length(p_answer)>300 THEN
    RAISE EXCEPTION 'Resposta vazia ou demasiado longa.';
  END IF;
  SELECT * INTO v_player FROM public.atina_v2_room_players
  WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' THEN RAISE EXCEPTION 'A partida não tem uma ronda ativa.'; END IF;
  v_now:=clock_timestamp();
  IF v_game.round_locked OR (v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now) THEN
    IF NOT v_game.round_locked THEN
      UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
      v_game.round_locked:=true;
      v_state:=private.atina_v2_room_public_state(p_room_id) || jsonb_build_object('feedback','Tempo esgotado.','locked',true);
      UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
    END IF;
    RETURN jsonb_build_object('status','locked','score',v_player.score,'state',coalesce(v_state,private.atina_v2_room_public_state(p_room_id)));
  END IF;
  SELECT EXISTS(
    SELECT 1 FROM public.atina_v2_room_answers
    WHERE room_id=p_room_id AND player_id=v_player.id
      AND challenge_index=v_game.position-1 AND is_correct
  ) INTO v_prior_correct;
  IF v_prior_correct THEN
    RETURN jsonb_build_object('status','already_correct','correct',true,'score',v_player.score,'points',0);
  END IF;
  v_correct:=private.atina_v2_challenge_answer_matches(v_game.challenge_queue[v_game.position],btrim(p_answer));
  IF v_correct THEN
    SELECT CASE
      WHEN c.image_url IS NOT NULL THEN (ARRAY[20,16,12,8,6,5])[v_game.revealed_clues]
      ELSE (ARRAY[20,16,12,8,5])[v_game.revealed_clues]
    END INTO v_base
    FROM private.atina_challenges c
    WHERE c.challenge_id=v_game.challenge_queue[v_game.position] AND c.active;
    IF v_game.deadline_at IS NOT NULL THEN
      -- Replica o ceil dos segundos restantes feito no frontend original, antes de dividir por 10.
      v_speed:=greatest(0,floor(ceil(extract(epoch FROM (v_game.deadline_at-v_now)))/10)::integer);
    END IF;
    v_points:=v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END;
    UPDATE public.atina_v2_room_players SET score=score+v_points,last_seen_at=v_now
    WHERE id=v_player.id RETURNING score INTO v_score;
  ELSE
    UPDATE public.atina_v2_room_players SET score=greatest(0,score-10),last_seen_at=v_now
    WHERE id=v_player.id RETURNING score INTO v_score;
  END IF;
  INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
  VALUES(p_room_id,v_player.id,v_game.position-1,v_correct,v_points,v_now);
  RETURN jsonb_build_object(
    'status',CASE WHEN v_correct THEN 'correct' ELSE 'wrong' END,
    'correct',v_correct,'points',v_points,'score',v_score,
    'penalty',CASE WHEN v_correct THEN 0 ELSE 10 END,
    'state',private.atina_v2_room_public_state(p_room_id)
  );
END;
$function$;


-- Source 20261031222318_012_block_team_individual_submission.sql, isolated in v2 namespace.
CREATE OR REPLACE FUNCTION public.atina_v2_submit_room_answer(
  p_room_id uuid,p_token text,p_answer text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_player public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_now timestamptz; v_correct boolean; v_base integer;
  v_speed integer:=0; v_points integer:=0; v_score integer;
  v_prior_correct boolean; v_state jsonb;
BEGIN
  IF p_answer IS NULL OR char_length(btrim(p_answer))=0 OR char_length(p_answer)>300 THEN
    RAISE EXCEPTION 'Resposta vazia ou demasiado longa.';
  END IF;
  SELECT * INTO v_player FROM public.atina_v2_room_players
  WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
  IF v_player.team_label IS NOT NULL THEN
    RAISE EXCEPTION 'As respostas de equipa exigem o fluxo seguro de propostas e votação.';
  END IF;
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' THEN RAISE EXCEPTION 'A partida não tem uma ronda ativa.'; END IF;
  v_now:=clock_timestamp();
  IF v_game.round_locked OR (v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now) THEN
    IF NOT v_game.round_locked THEN
      UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
      v_game.round_locked:=true;
      v_state:=private.atina_v2_room_public_state(p_room_id)||jsonb_build_object('feedback','Tempo esgotado.','locked',true);
      UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
    END IF;
    RETURN jsonb_build_object('status','locked','score',v_player.score,'state',coalesce(v_state,private.atina_v2_room_public_state(p_room_id)));
  END IF;
  SELECT EXISTS(SELECT 1 FROM public.atina_v2_room_answers
    WHERE room_id=p_room_id AND player_id=v_player.id
      AND challenge_index=v_game.position-1 AND is_correct) INTO v_prior_correct;
  IF v_prior_correct THEN
    RETURN jsonb_build_object('status','already_correct','correct',true,'score',v_player.score,'points',0);
  END IF;
  v_correct:=private.atina_v2_challenge_answer_matches(v_game.challenge_queue[v_game.position],btrim(p_answer));
  IF v_correct THEN
    SELECT CASE WHEN c.image_url IS NOT NULL
      THEN (ARRAY[20,16,12,8,6,5])[v_game.revealed_clues]
      ELSE (ARRAY[20,16,12,8,5])[v_game.revealed_clues] END
    INTO v_base FROM private.atina_challenges c
    WHERE c.challenge_id=v_game.challenge_queue[v_game.position] AND c.active;
    IF v_game.deadline_at IS NOT NULL THEN
      v_speed:=greatest(0,floor(ceil(extract(epoch FROM (v_game.deadline_at-v_now)))/10)::integer);
    END IF;
    v_points:=v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END;
    UPDATE public.atina_v2_room_players SET score=score+v_points,last_seen_at=v_now
    WHERE id=v_player.id RETURNING score INTO v_score;
  ELSE
    UPDATE public.atina_v2_room_players SET score=greatest(0,score-10),last_seen_at=v_now
    WHERE id=v_player.id RETURNING score INTO v_score;
  END IF;
  INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
  VALUES(p_room_id,v_player.id,v_game.position-1,v_correct,v_points,v_now);
  RETURN jsonb_build_object('status',CASE WHEN v_correct THEN 'correct' ELSE 'wrong' END,
    'correct',v_correct,'points',v_points,'score',v_score,
    'penalty',CASE WHEN v_correct THEN 0 ELSE 10 END,
    'state',private.atina_v2_room_public_state(p_room_id));
END;
$function$;


-- Source 20261031222441_013_multiplayer_pass_next_results.sql, isolated in v2 namespace.
-- Server-authoritative pass, next challenge and room completion.
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
    'revealed',v_game.revealed_clues,'timedMode',v_game.timed_mode_seconds,
    'deadline',CASE WHEN v_game.deadline_at IS NULL THEN 0 ELSE extract(epoch FROM v_game.deadline_at)*1000 END,
    'locked',v_game.round_locked,'revision',v_room.state_version
  );
END;
$function$;
REVOKE ALL ON FUNCTION private.atina_v2_room_public_state(uuid) FROM public,anon,authenticated;

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
BEGIN
  SELECT * INTO v_player FROM public.atina_v2_room_players
  WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND OR NOT v_player.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode passar o desafio.'; END IF;
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' THEN RAISE EXCEPTION 'A ronda não está ativa.'; END IF;
  v_now:=clock_timestamp();
  v_status:=CASE WHEN v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN 'timeout' ELSE 'passed' END;
  UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
  v_state:=private.atina_v2_room_public_state(p_room_id)||jsonb_build_object(
    'feedback',CASE WHEN v_status='timeout' THEN 'Tempo esgotado.' ELSE 'Desafio passado.' END,
    'locked',true
  );
  UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
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
BEGIN
  SELECT * INTO v_player FROM public.atina_v2_room_players
  WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND OR NOT v_player.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode avançar o desafio.'; END IF;
  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' THEN RAISE EXCEPTION 'A ronda não está ativa.'; END IF;
  v_now:=clock_timestamp();

  IF v_game.position<cardinality(v_game.challenge_queue) THEN
    UPDATE private.atina_v2_room_game_state
    SET position=position+1,revealed_clues=1,round_locked=false,
        deadline_at=CASE WHEN timed_mode_seconds=0 THEN NULL
          ELSE v_now+make_interval(secs=>timed_mode_seconds) END,
        updated_at=v_now
    WHERE room_id=p_room_id;
    v_state:=private.atina_v2_room_public_state(p_room_id);
    UPDATE public.atina_v2_rooms
    SET game_state=v_state,state_version=state_version+1,updated_at=v_now
    WHERE id=p_room_id;
    RETURN jsonb_build_object('status','next','state',v_state);
  END IF;

  UPDATE private.atina_v2_room_game_state
  SET status='completed',round_locked=true,updated_at=v_now
  WHERE room_id=p_room_id;

  INSERT INTO public.atina_v2_room_results(room_id,player_id,nickname,team_label,score,completed_at)
  SELECT p.room_id,p.id,p.nickname,p.team_label,p.score,v_now
  FROM public.atina_v2_room_players p
  WHERE p.room_id=p_room_id
  ON CONFLICT(room_id,player_id) DO UPDATE
  SET nickname=excluded.nickname,team_label=excluded.team_label,
      score=excluded.score,completed_at=excluded.completed_at;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'player_id',r.player_id,'nickname',r.nickname,'team',r.team_label,'score',r.score
  ) ORDER BY r.score DESC,r.nickname),'[]'::jsonb)
  INTO v_results
  FROM public.atina_v2_room_results r WHERE r.room_id=p_room_id;

  UPDATE public.atina_v2_rooms
  SET status='completed',
      game_state=jsonb_build_object(
        'mode','completed','protocol_version',1,
        'pos',cardinality(v_game.challenge_queue),
        'queue_length',cardinality(v_game.challenge_queue),
        'locked',true,'revision',state_version+1
      ),
      state_version=state_version+1,updated_at=v_now
  WHERE id=p_room_id;

  RETURN jsonb_build_object('status','completed','results',v_results);
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_pass_room_challenge(uuid,text) FROM public;
REVOKE ALL ON FUNCTION public.atina_v2_next_room_challenge(uuid,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_pass_room_challenge(uuid,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_next_room_challenge(uuid,text) TO anon,authenticated;


-- Source 20261031222521_014_multiplayer_deadline_state_reconciliation.sql, isolated in v2 namespace.
-- Reconcile multiplayer round deadlines from the authoritative room-state poll.
CREATE OR REPLACE FUNCTION public.atina_v2_room_state(p_room_id uuid,p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_me public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_players jsonb;
  v_team_proposal jsonb;
  v_team text;
  v_now timestamptz;
  v_state jsonb;
BEGIN
  SELECT * INTO v_me FROM public.atina_v2_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;

  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sala não encontrada.'; END IF;

  SELECT * INTO v_game FROM private.atina_v2_room_game_state
  WHERE room_id=p_room_id FOR UPDATE;

  -- Read the clock only after all relevant row locks have been acquired.
  v_now:=clock_timestamp();
  IF FOUND AND v_game.status='active' AND NOT v_game.round_locked
     AND v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_v2_room_game_state
    SET round_locked=true,updated_at=v_now
    WHERE room_id=p_room_id;
    v_state:=private.atina_v2_room_public_state(p_room_id)
      || jsonb_build_object('feedback','Tempo esgotado.','locked',true);
    UPDATE public.atina_v2_rooms
    SET game_state=v_state,state_version=state_version+1,updated_at=v_now
    WHERE id=p_room_id
    RETURNING * INTO v_room;
  END IF;

  UPDATE public.atina_v2_room_players SET last_seen_at=v_now WHERE id=v_me.id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'nickname',p.nickname,'is_host',p.is_host,'ready',p.ready,
    'team',p.team_label,'score',p.score
  ) ORDER BY p.created_at,p.id),'[]'::jsonb)
  INTO v_players FROM public.atina_v2_room_players p WHERE p.room_id=p_room_id;

  v_team:=v_me.team_label;
  IF v_team IS NOT NULL THEN
    SELECT jsonb_build_object(
      'id',pr.id,'team',pr.team_label,'proposer_id',pr.proposer_id,
      'proposer',pp.nickname,'answer',pr.answer_text,'status',pr.status,
      'votes',coalesce((SELECT jsonb_agg(jsonb_build_object('player_id',v.player_id,'agrees',v.agrees) ORDER BY v.created_at)
        FROM public.atina_v2_room_team_votes v WHERE v.proposal_id=pr.id),'[]'::jsonb)
    ) INTO v_team_proposal
    FROM public.atina_v2_room_team_proposals pr
    JOIN public.atina_v2_room_players pp ON pp.id=pr.proposer_id
    WHERE pr.room_id=p_room_id AND pr.team_label=v_team
      AND pr.challenge_index=coalesce((v_room.game_state->>'pos')::integer,-1)
    ORDER BY pr.created_at DESC LIMIT 1;
  END IF;

  RETURN jsonb_build_object(
    'room_id',v_room.id,'code',v_room.code,'status',v_room.status,
    'max_players',v_room.max_players,'is_host',v_me.is_host,
    'player_id',v_me.id,'ready',v_me.ready,'team',v_team,
    'my_score',v_me.score,'players',v_players,
    'game_state',v_room.game_state,
    'team_proposal',v_team_proposal,
    'timeouts',jsonb_build_object(
      'player_remaining_seconds',v_me.player_timeout_seconds,
      'team_remaining_seconds',CASE WHEN v_team IS NULL THEN 0 ELSE 3600 END
    )
  );
END;
$function$;


-- Source 20261031222726_015_secure_team_proposals_and_voting.sql, isolated in v2 namespace.
-- Team proposals are text-only; the server validates correctness and awards points after unanimous consent.
ALTER TABLE public.atina_v2_room_team_proposals
  ADD COLUMN IF NOT EXISTS resolution_reason text
  CHECK (resolution_reason IS NULL OR resolution_reason IN ('disagreement','incorrect_answer','correct_answer','timeout'));

CREATE UNIQUE INDEX IF NOT EXISTS atina_v2_atina_room_team_one_pending_proposal_idx
  ON public.atina_v2_room_team_proposals(room_id,challenge_index,team_label)
  WHERE status='pending';

CREATE OR REPLACE FUNCTION public.atina_v2_submit_team_proposal(
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
  v_room public.atina_v2_rooms%rowtype;
  v_player public.atina_v2_room_players%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_proposal public.atina_v2_room_team_proposals%rowtype;
  v_team_size integer;
  v_now timestamptz;
  v_state jsonb;
BEGIN
  IF p_answer IS NULL OR char_length(btrim(p_answer)) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'Resposta vazia ou demasiado longa.';
  END IF;

  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;

  SELECT * INTO v_player FROM public.atina_v2_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
  IF v_player.team_label IS NULL THEN RAISE EXCEPTION 'O jogador não pertence a uma equipa.'; END IF;

  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' OR v_game.round_locked THEN
    RAISE EXCEPTION 'A ronda não está ativa.';
  END IF;
  IF p_challenge IS DISTINCT FROM v_game.position-1 THEN
    RAISE EXCEPTION 'O desafio indicado já não é o desafio atual.';
  END IF;

  v_now:=clock_timestamp();
  IF v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
    v_state:=private.atina_v2_room_public_state(p_room_id)
      || jsonb_build_object('feedback','Tempo esgotado.','locked',true);
    UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now
    WHERE id=p_room_id;
    RETURN jsonb_build_object('status','locked','state',v_state);
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.atina_v2_room_answers a
    JOIN public.atina_v2_room_players p ON p.id=a.player_id
    WHERE a.room_id=p_room_id AND a.challenge_index=v_game.position-1
      AND a.is_correct AND p.team_label=v_player.team_label
  ) THEN
    RETURN jsonb_build_object('status','already_correct');
  END IF;

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
  ) VALUES (
    p_room_id,v_game.position-1,v_player.team_label,v_player.id,btrim(p_answer),'pending'
  ) RETURNING * INTO v_proposal;

  RETURN jsonb_build_object(
    'status','pending','proposal_id',v_proposal.id,
    'message','Proposta registada; aguarda os votos dos restantes membros.'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_vote_team_proposal(
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
BEGIN
  IF p_agrees IS NULL THEN RAISE EXCEPTION 'Voto inválido.'; END IF;

  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;

  SELECT * INTO v_player FROM public.atina_v2_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
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

  v_now:=clock_timestamp();
  IF v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
    v_state:=private.atina_v2_room_public_state(p_room_id)
      || jsonb_build_object('feedback','Tempo esgotado.','locked',true);
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
  INTO v_votes,v_disagrees
  FROM public.atina_v2_room_team_votes WHERE proposal_id=v_proposal.id;

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

    UPDATE public.atina_v2_room_players
    SET score=score+v_points,last_seen_at=v_now
    WHERE room_id=p_room_id AND team_label=v_proposal.team_label;

    INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
    SELECT p_room_id,p.id,v_game.position-1,true,v_points,v_now
    FROM public.atina_v2_room_players p
    WHERE p.room_id=p_room_id AND p.team_label=v_proposal.team_label;

    UPDATE public.atina_v2_room_team_proposals
    SET status='accepted',resolution_reason='correct_answer',resolved_at=v_now
    WHERE id=v_proposal.id;

    SELECT coalesce(jsonb_agg(jsonb_build_object('player_id',p.id,'score',p.score) ORDER BY p.created_at,p.id),'[]'::jsonb)
    INTO v_scores FROM public.atina_v2_room_players p
    WHERE p.room_id=p_room_id AND p.team_label=v_proposal.team_label;

    RETURN jsonb_build_object(
      'status','accepted','correct',true,'points_per_player',v_points,
      'scores',v_scores,'votes',v_votes
    );
  END IF;

  UPDATE public.atina_v2_room_players
  SET score=greatest(0,score-10),last_seen_at=v_now
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

  RETURN jsonb_build_object(
    'status','rejected','reason','incorrect_answer','correct',false,
    'penalty_per_player',10,'scores',v_scores,'votes',v_votes
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_submit_team_proposal(uuid,text,integer,text,boolean,integer) FROM public;
REVOKE ALL ON FUNCTION public.atina_v2_vote_team_proposal(uuid,text,uuid,boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_submit_team_proposal(uuid,text,integer,text,boolean,integer) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_vote_team_proposal(uuid,text,uuid,boolean) TO anon,authenticated;


-- Source 20261031223004_016_secure_mimicas_server_authority.sql, isolated in v2 namespace.
-- Secure authoritative Mímicas flow. Never accept client-provided points or deadlines.
CREATE TABLE IF NOT EXISTS private.atina_v2_mime_rounds (
  room_id uuid NOT NULL REFERENCES public.atina_v2_rooms(id) ON DELETE CASCADE,
  round_number integer NOT NULL CHECK(round_number>=0),
  card_id bigint NOT NULL REFERENCES private.atina_mime_cards(id),
  representative_id uuid NOT NULL REFERENCES public.atina_v2_room_players(id),
  started_at timestamptz,
  deadline_at timestamptz,
  duration_seconds integer NOT NULL CHECK(duration_seconds IN (0,60,90)),
  clue_index integer NOT NULL DEFAULT 0 CHECK(clue_index BETWEEN 0 AND 4),
  locked boolean NOT NULL DEFAULT false,
  outcome text CHECK(outcome IS NULL OR outcome IN ('correct','pass','timeout')),
  points_awarded integer NOT NULL DEFAULT 0 CHECK(points_awarded>=0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(room_id,round_number),
  CONSTRAINT atina_mime_round_rep_room_fk FOREIGN KEY(room_id,representative_id)
    REFERENCES public.atina_v2_room_players(room_id,id) ON DELETE CASCADE
);
ALTER TABLE private.atina_v2_mime_rounds ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.atina_mime_cards,private.atina_v2_mime_rounds FROM public,anon,authenticated;
CREATE INDEX IF NOT EXISTS atina_v2_mime_rounds_representative_idx
  ON private.atina_v2_mime_rounds(representative_id);
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
 VALUES(p_room_id,p_round_number,v_card.id,v_rep.id,v_now,v_deadline,p_duration_seconds);
 v_state:=jsonb_build_object(
  'mode','mimicas','round',p_round_number,'total_rounds',v_total,
  'representative_id',v_rep.id,'representative_name',v_rep.nickname,
  'team_label',v_rep.team_label,'category',v_card.category,
  'clues',jsonb_build_array(v_card.clues->0),'clue_index',0,
  'duration_seconds',p_duration_seconds,'started',true,'locked',false,
  'deadline',CASE WHEN v_deadline IS NULL THEN 0 ELSE floor(extract(epoch FROM v_deadline)*1000)::bigint END,
  'revision',coalesce((v_room.game_state->>'revision')::integer,0)+1
 );
 UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
 RETURN v_state;
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_get_mime_secret(p_room_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE v_player public.atina_v2_room_players%rowtype; v_round private.atina_v2_mime_rounds%rowtype; v_word text;
BEGIN
 SELECT * INTO v_player FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256');
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
 SELECT * INTO v_round FROM private.atina_v2_mime_rounds
 WHERE room_id=p_room_id
 ORDER BY round_number DESC LIMIT 1;
 IF NOT FOUND OR v_round.representative_id<>v_player.id THEN
  RAISE EXCEPTION 'Só o representante desta ronda pode ver a palavra secreta.';
 END IF;
 SELECT word INTO v_word FROM private.atina_mime_cards WHERE id=v_round.card_id;
 RETURN jsonb_build_object('word',v_word);
END;
$function$;

-- This replaces the arbitrary host JSON publisher with a narrowly constrained Mímicas transition.
-- Only the start-clock and reveal-clue actions from the existing client are accepted.
CREATE OR REPLACE FUNCTION public.atina_v2_publish_game_state(p_room_id uuid,p_token text,p_state jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_host public.atina_v2_room_players%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_round private.atina_v2_mime_rounds%rowtype;
 v_now timestamptz;
 v_state jsonb;
 v_requested_clue integer;
BEGIN
 SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A sala não está ativa.'; END IF;
 SELECT * INTO v_host FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND OR NOT v_host.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode atualizar a ronda.'; END IF;
 IF coalesce(v_room.game_state->>'mode','')<>'mimicas' OR jsonb_typeof(p_state)<>'object' THEN
  RAISE EXCEPTION 'Publicação de estado arbitrário não é permitida.';
 END IF;
 SELECT * INTO v_round FROM private.atina_v2_mime_rounds
 WHERE room_id=p_room_id ORDER BY round_number DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND OR v_round.locked THEN RAISE EXCEPTION 'A ronda já terminou.'; END IF;
 v_now:=clock_timestamp();
 IF v_round.deadline_at IS NOT NULL AND v_round.deadline_at<=v_now THEN
  RAISE EXCEPTION 'O tempo desta ronda terminou.';
 END IF;
 v_state:=v_room.game_state;
 v_requested_clue:=coalesce((p_state->>'clue_index')::integer,v_round.clue_index);
 IF coalesce((p_state->>'started')::boolean,false) AND v_round.started_at IS NULL THEN
  UPDATE private.atina_v2_mime_rounds SET started_at=v_now,
    deadline_at=CASE WHEN duration_seconds=0 THEN NULL ELSE v_now+make_interval(secs=>duration_seconds) END,
    updated_at=v_now
  WHERE room_id=p_room_id AND round_number=v_round.round_number
  RETURNING * INTO v_round;
  v_state:=jsonb_set(v_state,'{started}','true'::jsonb,true);
  v_state:=jsonb_set(v_state,'{deadline}',to_jsonb(CASE WHEN v_round.deadline_at IS NULL THEN 0 ELSE floor(extract(epoch FROM v_round.deadline_at)*1000)::bigint END),true);
 ELSIF v_requested_clue=v_round.clue_index+1 AND v_requested_clue BETWEEN 1 AND 4 THEN
  UPDATE private.atina_v2_mime_rounds SET clue_index=v_requested_clue,updated_at=v_now
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
 UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
 RETURN v_state;
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_resolve_mime_round(
 p_room_id uuid,p_token text,p_correct boolean,p_points integer,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_host public.atina_v2_room_players%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_round private.atina_v2_mime_rounds%rowtype;
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
 SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id AND status='playing' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
 SELECT * INTO v_host FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND OR NOT v_host.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode terminar a ronda.'; END IF;
 SELECT * INTO v_round FROM private.atina_v2_mime_rounds
 WHERE room_id=p_room_id ORDER BY round_number DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND OR v_round.locked THEN RAISE EXCEPTION 'A ronda já terminou.'; END IF;
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
 SELECT team_label INTO v_team FROM public.atina_v2_room_players WHERE id=v_rep AND room_id=p_room_id;
 IF v_correct THEN
  IF v_round.deadline_at IS NOT NULL THEN
   v_remaining:=greatest(0,ceil(extract(epoch FROM (v_round.deadline_at-v_now)))::integer);
  END IF;
  v_points:=(ARRAY[20,16,12,8,5])[v_round.clue_index+1]
    +CASE WHEN v_round.duration_seconds>0 THEN floor(v_remaining/10)::integer ELSE 0 END;
  IF v_team IS NOT NULL THEN
   UPDATE public.atina_v2_room_players SET score=score+v_points
   WHERE room_id=p_room_id AND team_label=v_team;
   INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
   SELECT p_room_id,id,v_round.round_number,true,v_points,v_now
   FROM public.atina_v2_room_players WHERE room_id=p_room_id AND team_label=v_team;
  ELSE
   UPDATE public.atina_v2_room_players SET score=score+v_points
   WHERE room_id=p_room_id AND id<>v_rep;
   INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
   SELECT p_room_id,id,v_round.round_number,true,v_points,v_now
   FROM public.atina_v2_room_players WHERE room_id=p_room_id AND id<>v_rep;
  END IF;
 END IF;
 UPDATE private.atina_v2_mime_rounds SET locked=true,outcome=v_reason,
  points_awarded=v_points,updated_at=v_now
 WHERE room_id=p_room_id AND round_number=v_round.round_number;
 v_state:=v_room.game_state;
 v_state:=jsonb_set(v_state,'{locked}','true'::jsonb,true);
 v_state:=jsonb_set(v_state,'{deadline}','0'::jsonb,true);
 v_state:=jsonb_set(v_state,'{answer}',to_jsonb(v_card.word),true);
 v_state:=jsonb_set(v_state,'{correct}',to_jsonb(v_correct),true);
 v_state:=jsonb_set(v_state,'{points_awarded}',to_jsonb(v_points),true);
 v_state:=jsonb_set(v_state,'{feedback}',to_jsonb(CASE WHEN v_correct THEN 'Acertaram! +'||v_points||' pontos.' WHEN v_reason='timeout' THEN 'Tempo esgotado.' ELSE 'Palavra passada.' END),true);
 v_state:=jsonb_set(v_state,'{revision}',to_jsonb(coalesce((v_state->>'revision')::integer,0)+1),true);
 UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
 RETURN v_state;
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_finish_mime_room(p_room_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_host public.atina_v2_room_players%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_round private.atina_v2_mime_rounds%rowtype;
 v_results jsonb;
 v_state jsonb;
BEGIN
 SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sala não encontrada.'; END IF;
 SELECT * INTO v_host FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND OR NOT v_host.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode finalizar a partida.'; END IF;
 SELECT * INTO v_round FROM private.atina_v2_mime_rounds
 WHERE room_id=p_room_id ORDER BY round_number DESC LIMIT 1 FOR UPDATE;
 IF v_room.status<>'playing' OR coalesce(v_room.game_state->>'mode','')<>'mimicas'
  OR NOT FOUND OR NOT v_round.locked
  OR v_round.round_number<(SELECT count(*) FROM private.atina_mime_cards)-1 THEN
  RAISE EXCEPTION 'A partida ainda não terminou.';
 END IF;
 INSERT INTO public.atina_v2_room_results(room_id,player_id,nickname,team_label,score)
 SELECT p_room_id,p.id,p.nickname,p.team_label,p.score FROM public.atina_v2_room_players p WHERE p.room_id=p_room_id
 ON CONFLICT(room_id,player_id) DO UPDATE SET nickname=excluded.nickname,team_label=excluded.team_label,score=excluded.score,completed_at=clock_timestamp();
 SELECT coalesce(jsonb_agg(jsonb_build_object('nickname',nickname,'team',team_label,'score',score) ORDER BY score DESC),'[]'::jsonb)
 INTO v_results FROM public.atina_v2_room_results WHERE room_id=p_room_id;
 v_state:=jsonb_set(v_room.game_state,'{finished}','true'::jsonb,true);
 v_state:=jsonb_set(v_state,'{revision}',to_jsonb(coalesce((v_state->>'revision')::integer,0)+1),true);
 UPDATE public.atina_v2_rooms SET status='finished',game_state=v_state,state_version=state_version+1 WHERE id=p_room_id;
 RETURN jsonb_build_object('finished',true,'results',v_results,'game_state',v_state);
END;
$function$;

-- Reconcile expired Mímicas deadlines during the normal room-state polling.
CREATE OR REPLACE FUNCTION public.atina_v2_room_state(p_room_id uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_me public.atina_v2_room_players%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_game private.atina_v2_room_game_state%rowtype;
 v_mime private.atina_v2_mime_rounds%rowtype;
 v_players jsonb;
 v_team_proposal jsonb;
 v_team text;
 v_now timestamptz;
 v_state jsonb;
 v_card private.atina_mime_cards%rowtype;
 v_pause jsonb;
 v_player_used integer := 0;
 v_team_used integer := 0;
BEGIN
 SELECT * INTO v_me FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
 SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sala não encontrada.'; END IF;
 v_pause := v_room.game_state->'pause';
 IF v_pause IS NOT NULL AND (v_pause->>'ends_at')::timestamptz <= clock_timestamp() THEN
  v_now := clock_timestamp();
  v_state := jsonb_set(
    jsonb_set(v_room.game_state-'pause','{deadline}',
      to_jsonb(CASE WHEN coalesce((v_pause->>'remaining_seconds')::integer,0)>0
        THEN floor(extract(epoch FROM v_now)*1000)::bigint
             + coalesce((v_pause->>'remaining_seconds')::integer,0)*1000
        ELSE 0 END),true),
    '{revision}',to_jsonb(coalesce((v_room.game_state->>'revision')::integer,0)+1),true);
  UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now
   WHERE id=p_room_id RETURNING * INTO v_room;
 END IF;
 SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
 IF FOUND AND v_game.status='active' AND NOT v_game.round_locked
    AND v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=clock_timestamp() THEN
  UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=clock_timestamp() WHERE room_id=p_room_id;
  v_state:=private.atina_v2_room_public_state(p_room_id)||jsonb_build_object('feedback','Tempo esgotado.','locked',true);
  UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=clock_timestamp() WHERE id=p_room_id RETURNING * INTO v_room;
 END IF;
 IF coalesce(v_room.game_state->>'mode','')='mimicas' THEN
  SELECT * INTO v_mime FROM private.atina_v2_mime_rounds
  WHERE room_id=p_room_id ORDER BY round_number DESC LIMIT 1 FOR UPDATE;
  v_now:=clock_timestamp();
  IF FOUND AND NOT v_mime.locked AND v_mime.deadline_at IS NOT NULL AND v_mime.deadline_at<=v_now THEN
   UPDATE private.atina_v2_mime_rounds SET locked=true,outcome='timeout',updated_at=v_now
   WHERE room_id=p_room_id AND round_number=v_mime.round_number;
   SELECT * INTO v_card FROM private.atina_mime_cards WHERE id=v_mime.card_id;
   v_state:=v_room.game_state||jsonb_build_object(
    'locked',true,'deadline',0,'answer',v_card.word,'correct',false,
    'points_awarded',0,'feedback','Tempo esgotado.',
    'revision',coalesce((v_room.game_state->>'revision')::integer,0)+1
   );
   UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id RETURNING * INTO v_room;
  END IF;
 END IF;
 v_now:=clock_timestamp();
 UPDATE public.atina_v2_room_players SET last_seen_at=v_now WHERE id=v_me.id;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'nickname',p.nickname,'is_host',p.is_host,'ready',p.ready,'team',p.team_label,'score',p.score) ORDER BY p.created_at,p.id),'[]'::jsonb)
 INTO v_players FROM public.atina_v2_room_players p WHERE p.room_id=p_room_id;
 v_team:=v_me.team_label;
 IF v_team IS NOT NULL THEN
  SELECT jsonb_build_object('id',pr.id,'team',pr.team_label,'proposer_id',pr.proposer_id,'proposer',pp.nickname,'answer',pr.answer_text,'status',pr.status,
   'votes',coalesce((SELECT jsonb_agg(jsonb_build_object('player_id',v.player_id,'agrees',v.agrees) ORDER BY v.created_at) FROM public.atina_v2_room_team_votes v WHERE v.proposal_id=pr.id),'[]'::jsonb))
  INTO v_team_proposal FROM public.atina_v2_room_team_proposals pr JOIN public.atina_v2_room_players pp ON pp.id=pr.proposer_id
  WHERE pr.room_id=p_room_id AND pr.team_label=v_team AND pr.challenge_index=coalesce((v_room.game_state->>'pos')::integer,-1)
  ORDER BY pr.created_at DESC LIMIT 1;
 END IF;
 SELECT coalesce(used_seconds,0) INTO v_player_used
 FROM private.atina_v2_room_timeout_budgets
 WHERE room_id=p_room_id AND scope='player' AND scope_key=v_me.id::text;
 SELECT coalesce(used_seconds,0) INTO v_team_used
 FROM private.atina_v2_room_timeout_budgets
 WHERE room_id=p_room_id AND scope='team' AND scope_key=v_team;
 RETURN jsonb_build_object('room_id',v_room.id,'code',v_room.code,'status',v_room.status,'max_players',v_room.max_players,
  'is_host',v_me.is_host,'player_id',v_me.id,'ready',v_me.ready,'team',v_team,'my_score',v_me.score,'players',v_players,
  'game_state',v_room.game_state,'team_proposal',v_team_proposal,
  'timeouts',jsonb_build_object('player_remaining_seconds',greatest(0,3600-coalesce(v_player_used,0)),
   'team_remaining_seconds',CASE WHEN v_team IS NULL THEN 0 ELSE greatest(0,3600-coalesce(v_team_used,0)) END));
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_start_mime_round(uuid,text,integer,uuid,integer) FROM public;
REVOKE ALL ON FUNCTION public.atina_v2_get_mime_secret(uuid,text) FROM public;
REVOKE ALL ON FUNCTION public.atina_v2_publish_game_state(uuid,text,jsonb) FROM public;
REVOKE ALL ON FUNCTION public.atina_v2_resolve_mime_round(uuid,text,boolean,integer,text) FROM public;
REVOKE ALL ON FUNCTION public.atina_v2_finish_mime_room(uuid,text) FROM public;
REVOKE ALL ON FUNCTION public.atina_v2_room_state(uuid,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_start_mime_round(uuid,text,integer,uuid,integer) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_get_mime_secret(uuid,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_publish_game_state(uuid,text,jsonb) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_resolve_mime_round(uuid,text,boolean,integer,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_finish_mime_room(uuid,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_room_state(uuid,text) TO anon,authenticated;


-- Source 20261031223119_017_mimicas_server_clock_guards.sql, isolated in v2 namespace.
-- Mímicas: the server clock starts only on the host's explicit start action.
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
  IF coalesce(v_room.game_state->>'mode','')<>'pending'
     OR EXISTS(SELECT 1 FROM private.atina_v2_mime_rounds WHERE room_id=p_room_id) THEN
   RAISE EXCEPTION 'A partida não está preparada para iniciar Mímicas.';
  END IF;
 ELSE
  SELECT * INTO v_prev FROM private.atina_v2_mime_rounds
  WHERE room_id=p_room_id AND round_number=p_round_number-1 FOR UPDATE;
  IF coalesce(v_room.game_state->>'mode','')<>'mimicas'
     OR coalesce((v_room.game_state->>'round')::integer,-1)<>p_round_number-1
     OR coalesce((v_room.game_state->>'locked')::boolean,false)=false
     OR NOT FOUND OR NOT v_prev.locked THEN
   RAISE EXCEPTION 'A ronda anterior ainda não terminou.';
  END IF;
 END IF;
 SELECT * INTO v_card FROM private.atina_mime_cards c
 WHERE NOT EXISTS(SELECT 1 FROM private.atina_v2_mime_rounds r WHERE r.room_id=p_room_id AND r.card_id=c.id)
 ORDER BY random() LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'Não existem mais cartões inéditos nesta partida.'; END IF;
 v_now:=clock_timestamp();
 INSERT INTO private.atina_v2_mime_rounds(room_id,round_number,card_id,representative_id,started_at,deadline_at,duration_seconds)
 VALUES(p_room_id,p_round_number,v_card.id,v_rep.id,NULL,NULL,p_duration_seconds);
 v_state:=jsonb_build_object(
  'mode','mimicas','round',p_round_number,'total_rounds',v_total,
  'representative_id',v_rep.id,'representative_name',v_rep.nickname,
  'team_label',v_rep.team_label,'category',v_card.category,
  'clues',jsonb_build_array(v_card.clues->0),'clue_index',0,
  'duration_seconds',p_duration_seconds,'started',false,'locked',false,
  'deadline',0,'revision',coalesce((v_room.game_state->>'revision')::integer,0)+1
 );
 UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
 RETURN v_state;
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_publish_game_state(p_room_id uuid,p_token text,p_state jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_host public.atina_v2_room_players%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_round private.atina_v2_mime_rounds%rowtype;
 v_now timestamptz;
 v_state jsonb;
 v_requested_clue integer;
BEGIN
 SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A sala não está ativa.'; END IF;
 SELECT * INTO v_host FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND OR NOT v_host.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode atualizar a ronda.'; END IF;
 IF coalesce(v_room.game_state->>'mode','')<>'mimicas' OR jsonb_typeof(p_state)<>'object' THEN
  RAISE EXCEPTION 'Publicação de estado arbitrário não é permitida.';
 END IF;
 SELECT * INTO v_round FROM private.atina_v2_mime_rounds
 WHERE room_id=p_room_id ORDER BY round_number DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND OR v_round.locked THEN RAISE EXCEPTION 'A ronda já terminou.'; END IF;
 v_now:=clock_timestamp();
 IF v_round.deadline_at IS NOT NULL AND v_round.deadline_at<=v_now THEN
  RAISE EXCEPTION 'O tempo desta ronda terminou.';
 END IF;
 v_state:=v_room.game_state;
 v_requested_clue:=coalesce((p_state->>'clue_index')::integer,v_round.clue_index);
 IF coalesce((p_state->>'started')::boolean,false) AND v_round.started_at IS NULL THEN
  UPDATE private.atina_v2_mime_rounds SET started_at=v_now,
    deadline_at=CASE WHEN duration_seconds=0 THEN NULL ELSE v_now+make_interval(secs=>duration_seconds) END,
    updated_at=v_now
  WHERE room_id=p_room_id AND round_number=v_round.round_number
  RETURNING * INTO v_round;
  v_state:=jsonb_set(v_state,'{started}','true'::jsonb,true);
  v_state:=jsonb_set(v_state,'{deadline}',to_jsonb(CASE WHEN v_round.deadline_at IS NULL THEN 0 ELSE floor(extract(epoch FROM v_round.deadline_at)*1000)::bigint END),true);
 ELSIF v_round.started_at IS NOT NULL AND v_requested_clue=v_round.clue_index+1 AND v_requested_clue BETWEEN 1 AND 4 THEN
  UPDATE private.atina_v2_mime_rounds SET clue_index=v_requested_clue,updated_at=v_now
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
 UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
 RETURN v_state;
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_resolve_mime_round(
 p_room_id uuid,p_token text,p_correct boolean,p_points integer,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_host public.atina_v2_room_players%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_round private.atina_v2_mime_rounds%rowtype;
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
 SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id AND status='playing' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
 SELECT * INTO v_host FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND OR NOT v_host.is_host THEN RAISE EXCEPTION 'Só o anfitrião pode terminar a ronda.'; END IF;
 SELECT * INTO v_round FROM private.atina_v2_mime_rounds
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
 SELECT team_label INTO v_team FROM public.atina_v2_room_players WHERE id=v_rep AND room_id=p_room_id;
 IF v_correct THEN
  IF v_round.deadline_at IS NOT NULL THEN
   v_remaining:=greatest(0,ceil(extract(epoch FROM (v_round.deadline_at-v_now)))::integer);
  END IF;
  v_points:=(ARRAY[20,16,12,8,5])[v_round.clue_index+1]
    +CASE WHEN v_round.duration_seconds>0 THEN floor(v_remaining/10)::integer ELSE 0 END;
  IF v_team IS NOT NULL THEN
   UPDATE public.atina_v2_room_players SET score=score+v_points
   WHERE room_id=p_room_id AND team_label=v_team;
   INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
   SELECT p_room_id,id,v_round.round_number,true,v_points,v_now
   FROM public.atina_v2_room_players WHERE room_id=p_room_id AND team_label=v_team;
  ELSE
   UPDATE public.atina_v2_room_players SET score=score+v_points
   WHERE room_id=p_room_id AND id<>v_rep;
   INSERT INTO public.atina_v2_room_answers(room_id,player_id,challenge_index,is_correct,points,created_at)
   SELECT p_room_id,id,v_round.round_number,true,v_points,v_now
   FROM public.atina_v2_room_players WHERE room_id=p_room_id AND id<>v_rep;
  END IF;
 END IF;
 UPDATE private.atina_v2_mime_rounds SET locked=true,outcome=v_reason,points_awarded=v_points,updated_at=v_now
 WHERE room_id=p_room_id AND round_number=v_round.round_number;
 v_state:=v_room.game_state;
 v_state:=jsonb_set(v_state,'{locked}','true'::jsonb,true);
 v_state:=jsonb_set(v_state,'{deadline}','0'::jsonb,true);
 v_state:=jsonb_set(v_state,'{answer}',to_jsonb(v_card.word),true);
 v_state:=jsonb_set(v_state,'{correct}',to_jsonb(v_correct),true);
 v_state:=jsonb_set(v_state,'{points_awarded}',to_jsonb(v_points),true);
 v_state:=jsonb_set(v_state,'{feedback}',to_jsonb(CASE WHEN v_correct THEN 'Acertaram! +'||v_points||' pontos.' WHEN v_reason='timeout' THEN 'Tempo esgotado.' ELSE 'Palavra passada.' END),true);
 v_state:=jsonb_set(v_state,'{revision}',to_jsonb(coalesce((v_state->>'revision')::integer,0)+1),true);
 UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
 RETURN v_state;
END;
$function$;


-- Source 20261031223208_018_mimicas_round_indexes.sql, isolated in v2 namespace.
-- Cover Mímicas round foreign keys flagged by Supabase Advisor.
CREATE INDEX IF NOT EXISTS atina_v2_mime_rounds_room_representative_idx
  ON private.atina_v2_mime_rounds(room_id,representative_id);
CREATE INDEX IF NOT EXISTS atina_v2_mime_rounds_card_id_idx
  ON private.atina_v2_mime_rounds(card_id);


-- Independent timeout budget for v2 rooms; legacy budgets remain untouched.
CREATE TABLE private.atina_v2_room_timeout_budgets (
 room_id uuid NOT NULL REFERENCES public.atina_v2_rooms(id) ON DELETE CASCADE,
 scope text NOT NULL CHECK(scope IN ('player','team')),
 scope_key text NOT NULL,
 used_seconds integer NOT NULL DEFAULT 0 CHECK(used_seconds BETWEEN 0 AND 3600),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(room_id,scope,scope_key)
);
ALTER TABLE private.atina_v2_room_timeout_budgets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.atina_v2_room_timeout_budgets FROM public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.atina_v2_request_timeout(
 p_room_id uuid,p_token text,p_scope text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
 v_player public.atina_v2_room_players%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_scope_key text;
 v_used integer;
 v_deadline bigint;
 v_remaining integer := 0;
 v_now timestamptz := clock_timestamp();
 v_pause jsonb;
 v_state jsonb;
BEGIN
 IF p_scope NOT IN ('player','team') THEN RAISE EXCEPTION 'Tipo de pausa inválido.'; END IF;
 SELECT * INTO v_player FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
 IF p_scope='team' AND v_player.team_label IS NULL THEN
  RAISE EXCEPTION 'Só jogadores integrados numa equipa podem usar a pausa da equipa.';
 END IF;
 v_scope_key:=CASE WHEN p_scope='player' THEN v_player.id::text ELSE v_player.team_label END;
 SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_room.status<>'playing' THEN RAISE EXCEPTION 'A partida não está ativa.'; END IF;
 v_pause:=v_room.game_state->'pause';
 IF v_pause IS NOT NULL AND (v_pause->>'ends_at')::timestamptz>v_now THEN
  RAISE EXCEPTION 'Já existe uma pausa global ativa.';
 ELSIF v_pause IS NOT NULL THEN
  v_remaining:=greatest(0,coalesce((v_pause->>'remaining_seconds')::integer,0));
  v_state:=jsonb_set(jsonb_set(v_room.game_state-'pause','{deadline}',
   to_jsonb(CASE WHEN v_remaining>0 THEN floor(extract(epoch FROM v_now)*1000)::bigint+v_remaining*1000 ELSE 0 END),true),
   '{revision}',to_jsonb(coalesce((v_room.game_state->>'revision')::integer,0)+1),true);
  UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1 WHERE id=p_room_id RETURNING * INTO v_room;
 END IF;
 v_deadline:=nullif(v_room.game_state->>'deadline','')::bigint;
 IF v_deadline IS NOT NULL AND v_deadline>0 THEN
  v_remaining:=greatest(0,ceil((v_deadline-floor(extract(epoch FROM v_now)*1000))/1000.0)::integer);
  IF v_remaining=0 THEN RAISE EXCEPTION 'O tempo deste desafio já terminou.'; END IF;
 ELSE v_remaining:=0;
 END IF;
 INSERT INTO private.atina_v2_room_timeout_budgets(room_id,scope,scope_key)
 VALUES(p_room_id,p_scope,v_scope_key) ON CONFLICT(room_id,scope,scope_key) DO NOTHING;
 SELECT used_seconds INTO v_used FROM private.atina_v2_room_timeout_budgets
 WHERE room_id=p_room_id AND scope=p_scope AND scope_key=v_scope_key FOR UPDATE;
 IF v_used+900>3600 THEN RAISE EXCEPTION 'Já esgotaste o tempo de pausa disponível neste âmbito.'; END IF;
 UPDATE private.atina_v2_room_timeout_budgets SET used_seconds=used_seconds+900,updated_at=v_now
 WHERE room_id=p_room_id AND scope=p_scope AND scope_key=v_scope_key;
 v_pause:=jsonb_build_object('scope',p_scope,'requester',v_player.nickname,'requester_id',v_player.id,
  'started_at',v_now,'ends_at',v_now+interval '15 minutes','duration_seconds',900,'remaining_seconds',v_remaining);
 v_state:=jsonb_set(jsonb_set(jsonb_set(v_room.game_state,'{deadline}','0'::jsonb,true),
  '{pause}',v_pause,true),'{revision}',to_jsonb(coalesce((v_room.game_state->>'revision')::integer,0)+1),true);
 UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1 WHERE id=p_room_id;
 RETURN jsonb_build_object('paused',true,'pause',v_pause,'remaining_seconds',3600-(v_used+900));
END;
$function$;
REVOKE ALL ON FUNCTION public.atina_v2_request_timeout(uuid,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_v2_request_timeout(uuid,text,text) TO anon,authenticated;

