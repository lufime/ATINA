// Opt-in integration tests for a dedicated, isolated Supabase project only.
const test = require('node:test');
const assert = require('node:assert/strict');

let base = process.env.ATINA_ERROR_REPORTS_TEST_URL || '';
while (base.endsWith('/')) base = base.slice(0, -1);
const adminToken = process.env.ATINA_ERROR_REPORTS_TEST_ADMIN_TOKEN || '';
const playerToken = process.env.ATINA_ERROR_REPORTS_TEST_PLAYER_TOKEN || '';
const anonKey = process.env.ATINA_ERROR_REPORTS_TEST_ANON_KEY || '';
const allowRemote = process.env.ATINA_ERROR_REPORTS_TEST_ALLOW_REMOTE === 'true';
const prodHost = 'qvvlqrgbtjujsejvenld.supabase.co';
const host = (() => { try { return new URL(base).hostname; } catch { return ''; } })();
const configured = Boolean(base && host && anonKey && adminToken && playerToken);
const safeTarget = Boolean(configured && host !== prodHost && (['localhost','127.0.0.1'].includes(host) || allowRemote));
const skipReason = !configured ? 'Set explicit isolated-test URL and admin/player tokens to enable.' :
  !safeTarget ? 'Remote tests require explicit opt-in and production hostname is forbidden.' : false;
const adminEndpoint = base + '/functions/v1/atina-error-reports-admin';
const submitEndpoint = base + '/functions/v1/atina-error-reports-submit';
const origin = 'https://lufime.github.io';

async function request(url, token, method='GET', body, requestOrigin=origin) {
  return fetch(url, { method, headers: { Origin: requestOrigin, apikey: anonKey, ...(token ? { Authorization: 'Bearer ' + token } : {}), ...(body !== undefined ? {'Content-Type':'application/json'} : {}) }, ...(body !== undefined ? {body:JSON.stringify(body)} : {}) });
}

test('Admin endpoint rejects missing and invalid JWTs', {skip:skipReason}, async () => {
  assert.equal((await request(adminEndpoint, '')).status, 401);
  assert.equal((await request(adminEndpoint, 'invalid-test-token')).status, 401);
});

test('Admin endpoint denies authenticated non-admin users', {skip:skipReason}, async () => {
  assert.equal((await request(adminEndpoint, playerToken)).status, 403);
});

test('Admin CORS rejects disallowed origins and permits preflight for allowed origin', {skip:skipReason}, async () => {
  assert.equal((await request(adminEndpoint, adminToken, 'GET', undefined, 'https://invalid.example')).status, 403);
  const preflight = await request(adminEndpoint, '', 'OPTIONS');
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), origin);
  assert.match(preflight.headers.get('access-control-allow-methods') || '', /PATCH/);
});

test('Allowlisted admin can read reports and receives a reports array', {skip:skipReason}, async () => {
  const response = await request(adminEndpoint, adminToken);
  assert.equal(response.status, 200);
  assert.ok(Array.isArray((await response.json()).reports));
});

test('Admin PATCH validates report identifiers, status, notes and empty updates', {skip:skipReason}, async () => {
  assert.equal((await request(adminEndpoint, adminToken, 'PATCH', { report_id: 'not-a-uuid', status: 'resolved' })).status, 400);
  const validId = '00000000-0000-4000-8000-000000000001';
  assert.equal((await request(adminEndpoint, adminToken, 'PATCH', { report_id: validId, status: 'invalid-status' })).status, 400);
  assert.equal((await request(adminEndpoint, adminToken, 'PATCH', { report_id: validId, internal_note: 'x'.repeat(2001) })).status, 400);
  assert.equal((await request(adminEndpoint, adminToken, 'PATCH', { report_id: validId })).status, 400);
  assert.equal((await request(adminEndpoint, adminToken, 'PATCH', null)).status, 400);
});

test('Submit endpoint validates category, nickname, description and origin', {skip:skipReason}, async () => {
  assert.equal((await request(submitEndpoint, '', 'POST', {nickname:'Test',category:'invalid',description:'This description is long enough for validation.'})).status, 400);
  assert.equal((await request(submitEndpoint, '', 'POST', {nickname:'Test',category:'technical',description:'Too short'})).status, 400);
  assert.equal((await request(submitEndpoint, '', 'POST', {nickname:'',category:'technical',description:'This description is long enough for validation.'})).status, 400);
  assert.equal((await request(submitEndpoint, '', 'POST', {nickname:'Test',category:'technical',description:'This description is long enough for validation.'}, 'https://invalid.example')).status, 403);
});

test('Admin updates a submitted report and subsequent GET confirms persistence', {skip:skipReason}, async () => {
  const nickname = 'backend-test-' + Date.now().toString(36).slice(-8);
  const submission = await request(submitEndpoint, '', 'POST', {
    nickname, category:'technical', description:'Isolated integration report for update and persistence validation.'
  });
  assert.equal(submission.status, 200);
  const submitted = await submission.json();
  assert.equal(submitted.success, true);
  assert.ok(submitted.report_id);

  const patch = await request(adminEndpoint, adminToken, 'PATCH', {
    report_id: submitted.report_id, status:'in_review', internal_note:'Integration test persistence marker.'
  });
  assert.equal(patch.status, 200);
  const updated = (await patch.json()).report;
  assert.equal(updated.report_id, submitted.report_id);
  assert.equal(updated.status, 'in_review');
  assert.equal(updated.internal_note, 'Integration test persistence marker.');

  const listing = await request(adminEndpoint, adminToken);
  assert.equal(listing.status, 200);
  const reports = (await listing.json()).reports;
  const persisted = reports.find((item) => item.report_id === submitted.report_id);
  assert.ok(persisted, 'report must be returned by subsequent Admin GET');
  assert.equal(persisted.status, 'in_review');
  assert.equal(persisted.internal_note, 'Integration test persistence marker.');
});
