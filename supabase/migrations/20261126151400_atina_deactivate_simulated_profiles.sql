-- Deactivate every retained simulated profile and make availability permanently false.
UPDATE private.atina_v2_bot_profiles
SET active = false
WHERE active IS DISTINCT FROM false;

CREATE OR REPLACE FUNCTION private.atina_v2_bot_is_available(p_bot private.atina_v2_bot_profiles)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO ''
AS $function$
  SELECT false;
$function$;
