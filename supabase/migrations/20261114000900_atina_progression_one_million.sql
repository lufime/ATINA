-- ATINA progression: increasing XP requirements up to 1,000,000 XP at level 30.
CREATE OR REPLACE FUNCTION private.atina_level_for_xp(p_xp integer)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $$
DECLARE
  v_xp integer := greatest(coalesce(p_xp,0),0);
  v_thresholds integer[] := ARRAY[
    0,2000,5000,9000,15000,23000,33000,46000,61000,79000,
    99000,122000,147000,175000,206000,239000,275000,313000,353000,397000,
    442000,491000,542000,597000,656000,718000,783000,852000,924000,1000000
  ];
  v_level integer := 1;
  v_next_threshold integer := 1080000;
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
