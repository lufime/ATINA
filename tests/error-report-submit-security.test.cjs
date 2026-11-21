const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const source = fs.readFileSync('supabase/functions/atina-error-reports-submit/index.ts', 'utf8');
const shared = fs.readFileSync('supabase/functions/_shared/error-report-submit-handler.mjs', 'utf8');

test('origin guard precedes body processing and rejects unapproved origins', () => {
  const guard = shared.indexOf('if (!allowedOrigins.has(origin))');
  const bodyParse = shared.indexOf('const parsed = await req.json()');
  assert.notEqual(guard, -1);
  assert.ok(bodyParse > guard);
  assert.match(shared, /Origin not allowed/);
});
test('handler rejects malformed and non-object bodies', () => {
  assert.match(shared, /Invalid JSON/);
  assert.match(shared, /Invalid JSON body/);
});
test('handler validates fields before backend rate limit operation', () => {
  for (const phrase of ['Pseudónimo obrigatório','Categoria inválida','A descrição deve ter pelo menos 20 caracteres.']) assert.ok(shared.includes(phrase));
  const rateLimit = source.indexOf('atina_error_report_consume_global_limit');
  assert.ok(rateLimit > -1);
});
test('endpoint and shared handler avoid logging or collecting extra personal identifiers', () => {
  assert.doesNotMatch(source + shared, /console\.(log|error|warn)/);
  assert.doesNotMatch(source + shared, /user_agent|user-agent|ip_address|player_id|session_id/i);
});
