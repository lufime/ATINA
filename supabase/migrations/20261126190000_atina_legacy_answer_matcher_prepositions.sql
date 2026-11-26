-- Apply the same harmless Portuguese article/preposition tolerance to the
-- legacy challenge-answer matcher used by the authoritative game RPCs.
-- Content words remain mandatory; single-word answers are never stripped.

CREATE OR REPLACE FUNCTION private.atina_answer_matches(p_expected text, p_actual text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = ''
AS $function$
DECLARE
  v_expected text := private.atina_normalize_answer(p_expected);
  v_actual text := private.atina_normalize_answer(p_actual);
  v_words_expected text[];
  v_words_actual text[];
  v_used boolean[];
  v_best integer;
  v_best_distance integer;
  v_distance integer;
  v_allowed integer;
  v_fillers text[] := ARRAY[
    'a','as','o','os','um','uma','uns','umas',
    'de','do','da','dos','das',
    'e','em','no','na','nos','nas',
    'por','para','com','ao','aos'
  ]::text[];
BEGIN
  IF v_expected = '' OR v_actual = '' THEN
    RETURN false;
  END IF;
  IF v_expected = v_actual THEN
    RETURN true;
  END IF;

  v_words_expected := string_to_array(v_expected, ' ');
  v_words_actual := string_to_array(v_actual, ' ');

  -- Articles and prepositions are optional only in multi-word answers.
  -- A one-word answer such as "A" or "O" remains meaningful.
  IF cardinality(v_words_expected) > 1 THEN
    SELECT coalesce(array_agg(t.word ORDER BY t.ordinality), ARRAY[]::text[])
      INTO v_words_expected
    FROM unnest(v_words_expected) WITH ORDINALITY AS t(word, ordinality)
    WHERE NOT (t.word = ANY(v_fillers));
  END IF;

  IF cardinality(v_words_actual) > 1 THEN
    SELECT coalesce(array_agg(t.word ORDER BY t.ordinality), ARRAY[]::text[])
      INTO v_words_actual
    FROM unnest(v_words_actual) WITH ORDINALITY AS t(word, ordinality)
    WHERE NOT (t.word = ANY(v_fillers));
  END IF;

  IF cardinality(v_words_expected) = 0 OR cardinality(v_words_actual) = 0 THEN
    RETURN false;
  END IF;
  IF cardinality(v_words_expected) <> cardinality(v_words_actual) THEN
    RETURN false;
  END IF;

  v_used := array_fill(false, ARRAY[cardinality(v_words_actual)]);
  FOR i IN 1..cardinality(v_words_expected) LOOP
    v_best := 0;
    v_best_distance := 3;
    FOR j IN 1..cardinality(v_words_actual) LOOP
      IF NOT v_used[j] THEN
        v_distance := private.atina_levenshtein_bounded(v_words_expected[i], v_words_actual[j]);
        IF v_distance < v_best_distance THEN
          v_best_distance := v_distance;
          v_best := j;
        END IF;
      END IF;
    END LOOP;

    v_allowed := CASE
      WHEN char_length(v_words_expected[i]) >= 8 THEN 2
      WHEN char_length(v_words_expected[i]) >= 4 THEN 1
      ELSE 0
    END;

    IF v_best = 0 OR v_best_distance > v_allowed THEN
      RETURN false;
    END IF;
    v_used[v_best] := true;
  END LOOP;

  RETURN true;
END;
$function$;

-- Regression checks against the exact challenge and against false positives.
DO $tests$
BEGIN
  IF NOT private.atina_challenge_answer_matches(1505, 'Leitão a Bairrada') THEN
    RAISE EXCEPTION 'Expected harmless preposition variation to be accepted.';
  END IF;

  IF private.atina_challenge_answer_matches(1505, 'Leitão')
     OR private.atina_challenge_answer_matches(1505, 'Leitão de Lisboa') THEN
    RAISE EXCEPTION 'False-positive guard regression for challenge 1505.';
  END IF;

  IF NOT private.atina_answer_matches('A letra o', 'letra o')
     OR private.atina_answer_matches('A letra o', 'letra a') THEN
    RAISE EXCEPTION 'Single-letter answer guard regression.';
  END IF;
END
$tests$;

REVOKE ALL ON FUNCTION private.atina_answer_matches(text, text) FROM PUBLIC, anon, authenticated;
