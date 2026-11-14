-- Seed the permanent no-repeat ledger from previously recorded play.
-- For local games, positions up to the current position have already been shown.
insert into private.atina_challenge_exposures(scope_type,scope_key,challenge_id)
select 'player',h.player_id::text,h.challenge_id
  from private.atina_difficulty_history h
 where h.player_id is not null
on conflict(scope_type,scope_key,challenge_id) do nothing;

insert into private.atina_challenge_exposures(scope_type,scope_key,challenge_id)
select 'player',o.player_id::text,s.challenge_queue[pos.position]
  from private.atina_v2_local_sessions s
  join private.atina_xp_session_owners o on o.session_id=s.id
  cross join lateral generate_series(
    1,least(greatest(s.position,0),coalesce(cardinality(s.challenge_queue),0))
  ) as pos(position)
 where o.player_id is not null
on conflict(scope_type,scope_key,challenge_id) do nothing;

-- Room sessions retain their player/team roster. Reconstruct each team's
-- previously presented challenges from the queue positions already reached.
insert into private.atina_challenge_exposures(scope_type,scope_key,challenge_id)
select scopes.scope_type,scopes.scope_key,g.challenge_queue[pos.position]
  from private.atina_v2_room_game_state g
  cross join lateral generate_series(
    1,least(greatest(g.position,0),coalesce(cardinality(g.challenge_queue),0))
  ) as pos(position)
  cross join lateral private.atina_room_challenge_scopes(g.room_id) scopes
on conflict(scope_type,scope_key,challenge_id) do nothing;
