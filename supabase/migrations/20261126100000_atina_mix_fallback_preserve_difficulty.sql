-- Preserve the selected difficulty in every server-side queue fallback.
DO $migration$
DECLARE d text; p text; r text; n integer; f text; fr text;
BEGIN
 SELECT pg_get_functiondef('public.atina_v2_start_local_game(text,text,integer,text,text,integer,text)'::regprocedure) INTO d;
 p:=E'and (p_category is null or c.category=p_category)\n                   and not (c.challenge_id=any(coalesce(v_queue,ARRAY[]::integer[])))';
 r:=E'and (p_category is null or c.category=p_category)\n                   and (p_difficulty=''mixed'' or c.difficulty=p_difficulty)\n                   and not (c.challenge_id=any(coalesce(v_queue,ARRAY[]::integer[])))';
 n:=(length(d)-length(replace(d,p,'')))/length(p);
 IF n<>4 THEN RAISE EXCEPTION 'Unexpected fallback query structure: %',n; END IF;
 d:=replace(d,p,r);
 f:=E'and (p_category is null or c.category=p_category);';
 fr:=E'and (p_category is null or c.category=p_category)\n         and (p_difficulty=''mixed'' or c.difficulty=p_difficulty);';
 n:=(length(d)-length(replace(d,f,'')))/length(f);
 IF n<>2 THEN RAISE EXCEPTION 'Unexpected empty-queue fallback structure: %',n; END IF;
 d:=replace(d,f,fr);
 IF (length(d)-length(replace(d,'and (p_difficulty=''mixed'' or c.difficulty=p_difficulty)','')))/length('and (p_difficulty=''mixed'' or c.difficulty=p_difficulty)')<>7 THEN
   RAISE EXCEPTION 'Difficulty predicate count mismatch';
 END IF;
 EXECUTE d;
END
$migration$;
