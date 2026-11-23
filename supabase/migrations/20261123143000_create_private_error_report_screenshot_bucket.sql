-- Private storage bucket for ATINA error-report screenshots.
-- Bucket was provisioned in production; this migration keeps schema history reproducible.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'atina-error-report-screenshots',
  'atina-error-report-screenshots',
  false,
  3145728,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 3145728,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp'];

-- No storage.objects policies are added. Only Edge Functions using service role
-- upload/delete and generate short-lived signed URLs for admin viewing.
