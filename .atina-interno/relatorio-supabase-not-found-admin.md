# Supabase Support Report — `atina-error-reports-admin` pre-execution 404

**Status:** investigation report, evidence-backed; exact infrastructure cause remains unconfirmed.  
**Safety:** no production changes, deploy, migrations, secrets, merge, or Render usage.

## Summary
The admin Edge Function is registered as `atina-error-reports-admin` and was observed as **ACTIVE, version 1, verify_jwt=true**. Its deployed handler contains CORS preflight handling for `OPTIONS`, and the allowed-origin list includes `https://lufime.github.io` and `http://localhost:5173`.

The recent platform log query returned **27** `OPTIONS` entries with HTTP **404**, `sb-error-code=NOT_FOUND`, and an empty `execution_id`, spanning **2026-11-21 21:36–23:03**. The empty execution ID is evidence that the request was rejected before a function execution was recorded. It does **not**, by itself, prove the exact internal platform cause.

## Evidence and identifiers
- Function: `atina-error-reports-admin`
- Endpoint path: `/functions/v1/atina-error-reports-admin`
- Project ref: `qvvlqrgbtjujsejvenld`
- Observed function registry state: ACTIVE, version 1, JWT verification enabled
- Observed log signature: HTTP 404 + `NOT_FOUND` + empty `execution_id`
- Observed request IDs include `01a2005a-249d-7d69-9a87-5ec38295f971` and `01a2005a-1fea-70e0-80d5-9d35fa17b0a8`
- Code path: `supabase/functions/atina-error-reports-admin/index.ts`
- Shared handler: `supabase/functions/_shared/error-report-admin-handler.mjs`

## Reproducible support steps
1. In Supabase Dashboard, open Edge Functions and confirm the function slug and ACTIVE deployment/version.
2. Open Edge Function logs and filter by the endpoint path and the time window **2026-11-21 21:36–23:03** (project-local display timezone may vary).
3. Inspect the HTTP status, `sb-error-code`, and `execution_id` fields. Confirm whether the 404/NOT_FOUND entries have no execution ID.
4. Correlate by request ID, including the examples above.
5. Compare with the function registry/deployment metadata and ask Supabase Support to investigate routing/recognition or deployment metadata propagation for this function/project. Do not infer a handler/CORS defect from a pre-execution log signature.

## What this does and does not establish
- **Established:** requests matching the log signature did not have a function execution ID recorded; failure layer is before handler execution.
- **Not established:** the precise runtime/region/metadata component causing the platform 404. Function ACTIVE state and the log signature alone cannot pinpoint that internals.
- CORS handler code already returns 204 for allowed-origin OPTIONS when invoked, so changing handler CORS is not an evidence-based fix for this pre-execution signature.

## Support request
Please investigate why requests for `/functions/v1/atina-error-reports-admin` are returned as 404 `NOT_FOUND` with an empty execution ID while the function is listed as ACTIVE/version 1. Confirm whether routing/function recognition or deployment metadata propagation is inconsistent, and advise the supported remediation. No production redeployment was performed for this investigation.

## CI signature test
The accompanying offline Node test validates the log signature using committed synthetic fixtures only. It has no network access, no Supabase credentials, and does not call production. It checks that `NOT_FOUND` plus empty execution ID is classified as pre-execution, while a missing bundle code and a non-empty execution ID are not misclassified.
