-- Align Detective adventure with the ATINA V2 room system used by the web client.
-- The private Detective tables are empty at this point; all constraints are moved atomically.
ALTER TABLE private.atina_detective_sessions DROP CONSTRAINT atina_detective_sessions_room_id_fkey;
ALTER TABLE private.atina_detective_sessions ADD CONSTRAINT atina_detective_sessions_room_id_fkey
 FOREIGN KEY (room_id) REFERENCES public.atina_v2_rooms(id) ON DELETE CASCADE;
ALTER TABLE private.atina_detective_sessions DROP CONSTRAINT atina_detective_sessions_detective_player_id_fkey;
ALTER TABLE private.atina_detective_sessions ADD CONSTRAINT atina_detective_sessions_detective_player_id_fkey
 FOREIGN KEY (detective_player_id) REFERENCES public.atina_v2_room_players(id) ON DELETE SET NULL;
ALTER TABLE private.atina_detective_characters DROP CONSTRAINT atina_detective_characters_player_id_fkey;
ALTER TABLE private.atina_detective_characters ADD CONSTRAINT atina_detective_characters_player_id_fkey
 FOREIGN KEY (player_id) REFERENCES public.atina_v2_room_players(id) ON DELETE SET NULL;
ALTER TABLE private.atina_detective_discoveries DROP CONSTRAINT atina_detective_discoveries_discovered_by_player_id_fkey;
ALTER TABLE private.atina_detective_discoveries ADD CONSTRAINT atina_detective_discoveries_discovered_by_player_id_fkey
 FOREIGN KEY (discovered_by_player_id) REFERENCES public.atina_v2_room_players(id) ON DELETE SET NULL;
ALTER TABLE private.atina_detective_interactions DROP CONSTRAINT atina_detective_interactions_player_id_fkey;
ALTER TABLE private.atina_detective_interactions ADD CONSTRAINT atina_detective_interactions_player_id_fkey
 FOREIGN KEY (player_id) REFERENCES public.atina_v2_room_players(id) ON DELETE SET NULL;

DO $$
DECLARE fn text; def text;
BEGIN
 FOREACH fn IN ARRAY ARRAY[
  'atina_detective_start','atina_detective_state','atina_detective_move','atina_detective_discover',
  'atina_detective_interrogate','atina_detective_adjunct','atina_detective_accuse'
 ] LOOP
  SELECT pg_get_functiondef(p.oid) INTO def
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname=fn
  ORDER BY p.oid DESC LIMIT 1;
  IF def IS NULL THEN RAISE EXCEPTION 'Missing Detective RPC: %',fn; END IF;
  def:=replace(def,'public.atina_room_players','public.atina_v2_room_players');
  def:=replace(def,'public.atina_rooms','public.atina_v2_rooms');
  EXECUTE def;
 END LOOP;
END $$;
