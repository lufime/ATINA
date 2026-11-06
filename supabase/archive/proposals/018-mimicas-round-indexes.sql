-- Cover Mímicas round foreign keys flagged by Supabase Advisor.
CREATE INDEX IF NOT EXISTS atina_mime_rounds_room_representative_idx
  ON private.atina_mime_rounds(room_id,representative_id);
CREATE INDEX IF NOT EXISTS atina_mime_rounds_card_id_idx
  ON private.atina_mime_rounds(card_id);
