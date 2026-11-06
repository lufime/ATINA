-- Cover the session foreign key used when pruning a player's history.
create index if not exists atina_difficulty_history_session_idx
  on private.atina_difficulty_history (session_id);
