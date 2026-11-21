const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync('supabase/functions/atina-error-reports-submit/index.ts', 'utf8');

test('submission handler rejects missing and non-allowlisted origins before body processing', () => {
  const guard = source.indexOf('if (!allowedOrigins.has(origin))');
  const bodyParse = source.indexOf('const parsed = await req.json()');
  assert.notEqual(guard, -1);
  assert.ok(bodyParse > guard, 'origin guard must precede parsing and writes');
  assert.match(source, /return json\(req, \{ error: "Origin not allowed" \}, 403\)/);
});

test('submission handler returns 400 for malformed or non-object request bodies', () => {
  assert.match(source, /return json\(req, \{ error: "Invalid JSON" \}, 400\)/);
  assert.match(source, /Invalid JSON body/);
});

test('submission validates nickname, category, and description before rate-limit consumption', () => {
  const validations = ['Pseudónimo obrigatório', 'Categoria inválida', 'A descrição deve ter pelo menos 20 caracteres.'];
  const rateLimit = source.indexOf('atina_error_report_consume_global_limit');
  assert.ok(rateLimit > -1);
  for (const validation of validations) {
    assert.ok(source.indexOf(validation) < rateLimit, validation + ' must precede rate-limit consumption');
  }
});

test('submission endpoint does not accept extra personal identifiers or log request contents', () => {
  assert.doesNotMatch(source, /console\.(log|error|warn)/);
  assert.doesNotMatch(source, /user_agent|user-agent|ip_address|player_id|session_id/i);
});
