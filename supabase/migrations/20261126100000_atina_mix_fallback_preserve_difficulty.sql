-- Preserve the selected difficulty in every Mix fallback path.
-- The initial queue already applies this constraint; the fallback queries must do the same.
DO $migration$
DECLARE
  v_definition text;
  v_pattern text;
  v_replacement text;
  v_pattern_count integer;
  v_final_pattern text;
  v_final_replacement text;
BEGIN
  SELECT pg_get_functiondef(
    'public.atina_v2_start_local_game(text,text,integer,text,text,integer,text)'::regprocedure
  ) INTO v_definition;

  v_pattern := E'and (p_category is null or c.category=p_category)\n                   and not (c.challenge_id=any(coalesce(v_queue,ARRAY[]::integer[])))';
  v_replacement := E'and (p_category is null or c.category=p_category)\n                   and (p_difficulty=''mixed'' or c.difficulty=p_difficulty)\n                   and not (c.challenge_id=any(coalesce(v_queue,ARRAY[]::integer[])))';
  v_pattern_count := (length(v_definition)-length(replace(v_definition,v_pattern,''))) / length(v_pattern);
  IF v_pattern_count <> 2 THEN
    RAISE EXCEPTION 'Expected 2 Mix fallback exclusion queries, found %', v_pattern_count;
  END IF;
  v_definition := replace(v_definition,v_pattern,v_replacement);

  v_final_pattern := E'and (p_category is null or c.category=p_category);';
  v_final_replacement := E'and (p_category is null or c.category=p_category)\n         and (p_difficulty=''mixed'' or c.difficulty=p_difficulty);';
  v_pattern_count := (length(v_definition)-length(replace(v_definition,v_final_pattern,''))) / length(v_final_pattern);
  IF v_pattern_count <> 1 THEN
    RAISE EXCEPTION 'Expected 1 Mix empty-queue fallback, found %', v_pattern_count;
  END IF;
  v_definition := replace(v_definition,v_final_pattern,v_final_replacement);

  IF (length(v_definition)-length(replace(v_definition,'and (p_difficulty=''mixed'' or c.difficulty=p_difficulty)',''))) /
     length('and (p_difficulty=''mixed'' or c.difficulty=p_difficulty)') <> 4 THEN
    RAISE EXCEPTION 'Difficulty predicate count is not 4 after patching';
  END IF;
  EXECUTE v_definition;
END
$migration$;
