-- Store the Storage object path for error-report screenshots.
-- Additive and idempotent: preserves all existing report rows and values.
ALTER TABLE public.atina_error_reports
  ADD COLUMN IF NOT EXISTS screenshot_path text;
