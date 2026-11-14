-- Add context-specific, well-known surname forms for personality challenges.
-- First names are deliberately not accepted automatically: aliases are curated
-- per challenge to avoid ambiguous matches across the ATINA catalogue.
DO $$
DECLARE
  v_aliases jsonb;
  v_item record;
BEGIN
  FOR v_item IN
    SELECT *
    FROM (VALUES
      (0, 'Einstein'),
      (15, 'Mandela'),
      (48, 'Ronaldo'),
      (124, 'Curie'),
      (125, 'Shakespeare'),
      (168, 'Darwin'),
      (183, 'Lovelace'),
      (198, 'Gandhi'),
      (227, 'Kahlo'),
      (242, 'Turing'),
      (311, 'Cabral'),
      (315, 'Galilei'),
      (316, 'Newton'),
      (317, 'Tesla'),
      (318, 'Edison'),
      (319, 'Pasteur'),
      (320, 'Nightingale'),
      (321, 'Parks'),
      (323, 'Yousafzai'),
      (324, 'Earhart'),
      (325, 'Dumont'),
      (327, 'Magalhães'),
      (329, 'Camões'),
      (330, 'Pessoa'),
      (331, 'Saramago'),
      (332, 'Queirós'),
      (333, 'Picasso'),
      (334, 'Van Gogh'),
      (335, 'Monet'),
      (336, 'Mozart'),
      (337, 'Beethoven'),
      (338, 'Chopin'),
      (339, 'Variações'),
      (340, 'Rainha do Fado'),
      (342, 'Ali'),
      (344, 'Jordan'),
      (345, 'Bolt'),
      (346, 'Thunberg'),
      (347, 'Berners-Lee'),
      (348, 'Jobs'),
      (456, 'Armstrong')
    ) AS aliases(challenge_id, alias)
  LOOP
    UPDATE private.atina_challenges AS c
       SET accepted_answers = CASE
         WHEN jsonb_typeof(c.accepted_answers) = 'array' THEN c.accepted_answers
         ELSE '[]'::jsonb
       END || jsonb_build_array(v_item.alias)
     WHERE c.challenge_id = v_item.challenge_id
       AND c.active
       AND NOT EXISTS (
         SELECT 1
         FROM jsonb_array_elements_text(
           CASE WHEN jsonb_typeof(c.accepted_answers) = 'array'
                THEN c.accepted_answers ELSE '[]'::jsonb END
         ) AS existing(value)
         WHERE private.atina_v2_normalize_answer(existing.value)
             = private.atina_v2_normalize_answer(v_item.alias)
       );
  END LOOP;
END;
$$;

-- Regression checks: surname/known form accepted, ambiguous first name not auto-accepted.
DO $tests$
BEGIN
  IF NOT private.atina_v2_challenge_answer_matches(456, 'Armstrong') THEN
    RAISE EXCEPTION 'Expected Armstrong to be accepted for Neil Armstrong.';
  END IF;
  IF NOT private.atina_v2_challenge_answer_matches(318, 'Edison') THEN
    RAISE EXCEPTION 'Expected Edison to be accepted for Thomas Edison.';
  END IF;
  IF private.atina_v2_challenge_answer_matches(456, 'Neil') THEN
    RAISE EXCEPTION 'A first name must not be accepted automatically for Neil Armstrong.';
  END IF;
  IF private.atina_v2_challenge_answer_matches(318, 'Thomas') THEN
    RAISE EXCEPTION 'A first name must not be accepted automatically for Thomas Edison.';
  END IF;
END
$tests$;
