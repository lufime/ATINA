# Supabase Support Report — pre-execution NOT_FOUND for ATINA admin Edge Function

## Summary
Repeated requests to `/functions/v1/atina-error-reports-admin` were recorded as HTTP 404 with platform code `NOT_FOUND` and an empty `execution_id`. This signature indicates the request was rejected before a function execution was recorded. The deployed function's handler therefore is not the first layer implicated by these entries.

## Target
- Function slug: `atina-error-reports-admin`
- Endpoint path: `/functions/v1/atina-error-reports-admin`
- Observed function registry state: ACTIVE, version 1, JWT verification enabled (verified separately through Supabase function metadata)
- Handler: `supabase/functions/atina-error-reports-admin/index.ts`
- Shared handler: `supabase/functions/_shared/error-report-admin-handler.mjs`

## Observed evidence (sanitized)
- Matching log records: 27
- HTTP status: 404
- platform error code: `NOT_FOUND`
- `execution_id`: empty string
- request path: `/functions/v1/atina-error-reports-admin`
- observed time range: 2026-11-21 21:36–23:03 (timezone as displayed in the source query)
- request type included OPTIONS/preflight requests
- no tokens, authorization headers, user IDs, or secrets included

## Interpretation
The evidence points to a routing/function-recognition or deployment-metadata layer before the handler starts. The exact internal cause (for example, propagation, metadata lookup, or regional routing) is not established by the available logs. The function being marked ACTIVE does not, by itself, explain why these requests were returned as NOT_FOUND.

This does **not** support blaming CORS or handler logic: an empty execution ID is the distinguishing evidence that no function execution was recorded for these requests. Confirm the exact platform-side cause with Supabase.

## Questions for Supabase Support
1. For the supplied request IDs and timestamps, why did the Edge Functions router return `NOT_FOUND` while the function metadata reported `atina-error-reports-admin` as ACTIVE?
2. Can you confirm whether these requests reached the Edge Functions runtime/region and whether function metadata propagation or routing lookup failed?
3. Please check the platform trace for the empty execution IDs and identify the layer returning the 404.
4. Is there a known propagation/cache/routing issue that would cause this function to be ACTIVE in metadata but return platform `NOT_FOUND`?

## Reproduction / diagnostics to attach
- Function slug and path above.
- Sanitized request IDs from the log sample, such as `01a2005a-249d-7d69-9a87-5ec38295f971` and `01a2005a-1fea-70e0-80d5-9d35fa17b0a8`.
- Export of the matching log rows showing status, `sb-error-code`, empty `execution_id`, timestamps, and path.
- The isolated CI regression test added with this report validates the signature detection only; it does not attempt to reproduce Supabase infrastructure routing.

## Safety / scope
Prepared from read-only evidence. No production configuration, deployments, migrations, secrets, or function code were changed. No Render was used.
