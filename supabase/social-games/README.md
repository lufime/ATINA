# ATINA social games — isolated SQL track

This folder is deliberately separate from `supabase/migrations/`.

## Why this is isolated

The repository's active Supabase migration directory contains older ATINA/Mímicas migrations with their own prerequisites. The social-games foundation must not be picked up by a normal `supabase db push` or applied as part of that legacy chain.

## Current migration

- `migrations/20261113160000_atina_social_games_foundation.sql`
- Creates the private schema and 11 social-games tables.
- Does not create RPCs or import the 2,150 content records.
- Does not modify existing game engines.

## Validation

A GitHub Actions workflow starts a disposable PostgreSQL 17 service, creates only the minimal Supabase role names (`anon` and `authenticated`), applies only the migration in this folder, then runs the rollback-only structural test from `supabase/tests/`.

No project secrets, hosted Supabase connection, production database, or paid service is used by this workflow.

The workflow must pass before this SQL is considered parser/runtime validated. Static inspection alone is not a substitute.

## Applying to hosted Supabase

Do not apply this file through the normal repository migration chain. Hosted application is a separate, deliberate step after CI passes and after reviewing the final SQL. The isolated test project must be checked immediately before and after any approved application. Never apply to production without explicit approval.
