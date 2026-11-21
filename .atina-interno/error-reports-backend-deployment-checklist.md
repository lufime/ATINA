# Reports backend rollout checklist (draft)

Review-only package. No migration or Edge Function is applied/deployed.

## Objects
- `atina_error_report_admins`: allowlist of verified Supabase Auth UUIDs.
- `atina_error_reports`: report records and workflow statuses.
- `atina_error_report_rate_limits`: global minute buckets.
- `atina_error_report_consume_global_limit(integer)`: atomic limiter used by submit function.

## Required before activation
1. Review SQL constraints, RLS, grants, indexes and definer function.
2. Verify admin Auth UUIDs independently; do not seed guessed values.
3. Owner approval is required before applying to `atina-development` (production).
4. Deploy Edge Functions only after migration and allowlist are approved.
5. Run backend integration tests in isolated Supabase with test JWTs only.
6. Validate unauthorized/authorized Admin GET/PATCH, submission validation and persistence, global 429 and CORS.
7. Review platform log retention/privacy settings.

## Privacy and limitations
- Rate limiting is global per minute (not keyed to IP/player); one abusive client can consume the shared quota.
- Screenshot upload is not implemented by these functions/migration.
- Data excludes email, IP, player IDs, session/room/challenge IDs and persistent client identifiers.
- No email or notification sends.
- Admin authorization is server-side allowlist based.

## Rollout status
Migration proposed only; Edge Functions not deployed; admin seeding awaits verified UUIDs and approval; tests need isolated credentials. Production unchanged. Render not used.
