-- Improve answer tolerance without exposing answer-checking helpers.
-- The existing matcher already ignores accents and tolerates bounded typos.
-- This update additionally ignores Portuguese articles/prepositions in multi-word
-- answers, so harmless omissions such as "Rio de Janeiro" / "Rio Janeiro" pass.
-- Curated synonyms remain in private.atina_challenges.accepted_answers and are
-- still checked by private.atina_v2_challenge_answer_matches.

create or replace function private.atina_v2_answer_matches(p_expected text, p_actual text)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  v_expected text := private.atina_v2_normalize_answer(p_expected);
  v_actual text := private.atina_v2_normalize_answer(p_actual);
  v_words_expected text[];
  v_words_actual text[];
  v_used boolean[];
  v_best integer;
  v_best_distance integer;
  v_distance integer;
  v_allowed integer;
  v_fillers text[] := array[
    'a','as','o','os','um','uma','uns','umas',
    'de','do','da','dos','das',
    'e','em','no','na','nos','nas',
    'por','para','com','ao','aos'
  ]::text[];
begin
  if v_expected = '' or v_actual = '' then return false; end if;
  if v_expected = v_actual then return true; end if;

  v_words_expected := string_to_array(v_expected, ' ');
  v_words_actual := string_to_array(v_actual, ' ');

  -- Only treat these as optional when the answer has other words.
  -- A one-word answer such as "O" or "A" is never reduced to an empty phrase.
  if cardinality(v_words_expected) > 1 then
    select coalesce(array_agg(t.word order by t.ordinality), array[]::text[])
      into v_words_expected
    from unnest(v_words_expected) with ordinality as t(word, ordinality)
    where not (t.word = any(v_fillers));
  end if;
  if cardinality(v_words_actual) > 1 then
    select coalesce(array_agg(t.word order by t.ordinality), array[]::text[])
      into v_words_actual
    from unnest(v_words_actual) with ordinality as t(word, ordinality)
    where not (t.word = any(v_fillers));
  end if;

  if cardinality(v_words_expected) = 0 or cardinality(v_words_actual) = 0 then
    return false;
  end if;
  if cardinality(v_words_expected) <> cardinality(v_words_actual) then
    return false;
  end if;

  v_used := array_fill(false, array[cardinality(v_words_actual)]);
  for i in 1..cardinality(v_words_expected) loop
    v_best := 0;
    v_best_distance := 3;
    for j in 1..cardinality(v_words_actual) loop
      if not v_used[j] then
        v_distance := private.atina_v2_levenshtein_bounded(v_words_expected[i], v_words_actual[j]);
        if v_distance < v_best_distance then
          v_best_distance := v_distance;
          v_best := j;
        end if;
      end if;
    end loop;
    v_allowed := case
      when char_length(v_words_expected[i]) >= 8 then 2
      when char_length(v_words_expected[i]) >= 4 then 1
      else 0
    end;
    if v_best = 0 or v_best_distance > v_allowed then return false; end if;
    v_used[v_best] := true;
  end loop;
  return true;
end;
$$;

-- Regression checks: fail the migration if the intended tolerance is absent
-- or if it starts accepting answers that omit a meaningful content word.
do $tests$
begin
  if not private.atina_v2_answer_matches('Rio de Janeiro', 'Rio Janeiro') then
    raise exception 'Answer matcher regression: omitted preposition should be accepted.';
  end if;
  if not private.atina_v2_answer_matches('O Rio de Janeiro', 'Rio Janeiro') then
    raise exception 'Answer matcher regression: omitted article should be accepted.';
  end if;
  if not private.atina_v2_answer_matches('Cão está a correr', 'cao esta correr') then
    raise exception 'Answer matcher regression: accents and omitted short words should be accepted.';
  end if;
  if not private.atina_v2_answer_matches('dinossauro', 'dinosauro') then
    raise exception 'Answer matcher regression: existing typo tolerance must remain.';
  end if;
  if private.atina_v2_answer_matches('Rio de Janeiro', 'Rio') then
    raise exception 'Answer matcher regression: missing content words must remain incorrect.';
  end if;
  if private.atina_v2_answer_matches('Rio de Janeiro', 'Rio de Madrid') then
    raise exception 'Answer matcher regression: unrelated content words must remain incorrect.';
  end if;
end
$tests$;

revoke all on function private.atina_v2_answer_matches(text, text) from public, anon, authenticated;

comment on function private.atina_v2_answer_matches(text, text) is
  'Internal-only answer comparison: accent normalization, bounded typos, and optional Portuguese articles/prepositions in multi-word answers.';
