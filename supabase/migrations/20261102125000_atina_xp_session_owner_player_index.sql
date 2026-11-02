-- Cover the player_id foreign key on pseudonymous session ownership.
create index if not exists atina_xp_session_owners_player_id_idx
  on private.atina_xp_session_owners (player_id);
