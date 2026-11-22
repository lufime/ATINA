import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { chromium } from 'playwright';

const indexHtml = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const challengeImageBank = indexHtml.match(/const games=\[[\s\S]*?\];/);
assert.ok(challengeImageBank, 'Banco de desafios deve existir no HTML.');
const gameCategories = new Set([...challengeImageBank[0].matchAll(/\[\s*\"([^\"]+)\"\s*,\s*\"[^\"]+\"\s*,/g)].map(match => match[1]));
assert.ok(gameCategories.size > 0, 'Banco local deve ter categorias reconhecíveis.');
assert.doesNotMatch(challengeImageBank[0], /https?:\/\//, 'Banco de desafios não deve conter imagens externas.');
const solutionImageCatalog = JSON.parse(await readFile(new URL('../solution-images.json', import.meta.url), 'utf8'));
assert.ok(Array.isArray(solutionImageCatalog.images), 'Catálogo de imagens deve ter uma lista válida.');
assert.ok(!solutionImageCatalog.images.some(item => String(item.image || '').includes('http://') || String(item.image || '').includes('https://')), 'Catálogo de soluções não deve conter imagens externas.');
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
const pageDialogs = [];
page.on('pageerror', error => pageErrors.push(error.message));
page.on('dialog', async dialog => { pageDialogs.push(dialog.message()); await dialog.dismiss(); });
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
  async function confirmPregame(){
    await page.locator('#atinaPregameOverlay.open').waitFor({state:'visible',timeout:5000});
    const categoryPicker = page.locator('#atinaSoloCategoryPicker');
    if (await categoryPicker.isVisible()) {
      const options = await page.locator('#atinaSoloCategory option').evaluateAll(nodes => nodes.map(n => n.value).filter(Boolean));
      if (options.length) await page.locator('#atinaSoloCategory').selectOption(options[0]);
    }
    await page.locator('#atinaPregameStart').waitFor({state:'visible',timeout:5000});
    await page.waitForFunction(() => {
      const button=document.querySelector('#atinaPregameStart');
      return button && !button.disabled;
    }, null, {timeout:5000});
    await page.locator('#atinaPregameStart').click();
  }
    await page.goto(`http://127.0.0.1:${server.address().port}/`, {waitUntil:'load'});
  assert.equal(await page.evaluate(() => typeof window.ATINARoomRuntime?.turnKey), 'function',
    'O runtime reconstruído do modo sala tem de carregar no browser.');

  // Countdown da sala: permitir a primeira pista manualmente, mantendo as outras ações bloqueadas.
  await page.evaluate(async () => {
    networkRoom = {room_id:'room-test',token:'t'.repeat(64)};
    networkGameActive = true;
    games[1001] = [null, null, ['Pista válida para o teste de preparação']];
    networkGameState = {
      mode:'challenges',pos:0,queue:[1001],challenge_id:1001,active_team:'Equipa A',
      prepare_until:Date.now()+15000,revealed:0,locked:false,total_clues:5
    };
    networkLobbyData = {team:'Equipa A',player_id:'player-a',players:[{id:'player-a',team:'Equipa A'}]};
    // Este cenário não simula o RPC de estado da sala: evitar que a resposta mock
    // (null) sobrescreva o estado de teste após a revelação manual.
    networkRefreshRoom = async () => {};
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
assert.ok(categories.every(name => gameCategories.has(name)), 'Solo não deve mostrar categorias sem desafios no banco local (causa do contador 0).');

  // Regressão: dificuldade sem desafios não deve recorrer a desafios de outra dificuldade.
  await page.evaluate(() => {
    window.__originalChallengeDifficulty = classifyChallenge;
    classifyChallenge = () => 'hard';
    difficultyMode = 'easy';
    $('difficultyMode').value = 'easy';
    localStorage.setItem('atinaDifficultyMode', 'easy');
    showHomePage('categories');
  });
  await page.locator('#categories [data-category]').filter({hasText:categories[0]}).click();
  await page.locator('#atinaPregameOverlay.open').waitFor({state:'visible',timeout:5000});
  assert.equal(await page.locator('#atinaPregameCount').inputValue(), '0',
    'Sem desafios da dificuldade selecionada, a quantidade deve ser zero (sem fallback para outra dificuldade).');
  assert.equal(await page.locator('#atinaPregameConfirm').isDisabled(), true,
    'Não deve permitir validar uma configuração sem desafios nessa dificuldade.');
  await page.locator('#atinaPregameCancel').click();
  await page.evaluate(() => {
    classifyChallenge = window.__originalChallengeDifficulty;
    // Restaurar estado consistente para não contaminar o cenário seguinte.
    difficultyMode = 'medium';
    $('difficultyMode').value = 'medium';
    localStorage.setItem('atinaDifficultyMode', 'medium');
  });

  // Regressão: o atalho Solo deve abrir a seleção de modalidades antes da partida.
  await page.evaluate(() => showHomePage('dashboard'));
  await page.locator('[data-atina-launch="solo"]').click();
  await page.locator('#home [data-home-page="categories"]').first().waitFor({state:'visible',timeout:5000});
  assert.equal(await page.locator('#categories [data-category]').first().isVisible(), true,
    'O atalho Solo deve apresentar a seleção de modalidades.');
  // O utilizador escolhe uma modalidade e inicia a partida.
  await page.locator('#categories [data-category]').filter({hasText: categories[0]}).click();
  await page.locator('#atinaPregameOverlay.open').waitFor({state:'visible',timeout:5000});
  assert.equal(await page.locator('#atinaPregameCount').inputValue(),'10','Solo deve iniciar com 10 desafios por defeito.');
  assert.equal(await page.locator('#atinaPregameDifficulty').inputValue(),'medium','Solo deve iniciar com dificuldade média por defeito.');
  await confirmPregame();
  await page.locator('#game').waitFor({state:'visible',timeout:5000}).catch(async () => {
    const state = await page.evaluate(() => ({startType:typeof start,session:localStorage.getItem('atinaAccountSessionV1'),guest:atinaGuestLimitReached(),guestCount:localStorage.getItem('atinaGuestChallengesCompletedV1'),gameCount:games.length,difficulty:difficultyMode,queueLength:queue.length,mode,screen:localStorage.getItem('atinaLastScreen'),dashboardHidden:document.querySelector('[data-home-page="dashboard"]')?.hidden,launchVisible:document.querySelector('[data-atina-launch="solo"]')?.getBoundingClientRect().height>0}));
    throw new Error('Quick Solo não abriu a partida. Diagnóstico: '+JSON.stringify({state,pageDialogs,pageErrors}));
  });
  await page.waitForFunction(() => document.querySelector('#category')?.textContent.trim().length > 0);
  assert.equal(await page.locator('#answer').isEnabled(), true,
    'O arranque rápido Solo deve abrir uma partida jogável, com resposta ativa.');
  await page.evaluate(() => showHomePage('categories'));

  // Usar dificuldade aleatória neste ciclo para garantir desafios em todas as categorias.
  await page.evaluate(() => { difficultyMode='mixed'; $('difficultyMode').value='mixed'; localStorage.setItem('atinaDifficultyMode','mixed'); });
  // Exercitar o ciclo completo do modo individual em todas as modalidades.
  for (const category of categories) {
    await page.evaluate(() => showHomePage('categories'));
    await page.locator('#categories [data-category]').filter({hasText: category}).click();
    await confirmPregame();
    await page.locator('#game').waitFor({state:'visible',timeout:5000}).catch(async () => {
      const state=await page.evaluate(name=>({category:name,mode,difficultyMode,queueLength:queue.length,gameCount:games.length,categoryText:document.querySelector('#category')?.textContent,screen:localStorage.getItem('atinaLastScreen'),matchingGames:games.filter(g=>g&&g[0]===name).length,matchingIndices:games.map((g,i)=>g&&g[0]===name?i:null).filter(i=>i!==null).slice(0,8)}),category);
      throw new Error('Modalidade não abriu no browser: '+JSON.stringify({state,dialogs:pageDialogs.slice(-5),errors:pageErrors.slice(-5)}));
    });
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
  await confirmPregame();
  await page.locator('#game').waitFor({state:'visible'});
  await page.locator('#pass').click();
  await page.getByText(/Desafio passado/).waitFor();
  await page.locator('#continue').click();
  await page.waitForFunction(() => document.querySelector('#level')?.textContent.includes('DESAFIO 2'));

  // Resposta errada não fecha a ronda; a resposta certa seguinte fecha-a.
  await page.evaluate(() => showHomePage('play'));
  await page.locator('#solo').click();
  await page.locator('#home [data-home-page="categories"]').first().waitFor({state:'visible',timeout:5000});
  await page.locator('#categories [data-category]').filter({hasText:categories[0]}).click();
  await confirmPregame();
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
  await confirmPregame();
  await page.locator('#networkModeHint').getByText(/Duelo online/).waitFor();
  await page.evaluate(() => showHomePage('play'));
  await page.locator('#party').click();
  await confirmPregame();
  await page.locator('#networkModeHint').getByText(/Modo Equipas/).waitFor();
  // Mímicas encaminha para o fluxo de sala online.
  await page.evaluate(() => showHomePage('categories'));
  await page.locator('#categories [data-category="Mímicas"]').click();
  await confirmPregame();
  await page.locator('#networkModeHint').getByText(/Mímicas selecionado/).waitFor();

  // Navegação principal, definições e páginas de perfil/classificação sem erros JS.
  for (const target of ['howto','profile','ranking','settings','online','dashboard']) {
    await page.evaluate(name => showHomePage(name), target);
    await page.locator(`[data-home-page="${target}"]`).first().waitFor({state:'visible'});
  }

  // Regressão: a partida rápida mantém a procura online até haver correspondência ou cancelamento.
  await page.evaluate(() => showHomePage('online'));
  await page.evaluate(async () => {
    localStorage.setItem('atinaAccountSessionV1', 's'.repeat(64));
    localStorage.setItem('atinaProgressNicknameV1', 'BrowserTester');
    window.__quickOnlineCalls = [];
    window.__quickOnlineRpcOriginal = supabaseClient.rpc;
    window.__quickOnlineRefreshOriginal = networkRefreshRoom;
    window.__quickOnlinePollingOriginal = networkStartPolling;
    supabaseClient.rpc = async (name, args = {}) => {
      window.__quickOnlineCalls.push({name, args});
      if (name === 'atina_v2_matchmake') return {data:{status:'waiting'},error:null};
      if (name === 'atina_v2_matchmake_status') return {data:{status:'waiting'},error:null};
      if (name === 'atina_v2_cancel_matchmake') return {data:null,error:null};
      return {data:null,error:null};
    };
    networkRefreshRoom = async () => {};
    networkStartPolling = () => {};
    quickMatchStopPolling();
    quickMatchTicket = null;
    quickMatchBusy = false;
  });
  await page.locator('#quickMatchStart').click();
  await page.waitForFunction(() => window.__quickOnlineCalls.some(call => call.name === 'atina_v2_matchmake_status'), null, {timeout:5000});
  const quickStartCall = await page.evaluate(() => window.__quickOnlineCalls.find(call => call.name === 'atina_v2_matchmake'));
  assert.ok(quickStartCall, 'Partida rápida deve criar pedido de matchmaking.');
  assert.deepEqual(Object.keys(quickStartCall.args).sort(), ['p_nickname','p_session_token','p_ticket'],
    'O matchmaking deve enviar nickname, token de sessão e ticket esperados pela RPC.');
  assert.ok(quickStartCall.args.p_session_token, 'O matchmaking deve incluir o token de sessão autenticado.');
  assert.equal(quickStartCall.args.p_nickname, 'BrowserTester');
  // Espera além do antigo período de fallback e confirma que a procura não cria uma sala automática.
  await page.waitForTimeout(8500);
  const waitingState = await page.evaluate(() => ({
    calls: window.__quickOnlineCalls.slice(),
    lobbyVisible: !document.getElementById('networkLobby').classList.contains('hidden'),
    status: document.getElementById('quickMatchStatus').textContent
  }));
  assert.equal(waitingState.lobbyVisible, false, 'A procura sem correspondência não deve abrir uma sala.');
  assert.match(waitingState.status, /À procura de um adversário/);
  assert.equal(waitingState.calls.some(call => call.name === 'atina_v2_create_bot_match'), false,
    'A procura não deve criar uma partida de forma automática.');
  await page.locator('#quickMatchCancel').click();
  await page.waitForFunction(() => window.__quickOnlineCalls.some(call => call.name === 'atina_v2_cancel_matchmake'), null, {timeout:5000});
  await page.evaluate(() => {
    supabaseClient.rpc = window.__quickOnlineRpcOriginal;
    networkRefreshRoom = window.__quickOnlineRefreshOriginal;
    networkStartPolling = window.__quickOnlinePollingOriginal;
    quickMatchTicket = null;
    quickMatchBusy = false;
    networkRoom = null;
    localStorage.removeItem('atinaNetworkRoom');
    screen('home');
    showHomePage('online');
  });
  // Ações online sem sessão devem ser recusadas de forma explícita e segura.
  await page.evaluate(() => showHomePage('online'));
  await page.evaluate(() => localStorage.removeItem('atinaAccountSessionV1'));
  assert.equal(await page.locator('#networkNickname').count(), 0,
    'A interface da sala não deve expor um campo de pseudónimo; o nome vem do perfil ATINA.');
  await page.locator('.network-room-options summary').click();
  await page.locator('#createNetworkRoom').click();
  await page.getByText(/Inicia sessão na tua conta ATINA/).waitFor();
  const starts = await page.evaluate(() => window.__rpcCalls.filter(call => call.name === 'atina_v2_start_local_game').length);
  assert.equal(starts, categories.length + 3, 'Cada modalidade, Solo rápido, Mix e Solo devem iniciar exatamente uma sessão.');
  assert.deepEqual(pageErrors, [], 'A aplicação não deve produzir erros JavaScript durante os fluxos principais.');
  process.stdout.write(`Game browser regression passed: ${categories.length} categorias, Solo, Mix, revelar, resposta errada/certa, PASSO, CONTINUAR, encaminhamento online, bloqueio sem sessão e navegação.\\n`);
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
