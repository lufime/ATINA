/* ATINA server-authoritative client. No answer keys are shipped to the browser. */
const ATINA_SERVER_SESSION_KEY = 'atinaServerSessionV1';
let atinaServerSession = null;
let atinaServerState = null;
let atinaServerTimer = null;
let atinaServerPolling = null;
let atinaServerBusy = false;
let atinaServerLastResult = '{}';
let atinaNetworkChallengeKey = '';
let atinaNetworkFeedback = '';

async function atinaServerRpc(name, args) {
  if (!supabaseClient) throw new Error('É necessária uma ligação à Internet para jogar. Atualiza a página e tenta novamente.');
  const { data, error } = await supabaseClient.rpc(name, args);
  if (error) throw error;
  return data;
}
function atinaServerMessage(message) {
  const gameVisible = $('game') && !$('game').classList.contains('hidden');
  if (gameVisible) {
    $('feedback').textContent = message;
  if (locked) atinaShowSolutionImage(challenge.answer, challenge.category, 'solutionImage'); else $('solutionImage')?.classList.add('hidden');
    return;
  }
  const target = $('networkStatus') || $('networkLobbyStatus');
  if (target) target.textContent = message;
  const home = $('home');
  if (home) {
    let notice = $('atinaConnectionNotice');
    if (!notice) {
      notice = document.createElement('p');
      notice.id = 'atinaConnectionNotice';
      notice.className = 'feedback';
      notice.setAttribute('aria-live', 'polite');
      home.insertBefore(notice, home.firstChild);
    }
    notice.textContent = message;
  }
}
function atinaServerStopTimers() {
  if (atinaServerTimer !== null) clearInterval(atinaServerTimer);
  if (atinaServerPolling !== null) clearInterval(atinaServerPolling);
  atinaServerTimer = null;
  atinaServerPolling = null;
  if (timerInterval !== null) clearInterval(timerInterval);
  timerInterval = null;
}
function atinaServerRenderTimer() {
  const challenge = atinaServerState?.challenge;
  const deadline = atinaServerState?.deadline_at ? Date.parse(atinaServerState.deadline_at) : 0;
  if (!deadline || atinaServerState?.round_locked) {
    $('timerDisplay').textContent = deadline ? '00:00' : 'Sem limite';
    $('timerDisplay').classList.remove('urgent');
    return;
  }
  const remaining = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
  timeLeft = remaining;
  $('timerDisplay').textContent = String(Math.floor(remaining / 60)).padStart(2, '0') + ':' + String(remaining % 60).padStart(2, '0');
  $('timerDisplay').classList.toggle('urgent', remaining <= 10);
  if (remaining === 0) atinaServerRefresh().catch(() => {});
}
function atinaServerStartTimers() {
  atinaServerStopTimers();
  atinaServerRenderTimer();
  atinaServerTimer = setInterval(atinaServerRenderTimer, 250);
  atinaServerPolling = setInterval(() => atinaServerRefresh().catch(() => {}), 2500);
}
function atinaServerApplyState(state, announce = false) {
  if (!state?.challenge) throw new Error('O servidor devolveu um estado de jogo inválido.');
  const sameChallenge = !!(atinaServerState && atinaServerState.session_id === state.session_id && atinaServerState.position === state.position);
  const resultKey = JSON.stringify(state.last_result || {});
  const clearAnswer = !sameChallenge || resultKey !== atinaServerLastResult;
  atinaServerLastResult = resultKey;
  atinaServerState = state;
  mode = state.mode;
  scores = Array.isArray(state.scores) ? state.scores : [0, 0];
  player = Math.max(0, Number(state.current_player || 1) - 1);
  pos = Math.max(0, Number(state.position || 1) - 1);
  queue = Array.from({ length: Number(state.queue_size || 0) }, (_, i) => i);
  revealed = (state.challenge.clues || []).length;
  locked = !!state.round_locked;
  answeredCount = Number(state.answered_count || 0);
  difficultyMode = state.difficulty || difficultyMode;
  const challenge = state.challenge;
  const total = Number(challenge.total_clues || (challenge.image_url ? 6 : 5));
  $('category').textContent = (challenge.emoji || '') + ' ' + (challenge.category || 'Desafio');
  $('level').textContent = 'DESAFIO ' + (pos + 1) + ' / ' + queue.length + ' · ' + difficultyLabel(difficultyMode);
  $('player').textContent = mode === 'duel' ? 'Vez do Jogador ' + (player + 1) : mode === 'party' ? '🎉 Vez da Equipa ' + (player + 1) : mode === 'mix' ? '🔀 Modo Mix' : 'Modo individual';
  $('clues').replaceChildren();
  for (let i = 0; i < total; i++) {
    const item = document.createElement('div');
    const clue = challenge.clues?.[i];
    item.className = 'clue' + (clue === undefined ? ' hidden-clue' : '');
    item.textContent = clue === undefined ? 'Pista ' + (i + 1) + ': ainda escondida' : 'Pista ' + (i + 1) + ': ' + clue;
    $('clues').appendChild(item);
  }
  $('clueProgress').textContent = revealed + ' de ' + total + ' reveladas';
  $('nextClue').disabled = locked || revealed >= total;
  $('nextClue').textContent = revealed >= total ? 'Todas as pistas reveladas' : 'Revelar próxima pista';
  $('answer').disabled = locked;
  $('submit').disabled = locked;
  $('pass').disabled = locked;
  $('continue').classList.toggle('hidden', !locked);
  $('listenAnswer').classList.toggle('hidden', !locked || !challenge.answer);
  $('visualWrap').classList.toggle('hidden', !challenge.image_url);
  if (challenge.image_url) {
    $('mysteryImage').src = challenge.image_url;
    $('mysteryImage').style.setProperty('--blur', locked ? '0px' : Math.max(0, 24 - revealed * 4) + 'px');
    $('veil').style.setProperty('--veil', locked ? '0' : '.35');
    $('revealLabel').textContent = locked ? 'Imagem totalmente revelada' : 'Imagem misteriosa';
    renderPuzzle(Math.max(1, revealed));
  }
  const result = state.last_result || {};
  let message = '';
  if (result.outcome === 'correct') {
    message = 'Certo! ' + (challenge.answer || 'Resposta validada pelo servidor') + ' · +' + Number(result.points || 0) + ' pontos.';
    if (result.party_final_round_bonus) message += ' Bónus da última ronda aplicado.';
  } else if (result.outcome === 'wrong') message = 'Resposta errada: −' + Number(result.penalty || 10) + ' pontos. Tenta novamente.';
  else if (result.outcome === 'timeout') message = '⏰ Tempo esgotado. ' + (challenge.answer ? 'Resposta: ' + challenge.answer : '');
  else if (result.outcome === 'pass') message = 'Desafio passado. ' + (challenge.answer ? 'Resposta: ' + challenge.answer : '');
  else if (locked) message = challenge.answer ? 'Resposta: ' + challenge.answer : 'Ronda terminada.';
  else message = 'A validação é feita pelo servidor. Escreve a tua resposta.';
  $('feedback').textContent = message;
  if (clearAnswer) $('answer').value = '';
  $('feedback').classList.remove('is-correct', 'is-wrong', 'is-info');
  $('feedback').classList.add(result.outcome === 'correct' ? 'is-correct' : result.outcome === 'wrong' || result.outcome === 'timeout' ? 'is-wrong' : 'is-info');
  $('networkScoreboard').classList.add('hidden');
  update();
  board();
  if (announce) screen('game');
  if (state.status === 'completed') {
    atinaServerStopTimers();
    $('resultText').textContent = 'Partida concluída. Resultado: ' + scores.join('–') + ' pontos.';
    screen('result');
  } else if (sameChallenge) {
    atinaServerStartTimers();
  } else {
    atinaServerStopTimers();
    const expectedSession = state.session_id;
    const expectedPosition = state.position;
    const finalGame = [challenge.category || 'Desafio', challenge.emoji || '🎯'];
    mixDraw(finalGame, state.difficulty || difficultyMode).finally(() => {
      if (atinaServerState?.session_id === expectedSession && atinaServerState?.position === expectedPosition && atinaServerState?.status !== 'completed') atinaServerStartTimers();
    });
  }
}
async function atinaServerRefresh() {
  if (!atinaServerSession || atinaServerBusy) return;
  atinaServerBusy = true;
  try {
    const state = await atinaServerRpc('atina_v2_local_game_state', {
      p_session_id: atinaServerSession.session_id,
      p_token: atinaServerSession.token
    });
    atinaServerApplyState(state);
  } finally {
    atinaServerBusy = false;
  }
}
async function atinaServerStart(gameMode, category = null) {
  atinaServerStopTimers();
  atinaServerBusy = true;
  atinaServerMessage('A preparar uma partida segura no servidor…');
  try {
    const duration = Number($('timerMode')?.value ?? 60);
    const difficulty = $('difficultyMode')?.value || 'medium';
    const response = await atinaServerRpc('atina_v2_start_local_game', {
      p_game_mode: gameMode,
      p_difficulty: difficulty,
      p_category: category,
      p_timed_mode_seconds: Number.isFinite(duration) ? duration : 60
    });
    if (!response?.token || !response?.state?.session_id) throw new Error('Não foi possível iniciar a sessão segura.');
    atinaServerSession = { session_id: response.state.session_id, token: response.token };
    localStorage.setItem(ATINA_SERVER_SESSION_KEY, JSON.stringify(atinaServerSession));
    screen('game');
    atinaServerApplyState(response.state);
  } catch (error) {
    atinaServerMessage(error.message || 'Não foi possível iniciar a partida. É necessária ligação à Internet.');
    screen('home');
  } finally {
    atinaServerBusy = false;
  }
}
start = function(gameMode, category = null) { return atinaServerStart(gameMode, category); };
submit = async function() {
  if (!atinaServerState || locked || atinaServerBusy) return;
  const answer = $('answer').value.trim();
  if (!answer) { atinaServerMessage('Escreve primeiro a tua resposta.'); $('answer').focus(); return; }
  atinaServerBusy = true;
  try {
    const state = await atinaServerRpc('atina_v2_local_submit_answer', {
      p_session_id: atinaServerSession.session_id,
      p_token: atinaServerSession.token,
      p_answer: answer
    });
    playAtinaSound(state.last_result?.outcome === 'correct' ? 'correct' : 'wrong');
    $('answer').value = '';
    atinaServerApplyState(state);
  } catch (error) { atinaServerMessage(error.message || 'Não foi possível validar a resposta.'); }
  finally { atinaServerBusy = false; }
};
reveal = async function() {
  if (!atinaServerState || locked || atinaServerBusy) return;
  atinaServerBusy = true;
  try {
    const state = await atinaServerRpc('atina_v2_local_reveal_clue', {
      p_session_id: atinaServerSession.session_id, p_token: atinaServerSession.token
    });
    playAtinaSound('clue');
    atinaServerApplyState(state);
  } catch (error) { atinaServerMessage(error.message || 'Não foi possível revelar a pista.'); }
  finally { atinaServerBusy = false; }
};
pass = async function() {
  if (!atinaServerState || locked || atinaServerBusy) return;
  atinaServerBusy = true;
  try {
    const state = await atinaServerRpc('atina_v2_local_pass_challenge', {
      p_session_id: atinaServerSession.session_id, p_token: atinaServerSession.token
    });
    playAtinaSound('pass');
    atinaServerApplyState(state);
  } catch (error) { atinaServerMessage(error.message || 'Não foi possível passar o desafio.'); }
  finally { atinaServerBusy = false; }
};
next = async function() {
  if (!atinaServerState || !locked || atinaServerBusy) return;
  atinaServerBusy = true;
  try {
    const state = await atinaServerRpc('atina_v2_local_next_challenge', {
      p_session_id: atinaServerSession.session_id, p_token: atinaServerSession.token
    });
    atinaServerApplyState(state);
  } catch (error) { atinaServerMessage(error.message || 'Não foi possível avançar.'); }
  finally { atinaServerBusy = false; }
};
load = function() { if (atinaServerState) atinaServerApplyState(atinaServerState); };
saveLocalProgress = function() {};
restoreLocalProgress = function() { return false; };
update = function() {
  $('totalScore').textContent = (mode === 'duel' || mode === 'party')
    ? 'Jogador/Equipa 1: ' + scores[0] + ' · Jogador/Equipa 2: ' + scores[1]
    : '⭐ ' + scores[0] + ' pontos';
  $('progress').textContent = answeredCount + ' / ' + queue.length + ' desafios concluídos';
};
board = function() {
  const label = mode === 'duel' ? 'Jogador 1: ' + scores[0] + ' · Jogador 2: ' + scores[1]
    : mode === 'party' ? 'Equipa 1: ' + scores[0] + ' · Equipa 2: ' + scores[1]
    : 'Desafio ' + (pos + 1) + ' de ' + queue.length + ' · ' + scores[0] + ' pontos';
  $('scoreboard').textContent = label;
};
raceStart = function() {};
raceStop = function() {};
timerTick = function() { atinaServerRenderTimer(); };
stopTimer = function() {
  if (timerInterval !== null) clearInterval(timerInterval);
  timerInterval = null;
  if (atinaServerTimer !== null) clearInterval(atinaServerTimer);
  atinaServerTimer = null;
};
startTimer = function() { atinaServerStartTimers(); };
$('listenAnswer').onclick = () => {
  const answer = atinaServerState?.challenge?.answer || networkGameState?.answer;
  if (!answer) return;
  if ('speechSynthesis' in window) {
    window.speechSynthesis.cancel();
    const speech = new SpeechSynthesisUtterance('A resposta correta é: ' + answer);
    speech.lang = 'pt-PT';
    window.speechSynthesis.speak(speech);
  } else atinaServerMessage('A leitura em voz alta não está disponível neste navegador.');
};
$('back').onclick = () => {
  if (networkRoom) { networkLeaveRoom(); return; }
  atinaServerStopTimers();
  atinaServerSession = null;
  atinaServerState = null;
  localStorage.removeItem(ATINA_SERVER_SESSION_KEY);
  screen('home');
};
// O botão local de Mímicas é gerido pelo próprio modo local em index.html.

