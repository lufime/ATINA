const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;
const ROOT = path.resolve(__dirname, '../..');

function startStaticServer() {
  const server = http.createServer((req, res) => {
    const pathname = new URL(req.url, 'http://127.0.0.1').pathname;
    const relative = pathname === '/' ? 'index.html' : pathname.replace(/^\//, '');
    const file = path.resolve(ROOT, relative);
    if (!file.startsWith(ROOT + path.sep) && file !== path.join(ROOT, 'index.html')) {
      res.writeHead(403); res.end('Forbidden'); return;
    }
    fs.readFile(file, (error, data) => {
      if (error) { res.writeHead(404); res.end('Not found'); return; }
      const type = file.endsWith('.js') ? 'text/javascript; charset=utf-8' :
        file.endsWith('.css') ? 'text/css; charset=utf-8' : 'text/html; charset=utf-8';
      res.writeHead(200, { 'content-type': type });
      res.end(data);
    });
  });
  return new Promise(resolve => server.listen(0, '127.0.0.1', () => resolve({
    server, url: 'http://127.0.0.1:' + server.address().port
  })));
}

test('two real ATINA UI contexts create, join, start and advance a server-authoritative challenge room', async () => {
  assert.ok(SUPABASE_URL, 'SUPABASE_URL must target disposable local Supabase');
  assert.ok(SUPABASE_ANON_KEY, 'SUPABASE_ANON_KEY must be the local anon key');
  assert.match(SUPABASE_URL, /^http:\/\/(127\.0\.0\.1|localhost):\d+$/, 'Refusing non-local Supabase URL');

  const staticSite = await startStaticServer();
  const browser = await chromium.launch({ headless: true });
  const contexts = [];
  const errors = [];
  let hostRoom = null;
  let guestRoom = null;

  async function openPlayer(nickname) {
    const context = await browser.newContext();
    contexts.push(context);
    await context.addInitScript(config => { window.__ATINA_TEST_CONFIG__ = config; }, {
      url: SUPABASE_URL, anonKey: SUPABASE_ANON_KEY
    });
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(nickname + ': ' + error.message));
    await page.goto(staticSite.url, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => !!window.supabase?.createClient);
    return page;
  }

  try {
    const host = await openPlayer('host');
    await host.locator('.home-page-nav [data-home-target="online"]').click();
    await host.locator('#networkNickname').fill('UI-Host');
    await host.locator('#createNetworkRoom').click();
    await host.locator('#networkLobby').waitFor({ state: 'visible' });
    const code = (await host.locator('#networkLobbyCode').textContent()).trim();
    assert.match(code, /^[A-Z0-9]{6}$/);
    hostRoom = await host.evaluate(() => JSON.parse(localStorage.getItem('atinaNetworkRoom')));

    const guest = await openPlayer('guest');
    await guest.locator('#networkNickname').fill('UI-Guest');
    await guest.locator('#networkRoomCode').fill(code);
    await guest.locator('#joinNetworkRoom').click();
    await guest.locator('#networkLobby').waitFor({ state: 'visible' });
    guestRoom = await guest.evaluate(() => JSON.parse(localStorage.getItem('atinaNetworkRoom')));

    await guest.locator('#networkReady').click();
    await host.waitForFunction(() => document.querySelector('#networkLobbyInfo')?.textContent.includes('2 de'));
    await host.locator('#difficultyMode').selectOption('easy');
    await host.locator('#timerMode').selectOption('0');
    await host.locator('#networkStartGame').click();
    await host.locator('#game').waitFor({ state: 'visible' });
    await host.waitForFunction(() => document.querySelector('#category')?.textContent.trim().length > 0);
    await guest.waitForFunction(() => !document.querySelector('#game')?.classList.contains('hidden'));

    const hostState = await host.evaluate(() => ({
      mode: networkGameState?.mode,
      challengeId: networkGameState?.challenge_id,
      queueLength: networkGameState?.queue_length,
      hasAnswer: Object.hasOwn(networkGameState || {}, 'answer')
    }));
    assert.equal(hostState.mode, 'challenges');
    assert.ok(Number.isInteger(hostState.challengeId));
    assert.ok(hostState.queueLength >= 1);
    assert.equal(hostState.hasAnswer, false, 'active challenge state must not disclose the answer');

    await guest.locator('#answer').fill('resposta-ui-deliberadamente-errada');
    await guest.locator('#submit').click();
    await guest.waitForFunction(() => document.querySelector('#feedback')?.textContent.includes('tentar novamente'));
    await host.locator('#pass').click();
    await host.waitForFunction(() => !!networkGameState?.locked);
    await host.locator('#continue').click();
    await host.waitForFunction(() => networkGameState?.mode === 'challenges' && networkGameState?.pos === 1);

    const guestState = await guest.evaluate(() => ({
      mode: networkGameState?.mode,
      pos: networkGameState?.pos,
      challengeId: networkGameState?.challenge_id
    }));
    assert.equal(guestState.mode, 'challenges');
    assert.equal(guestState.pos, 1);
    assert.ok(Number.isInteger(guestState.challengeId));
    assert.deepEqual(errors, [], 'the actual UI must not emit uncaught JavaScript errors');
  } finally {
    for (const [pageContext, room] of [[contexts[0], hostRoom], [contexts[1], guestRoom]]) {
      if (!pageContext || !room?.room_id || !room?.token) continue;
      try {
        const page = pageContext.pages()[0];
        await page.evaluate(async ({ roomId, token }) => {
          await window.supabase.createClient(window.__ATINA_TEST_CONFIG__.url, window.__ATINA_TEST_CONFIG__.anonKey, {
            auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
          }).rpc('atina_v2_leave_room', { p_room_id: roomId, p_token: token });
        }, { roomId: room.room_id, token: room.token });
      } catch (_) {}
    }
    await Promise.all(contexts.map(context => context.close()));
    await browser.close();
    await new Promise(resolve => staticSite.server.close(resolve));
  }
});
