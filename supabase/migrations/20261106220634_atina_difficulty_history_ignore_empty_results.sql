-- Advancing to a new challenge clears last_result to {}, which is not an attempt.
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
  if v_outcome is null or v_outcome not in ('wrong','timeout','pass','correct') then
    return new;
  end if;

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
