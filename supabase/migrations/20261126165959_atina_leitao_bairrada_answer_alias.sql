-- Keep the reported regional-name variant as a curated alias on the
-- challenge itself. This migration must run before the existing 17:00
-- legacy-matcher migration, whose regression test validates challenge 1505.
DO $migration$
DECLARE
  v_updated integer;
BEGIN
  UPDATE private.atina_challenges
  SET accepted_answers = coalesce(accepted_answers, '[]'::jsonb)
    || jsonb_build_array('Leitão a Bairrada')
  WHERE challenge_id = 1505
    AND active
    AND private.atina_v2_normalize_answer(answer) =
        private.atina_v2_normalize_answer('Leitão da Bairrada')
    AND NOT coalesce(accepted_answers, '[]'::jsonb) ? 'Leitão a Bairrada';

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 AND NOT EXISTS (
    SELECT 1
    FROM private.atina_challenges
    WHERE challenge_id = 1505
      AND active
      AND private.atina_v2_normalize_answer(answer) =
          private.atina_v2_normalize_answer('Leitão da Bairrada')
      AND coalesce(accepted_answers, '[]'::jsonb) ? 'Leitão a Bairrada'
  ) THEN
    RAISE EXCEPTION 'Expected active challenge 1505 with canonical answer Leitão da Bairrada.';
  END IF;
END
$migration$;

DO $tests$
BEGIN
  IF NOT private.atina_challenge_answer_matches(1505, 'Leitão a Bairrada') THEN
    RAISE EXCEPTION 'Curated regional-name alias must be accepted.';
  END IF;

  IF private.atina_challenge_answer_matches(1505, 'Leitão')
     OR private.atina_challenge_answer_matches(1505, 'Leitão de Lisboa') THEN
    RAISE EXCEPTION 'Curated alias must not weaken content-word validation.';
  END IF;
END
$tests$;
