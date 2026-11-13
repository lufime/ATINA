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


## Room and team RPC migration

The second isolated migration is `migrations/20261113161000_atina_social_games_rooms_teams.sql`. It implements room creation, joining by code, token-authenticated room state, and balanced automatic team assignment. The matching rollback-only test is in `supabase/tests/20261113161000_atina_social_games_rooms_teams.test.sql`.

The CI workflow applies this migration after the foundation and runs both test files. Wait for a successful workflow run before treating this second stage as runtime-validated. It has not been applied to any hosted Supabase project.


The manual team migration is `migrations/20261113162000_atina_social_games_manual_teams.sql`; its rollback-only tests are in `supabase/tests/20261113162000_atina_social_games_manual_teams.test.sql`. The latest isolated CI run passed all three migrations and test suites in disposable PostgreSQL 17. No hosted Supabase project was changed.


## Authoritative game start and round clock

The isolated migration `migrations/20261113163000_atina_social_games_start_room.sql` adds `atina_social_game_start_room`. It validates the host token, one of the five social game codes, play mode, difficulty, 1–50 rounds, available non-repeating content, and team completeness/balance. It freezes the selected setup, creates the round rows, and sets the first server deadline.

The approved round duration is **60 seconds**. The RPC accepts a duration argument for future flexibility but currently validates 30–180 seconds; the beta page sends 60. The room and first round deadlines are calculated by PostgreSQL, not the browser. Individual mode clears any pre-existing team assignments.

Matching rollback-only tests are in `supabase/tests/20261113163000_atina_social_games_start_room.test.sql`. The GitHub Actions workflow now applies this migration and runs its tests after the three earlier SQL stages.

Important: the content table is still empty in hosted test Supabase, and the 2,150 approved content records have not yet been imported or validated against per-game payload contracts. Consequently the start RPC correctly refuses to start until sufficient content exists. This migration is isolated and has not been applied to any hosted Supabase project.
