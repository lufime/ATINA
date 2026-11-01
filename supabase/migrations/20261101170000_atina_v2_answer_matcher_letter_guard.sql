-- Tighten answer matching for single-letter answers and add a common
-- singular typo variant for challenge 728 ("Todos os meses").
-- This migration is intentionally separate from deployment and must be applied
-- only after review/approval.

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

  -- In letter riddles, the final single-letter token carries the answer.
  -- Keep it intact, including when the canonical answer starts with "A letra".
  if v_expected ~ '^a letra [a-z]$' then
    v_expected := substring(v_expected from 3);
  end if;
  if v_actual ~ '^a letra [a-z]$' then
    v_actual := substring(v_actual from 3);
  end if;
  if v_expected ~ '^letra [a-z]$' or v_actual ~ '^letra [a-z]$' then
    return v_expected = v_actual;
  end if;

  v_words_expected := string_to_array(v_expected, ' ');
  v_words_actual := string_to_array(v_actual, ' ');

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

-- A bounded typo tolerance of two edits is too permissive for this short
-- inflection, so retain it as an explicit curated accepted answer instead.
update private.atina_challenges
set accepted_answers = accepted_answers || '["todos os mes"]'::jsonb
where challenge_id = 728
  and category = 'Ilusões e truques mentais'
  and not accepted_answers ? 'todos os mes';

do $tests$
begin
  if not private.atina_v2_answer_matches('A letra «o»', 'letra o') then
    raise exception 'Answer matcher regression: the correct single letter must be accepted.';
  end if;
  if private.atina_v2_answer_matches('A letra «o»', 'letra a') then
    raise exception 'Answer matcher regression: a different single letter must be rejected.';
  end if;
  if not private.atina_v2_challenge_answer_matches(728, 'todos os mes') then
    raise exception 'Answer matcher regression: the curated singular typo for challenge 728 must be accepted.';
  end if;
  if private.atina_v2_challenge_answer_matches(765, 'letra a') then
    raise exception 'Answer matcher regression: wrong letter for challenge 765 must be rejected.';
  end if;
  if not private.atina_v2_challenge_answer_matches(765, 'letra o') then
    raise exception 'Answer matcher regression: correct letter for challenge 765 must be accepted.';
  end if;
  if private.atina_v2_answer_matches('Rio de Janeiro', 'Rio') then
    raise exception 'Answer matcher regression: missing content words must remain incorrect.';
  end if;
end
$tests$;

revoke all on function private.atina_v2_answer_matches(text, text) from public, anon, authenticated;

comment on function private.atina_v2_answer_matches(text, text) is
  'Internal-only answer comparison: accent normalization, bounded typos, optional Portuguese fillers, and strict single-letter riddle matching.';
