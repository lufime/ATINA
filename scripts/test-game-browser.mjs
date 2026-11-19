import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { chromium } from 'playwright';

const indexHtml = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const serverClient = await readFile(new URL('../atina-server-client.js', import.meta.url), 'utf8');
const roomRuntime = await readFile(new URL('../assets/network-room-runtime.js', import.meta.url), 'utf8');
const server = createServer((request, response) => {
  const pathname = new URL(request.url || '/', 'http://127.0.0.1').pathname;
  if (pathname === '/' || pathname === '/index.html') {
    response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    response.end(indexHtml);
  } else if (pathname === '/atina-server-client.js') {
    response.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8' });
    response.end(serverClient);
  } else if (pathname === '/assets/network-room-runtime.js') {
    response.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8' });
    response.end(roomRuntime);
  } else { response.writeHead(404); response.end('Not found'); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
await page.addInitScript(() => {
  localStorage.setItem('atinaAccountSessionV1', 's'.repeat(64));
  localStorage.setItem('atinaLegalAcknowledgedV2', '1');
  localStorage.setItem('atinaClueSpeechConsent', 'false');
  localStorage.setItem('atinaClueSpeechEnabled', 'false');
  // Headless CI has no guaranteed system voice; disable the browser TTS API deterministically.
  try { Object.defineProperty(window, 'speechSynthesis', {value: undefined, configurable: true}); } catch {}
  try { Object.defineProperty(window, 'SpeechSynthesisUtterance', {value: undefined, configurable: true}); } catch {}
});
const pageErrors = [];
page.on('pageerror', error => pageErrors.push(error.message));
await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2', route => route.fulfill({
  status: 200,
  contentType: 'application/javascript',
  body: `
    window.__rpcCalls = [];
    let session = null;
    const state = () => ({
      session_id: session.id, mode: session.mode, position: session.position,
      queue_size: 3, status: 'playing', scores: session.scores, current_player: 1,
      answered_count: session.answered, round_locked: session.locked,
      difficulty: 'medium', last_result: session.result,
      challenge: {
        id: 1000 + session.position, category: session.category || 'Cultura geral',
        emoji: '🎯', clues: session.clues, total_clues: 5,
        answer: 'Resposta ATINA', tags: [], image_url: null
      }
    });
    const auth = {
      onAuthStateChange: () => ({data:{subscription:{unsubscribe(){}}}}),
      getSession: async () => ({data:{session:null},error:null}),
      signOut: async () => ({error:null}), signInWithPassword: async () => ({error:null}),
      signUp: async () => ({data:{session:null},error:null}),
      resetPasswordForEmail: async () => ({error:null}), updateUser: async () => ({error:null})
    };
    window.supabase = {createClient: () => ({
      auth,
      from: () => ({select(){return this;},eq(){return this;},order(){return this;},limit(){return this;},
        maybeSingle:async()=>({data:null,error:null}),insert:async()=>({data:null,error:null})}),
      rpc: async (name,args={}) => {
        window.__rpcCalls.push({name,args});
        if (name === 'atina_v2_start_local_game') {
          session = {id:'00000000-0000-4000-8000-000000000001',mode:args.p_game_mode,
            category:args.p_category || 'Cultura geral',position:1,clues:[],scores:[0,0],answered:0,locked:false,result:null};
          return {data:{token:'t'.repeat(64),state:state()},error:null};
        }
        if (name === 'atina_v2_local_reveal_clue') {
          session.clues.push('Pista de teste número '+(session.clues.length+1));
          return {data:state(),error:null};
        }
        if (name === 'atina_v2_local_submit_answer') {
          if (String(args.p_answer).trim().toLocaleLowerCase('pt-PT') === 'resposta atina') {
            session.locked=true; session.answered++; session.scores[0]+=20;
            session.result={outcome:'correct',points:20};
          } else {
            session.result={outcome:'wrong',penalty:10};
          }
          return {data:state(),error:null};
        }
        if (name === 'atina_v2_local_pass_challenge') {
          session.locked=true; session.answered++; session.result={outcome:'pass'};
          return {data:state(),error:null};
        }
        if (name === 'atina_v2_local_next_challenge') {
          session.position++; session.clues=[]; session.locked=false; session.result=null;
          return {data:state(),error:null};
        }
        if (name === 'atina_account_profile') return {data:{player_id:'00000000-0000-4000-8000-000000000002',nickname:'BrowserTester',xp:0,level:1,total_challenges:0},error:null};
        if (name === 'atina_progress_claim_local') return {data:{nickname:'BrowserTester',xp:10,level:1,total_challenges:1,awarded:true,challenge_xp:10},error:null};
        if (name === 'atina_points_leaderboard') return {data:[],error:null};
        if (name === 'atina_progress_leaderboard') return {data:[],error:null};
        if (name === 'atina_image_credit') return {data:null,error:null};
        return {data:null,error:null};
      }
    })};
  `
}));
await page.route('https://commons.wikimedia.org/**', route => route.fulfill({
  status: 200, contentType: 'application/json', body: '{"query":{"pages":{}}}'
}));
await page.route('https://images.unsplash.com/**', route => route.abort());

