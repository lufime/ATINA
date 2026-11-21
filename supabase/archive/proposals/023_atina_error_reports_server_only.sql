-- PROPOSAL ONLY. Keep under archive/proposals; do not apply to production.
-- Anonymous ATINA error reports with server-only data access and admin allowlist.
CREATE TABLE IF NOT EXISTS public.atina_error_report_admins (
  user_id uuid PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.atina_error_reports (
  report_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nickname text NOT NULL CHECK (char_length(nickname) BETWEEN 1 AND 40),
  category text NOT NULL CHECK (category IN ('visual','game','points_xp','technical','other')),
  description text NOT NULL CHECK (char_length(description) BETWEEN 20 AND 2000),
  game_version text NULL CHECK (game_version IS NULL OR char_length(game_version) <= 40),
  game_area text NULL CHECK (game_area IS NULL OR char_length(game_area) <= 80),
  status text NOT NULL DEFAULT 'new' CHECK (status IN ('new','in_review','fixing','resolved','archived')),
  internal_note text NULL CHECK (internal_note IS NULL OR char_length(internal_note) <= 2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS atina_error_reports_status_created_idx ON public.atina_error_reports(status,created_at DESC);
CREATE INDEX IF NOT EXISTS atina_error_reports_nickname_idx ON public.atina_error_reports(nickname);
CREATE TABLE IF NOT EXISTS public.atina_error_report_rate_limits (
  minute_bucket timestamptz PRIMARY KEY,
  submission_count integer NOT NULL DEFAULT 0 CHECK (submission_count >= 0)
);
ALTER TABLE public.atina_error_report_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.atina_error_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.atina_error_report_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.atina_error_report_admins FROM anon, authenticated, public;
REVOKE ALL ON public.atina_error_reports FROM anon, authenticated, public;
REVOKE ALL ON public.atina_error_report_rate_limits FROM anon, authenticated, public;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.atina_error_report_admins TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.atina_error_reports TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.atina_error_report_rate_limits TO service_role;

-- Privacy-preserving initial abuse cap: global per-minute count, no IP/player key.
-- Limitation: one abusive submitter can exhaust the shared window.
CREATE OR REPLACE FUNCTION public.atina_error_report_consume_global_limit(p_limit integer DEFAULT 50)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_bucket timestamptz := date_trunc('minute', now());
  v_count integer;
BEGIN
  IF p_limit < 1 OR p_limit > 200 THEN RETURN false; END IF;
  INSERT INTO public.atina_error_report_rate_limits AS limits(minute_bucket, submission_count)
  VALUES (v_bucket, 1)
  ON CONFLICT (minute_bucket) DO UPDATE
    SET submission_count = limits.submission_count + 1
  RETURNING submission_count INTO v_count;
  DELETE FROM public.atina_error_report_rate_limits
    WHERE minute_bucket < v_bucket - interval '10 minutes';
  RETURN v_count <= p_limit;
END;
$$;
REVOKE ALL ON FUNCTION public.atina_error_report_consume_global_limit(integer) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atina_error_report_consume_global_limit(integer) TO service_role;
