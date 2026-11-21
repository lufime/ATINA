# ATINA Push reminders — branch implementation

This is a review-only rebuild. **Do not deploy or apply migrations to the production Supabase project** until a reviewer explicitly approves.

## Behavior
- Only subscriptions saved by the player's explicit opt-in are eligible.
- Push reminders become due after 48 hours without reported activity.
- Successful reminders are cooled down for 7 days.
- Claims are throttled for 15 minutes, to reduce overlapping scheduled invocations.
- Expired Web Push subscriptions (HTTP 404/410) are deleted.
- Malformed endpoint subscriptions are deleted; valid endpoints from unsupported providers are retained but skipped.
- Claims are cooldown-throttled, so skipped unsupported endpoints do not permanently monopolize batches.
- The sender logs provider hostnames only, never subscription endpoints or payload keys.

## Required Supabase Edge Function secrets
Set in the target Supabase environment only after approval:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY` (secret; never commit)
- `CRON_SECRET` (long random secret; never commit)
- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY` (secret; never commit)
- `VAPID_SUBJECT` (mailto or URL)
- Optional: `ATINA_PUBLIC_URL` (default points to the ATINA web app)

Generate a new VAPID key pair in a secure environment. Do not reuse the old historical public key unless its matching private key is verified. The client module still has an empty VAPID public key; reminders cannot be opted in until the verified public key is inserted in the client and reviewed.

## Deploy (not executed)
The function uses its own CRON_SECRET bearer check; deploy with JWT verification disabled only after configuring the secrets:
```sh
supabase functions deploy atina-push-reminders --no-verify-jwt
```

## Schedule (not executed)
Schedule a POST every 15 minutes to the deployed function using the cron secret stored in Vault. Use Supabase Cron/pg_cron with `net.http_post`; keep the secret in Vault and never hardcode it into a migration or repo. Example call shape:

```sql
select net.http_post(
  url := '<function-url>',
  headers := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = '<vault-secret-name>' limit 1)
  ),
  body := '{}'::jsonb
);
```

The schedule itself should be created only after verifying the Vault secret name and the project environment. Do not execute this example as-is.

## Tests
Run from the function directory with Deno:
```sh
deno test helpers_test.ts
```
Tests cover 48-hour threshold, seven-day cooldown, claim cooldown, notification payload, and endpoint allowlist. They have **not yet been run in Deno** in this environment.
