-- ATINA Push reminders foundation (proposal only; not deployed)
-- Adds server-side inactivity and reminder timestamps for opt-in subscriptions.
ALTER TABLE public.atina_push_subscriptions
  ADD COLUMN IF NOT EXISTS last_activity_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS last_reminded_at timestamptz;

-- Existing subscriptions use their update timestamp as the best available activity baseline.
UPDATE public.atina_push_subscriptions
SET last_activity_at = COALESCE(updated_at, created_at, now())
WHERE last_activity_at IS NULL;

CREATE INDEX IF NOT EXISTS atina_push_reminders_due_idx
  ON public.atina_push_subscriptions (last_activity_at, last_reminded_at);

-- A signed-in ATINA session can report activity only for its own saved endpoint.
CREATE OR REPLACE FUNCTION public.atina_push_subscription_activity(
  p_session_token text,
  p_endpoint text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_player uuid;
  v_count int;
BEGIN
  v_player := private.atina_social_player_from_session(p_session_token);
  IF p_endpoint IS NULL OR length(p_endpoint) > 2048 THEN
    RAISE EXCEPTION 'Endpoint Push inválido.';
  END IF;

  UPDATE public.atina_push_subscriptions
  SET last_activity_at = now()
  WHERE player_id = v_player AND endpoint = p_endpoint;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('ok', v_count > 0, 'updated', v_count);
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_push_subscription_activity(text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_push_subscription_activity(text,text) TO anon, authenticated;
