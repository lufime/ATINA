-- Fix integer/text comparison when validating a completed local challenge.
-- Keep the stored challenge queue and existing RPC contract unchanged.
DO $$
DECLARE
  v_definition text;
  v_original text := 'where challenge_id=v_challenge_id and active;';
  v_fixed text := 'where challenge_id=v_challenge_id::integer and active;';
BEGIN
  SELECT pg_get_functiondef(
    'public.atina_progress_claim_local(text,uuid,text,integer)'::regprocedure
  ) INTO v_definition;

  IF position(v_original IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Expected challenge lookup was not found; refusing to modify function';
  END IF;

  v_definition := replace(v_definition, v_original, v_fixed);
  EXECUTE v_definition;
END;
$$;
