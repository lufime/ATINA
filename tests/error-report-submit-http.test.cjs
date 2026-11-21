// HTTP integration tests for the shared report submission handler. Uses only a local Node server and mocks the DB boundary.
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { once } = require('node:events');

const { createSubmitHandler } = await import('../supabase/functions/_shared/error-report-submit-handler.mjs');

async function startServer(submitReport) {
  const handler = createSubmitHandler({ submitReport });
  const server = http.createServer(async (incoming, outgoing) => {
    try {
      const chunks = [];
      for await (const chunk of incoming) chunks.push(chunk);
      const body = Buffer.concat(chunks);
      const request = new Request(`http://127.0.0.1:${server.address()?.port || 0}${incoming.url}`, {
        method: incoming.method,
        headers: incoming.headers,
        ...(body.length ? { body, duplex: 'half' } : {}),
      });
      const response = await handler(request);
      outgoing.statusCode = response.status;
      response.headers.forEach((value, name) => outgoing.setHeader(name, value));
      outgoing.end(Buffer.from(await response.arrayBuffer()));
    } catch (error) {
      outgoing.statusCode = 500;
      outgoing.end(String(error));
    }
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return { server, base: `http://127.0.0.1:${server.address().port}`, close: () => new Promise(resolve => server.close(resolve)) };
}

const origin = 'https://lufime.github.io';
const validBody = { nickname: 'DUMMY', category: 'technical', description: 'O botão de enviar report não funciona corretamente.', game_version: '0.1.222', game_area: 'menu' };

test('HTTP preflight returns the allowlisted CORS headers', async () => {
  const app = await startServer(async () => ({ data: { report_id: 'r1', created_at: '2026-11-21T00:00:00Z' } }));
  try {
    const response = await fetch(app.base, { method: 'OPTIONS', headers: { Origin: origin } });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('access-control-allow-origin'), origin);
    assert.match(response.headers.get('access-control-allow-methods'), /POST/);
    assert.match(response.headers.get('access-control-allow-headers'), /content-type/i);
  } finally { await app.close(); }
});

test('HTTP rejects a non-allowlisted origin without CORS approval', async () => {
  const app = await startServer(async () => ({ data: { report_id: 'r2', created_at: '2026-11-21T00:00:00Z' } }));
  try {
    const response = await fetch(app.base, { method: 'POST', headers: { Origin: 'https://evil.example', 'Content-Type': 'application/json' }, body: JSON.stringify(validBody) });
    assert.equal(response.status, 403);
    assert.equal(response.headers.get('access-control-allow-origin'), null);
  } finally { await app.close(); }
});

test('HTTP POST returns success and CORS headers for valid payload', async () => {
  const app = await startServer(async fields => ({ data: { report_id: 'test-report-id', created_at: '2026-11-21T00:00:00Z' } }));
  try {
    const response = await fetch(app.base, { method: 'POST', headers: { Origin: origin, 'Content-Type': 'application/json' }, body: JSON.stringify(validBody) });
    const data = await response.json();
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('access-control-allow-origin'), origin);
    assert.equal(data.success, true);
    assert.equal(data.report_id, 'test-report-id');
  } finally { await app.close(); }
});

test('HTTP POST validates category and short description before DB boundary', async () => {
  let calls = 0;
  const app = await startServer(async () => { calls++; return { data: { report_id: 'unused', created_at: 'unused' } }; });
  try {
    const response = await fetch(app.base, { method: 'POST', headers: { Origin: origin, 'Content-Type': 'application/json' }, body: JSON.stringify({ ...validBody, category: 'invalid', description: 'short' }) });
    assert.equal(response.status, 400);
    assert.equal(calls, 0);
  } finally { await app.close(); }
});

test('HTTP POST hides backend errors behind a generic failure', async () => {
  const app = await startServer(async () => { throw new Error('private database detail'); });
  try {
    const response = await fetch(app.base, { method: 'POST', headers: { Origin: origin, 'Content-Type': 'application/json' }, body: JSON.stringify(validBody) });
    const data = await response.json();
    assert.equal(response.status, 500);
    assert.match(data.error, /Não foi possível enviar/);
    assert.doesNotMatch(JSON.stringify(data), /private database detail/);
  } finally { await app.close(); }
});
