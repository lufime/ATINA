-- Adaptive difficulty and per-player challenge rotation for registered Solo/Mix profiles.
-- More errors move the profile toward hard; fewer errors move it toward easy.
-- The fixed Admin pseudonym is deliberately excluded from learning and rotation history.

create table if not exists private.atina_difficulty_history (
  id bigint generated always as identity primary key,
  player_id uuid not null references private.atina_players(id) on delete cascade,
  session_id uuid not null references private.atina_v2_local_sessions(id) on delete cascade,
  challenge_position integer not null check (challenge_position > 0),
  challenge_id integer not null,
  difficulty text not null check (difficulty in ('easy','medium','hard')),
  outcome text not null check (outcome in ('wrong','timeout','pass','correct')),
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists atina_difficulty_history_player_recent_idx
  on private.atina_difficulty_history (player_id, created_at desc);
create index if not exists atina_difficulty_history_player_challenge_idx
  on private.atina_difficulty_history (player_id, challenge_id, created_at desc);

alter table private.atina_difficulty_history enable row level security;
revoke all on table private.atina_difficulty_history from public, anon, authenticated;

create or replace function private.atina_record_difficulty_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player_id uuid;
  v_nickname text;
  v_outcome text;
begin
  v_outcome := new.last_result ->> 'outcome';
  if v_outcome not in ('wrong','timeout','pass','correct') then
    return new;
  end if;

  -- Wrong answers remain unlocked so every failed attempt is recorded.
  -- The trigger only runs when last_result is assigned by an answer RPC.
  if v_outcome = 'wrong' and new.round_locked then
    return new;
  end if;
  if v_outcome <> 'wrong' and not new.round_locked then
    return new;
  end if;

  select o.player_id, p.nickname
    into v_player_id, v_nickname
    from private.atina_xp_session_owners o
    join private.atina_players p on p.id = o.player_id
   where o.session_id = new.id;

  if v_player_id is null or lower(btrim(coalesce(v_nickname,''))) = 'admin' then
    return new;
  end if;

  insert into private.atina_difficulty_history
    (player_id, session_id, challenge_position, challenge_id, difficulty, outcome)
  values
    (v_player_id, new.id, new.position, new.challenge_queue[new.position],
     new.difficulty, v_outcome);

  return new;
end;
$function$;

revoke all on function private.atina_record_difficulty_result() from public, anon, authenticated;
drop trigger if exists atina_record_difficulty_result on private.atina_v2_local_sessions;
create trigger atina_record_difficulty_result
after update of last_result on private.atina_v2_local_sessions
for each row execute function private.atina_record_difficulty_result();

create or replace function private.atina_apply_adaptive_difficulty()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player private.atina_players;
  v_session private.atina_v2_local_sessions;
  v_total integer := 0;
  v_errors integer := 0;
  v_difficulty text;
  v_queue integer[];
begin
  select * into v_player
    from private.atina_players
   where id = new.player_id;

  if not found or lower(btrim(v_player.nickname)) = 'admin' then
    return new;
  end if;

  select * into v_session
    from private.atina_v2_local_sessions
   where id = new.session_id;

  if not found or v_session.game_mode not in ('solo','mix') then
    return new;
  end if;

  -- Evaluate the latest 20 recorded attempts. Require five observations
  -- before replacing the player's explicitly selected starting difficulty.
  select count(*),
         count(*) filter (where recent.outcome in ('wrong','timeout','pass'))
    into v_total, v_errors
    from (
      select h.outcome
        from private.atina_difficulty_history h
       where h.player_id = new.player_id
       order by h.created_at desc, h.id desc
       limit 20
    ) recent;

  v_difficulty := v_session.difficulty;
  if v_total >= 5 then
    if v_errors::numeric / v_total >= 0.50 then
      v_difficulty := 'hard';
    elsif v_errors::numeric / v_total <= 0.20 then
      v_difficulty := 'easy';
    else
      v_difficulty := 'medium';
    end if;
  end if;

  -- Avoid the player's 20 most recently served challenges. If the pool
  -- is too small, fall back to the complete pool at the chosen level.
  select array_agg(c.challenge_id order by random())
    into v_queue
    from private.atina_challenges c
   where c.active
     and c.difficulty = v_difficulty
     and (v_session.category is null or c.category = v_session.category)
     and not exists (
       select 1
         from (
           select h.challenge_id
             from private.atina_difficulty_history h
            where h.player_id = new.player_id
            order by h.created_at desc, h.id desc
            limit 20
         ) recent
        where recent.challenge_id = c.challenge_id
     );

  if coalesce(cardinality(v_queue),0) = 0 then
    select array_agg(c.challenge_id order by random())
      into v_queue
      from private.atina_challenges c
     where c.active
       and c.difficulty = v_difficulty
       and (v_session.category is null or c.category = v_session.category);
  end if;

  -- Keep the existing valid queue if the adaptive level has no challenges
  -- in this category.
  if coalesce(cardinality(v_queue),0) > 0 then
    update private.atina_v2_local_sessions
       set difficulty = v_difficulty,
           challenge_queue = case
             when game_mode = 'party' then v_queue[1:least(10,cardinality(v_queue))]
             else v_queue
           end,
           position = 1,
           updated_at = clock_timestamp()
     where id = v_session.id;
  end if;

  return new;
end;
$function$;

revoke all on function private.atina_apply_adaptive_difficulty() from public, anon, authenticated;
drop trigger if exists atina_apply_adaptive_difficulty on private.atina_xp_session_owners;
create trigger atina_apply_adaptive_difficulty
after insert on private.atina_xp_session_owners
for each row execute function private.atina_apply_adaptive_difficulty();
