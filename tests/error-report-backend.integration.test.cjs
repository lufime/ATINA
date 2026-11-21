// Opt-in integration tests for a dedicated, isolated Supabase project only.
const test = require('node:test');
const assert = require('node:assert/strict');

const base = (process.env.ATINA_ERROR_REPORTS_TEST_URL || '').replace(/\\/$/, '');
const adminToken = process.env.ATINA_ERROR_REPORTS_TEST_ADMIN_TOKEN || '';
const playerToken = process.env.ATINA_ERROR_REPORTS_TEST_PLAYER_TOKEN || '';\nconst anonKey = process.env.ATINA_ERROR_REPORTS_TEST_ANON_KEY || '';
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

async function request(url, token, method='GET', body) {
  return fetch(url, { method, headers: { Origin: origin, apikey: anonKey, ...(token ? { Authorization: 'Bearer ' + token } : {}), ...(body !== undefined ? {'Content-Type':'application/json'} : {}) }, ...(body !== undefined ? {body:JSON.stringify(body)} : {}) });
}

test('Admin endpoint rejects missing and invalid JWTs', {skip:skipReason}, async () => {
  const noToken = await request(adminEndpoint, '');
  assert.equal(noToken.status, 401);
  const invalid = await request(adminEndpoint, 'invalid-test-token');
  assert.equal(invalid.status, 401);
});

test('Admin endpoint denies authenticated non-admin users', {skip:skipReason}, async () => {
  const response = await request(adminEndpoint, playerToken);
  assert.equal(response.status, 403);
});

test('Allowlisted admin can read reports and receives a reports array', {skip:skipReason}, async () => {
  const response = await request(adminEndpoint, adminToken);
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.ok(Array.isArray(data.reports));
});

test('Admin PATCH validates report identifiers before any update', {skip:skipReason}, async () => {
  const response = await request(adminEndpoint, adminToken, 'PATCH', { report_id: 'not-a-uuid', status: 'resolved' });
  assert.equal(response.status, 400);
});

test('Submit endpoint rejects invalid category and short description without writing', {skip:skipReason}, async () => {
  const invalidCategory = await request(submitEndpoint, '', 'POST', {nickname:'Test',category:'invalid',description:'This description is long enough for validation.'});
  assert.equal(invalidCategory.status, 400);
  const shortDescription = await request(submitEndpoint, '', 'POST', {nickname:'Test',category:'technical',description:'Too short'});
  assert.equal(shortDescription.status, 400);
});

test('Submit endpoint rejects unapproved browser origin', {skip:skipReason}, async () => {
  const response = await fetch(submitEndpoint, {method:'POST',headers:{Origin:'https://invalid.example',apikey:anonKey,'Content-Type':'application/json'},body:JSON.stringify({nickname:'Test',category:'technical',description:'This is a valid long description for testing.'})});
  assert.equal(response.status, 403);
});
