-- Additional deterministic challenge data for the disposable RPC browser suite only.
-- This file is never applied to a hosted Supabase project.
INSERT INTO private.atina_challenges
  (challenge_id,category,emoji,clues,answer,accepted_answers,image_url,active,difficulty)
VALUES
  (2,'fixture','🧪',
   '["pista 1b","pista 2b","pista 3b","pista 4b","pista 5b"]'::jsonb,
   'teste-dois','["teste-dois"]'::jsonb,NULL,true,'easy')
ON CONFLICT (challenge_id) DO UPDATE
SET category=excluded.category,emoji=excluded.emoji,clues=excluded.clues,
    answer=excluded.answer,accepted_answers=excluded.accepted_answers,
    image_url=excluded.image_url,active=excluded.active,difficulty=excluded.difficulty;