function atinaServerIsInvalidSession(error) {
  return error?.code === '28000' || /Sessão inválida ou expirada/i.test(error?.message || '');
}
async function atinaServerRestoreSession() {
  let saved = null;
  try { saved = JSON.parse(localStorage.getItem(ATINA_SERVER_SESSION_KEY) || 'null'); } catch (_) { localStorage.removeItem(ATINA_SERVER_SESSION_KEY); }
  if (!saved?.session_id || !saved?.token) return false;
  atinaServerSession = saved;
  try {
    const state = await atinaServerRpc('atina_v2_local_game_state', { p_session_id: saved.session_id, p_token: saved.token });
    screen('game');
    atinaServerApplyState(state);
    return true;
  } catch (error) {
    if (atinaServerIsInvalidSession(error)) {
      atinaServerSession = null;
      localStorage.removeItem(ATINA_SERVER_SESSION_KEY);
    } else {
      atinaServerMessage('Não foi possível recuperar a partida devido a uma falha de ligação. A sessão foi preservada; verifica a Internet e tenta novamente.');
    }
    return false;
  }
}

/* Multiplayer challenges use only server-issued state and server-side scoring. */
networkDrawClock = function() {
  const st = networkGameState;
  if (!st || !networkGameActive) return;
  if (st.mode === 'mimicas') {
    const deadline = Number(st.deadline || 0);
    const remaining = deadline ? Math.max(0, Math.ceil((deadline - Date.now()) / 1000)) : 0;
    $('mimeTimer').textContent = deadline ? String(Math.floor(remaining / 60)).padStart(2, '0') + ':' + String(remaining % 60).padStart(2, '0') : '∞';
    return;
  }
  const pause = st.pause;
  if (pause && Date.parse(pause.ends_at) > Date.now()) {
    const left = Math.max(0, Math.ceil((Date.parse(pause.ends_at) - Date.now()) / 1000));
    $('timerDisplay').textContent = 'PAUSA · ' + String(Math.floor(left / 60)).padStart(2, '0') + ':' + String(left % 60).padStart(2, '0');
    $('timerDisplay').classList.remove('urgent');
    return;
  }
  const deadline = Number(st.deadline || 0);
  const remaining = deadline ? Math.max(0, Math.ceil((deadline - Date.now()) / 1000)) : 0;
  $('timerDisplay').textContent = deadline ? String(Math.floor(remaining / 60)).padStart(2, '0') + ':' + String(remaining % 60).padStart(2, '0') : 'Sem limite';
  $('timerDisplay').classList.toggle('urgent', !!deadline && remaining <= 10);
  timeLeft = remaining;
};
networkReceiveState = function(st) {
  if (!st || (!['challenges', 'mimicas', 'completed'].includes(st.mode))) return;
  if (networkGameState && Number(st.revision || 0) <= Number(networkLastRevision || 0)) return;
  const previous = networkGameState;
  const changed = !previous || previous.pos !== st.pos || previous.challenge_id !== st.challenge_id || previous.round !== st.round || previous.mode !== st.mode;
  if (changed) { atinaNetworkChallengeKey = [st.mode,st.pos,st.challenge_id,st.round].join(':'); atinaNetworkFeedback = ''; $('answer').value = ''; }
  networkGameState = st;
  networkLastRevision = Number(st.revision || 0);
  networkGameActive = st.mode !== 'completed';
  if (changed) networkAnsweredThisChallenge = false;
  networkGameHost = !!networkLobbyData?.is_host;
  if (st.mode === 'mimicas') {
    if (st.finished && networkClockHandle !== null) { clearInterval(networkClockHandle); networkClockHandle = null; }
    networkRenderMimeState();
    if (!st.finished) ensureNetworkClock();
  } else if (st.mode === 'completed') {
    networkGameActive = false;
    if (networkClockHandle !== null) { clearInterval(networkClockHandle); networkClockHandle = null; }
    $('resultText').textContent = 'Partida multiplayer concluída. Consulta a classificação da sala.';
    screen('result');
  } else {
    if ($('game').classList.contains('hidden')) screen('game');
    networkRenderGameState();
    ensureNetworkClock();
  }
};
networkStartGame = async function() {
  if (!networkRoom || !networkLobbyData?.is_host) return;
  try {
    await networkCall('atina_v2_start_room', { p_room_id: networkRoom.room_id, p_token: networkRoom.token });
    const duration = Number($('timerMode')?.value ?? 60);
    const difficulty = $('difficultyMode')?.value || 'medium';
    await networkCall('atina_v2_start_room_challenges', {
      p_room_id: networkRoom.room_id, p_token: networkRoom.token,
      p_difficulty: difficulty, p_duration_seconds: Number.isFinite(duration) ? duration : 60,
      p_category: null
    });
    networkGameActive = true;
    await networkRefreshRoom();
    screen('game');
  } catch (error) { networkMessage('networkLobbyStatus', error.message || 'Não foi possível iniciar os desafios.'); }
};
networkRenderGameState = function() {
  const st = networkGameState;
  if (!st || st.mode !== 'challenges') return;
  if (Number(st.pos) >= Number(st.queue_length)) {
    networkGameActive = false;
    if (networkClockHandle) clearInterval(networkClockHandle);
    networkClockHandle = null;
    const players = (networkLobbyData?.players || []).slice().sort((a, b) => b.score - a.score);
    $('resultText').textContent = 'Partida multiplayer concluída.\n' + players.map((p, i) => (i + 1) + '. ' + p.nickname + ' — ' + p.score + ' pontos').join('\n');
    screen('result');
    return;
  }
  const paused = !!(st.pause && Date.parse(st.pause.ends_at) > Date.now());
  $('category').textContent = (st.emoji || '') + ' ' + (st.category || 'Desafio');
  $('level').textContent = 'DESAFIO ' + (Number(st.pos) + 1) + ' / ' + st.queue_length;
  $('player').textContent = 'Multijogador · ' + (networkGameHost ? 'Anfitrião' : 'Jogador');
  $('clues').replaceChildren();
  const total = st.image_url ? 6 : 5;
  for (let i = 0; i < total; i++) {
    const item = document.createElement('div');
    const clue = st.clues?.[i];
    item.className = 'clue' + (clue === undefined ? ' hidden-clue' : '');
    item.textContent = clue === undefined ? 'Pista ' + (i + 1) + ': ainda escondida' : 'Pista ' + (i + 1) + ': ' + clue;
    $('clues').appendChild(item);
  }
  $('clueProgress').textContent = Number(st.revealed || 1) + ' de ' + total + ' reveladas';
  $('nextClue').disabled = !networkGameHost || st.locked || Number(st.revealed) >= total || paused;
  $('pass').disabled = !networkGameHost || st.locked || paused;
  $('pass').classList.toggle('hidden', !networkGameHost);
  $('continue').classList.toggle('hidden', !networkGameHost || !st.locked || paused);
  $('answer').disabled = !!st.locked || paused || networkAnsweredThisChallenge;
  $('submit').disabled = !!st.locked || paused || networkAnsweredThisChallenge;
  $('feedback').textContent = st.locked ? 'Resposta: ' + (st.answer || 'ronda terminada') : (atinaNetworkFeedback || 'A resposta será validada pelo servidor.');
  $('networkScoreboard').classList.remove('hidden');
  renderTeamProposal();
  const players = networkLobbyData?.players || [];
  const totals = {};
  players.forEach(p => { if (p.team) totals[p.team] = (totals[p.team] || 0) + Number(p.score || 0); });
  $('scoreboard').textContent = Object.keys(totals).length
    ? Object.entries(totals).map(([team, score]) => team + ': ' + score + ' pontos').join(' · ')
    : players.map(p => p.nickname + ': ' + p.score + ' pontos').join(' · ');
  const deadline = Number(st.deadline || 0);
  const remaining = deadline ? Math.max(0, Math.ceil((deadline - Date.now()) / 1000)) : 0;
  $('timerDisplay').textContent = deadline ? String(Math.floor(remaining / 60)).padStart(2, '0') + ':' + String(remaining % 60).padStart(2, '0') : 'Sem limite';
  $('visualWrap').classList.toggle('hidden', !st.image_url);
  if (st.image_url) {
    $('mysteryImage').src = st.image_url;
    $('mysteryImage').style.setProperty('--blur', st.locked ? '0px' : Math.max(0, 24 - Number(st.revealed || 1) * 4) + 'px');
    $('veil').style.setProperty('--veil', st.locked ? '0' : '.35');
    renderPuzzle(Math.max(1, Number(st.revealed || 1)));
  }
};
networkSubmitAnswer = async function() {
  if (!networkGameActive || !networkGameState || networkGameState.locked || networkGameState.pause || networkAnsweredThisChallenge) return;
  const answer = $('answer').value.trim();
  if (!answer) { $('feedback').textContent = 'Escreve primeiro a tua resposta.'; return; }
  try {
    if (networkLobbyData?.team) {
      await networkCall('atina_v2_submit_team_proposal', {
        p_room_id: networkRoom.room_id, p_token: networkRoom.token,
        p_challenge: networkGameState.pos, p_answer: answer
      });
      networkAnsweredThisChallenge = true;
      $('answer').value = '';
    } else {
      const result = await networkCall('atina_v2_submit_room_answer', {
        p_room_id: networkRoom.room_id, p_token: networkRoom.token, p_answer: answer
      });
      atinaNetworkFeedback = result.status === 'correct' ? '✓ Resposta certa! +' + Number(result.points || 0) + ' pontos atribuídos pelo servidor.' : result.status === 'wrong' ? 'Resposta errada: −10 pontos. Tenta novamente.' : result.status === 'already_correct' ? 'Esta resposta já foi contabilizada.' : result.status === 'locked' ? 'A ronda já terminou.' : 'Resposta recebida pelo servidor.';
      if (result.status === 'correct' || result.status === 'already_correct') networkAnsweredThisChallenge = true;
      if (result.status === 'correct') playAtinaSound('correct');
      else if (result.status === 'wrong') playAtinaSound('wrong');
      $('answer').value = '';
    }
    await networkRefreshRoom();
  } catch (error) { $('feedback').textContent = error.message || 'Não foi possível enviar a resposta.'; }
};
networkHostReveal = async function() {
  if (!networkGameHost || !networkGameState || networkGameState.locked) return;
  try { await networkCall('atina_v2_reveal_room_clue', { p_room_id: networkRoom.room_id, p_token: networkRoom.token }); await networkRefreshRoom(); }
  catch (error) { networkMessage('feedback', error.message || 'Não foi possível revelar a pista.'); }
};
networkHostPass = async function() {
  if (!networkGameHost || !networkGameState || networkGameState.locked) return;
  try { await networkCall('atina_v2_pass_room_challenge', { p_room_id: networkRoom.room_id, p_token: networkRoom.token }); await networkRefreshRoom(); }
  catch (error) { networkMessage('feedback', error.message || 'Não foi possível passar o desafio.'); }
};
networkHostNext = async function() {
  if (!networkGameHost || !networkGameState || !networkGameState.locked) return;
  try { await networkCall('atina_v2_next_room_challenge', { p_room_id: networkRoom.room_id, p_token: networkRoom.token }); await networkRefreshRoom(); }
  catch (error) { networkMessage('feedback', error.message || 'Não foi possível avançar o desafio.'); }
};
networkMimeResolveRound = async function(correct, reason) {
  if (!networkGameHost || !networkGameState || networkGameState.mode !== 'mimicas' || networkGameState.locked) return;
  $('mimeCorrect').disabled = true;
  $('mimeSkip').disabled = true;
  try {
    await networkCall('atina_v2_resolve_mime_round', {
      p_room_id: networkRoom.room_id, p_token: networkRoom.token,
      p_correct: !!correct, p_points: 0, p_reason: reason || (correct ? 'correct' : 'pass')
    });
    await networkRefreshRoom();
  } catch (error) {
    $('mimeCorrect').disabled = false;
    $('mimeSkip').disabled = false;
    networkMessage('mimeFeedback', error.message || 'Não foi possível registar o resultado.');
  }
};
$('networkStartGame').onclick = networkStartGame;
$('networkStartMimicas').onclick = networkStartMimicas;
$('createNetworkRoom').onclick = networkCreateRoom;
$('joinNetworkRoom').onclick = networkJoinRoom;
$('leaveNetworkRoom').onclick = networkLeaveRoom;
$('networkReady').onclick = () => networkSetReady(!networkLobbyData?.ready);
$('networkAutoTeams').onclick = networkAutoTeams;
$('networkStartMimicas').onclick = networkStartMimicas;
$('submit').onclick = submit;
$('nextClue').onclick = reveal;
$('pass').onclick = pass;
$('continue').onclick = next;
$('answer').addEventListener('keydown', e => { if (e.key === 'Enter' && !$('answer').disabled) { e.preventDefault(); submit(); } });
(async function atinaServerBoot() {
  try {
    await networkRestoreSession();
    if (!networkRoom) {
      const restored = await atinaServerRestoreSession();
      if (!restored) screen('home');
    }
  } catch (_) { screen('home'); }
})();
