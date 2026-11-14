-- ATINA player level progression: curated thresholds for levels 1-30,
-- then an increasing XP step for unlimited levels.
CREATE OR REPLACE FUNCTION private.atina_level_for_xp(p_xp integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $$
DECLARE
  v_xp integer := greatest(coalesce(p_xp,0),0);
  v_thresholds integer[] := ARRAY[
    0,250,600,1100,1800,2700,3900,5400,7200,9300,
    11700,14400,17400,20700,24300,28200,32400,36900,41700,46800,
    52200,57900,64000,70500,77400,84700,92400,100500,109000,118000
  ];
  v_level integer := 1;
  v_next_threshold integer := 128000;
  v_increment integer := 10000;
BEGIN
  FOR i IN 2..array_length(v_thresholds,1) LOOP
    IF v_xp >= v_thresholds[i] THEN
      v_level := i;
    ELSE
      RETURN v_level;
    END IF;
  END LOOP;

  WHILE v_xp >= v_next_threshold LOOP
    v_level := v_level + 1;
    v_next_threshold := v_next_threshold + v_increment;
    v_increment := v_increment + 1000;
  END LOOP;
  RETURN v_level;
END;
$$;

-- Keep every server response consistent with the same progression table.
DO $$
DECLARE
  v_signature text;
  v_definition text;
  v_updated text;
  v_signatures text[] := ARRAY[
    'public.atina_account_login(text,text)',
    'public.atina_account_profile(text)',
    'public.atina_progress_register(text,text)',
    'public.atina_progress_claim_local(text,uuid,text,integer)',
    'public.atina_progress_leaderboard(integer)'
  ];
BEGIN
  FOREACH v_signature IN ARRAY v_signatures LOOP
    v_definition := pg_get_functiondef(v_signature::regprocedure);
    v_updated := v_definition;
    v_updated := replace(v_updated, 'floor(p.total_xp/250.0)::integer+1', 'private.atina_level_for_xp(p.total_xp)');
    v_updated := replace(v_updated, 'floor(p.total_xp / 250.0)::integer + 1', 'private.atina_level_for_xp(p.total_xp)');
    v_updated := replace(v_updated, 'floor(v_player.total_xp/250.0)::integer+1', 'private.atina_level_for_xp(v_player.total_xp)');
    v_updated := replace(v_updated, 'floor(v_player.total_xp / 250.0)::integer + 1', 'private.atina_level_for_xp(v_player.total_xp)');
    v_updated := replace(v_updated, '(p.xp / 250) + 1', 'private.atina_level_for_xp(p.xp)');
    IF v_updated = v_definition THEN
      RAISE EXCEPTION 'No level formula was replaced in %', v_signature;
    END IF;
    EXECUTE v_updated;
  END LOOP;
END;
$$;
