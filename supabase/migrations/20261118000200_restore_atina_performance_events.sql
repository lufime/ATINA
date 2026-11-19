-- Restore the performance-event schema and capture triggers required by QI ranking.
-- This migration is idempotent for environments where the objects already exist.

create table if not exists private.atina_performance_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null,
  nickname text not null,
  source text not null check (source = any (array['local'::text, 'room'::text])),
  source_id uuid not null,
  challenge_position integer not null,
  challenge_id integer not null,
  difficulty text not null,
  outcome text not null check (outcome = any (array['correct'::text, 'wrong'::text, 'timeout'::text, 'pass'::text])),
  response_ms integer,
  created_at timestamptz not null default clock_timestamp(),
  constraint atina_performance_events_source_source_id_actor_id_challeng_key
    unique (source, source_id, actor_id, challenge_position)
);

create index if not exists atina_performance_events_actor_created_idx
  on private.atina_performance_events (actor_id, created_at desc);
create index if not exists atina_performance_events_created_idx
  on private.atina_performance_events (created_at desc);

create or replace function private.atina_log_local_performance()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare v_player_id uuid; v_nickname text;
begin
  select o.player_id,p.nickname into v_player_id,v_nickname
    from private.atina_xp_session_owners o
    join private.atina_players p on p.id=o.player_id
   where o.session_id=new.session_id;
  if v_player_id is null or lower(btrim(coalesce(v_nickname,'')))='admin' then return new; end if;
  insert into private.atina_performance_events
    (actor_id,nickname,source,source_id,challenge_position,challenge_id,difficulty,outcome,response_ms,created_at)
  values(v_player_id,v_nickname,'local',new.session_id,new.challenge_position,
    new.challenge_id,new.difficulty,new.outcome,new.response_ms,new.created_at)
  on conflict(source,source_id,actor_id,challenge_position) do update
    set outcome=excluded.outcome,difficulty=excluded.difficulty,
        response_ms=coalesce(excluded.response_ms,private.atina_performance_events.response_ms);
  return new;
end;
$function$;

create or replace function private.atina_log_room_performance()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare v_player public.atina_v2_room_players;
begin
  select * into v_player from public.atina_v2_room_players
   where id=new.player_id and room_id=new.room_id;
  if not found then return new; end if;
  insert into private.atina_performance_events
    (actor_id,nickname,source,source_id,challenge_position,challenge_id,difficulty,outcome,response_ms,created_at)
  values(v_player.id,v_player.nickname,'room',new.room_id,new.challenge_index+1,
    new.challenge_id,new.difficulty,case when new.is_correct then 'correct' else 'wrong' end,
    new.response_ms,new.created_at)
  on conflict(source,source_id,actor_id,challenge_position) do update
    set outcome=excluded.outcome,difficulty=excluded.difficulty,
        response_ms=coalesce(excluded.response_ms,private.atina_performance_events.response_ms);
  return new;
end;
$function$;

drop trigger if exists atina_log_local_performance on private.atina_difficulty_history;
create trigger atina_log_local_performance
  after insert on private.atina_difficulty_history
  for each row execute function private.atina_log_local_performance();

drop trigger if exists atina_log_room_performance on public.atina_v2_room_answers;
create trigger atina_log_room_performance
  after insert on public.atina_v2_room_answers
  for each row execute function private.atina_log_room_performance();
