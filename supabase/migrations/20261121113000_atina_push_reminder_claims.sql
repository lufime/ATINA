-- ATINA Push reminder sender: atomic claims to prevent concurrent duplicate sends.
ALTER TABLE public.atina_push_subscriptions
  ADD COLUMN IF NOT EXISTS last_attempt_at timestamptz;

CREATE OR REPLACE FUNCTION public.atina_push_reminders_claim(
  p_limit integer DEFAULT 100
) RETURNS TABLE(id uuid, subscription jsonb)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH due AS (
    SELECT s.id
    FROM public.atina_push_subscriptions s
    WHERE s.last_activity_at <= now() - interval '48 hours'
      AND (s.last_reminded_at IS NULL OR s.last_reminded_at <= now() - interval '7 days')
      AND (s.last_attempt_at IS NULL OR s.last_attempt_at <= now() - interval '15 minutes')
      -- Claim malformed subscriptions for cleanup, but do not let valid unsupported providers monopolize batches.
      -- Normalize URL case because scheme and DNS host names are case-insensitive.
      AND (
        coalesce(lower(s.subscription->>'endpoint'), '') !~ '^https://[^/?#:@]+(:443)?(/|[?]|#|$)'
        OR lower(s.subscription->>'endpoint') ~ '^https://(fcm\.googleapis\.com|[a-z0-9.-]+\.fcm\.googleapis\.com|[a-z0-9.-]+\.push\.services\.mozilla\.com|web\.push\.apple\.com|notify\.windows\.com|wns\.windows\.com)(:443)?(/|[?]|#|$)'
      )
    ORDER BY s.last_activity_at ASC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 250)
    FOR UPDATE SKIP LOCKED
  ),
  claimed AS (
    UPDATE public.atina_push_subscriptions s
    SET last_attempt_at = now()
    FROM due
    WHERE s.id = due.id
    RETURNING s.id, s.subscription
  )
  SELECT claimed.id, claimed.subscription FROM claimed;
$function$;

REVOKE ALL ON FUNCTION public.atina_push_reminders_claim(integer) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atina_push_reminders_claim(integer) TO service_role;
