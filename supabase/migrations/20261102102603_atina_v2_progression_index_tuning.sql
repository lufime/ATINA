-- Keep the existing challenge-selection index shared by legacy and v2 sessions.
-- Add a covering index for the new session -> player foreign key.
drop index if exists private.atina_v2_challenges_local_selection_idx;

create index if not exists atina_v2_local_sessions_player_id_idx
  on private.atina_v2_local_sessions (player_id)
  where player_id is not null;
