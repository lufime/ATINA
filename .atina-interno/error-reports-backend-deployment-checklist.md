# Reports backend validation checklist (offline)\n

This validation is fully offline/local: no GitHub Secrets, JWTs, Supabase credentials, remote test project, or network calls are required.


## Offline checks
- Static validation of admin endpoint origin/method/status/UUID validation.
- Submission endpoint nickname/category/description validation and rate-limit handling.
- Migration RLS and service-role grants review.
- Privacy schema check for email/IP/player/session/room identifiers.


## Boundaries
- These checks validate source structure, not deployed HTTP behavior or database integration.
- No migration is applied and no Edge Function is deployed.
- Supabase `atina-development` is production and remains untouched.
- No Render use.


## Next steps before activation
1. Review migration, RLS, grants, indexes and security-definer function.
2. Confirm administrator Auth UUIDs without guessing.
3. Obtain explicit approval before any production migration or function deployment.
4. Perform any future runtime/integration testing only after separately approved, without requiring Secrets as part of this PR.
