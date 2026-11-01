-- PROPOSTA (não aplicar diretamente): validação de respostas no servidor.
-- Requer a tabela private.atina_challenges criada pela proposta 001 e carregada
-- exclusivamente por um canal privado. Não expõe uma RPC que permita testar
-- respostas arbitrárias; estes helpers destinam-se apenas a outras RPCs SECURITY DEFINER.

create or replace function private.atina_normalize_answer(p_value text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select trim(regexp_replace(
    regexp_replace(
      regexp_replace(normalize(lower(p_value), NFD), '[̀-ͯ]', '', 'g'),
      '[^a-z0-9 ]+', '', 'g'
    ),
    '[[:space:]]+', ' ', 'g'
  ));
$$;
create or replace function private.atina_levenshtein_bounded(p_left text, p_right text)
returns integer
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  v_left_len integer := char_length(p_left);
  v_right_len integer := char_length(p_right);
  v_prev integer[];
  v_curr integer[];
  v_cost integer;
  v_row_min integer;
begin
  if abs(v_left_len - v_right_len) > 2 then return 3; end if;
  v_prev := array_fill(0, array[v_right_len + 1]);
  for j in 1..v_right_len loop v_prev[j + 1] := j; end loop;
  for i in 1..v_left_len loop
    v_curr := array_fill(0, array[v_right_len + 1]);
    v_curr[1] := i;
    v_row_min := i;
    for j in 1..v_right_len loop
      v_cost := case when substr(p_left, i, 1) = substr(p_right, j, 1) then 0 else 1 end;
      v_curr[j + 1] := least(v_curr[j] + 1, v_prev[j + 1] + 1, v_prev[j] + v_cost);
      v_row_min := least(v_row_min, v_curr[j + 1]);
    end loop;
    if v_row_min > 2 then return 3; end if;
    v_prev := v_curr;
  end loop;
  return v_prev[v_right_len + 1];
end;
$$;

create or replace function private.atina_answer_matches(p_expected text, p_actual text)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  v_expected text := private.atina_normalize_answer(p_expected);
  v_actual text := private.atina_normalize_answer(p_actual);
  v_words_expected text[];
  v_words_actual text[];
  v_used boolean[];
  v_best integer;
  v_best_distance integer;
  v_distance integer;
  v_allowed integer;
begin
  if v_expected = '' or v_actual = '' then return false; end if;
  if v_expected = v_actual then return true; end if;
  v_words_expected := string_to_array(v_expected, ' ');
  v_words_actual := string_to_array(v_actual, ' ');
  if cardinality(v_words_expected) <> cardinality(v_words_actual) then return false; end if;
  v_used := array_fill(false, array[cardinality(v_words_actual)]);
  for i in 1..cardinality(v_words_expected) loop
    v_best := 0;
    v_best_distance := 3;
    for j in 1..cardinality(v_words_actual) loop
      if not v_used[j] then
        v_distance := private.atina_levenshtein_bounded(v_words_expected[i], v_words_actual[j]);
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

create or replace function private.atina_challenge_answer_matches(p_challenge_id integer, p_answer text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.atina_challenges c
    where c.challenge_id = p_challenge_id
      and c.active
      and (
        private.atina_answer_matches(c.answer, p_answer)
        or exists (
          select 1
          from jsonb_array_elements_text(c.accepted_answers) accepted(answer)
          where private.atina_answer_matches(accepted.answer, p_answer)
        )
      )
  );
$$;

revoke all on function private.atina_normalize_answer(text) from public, anon, authenticated;
revoke all on function private.atina_levenshtein_bounded(text, text) from public, anon, authenticated;
revoke all on function private.atina_answer_matches(text, text) from public, anon, authenticated;
revoke all on function private.atina_challenge_answer_matches(integer, text) from public, anon, authenticated;

comment on function private.atina_challenge_answer_matches(integer, text) is
  'Internal-only answer check for authoritative game RPCs; never grant EXECUTE to API roles.';
