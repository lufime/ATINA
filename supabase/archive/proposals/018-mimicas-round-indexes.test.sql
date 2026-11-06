BEGIN;
SELECT plan(2);
SELECT ok(EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='private' AND indexname='atina_mime_rounds_room_representative_idx'),'representative foreign key has covering index');
SELECT ok(EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='private' AND indexname='atina_mime_rounds_card_id_idx'),'card foreign key has covering index');
SELECT * FROM finish();
ROLLBACK;