try {
  await page.goto(`http://127.0.0.1:${server.address().port}/`, {waitUntil:'load'});
  assert.equal(await page.evaluate(() => typeof window.ATINARoomRuntime?.turnKey), 'function',
    'O runtime reconstruído do modo sala tem de carregar no browser.');

  // Countdown da sala: permitir a primeira pista manualmente, mantendo as outras ações bloqueadas.
  await page.evaluate(async () => {
    networkRoom = {room_id:'room-test',token:'t'.repeat(64)};
    networkGameActive = true;
    networkGameState = {
      mode:'challenges',pos:0,queue:[1001],challenge_id:1001,active_team:'Equipa A',
      prepare_until:Date.now()+15000,revealed:0,locked:false,total_clues:5
    };
    networkLobbyData = {team:'Equipa A',player_id:'player-a',players:[{id:'player-a',team:'Equipa A'}]};
    networkDrawClock();
    await networkHostReveal();
  });
  assert.equal(await page.locator('#nextClue').isDisabled(), false,
    'A primeira pista deve poder ser revelada durante a preparação.');
  for (const id of ['answer','submit','voice','pass','continue']) {
    assert.equal(await page.locator('#'+id).isDisabled(), true,
      id + ' deve ficar bloqueado durante a contagem da sala.');
  }
  assert.equal(await page.evaluate(() => window.__rpcCalls.some(call => call.name === 'atina_v2_reveal_room_clue')), true,
    'A revelação manual da primeira pista deve poder ser enviada durante o countdown.');
  await page.evaluate(() => {
    networkGameActive = false;
    networkGameState = null;
    networkRoom = null;
    // O cenário acima simula uma sala isolada; repor os controlos antes dos
    // testes seguintes de jogo solo, sem transportar o bloqueio do countdown.
    for (const id of ['nextClue','answer','submit','voice','pass','continue']) {
      const control = document.getElementById(id);
      if (control) control.disabled = false;
    }
  });
  // O turno ativo controla os botões em todos os dispositivos; o anfitrião não pode ignorar a rotação.
  const turnAccess = await page.evaluate(() => {
    networkGameState = {active_team:'Equipa B',pos:0};
    networkLobbyData = {team:'Equipa A'};
    networkGameHost = false;
    const inactiveTeam = networkCanControlTurn();
    networkLobbyData.team = 'Equipa B';
    const activeTeam = networkCanControlTurn();
    networkLobbyData.team = 'Equipa A';
    networkGameHost = true;
    const hostWhenOtherTeamPlays = networkCanControlTurn();
    return {inactiveTeam,activeTeam,hostWhenOtherTeamPlays};
  });
  assert.deepEqual(turnAccess,{inactiveTeam:false,activeTeam:true,hostWhenOtherTeamPlays:false},'Só a equipa ativa pode controlar a ronda, mesmo quando o anfitrião pertence à outra equipa.');
  assert.match(indexHtml, /\$\('nextClue'\)\.disabled=!canControlTurn/, 'A revelação de pistas deve respeitar a equipa ativa.');
  assert.match(indexHtml, /\$\('submit'\)\.disabled=!canControlTurn/, 'O envio de respostas deve respeitar a equipa ativa.');

  await page.evaluate(() => showHomePage('categories'));
  assert.equal(await page.evaluate(() => atinaClueSpeechEnabled), false, 'O teste browser não deve depender de síntese de voz do dispositivo.');
  // A lista final depende da consulta assíncrona de desafios ativos. Esperar
  // pela atualização evita capturar categorias provisórias que serão removidas.
  await page.waitForFunction(() => {
    const panel = document.querySelector('#categories');
    return typeof atinaActiveCategoryCounts !== 'undefined' && atinaActiveCategoryCounts instanceof Map;
  }, null, {timeout:10000}).catch(() => {});
  const categories = await page.locator('#categories [data-category]').evaluateAll(nodes =>
    nodes.map(node => node.getAttribute('data-category')).filter(name => name && name !== 'Mímicas'));
  assert.ok(categories.length > 0, 'Deve existir pelo menos uma modalidade com desafios ativos.');

  // Exercitar o ciclo completo do modo individual em todas as modalidades.
  for (const category of categories) {
    await page.evaluate(() => showHomePage('categories'));
    await page.locator('#categories [data-category]').filter({hasText: category}).click();
    await page.locator('#game').waitFor({state:'visible'});
    await page.waitForFunction(name => document.querySelector('#category')?.textContent.includes(name), category);
    await page.locator('#nextClue').click();
    await page.waitForFunction(() => document.querySelector('#clues .clue:not(.hidden-clue)'));
    await page.locator('#answer').fill('Resposta ATINA');
    await page.locator('#submit').click();
    await page.waitForFunction(() => document.querySelector('#feedback')?.textContent.includes('Certo! Resposta ATINA'), null, {timeout:10000}).catch(async () => {
      throw new Error(category + ': resposta certa não foi confirmada. Feedback: ' +
        await page.locator('#feedback').textContent() + ' · RPC: ' +
        JSON.stringify(await page.evaluate(() => window.__rpcCalls.slice(-5))) +
        ' · erros: ' + JSON.stringify(pageErrors));
    });
    assert.equal(await page.locator('#continue').isVisible(), true, category + ': deve permitir avançar após resposta certa.');
  }

  // Confirmar que Mix inicia uma sessão própria e que PASSO e CONTINUAR funcionam.
  await page.evaluate(() => showHomePage('play'));
  await page.locator('#mix').click();
  await page.locator('#game').waitFor({state:'visible'});
  await page.locator('#pass').click();
  await page.getByText(/Desafio passado/).waitFor();
  await page.locator('#continue').click();
  await page.waitForFunction(() => document.querySelector('#level')?.textContent.includes('DESAFIO 2'));

  // Resposta errada não fecha a ronda; a resposta certa seguinte fecha-a.
  await page.evaluate(() => showHomePage('play'));
  await page.locator('#solo').click();
  await page.locator('#game').waitFor({state:'visible'});
  await page.locator('#answer').fill('Resposta errada');
  await page.locator('#submit').click();
  await page.getByText(/Resposta errada/).waitFor();
  assert.equal(await page.locator('#answer').isEnabled(), true);
  await page.locator('#answer').fill('Resposta ATINA');
  await page.locator('#submit').click();
  await page.getByText(/Certo! Resposta ATINA/).waitFor();

  // Os modos que exigem vários dispositivos encaminham para a área online.
  await page.evaluate(() => showHomePage('play'));
  await page.locator('#duel').click();
  await page.locator('#networkModeHint').getByText(/Duelo online/).waitFor();
  await page.evaluate(() => showHomePage('play'));
  await page.locator('#party').click();
  await page.locator('#networkModeHint').getByText(/Modo Equipas/).waitFor();
  // Mímicas encaminha para o fluxo de sala online.
  await page.evaluate(() => showHomePage('categories'));
  await page.locator('#categories [data-category="Mímicas"]').click();
  await page.locator('#networkModeHint').getByText(/Mímicas selecionado/).waitFor();

  // Navegação principal, definições e páginas de perfil/classificação sem erros JS.
  for (const target of ['howto','profile','ranking','settings','online','dashboard']) {
    await page.evaluate(name => showHomePage(name), target);
    await page.locator(`[data-home-page="${target}"]`).first().waitFor({state:'visible'});
  }

  // Ações online sem sessão devem ser recusadas de forma explícita e segura.
  await page.evaluate(() => showHomePage('online'));
  await page.evaluate(() => localStorage.removeItem('atinaAccountSessionV1'));
  assert.equal(await page.locator('#networkNickname').isEditable(), false,
    'O pseudónimo da sala deve ser apenas de leitura e vir da conta ATINA.');
  await page.locator('.network-room-options summary').click();
  await page.locator('#createNetworkRoom').click();
  await page.getByText(/Inicia sessão na tua conta ATINA/).waitFor();
  const starts = await page.evaluate(() => window.__rpcCalls.filter(call => call.name === 'atina_v2_start_local_game').length);
  assert.equal(starts, categories.length + 2, 'Cada modalidade, Mix e Solo devem iniciar exatamente uma sessão.');
  assert.deepEqual(pageErrors, [], 'A aplicação não deve produzir erros JavaScript durante os fluxos principais.');
  process.stdout.write(`Game browser regression passed: ${categories.length} categorias, Solo, Mix, revelar, resposta errada/certa, PASSO, CONTINUAR, encaminhamento online, bloqueio sem sessão e navegação.\\n`);
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
