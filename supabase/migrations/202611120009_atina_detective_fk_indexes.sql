CREATE INDEX IF NOT EXISTS atina_detective_sessions_case_idx ON private.atina_detective_sessions(case_id);
CREATE INDEX IF NOT EXISTS atina_detective_sessions_detective_player_idx ON private.atina_detective_sessions(detective_player_id) WHERE detective_player_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS atina_detective_characters_player_idx ON private.atina_detective_characters(player_id) WHERE player_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS atina_detective_discoveries_discovered_by_idx ON private.atina_detective_discoveries(discovered_by_player_id) WHERE discovered_by_player_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS atina_detective_interactions_player_idx ON private.atina_detective_interactions(player_id) WHERE player_id IS NOT NULL;