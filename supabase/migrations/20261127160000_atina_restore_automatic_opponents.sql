-- Reativar adversários automáticos em partidas individuais de Duelo.
-- Mantém presença pública e rankings exclusivamente humanos; não reativa simulação em segundo plano.

CREATE OR REPLACE FUNCTION private.atina_v2_bot_is_available(p_bot private.atina_v2_bot_profiles)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path TO ''
AS $function$
DECLARE
  v_local time;
  v_day integer;
  v_sleeping boolean;
  v_working boolean;
BEGIN
  v_local := (clock_timestamp() AT TIME ZONE p_bot.timezone_name)::time;
  v_day := extract(isodow FROM clock_timestamp() AT TIME ZONE p_bot.timezone_name)::integer;
  v_sleeping := CASE
    WHEN p_bot.sleep_start < p_bot.sleep_end
      THEN v_local >= p_bot.sleep_start AND v_local < p_bot.sleep_end
    ELSE v_local >= p_bot.sleep_start OR v_local < p_bot.sleep_end
  END;
  v_working := v_day <= 5 AND CASE
    WHEN p_bot.work_start < p_bot.work_end
      THEN v_local >= p_bot.work_start AND v_local < p_bot.work_end
    ELSE v_local >= p_bot.work_start OR v_local < p_bot.work_end
  END;
  RETURN p_bot.active
    AND NOT v_sleeping
    AND NOT v_working
    AND abs(extract(epoch FROM (v_local-p_bot.breakfast_at))) > 1200
    AND abs(extract(epoch FROM (v_local-p_bot.lunch_at))) > 1200
    AND abs(extract(epoch FROM (v_local-p_bot.dinner_at))) > 1200;
END;
$function$;

-- Reativar os 100 perfis existentes, sem criar perfis duplicados.
UPDATE private.atina_v2_bot_profiles
SET active = true
WHERE active IS DISTINCT FROM true;

-- Os RPCs validam a sessão ATINA e o token da sala no servidor.
-- O cliente usa a chave pública e autenticação própria do ATINA.
GRANT EXECUTE ON FUNCTION public.atina_v2_create_bot_match(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_bot_tick(uuid, text) TO anon, authenticated;

-- Não reativar cron de simulação, presença artificial nem rankings com perfis simulados.
