import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { chromium } from 'playwright';

const root = new URL('../', import.meta.url);
const indexHtml = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const serverClient = await readFile(new URL('../atina-server-client.js', import.meta.url), 'utf8');
const server = createServer((request, response) => {
  const pathname = new URL(request.url || '/', 'http://127.0.0.1').pathname;
  if (pathname === '/' || pathname === '/index.html') {
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    response.end(indexHtml);
  } else if (pathname === '/atina-server-client.js') {
    response.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8' });
    response.end(serverClient);
  } else { response.writeHead(404); response.end('Not found'); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
const pageErrors = [];
const dialogMessages = [];
page.on('pageerror', error => pageErrors.push(error.message));
await page.route('https://commons.wikimedia.org/**', route => route.fulfill({status:200,contentType:'application/json',body:'{"query":{"pages":{}}}'}));
await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2', route => route.fulfill({
  status:200, contentType:'application/javascript',
  body:`
    window.__mockRpcCalls = [];
    let profile = {player_id:'00000000-0000-4000-8000-000000000001',nickname:'BrowserTester',xp:0,level:1,total_challenges:0,daily_count:0};
    const sessionToken = 'c'.repeat(64);
    const recoveryKey = 'd'.repeat(48);
    const auth = {
      onAuthStateChange: () => ({data:{subscription:{unsubscribe(){}}}}),
      getSession: async () => ({data:{session:null},error:null}),
      signOut: async () => ({error:null}),
      signInWithPassword: async () => ({error:null}),
      signUp: async () => ({data:{session:null},error:null}),
      resetPasswordForEmail: async () => ({error:null}),
      updateUser: async () => ({error:null})
    };
    window.supabase = {createClient: () => ({auth,
      from: () => ({select(){return this;},eq(){return this;},maybeSingle:async()=>({data:null,error:null})}),
      rpc: async (name,args) => {
        window.__mockRpcCalls.push({name,args});
        if(name==='atina_account_register') return {data:{session_token:sessionToken,recovery_key:recoveryKey,profile},error:null};
        if(name==='atina_account_login') return {data:{session_token:sessionToken,profile},error:null};
        if(name==='atina_account_recover') return {data:{session_token:sessionToken,recovery_key:'e'.repeat(48),recovered:true},error:null};
        if(name==='atina_account_profile') return {data:profile,error:null};
        if(name==='atina_progress_claim_local') {
          profile={...profile,xp:15,level:1,total_challenges:1,awarded:true,challenge_xp:15,daily_bonus:0};
          return {data:profile,error:null};
        }
        if(name==='atina_progress_leaderboard') return {data:[{nickname:'BrowserTester',xp:15,level:1}],error:null};
        return {data:null,error:null};
      }
    })};
  `
}));
try {
  await page.goto(`http://127.0.0.1:${server.address().port}/`, {waitUntil:'load'});
  await page.evaluate(() => showHomePage('profile'));
  await page.locator('#atinaAccountRegister').waitFor({state:'visible'});
  await page.locator('#atinaCloudNickname').fill('BrowserTester');
  await page.locator('#atinaAccountPassword').evaluate(el => { el.value = 'x'.repeat(73); });
  await page.locator('#atinaAccountRegister').click();
  assert.match(await page.locator('#atinaCloudStatus').textContent(), /72 bytes UTF-8/);
  assert.equal(await page.evaluate(() => window.__mockRpcCalls.filter(call=>call.name==='atina_account_register').length), 0,
    'Palavras-passe acima de 72 bytes não devem chegar ao RPC.');
  await page.locator('#atinaAccountPassword').fill('CorrectHorseBattery1!');
  page.on('dialog', dialog => { dialogMessages.push(dialog.message()); return dialog.accept(); });
  await page.locator('#atinaAccountRegister').click();
  await page.waitForFunction(() => document.querySelector('#atinaCloudStatus')?.textContent.includes('Conta criada.'), null, {timeout:10000}).catch(async () => {
    throw new Error('O registo não terminou. Estado: '+await page.locator('#atinaCloudStatus').textContent()
      +' · RPC: '+JSON.stringify(await page.evaluate(()=>window.__mockRpcCalls||[]))
      +' · erros: '+JSON.stringify(pageErrors));
  });
  assert.equal(await page.evaluate(() => localStorage.getItem('atinaAccountSessionV1')), 'c'.repeat(64));
  assert.equal(await page.locator('#atinaCloudXp').textContent(), '0 XP');

  // Account sign-in survives a fresh browser context through the server-issued session.
  await page.evaluate(() => localStorage.removeItem('atinaAccountSessionV1'));
  await page.locator('#atinaAccountPassword').fill('CorrectHorseBattery1!');
  await page.locator('#atinaAccountLogin').click();
  await page.getByText('Sessão iniciada. O teu progresso está sincronizado.').waitFor();
  assert.equal(await page.evaluate(() => localStorage.getItem('atinaAccountSessionV1')), 'c'.repeat(64));

  // Recovery must return and display a replacement single-use key.
  await page.locator('#atinaRecoveryArea summary').click();
  await page.locator('#atinaRecoveryKey').fill('d'.repeat(48));
  await page.locator('#atinaNewAccountPassword').fill('AnotherCorrectHorse2!');
  await page.locator('#atinaAccountRecover').click();
  await page.waitForFunction(() => document.querySelector('#atinaCloudStatus')?.textContent.includes('Conta recuperada.'), null, {timeout:10000});
  assert.ok(dialogMessages.some(message => message.includes('e'.repeat(48))),
    'A nova chave de recuperação tem de ser apresentada ao utilizador.');
  const recoveryCall = await page.evaluate(() => window.__mockRpcCalls.find(call => call.name==='atina_account_recover'));
  assert.equal(recoveryCall.args.p_recovery_key,'d'.repeat(48));
  assert.equal(await page.evaluate(() => localStorage.getItem('atinaAccountSessionV1')), 'c'.repeat(64));

  await page.evaluate(() => {
    atinaServerSession={session_id:'00000000-0000-4000-8000-000000000123',token:'a'.repeat(64)};
    atinaCloudProfile={player_id:'00000000-0000-4000-8000-000000000001',nickname:'BrowserTester',xp:0,level:1,total_challenges:0};
  });
  const claimState = {mode:'solo',session_id:'00000000-0000-4000-8000-000000000123',position:1,round_locked:true,last_result:{outcome:'correct',points:15}};
  await page.evaluate(state => atinaProgressClaim(state), claimState);
  await page.getByText(/\+15 XP confirmado pelo servidor/).waitFor();
  assert.equal(await page.locator('#atinaCloudXp').textContent(), '15 XP');
  await page.evaluate(state => atinaProgressClaim(state), claimState);
  const claims = await page.evaluate(() => window.__mockRpcCalls.filter(call=>call.name==='atina_progress_claim_local'));
  assert.equal(claims.length,1,'O mesmo desafio não deve originar claims repetidos no cliente.');
  assert.deepEqual(Object.keys(claims[0].args).sort(),['p_device_token','p_position','p_session_id','p_session_token'].sort());
  assert.equal(claims[0].args.p_device_token,'c'.repeat(64));

  await page.locator('button.home-nav-btn[data-home-target="ranking"]').click();
  await page.locator('#atinaCloudLeaderboardRefresh').click();
  await page.locator('#atinaCloudLeaderboard').getByText(/BrowserTester — 15 XP/).waitFor();
  assert.deepEqual(pageErrors,[],'A aplicação não deve produzir erros JavaScript.');
  process.stdout.write('Browser E2E passed: criar conta, iniciar sessão, sincronizar XP, impedir claims duplicados e apresentar ranking.\\n');
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
