-- Private screenshot attachments for player error reports.
-- Review only: do not apply to production without explicit approval.
ALTER TABLE public.atina_error_reports ADD COLUMN IF NOT EXISTS screenshot_path text NULL;
INSERT INTO storage.buckets (id, name, public)
VALUES ('atina-error-report-screenshots', 'atina-error-report-screenshots', false)
ON CONFLICT (id) DO UPDATE SET public = false;
-- No storage.objects policies are created for anon/authenticated: bucket access remains private.
-- Edge Functions use service_role for upload, cleanup, and short-lived admin signed URLs.
