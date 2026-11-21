// Offline validation tests for the error-report backend source. No credentials or network calls.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const admin = fs.readFileSync(path.join(root, 'supabase/functions/atina-error-reports-admin/index.ts'), 'utf8');
const submit = fs.readFileSync(path.join(root, 'supabase/functions/atina-error-reports-submit/index.ts'), 'utf8');
const sharedSubmit = fs.readFileSync(path.join(root, 'supabase/functions/_shared/error-report-submit-handler.mjs'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261121190000_atina_error_reports_backend.sql'), 'utf8');

test('admin endpoint restricts origins, methods, and statuses', () => {
  assert.match(admin, /allowedOrigins/);
  assert.match(admin, /\["GET", "PATCH"\]/);
  for (const status of ['new','in_review','fixing','resolved','archived']) assert.match(admin, new RegExp('"'+status+'"'));
  assert.match(admin, /uuidPattern/);
  assert.match(admin, /No update fields supplied/);
});

test('submission validates nickname, category and description and limits requests', () => {
  assert.ok(sharedSubmit.includes('categories'));
  assert.match(submit, /nickname/);
  assert.match(sharedSubmit, /description\.length < 20/);
  assert.match(submit, /atina_error_report_consume_global_limit/);
  assert.ok(sharedSubmit.includes('429'));
});

test('migration enables RLS and limits table grants to service role', () => {
  for (const table of ['atina_error_report_admins','atina_error_reports','atina_error_report_rate_limits']) {
    assert.match(migration, new RegExp('ALTER TABLE public\\.'+table+' ENABLE ROW LEVEL SECURITY', 'i'));
    assert.match(migration, new RegExp('REVOKE ALL ON public\\.'+table, 'i'));
  }
  assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.atina_error_report_consume_global_limit/);
});

test('privacy-sensitive identifiers are not present in backend schema', () => {
  assert.doesNotMatch(migration, /\b(email|ip_address|player_id|session_id|room_id)\b/i);
});
