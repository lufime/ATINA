CREATE TABLE IF NOT EXISTS private.atina_image_license_audit (
  challenge_id integer PRIMARY KEY REFERENCES private.atina_challenges(challenge_id) ON DELETE CASCADE,
  image_url text NOT NULL,
  source_domain text NOT NULL,
  license_status text NOT NULL DEFAULT 'pending_verification'
    CHECK (license_status IN ('pending_verification','verified_allowed','verified_allowed_with_attribution','verified_restricted','permission_required','unavailable','rejected')),
  author_name text,
  license_name text,
  license_url text,
  source_page_url text,
  attribution_text text,
  checked_at timestamptz,
  review_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO private.atina_image_license_audit (challenge_id, image_url, source_domain)
SELECT challenge_id, image_url, split_part(replace(image_url, 'https://', ''), '/', 1)
FROM private.atina_challenges
WHERE image_url IS NOT NULL
ON CONFLICT (challenge_id) DO UPDATE
SET image_url = EXCLUDED.image_url,
    source_domain = EXCLUDED.source_domain,
    updated_at = now();

ALTER TABLE private.atina_image_license_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.atina_image_license_audit FROM PUBLIC, anon, authenticated;
