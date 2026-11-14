create or replace function private.atina_v2_levenshtein_bounded(p_left text, p_right text)
returns integer
language plpgsql
immutable
strict
set search_path to ''
as $function$
declare
  v_left_len integer := char_length(p_left);
  v_right_len integer := char_length(p_right);
  v_matrix integer[][];
  v_cost integer;
  v_best integer;
begin
  if abs(v_left_len - v_right_len) > 2 then return 3; end if;

  v_matrix := array_fill(0, array[v_left_len + 1, v_right_len + 1]);

  for i in 0..v_left_len loop
    v_matrix[i + 1][1] := i;
  end loop;
  for j in 0..v_right_len loop
    v_matrix[1][j + 1] := j;
  end loop;

  for i in 1..v_left_len loop
    for j in 1..v_right_len loop
      v_cost := case when substr(p_left, i, 1) = substr(p_right, j, 1) then 0 else 1 end;
      v_best := least(
        v_matrix[i][j + 1] + 1,
        v_matrix[i + 1][j] + 1,
        v_matrix[i][j] + v_cost
      );

      if i > 1 and j > 1
         and substr(p_left, i, 1) = substr(p_right, j - 1, 1)
         and substr(p_left, i - 1, 1) = substr(p_right, j, 1) then
        v_best := least(v_best, v_matrix[i - 1][j - 1] + 1);
      end if;

      v_matrix[i + 1][j + 1] := v_best;
    end loop;
  end loop;

  return least(v_matrix[v_left_len + 1][v_right_len + 1], 3);
end;
$function$;