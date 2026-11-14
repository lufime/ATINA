-- Keep numeric tokens exact while preserving typo tolerance for text.
create or replace function private.atina_v2_answer_matches(p_expected text, p_actual text)
returns boolean
language plpgsql
immutable
strict
set search_path to ''
as $function$
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
  v_fillers text[] := array['a','as','o','os','um','uma','uns','umas','de','do','da','dos','das','e','em','no','na','nos','nas','por','para','com','ao','aos','la','las','el','los','the','le','les']::text[];
begin
  if v_expected = '' or v_actual = '' then return false; end if;
  if v_expected = v_actual then return true; end if;
  if v_expected ~ '^a letra [a-z]$' then v_expected := substring(v_expected from 3); end if;
  if v_actual ~ '^a letra [a-z]$' then v_actual := substring(v_actual from 3); end if;
  if v_expected ~ '^letra [a-z]$' or v_actual ~ '^letra [a-z]$' then return v_expected = v_actual; end if;
  v_words_expected := string_to_array(v_expected, ' ');
  v_words_actual := string_to_array(v_actual, ' ');
  if cardinality(v_words_expected) > 1 then
    select coalesce(array_agg(t.word order by t.ordinality), array[]::text[]) into v_words_expected
    from unnest(v_words_expected) with ordinality as t(word, ordinality)
    where not (t.word = any(v_fillers));
  end if;
  if cardinality(v_words_actual) > 1 then
    select coalesce(array_agg(t.word order by t.ordinality), array[]::text[]) into v_words_actual
    from unnest(v_words_actual) with ordinality as t(word, ordinality)
    where not (t.word = any(v_fillers));
  end if;
  if cardinality(v_words_expected) = 0 or cardinality(v_words_actual) = 0 then return false; end if;
  if cardinality(v_words_expected) <> cardinality(v_words_actual) then return false; end if;
  v_used := array_fill(false, array[cardinality(v_words_actual)]);
  for i in 1..cardinality(v_words_expected) loop
    v_best := 0; v_best_distance := 3;
    for j in 1..cardinality(v_words_actual) loop
      if not v_used[j] then
        if v_words_expected[i] ~ '^[0-9]+$' or v_words_actual[j] ~ '^[0-9]+$' then
          v_distance := case when v_words_expected[i] = v_words_actual[j] then 0 else 3 end;
        else
          v_distance := private.atina_v2_levenshtein_bounded(v_words_expected[i], v_words_actual[j]);
        end if;
        if v_distance < v_best_distance then v_best_distance := v_distance; v_best := j; end if;
      end if;
    end loop;
    v_allowed := case when char_length(v_words_expected[i]) >= 8 then 2 when char_length(v_words_expected[i]) >= 4 then 1 else 0 end;
    if v_best = 0 or v_best_distance > v_allowed then return false; end if;
    v_used[v_best] := true;
  end loop;
  return true;
end;
$function$;
