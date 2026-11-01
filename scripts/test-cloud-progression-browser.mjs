import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { chromium } from 'playwright';

const root = new URL('../', import.meta.url);
const indexHtml = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const serverClient = await readFile(new URL('../atina-server-client.js', import.meta.url), 'utf8');

const server = createServer((request, response) => {
  if (request.url === '/' || request.url === '/index.html') {
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    response.end(indexHtml);
    return;
  }
  if (request.url === '/atina-server-client.js') {
    response.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8' });
    response.end(serverClient);
    return;
  }
  response.writeHead(404);
  response.end('Not found');
});

await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const address = server.address();
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
const pageErrors = [];

page.on('pageerror', error => pageErrors.push(error.message));
await page.route('https://commons.wikimedia.org/**', route => route.fulfill({ status: 200, contentType: 'application/json', body: '{\"query\":{\"pages\":{}}}' }));\nawait page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2', route => route.fulfill({
  status: 200,
  contentType: 'application/javascript',
  body: `
    window.__mockRpcCalls = [];
    const auth = {
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
      getSession: async () => ({ data: { session: null }, error: null }),
      signOut: async () => ({ error: null }),
      signInWithPassword: async () => ({ error: null }),
      signUp: async () => ({ data: { session: null }, error: null }),
      resetPasswordForEmail: async () => ({ error: null }),
      updateUser: async () => ({ error: null })
    };
    window.supabase = {
      createClient: () => ({
        auth,
        from: () => ({
          select() { return this; },
          eq() { return this; },
          maybeSingle: async () => ({ data: null, error: null })
        }),
        rpc: async (name, args) => {
          window.__mockRpcCalls.push({ name, args });
          if (name === 'atina_progress_register') {
            return { data: { player_id: '00000000-0000-4000-8000-000000000001', nickname: args.p_nickname, xp: 0, level: 1, total_challenges: 0, daily_count: 0 }, error: null };
          }
          if (name === 'atina_progress_leaderboard') {
            return { data: [{ nickname: 'BrowserTester', xp: 10, level: 1, challenges: 1 }], error: null };
          }
          if (name === 'atina_progress_claim_local') {
            return { data: { awarded: true, challenge_xp: 10, daily_bonus: 0, xp: 10, level: 1, total_challenges: 1, daily_count: 1 }, error: null };
          }
          return { data: null, error: null };
        }
      })
    };
  `
}));

try {
  await page.goto(`http://127.0.0.1:${address.port}/`, { waitUntil: 'load' });
  await page.locator('#atinaCloudRegister').waitFor({ state: 'visible' });
  assert.equal(await page.title(), 'ATINA — Pensa. Descobre. Atina.');

  await page.locator('#atinaCloudNickname').fill('BrowserTester');
  await page.locator('#atinaCloudRegister').click();
  await page.getByText('Pseudónimo guardado. A progressão está sincronizada.').waitFor();
  const deviceToken = await page.evaluate(() => localStorage.getItem('atinaProgressDeviceTokenV1'));
  assert.match(deviceToken, /^[0-9a-f]{64}$/);
  assert.equal(await page.locator('#atinaCloudXp').textContent(), '0 XP');

  await page.locator('#atinaCloudLeaderboardRefresh').click();
  await page.locator('#atinaCloudLeaderboard').getByText(/BrowserTester — 10 XP/).waitFor();

  const wrongResultClaimCount = await page.evaluate(() => {
    const sessionId = '00000000-0000-4000-8000-000000000123';
    atinaServerSession = { session_id: sessionId, token: 'a'.repeat(64) };
    atinaServerState = { session_id: sessionId, position: 1 };
    const state = {
      session_id: sessionId, position: 1, round_locked: true, status: 'active',
      mode: 'solo', scores: [0, 0], current_player: 1, queue_size: 1,
      difficulty: 'easy', last_result: { outcome: 'wrong', penalty: 10 },
      challenge: { category: 'Teste', emoji: '🧪', clues: [], total_clues: 5, answer: 'Resposta' }
    };
    atinaServerApplyState(state);
    return window.__mockRpcCalls.filter(call => call.name === 'atina_progress_claim_local').length;
  });
  assert.equal(wrongResultClaimCount, 0, 'Uma resposta errada nunca pode gerar um pedido de XP.');

  await page.evaluate(() => {
    const sessionId = '00000000-0000-4000-8000-000000000123';
    atinaServerState = { session_id: sessionId, position: 1 };
    atinaServerApplyState({
      session_id: sessionId, position: 1, round_locked: true, status: 'active',
      mode: 'solo', scores: [10, 0], current_player: 1, queue_size: 1,
      difficulty: 'easy', last_result: { outcome: 'correct', points: 10 },
      challenge: { category: 'Teste', emoji: '🧪', clues: [], total_clues: 5, answer: 'Resposta' }
    });
  });
  await page.getByText(/\+10 XP confirmado pelo servidor/).waitFor();
  assert.equal(await page.locator('#atinaCloudXp').textContent(), '10 XP');

  const calls = await page.evaluate(() => window.__mockRpcCalls);
  const claims = calls.filter(call => call.name === 'atina_progress_claim_local');
  assert.equal(claims.length, 1, 'A ronda correta deve originar exatamente um claim.');
  assert.deepEqual(Object.keys(claims[0].args).sort(), [
    'p_device_token', 'p_position', 'p_session_id', 'p_session_token'
  ].sort(), 'O cliente não pode enviar XP ou pontos à RPC.');
  assert.equal(claims[0].args.p_device_token, deviceToken);
  assert.equal(claims[0].args.p_position, 1);
  assert.equal(claims[0].args.p_session_token, 'a'.repeat(64));

  assert.deepEqual(pageErrors, [], 'A página não deve produzir erros JavaScript.');
  process.stdout.write('Browser E2E passed: perfil pseudónimo, token de dispositivo, leaderboard, bloqueio de XP em respostas erradas e claim de +10 XP apenas após resultado correto bloqueado pelo servidor.\\n');
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
