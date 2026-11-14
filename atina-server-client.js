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

const ATINA_ACCOUNT_SESSION_KEY = 'atinaAccountSessionV1';
function atinaAccountSessionToken() { return localStorage.getItem(ATINA_ACCOUNT_SESSION_KEY) || ''; }
const ATINA_PROGRESS_DEVICE_KEY = 'atinaProgressDeviceTokenV1';
const ATINA_PROGRESS_NICKNAME_KEY = 'atinaProgressNicknameV1';
let atinaCloudProfile = null;
const atinaCloudClaimsInFlight = new Set();
const atinaCloudClaimsDone = new Set();

function atinaProgressDeviceToken(createIfMissing = true) {
  let token = localStorage.getItem(ATINA_PROGRESS_DEVICE_KEY) || '';
  if (/^[0-9a-f]{64}$/.test(token)) return token;
  if (!createIfMissing) return null;
  if (!window.crypto?.getRandomValues) throw new Error('Este navegador não permite criar um identificador seguro para o dispositivo.');
  const bytes = new Uint8Array(32);
  window.crypto.getRandomValues(bytes);
  token = Array.from(bytes, value => value.toString(16).padStart(2, '0')).join('');
  localStorage.setItem(ATINA_PROGRESS_DEVICE_KEY, token);
  return token;
}

function atinaProgressRender(profile) {
  const signedInName = $('atinaSignedInUserName');
  if (signedInName) signedInName.textContent = profile?.nickname ? 'Ligado como ' + profile.nickname : 'A jogar como convidado';
  if (!profile) return;
  const xp = Math.max(0, Number(profile.xp) || 0);
  const points = Math.max(0, Number(profile.points) || 0);
  if ($('atinaCloudPoints')) $('atinaCloudPoints').textContent = points + ' pontos';
  const thresholds = [0,250,600,1100,1800,2700,3900,5400,7200,9300,11700,14400,17400,20700,24300,28200,32400,36900,41700,46800,52200,57900,64000,70500,77400,84700,92400,100500,109000,118000];
  const titles = ['Iniciante','Explorador','Descobridor','Conhecedor','Especialista','Mestre','Perito','Sábio','Génio','Lenda ATINA','Veterano','Erudito','Grande Mestre','Ilustre','Campeão','Visionário','Eminência','Grão-Mestre','Imortal','Lenda Suprema','Mestre do Conhecimento','Explorador Supremo','Sábio Supremo','Grande Sábio','Mestre Lendário','Génio Supremo','Guardião do Saber','Ícone ATINA','Lenda Eterna','Lenda Absoluta'];
  const level = Math.max(1, Number(profile.level) || 1);
  const levelIndex = Math.min(level - 1, thresholds.length - 1);
  const currentThreshold = level <= 30 ? thresholds[levelIndex] : 128000 + ((level - 31) * 10000) + (((level - 31) * (level - 32)) / 2 * 1000);
  const nextThreshold = level < 30 ? thresholds[levelIndex + 1] : currentThreshold + 10000 + Math.max(0, level - 31) * 1000;
  const progress = Math.max(0, xp - currentThreshold);
  const needed = Math.max(1, nextThreshold - currentThreshold);
  const remaining = Math.max(0, nextThreshold - xp);
  const percent = Math.min(100, progress / needed * 100);
  const title = titles[levelIndex] || 'Lenda ATINA';
  const fill = $('atinaCloudXpFill');
  if ($('atinaCloudLevel')) $('atinaCloudLevel').textContent = 'Nível ' + level + ' · ' + title;
  if ($('atinaCloudXp')) $('atinaCloudXp').textContent = xp + ' XP';
  if ($('atinaCloudChallenges')) $('atinaCloudChallenges').textContent = (Number(profile.total_challenges) || 0) + ' desafios';
  if ($('atinaCloudNextLevel')) $('atinaCloudNextLevel').textContent = progress.toLocaleString('pt-PT') + ' / ' + needed.toLocaleString('pt-PT') + ' XP para o próximo nível · faltam ' + remaining.toLocaleString('pt-PT') + ' XP';
  if (fill) fill.style.width = percent + '%';
  if ($('atinaCloudNickname') && profile.nickname) $('atinaCloudNickname').value = profile.nickname;
  const homeXp = $('atinaXpValue'), homeLevel = $('atinaLevelValue');
  const homeFill = $('atinaXpFill'), homeMeta = $('atinaXpMeta');
  if (homeXp) homeXp.textContent = xp.toLocaleString('pt-PT') + ' XP';
  if (homeLevel) homeLevel.textContent = 'Nível ' + level + ' · ' + title;
  if (homeFill) homeFill.style.width = percent + '%';
  if (homeMeta) homeMeta.textContent = progress.toLocaleString('pt-PT') + ' / ' + needed.toLocaleString('pt-PT') + ' XP para o próximo nível';
  const badges = $('atinaBadges');
  if (badges) {
    const milestones = [{at:1,icon:'🌱',name:'Primeiros passos'},{at:10,icon:'🧠',name:'Mente ativa'},{at:25,icon:'🔥',name:'Persistente'},{at:50,icon:'🏅',name:'Veterano'},{at:100,icon:'👑',name:'Lenda ATINA'}];
    badges.innerHTML = milestones.map(b => '<span class="atina-badge ' + ((Number(profile.total_challenges)||0) >= b.at ? 'earned' : '') + '" title="' + b.name + '">' + b.icon + ' ' + b.name + '</span>').join('');
  }
}

async function atinaProgressCodeToken(code) {
  const clean = String(code || '').trim().normalize('NFKC');
  if (clean.length < 8 || clean.length > 64) throw new Error('O código pessoal deve ter entre 8 e 64 caracteres.');
  if (/^[0-9a-f]{64}$/i.test(clean)) return clean.toLowerCase(); // compatibilidade com códigos antigos
  if (!window.crypto?.subtle) throw new Error('Este navegador não suporta a criação segura do código. Atualiza o navegador.');
  const material = await window.crypto.subtle.importKey('raw', new TextEncoder().encode(clean), 'PBKDF2', false, ['deriveBits']);
  const bits = await window.crypto.subtle.deriveBits({name:'PBKDF2',salt:new TextEncoder().encode('ATINA-player-access-v1'),iterations:310000,hash:'SHA-256'}, material, 256);
  return Array.from(new Uint8Array(bits), value => value.toString(16).padStart(2, '0')).join('');
}

async function atinaProgressRegister(nickname, quiet = false, personalCode = '') {
  const clean = String(nickname || '').trim();
  if (!clean || clean.length > 20) throw new Error('Escolhe um pseudónimo entre 1 e 20 caracteres.');
  const savedNickname = localStorage.getItem(ATINA_PROGRESS_NICKNAME_KEY) || '';
  const deviceToken = personalCode ? await atinaProgressCodeToken(personalCode) : atinaProgressDeviceToken(!savedNickname);
  if (!deviceToken) {
    throw new Error('O código pessoal não está neste dispositivo. Introduz o teu código para recuperar o perfil.');
  }
  const data = await atinaServerRpc('atina_progress_register', {
    p_nickname: clean,
    p_device_token: deviceToken
  });
  localStorage.setItem(ATINA_PROGRESS_DEVICE_KEY, deviceToken);
  atinaCloudProfile = data;
  window.atinaCloudProfile = data;
  localStorage.setItem(ATINA_PROGRESS_NICKNAME_KEY, clean);
  atinaProgressRender(data);
  atinaRenderDailyMission();
  if ($('atinaCloudStatus')) $('atinaCloudStatus').textContent = quiet
    ? 'Perfil sincronizado. O progresso está pronto.'
    : 'Pseudónimo guardado. A progressão está sincronizada.';
  return data;
}

async function atinaProgressClaim(state) {
  if (!['solo', 'mix'].includes(state?.mode)) return;
  if (!state || !['correct', 'wrong', 'incorrect'].includes(state.last_result?.outcome) || !state.round_locked || !atinaServerSession) return;
  const deviceToken = atinaAccountSessionToken();
  if (!deviceToken) {
    if ($('atinaCloudStatus')) $('atinaCloudStatus').textContent = 'Inicia sessão com o teu pseudónimo para guardar XP.';
    return;
  }
  const key = state.session_id + ':' + state.position;
  if (atinaCloudClaimsDone.has(key) || atinaCloudClaimsInFlight.has(key)) return;
  atinaCloudClaimsInFlight.add(key);
  try {
    if (!atinaCloudProfile) {
      atinaCloudProfile = await atinaServerRpc('atina_account_profile', {p_session_token: deviceToken});
      atinaProgressRender(atinaCloudProfile);
    }
    const result = await atinaServerRpc('atina_progress_claim_local', {
      p_device_token: deviceToken,
      p_session_id: state.session_id,
      p_session_token: atinaServerSession.token,
      p_position: Number(state.position)
    });
    atinaCloudClaimsDone.add(key);
    atinaCloudProfile = result;
    window.atinaCloudProfile = result;
    atinaProgressRender(result);
    // Refresh the public points ranking immediately after the server confirms an award.
    void atinaProgressLoadPointsLeaderboard();
    atinaRenderDailyMission();
    if ($('atinaCloudStatus')) {
      $('atinaCloudStatus').textContent = result.awarded
        ? '✨ +' + (Number(result.challenge_xp) || 10) + ' XP' + (Number(result.bonus_total ?? result.daily_bonus) ? ' · bónus extra +' + Number(result.bonus_total ?? result.daily_bonus) + ' XP' : '') + ' confirmado pelo servidor.'
        : 'Este desafio já tinha sido contabilizado. XP sincronizado.';
    }
  } catch (error) {
    if ($('atinaCloudStatus')) $('atinaCloudStatus').textContent = 'Não foi possível sincronizar o XP. Será tentado novamente: ' + (error.message || 'falha de ligação');
  } finally {
    atinaCloudClaimsInFlight.delete(key);
  }
}

async function atinaProgressLoadPointsLeaderboard() {
  const list = $('atinaPointsLeaderboard');
  if (!list) return;
  try {
    const rows = await atinaServerRpc('atina_points_leaderboard', { p_limit: 25 });
    list.replaceChildren();
    const rankedRows = Array.isArray(rows)
      ? rows.filter(row => Number(row.points || 0) > 0).slice(0, 25)
      : [];
    if (!rankedRows.length) {
      const empty = document.createElement('tr');
      const cell = document.createElement('td');
      cell.colSpan = 3;
      cell.textContent = 'Ainda não há Pontos globais registados.';
      empty.appendChild(cell);
      list.appendChild(empty);
      return;
    }
    rankedRows.forEach((row, index) => {
      const item = document.createElement('tr');
      const rank = document.createElement('td');
      const nickname = document.createElement('td');
      const points = document.createElement('td');
      rank.textContent = String(index + 1);
      nickname.textContent = row.nickname;
      points.textContent = Number(row.points || 0).toLocaleString('pt-PT');
      item.append(rank, nickname, points);
      list.appendChild(item);
    });
  } catch (error) {
    list.replaceChildren();
    const item = document.createElement('li');
    item.textContent = error.message || 'Não foi possível carregar a classificação de Pontos.';
    list.appendChild(item);
  }
}

const ATINA_LEVEL_TITLES = ['Iniciante','Explorador','Descobridor','Conhecedor','Especialista','Mestre','Perito','Sábio','Génio','Lenda ATINA','Veterano','Erudito','Grande Mestre','Ilustre','Campeão','Visionário','Eminência','Grão-Mestre','Imortal','Lenda Suprema','Mestre do Conhecimento','Explorador Supremo','Sábio Supremo','Grande Sábio','Mestre Lendário','Génio Supremo','Guardião do Saber','Ícone ATINA','Lenda Eterna','Lenda Absoluta'];
function atinaLevelDesignation(level) {
  const safeLevel = Math.max(1, Number(level) || 1);
  return ATINA_LEVEL_TITLES[Math.min(safeLevel - 1, ATINA_LEVEL_TITLES.length - 1)];
}

async function atinaProgressLoadLeaderboard() {
  const list = $('atinaCloudLeaderboard');
  if (!list) return;
  try {
    const rows = await atinaServerRpc('atina_progress_leaderboard', { p_limit: 50 });
    list.replaceChildren();
    const rankedRows = Array.isArray(rows)
      ? rows.filter(row => Number(row.xp || 0) > 0).slice(0, 50)
      : [];
    if (!rankedRows.length) {
      const empty = document.createElement('tr');
      const cell = document.createElement('td');
      cell.colSpan = 4;
      cell.textContent = 'Ainda não há jogadores com XP registado.';
      empty.appendChild(cell);
      list.appendChild(empty);
      return;
    }
    rankedRows.forEach((row, index) => {
      const item = document.createElement('tr');
      const rank = document.createElement('td');
      const nickname = document.createElement('td');
      const xp = document.createElement('td');
      const level = document.createElement('td');
      rank.textContent = String(index + 1);
      nickname.textContent = row.nickname;
      xp.textContent = Number(row.xp || 0).toLocaleString('pt-PT');
      level.textContent = atinaLevelDesignation(row.level);
      item.append(rank, nickname, xp, level);
      list.appendChild(item);
    });
  } catch (error) {
    list.replaceChildren();
    const item = document.createElement('li');
    item.textContent = error.message || 'Não foi possível carregar a classificação global.';
    list.appendChild(item);
  }
}

async function atinaProgressCopyRecovery() {
  const token = atinaProgressDeviceToken(false);
  if (!token) {
    if ($('atinaCloudStatus')) $('atinaCloudStatus').textContent = 'Ainda não existe uma chave neste dispositivo. Regista um pseudónimo ou recupera-o com o código.';
    return;
  }
  if ($('atinaCloudRecoveryCode')) $('atinaCloudRecoveryCode').value = token;
  try {
    await navigator.clipboard.writeText(token);
    if ($('atinaCloudStatus')) $('atinaCloudStatus').textContent = 'Código de recuperação copiado. Guarda-o num local seguro.';
  } catch (_) {
    if ($('atinaCloudStatus')) $('atinaCloudStatus').textContent = 'Não foi possível copiar automaticamente. O código está no campo de recuperação para copiares manualmente.';
  }
}

async function atinaProgressRestoreFromCode() {
  const code = String($('atinaCloudRecoveryCode')?.value || '').trim();
  const nickname = String($('atinaCloudNickname')?.value || localStorage.getItem(ATINA_PROGRESS_NICKNAME_KEY) || '').trim();
  if (!nickname || nickname.length > 20) {
    if ($('atinaCloudStatus')) $('atinaCloudStatus').textContent = 'Indica o pseudónimo associado ao teu código pessoal.';
    return;
  }
  try {
    const deviceToken = await atinaProgressCodeToken(code);
    const data = await atinaServerRpc('atina_progress_register', {p_nickname:nickname,p_device_token:deviceToken});
    localStorage.setItem(ATINA_PROGRESS_DEVICE_KEY, deviceToken);
    localStorage.setItem(ATINA_PROGRESS_NICKNAME_KEY, nickname);
    atinaCloudProfile = data;
    window.atinaCloudProfile = data;
    atinaProgressRender(data);
    atinaRenderDailyMission();
    if ($('atinaCloudStatus')) $('atinaCloudStatus').textContent = 'Perfil recuperado. O pseudónimo e a progressão estão sincronizados neste dispositivo.';
  } catch (error) {
    if ($('atinaCloudStatus')) $('atinaCloudStatus').textContent = error.message || 'Não foi possível recuperar o perfil.';
  }
}

function atinaProgressBoot() {
  // New account model: never silently recreate a legacy device-only profile.
  const sessionToken = atinaAccountSessionToken();
  if (!sessionToken) return;
  atinaServerRpc('atina_account_profile', {p_session_token:sessionToken})
    .then(profile => {
      atinaCloudProfile = profile;
      window.atinaCloudProfile = profile;
      atinaProgressRender(profile);
      atinaRenderDailyMission();
      if ($('atinaCloudStatus')) $('atinaCloudStatus').textContent = 'Sessão recuperada. O teu progresso está sincronizado.';
      if ($('authSummary')) $('authSummary').textContent = 'Sessão iniciada como ' + profile.nickname + '. O teu progresso está sincronizado.';
      if ($('homeLoginBadge')) $('homeLoginBadge').classList.remove('hidden');
      if ($('homeLoginText')) $('homeLoginText').textContent = profile.nickname;
    })
    .catch(error => {
      localStorage.removeItem(ATINA_ACCOUNT_SESSION_KEY);
      atinaCloudProfile = null;
      window.atinaCloudProfile = null;
      if ($('atinaCloudStatus')) $('atinaCloudStatus').textContent = 'A sessão expirou. Entra novamente com o teu pseudónimo e palavra-passe.';
    });
}

function atinaServerMessage(message) {
  const gameVisible = $('game') && !$('game').classList.contains('hidden');
  if (gameVisible) {
    $('feedback').textContent = message;
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
function atinaRenderSolutionWikipedia(challenge, isLocked = false, activeChallengeId = null) {
  const target = $('solutionImage');
  if (!target) return;
  // A descrição editorial e o link «Sobre esta imagem» deixaram de ser
  // apresentados; a descrição continua disponível apenas como contexto
  // interno para encontrar uma imagem adequada.
  target.querySelector('[data-solution-wikipedia]')?.remove();
}

const atinaImageCreditCache = new Map();
async function atinaRenderChallengeImageCredit(challengeId) {
  const target = $('challengeImageCredit');
  if (!target) return;
  const id = Number(challengeId);
  if (!Number.isInteger(id) || id <= 0) { target.classList.add('hidden'); return; }
  target.dataset.challengeId = String(id);
  target.classList.remove('hidden');
  target.textContent = 'A carregar créditos da imagem…';
  try {
    let credit = atinaImageCreditCache.get(id);
    if (credit === undefined) {
      const { data, error } = await supabaseClient.rpc('atina_image_credit', { p_challenge_id: id });
      if (error) throw error;
      credit = data || null;
      atinaImageCreditCache.set(id, credit);
    }
    if (target.dataset.challengeId !== String(id)) return;
    target.replaceChildren();
    if (!credit) { target.classList.add('hidden'); return; }
    const attribution = String(credit.attribution || '').trim();
    const author = String(credit.author || '').trim();
    target.textContent = attribution || (author ? 'Fotografia: ' + author : '');
    const links = [];
    if (author === 'Jules Verne Times Two') links.push(['Site do autor', 'https://julesvernex2.com']);
    if (credit.source_url) links.push(['Ver imagem original', credit.source_url]);
    if (credit.license_url) links.push(['Licença ' + String(credit.license || '').trim(), credit.license_url]);
    for (const [label, url] of links) {
      if (!/^https:\/\//i.test(url)) continue;
      const link = document.createElement('a');
      link.href = url; link.target = '_blank'; link.rel = 'noopener noreferrer';
      link.textContent = label;
      link.style.marginLeft = '8px';
      target.append(link);
    }
    target.classList.toggle('hidden', !target.textContent.trim() && !links.length);
  } catch (error) {
    if (target.dataset.challengeId === String(id)) {
      target.textContent = 'Não foi possível carregar os créditos desta imagem.';
    }
  }
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
  atinaRenderChallengeImageCredit(challenge.id);
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
  // Renderiza o total devolvido pelo servidor diretamente no marcador da ronda.
  // O fallback para os pontos do resultado evita deixar o indicador a zero
  // caso uma resposta intermédia traga o resultado antes do total atualizado.
  const liveScoreNow = $('atinaRoundScore');
  if (liveScoreNow) {
    const scoreList = Array.isArray(state.scores) ? state.scores.map(value => Number(value) || 0) : [];
    const activeScore = scoreList[player] ?? scoreList[0] ?? 0;
    const awardedNow = result.outcome === 'correct' ? Number(result.points || 0) : 0;
    liveScoreNow.textContent = String(Math.max(activeScore, awardedNow));
  }
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
  if (locked) atinaRecordChallengeCompletion('server:' + state.session_id + ':' + state.position);
  if (locked && ['correct', 'wrong', 'incorrect'].includes(result.outcome)) atinaProgressClaim(state);
  if (locked) {
    atinaShowSolutionImage(
      challenge.answer,
      challenge.category,
      'solutionImage',
      Array.isArray(challenge.tags) ? challenge.tags : [],
      challenge.solution_image_url || null,
      challenge.solution_description || '',
      challenge.solution_image_credit || null
    ).then(() => atinaRenderSolutionWikipedia(challenge, !!atinaServerState?.round_locked, atinaServerState?.challenge?.id)).catch(() => {});
  } else {
    $('solutionImage')?.classList.add('hidden');
  }
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
  } catch (error) {
    if (atinaServerIsInvalidSession(error)) {
      atinaServerStopTimers();
      atinaServerSession = null;
      atinaServerState = null;
      localStorage.removeItem(ATINA_SERVER_SESSION_KEY);
      screen('home');
      atinaServerMessage('A partida expirou. Inicia uma nova partida.');
    }
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
    const selectedDifficulty = $('difficultyMode')?.value || 'medium';
    const difficulty = ['easy', 'medium', 'hard', 'mixed'].includes(selectedDifficulty) ? selectedDifficulty : 'medium';
    if (['solo', 'mix'].includes(gameMode) && atinaAccountSessionToken() && !atinaCloudProfile) {
      try { atinaCloudProfile = await atinaServerRpc('atina_account_profile', {p_session_token: atinaAccountSessionToken()}); atinaProgressRender(atinaCloudProfile); } catch (_) {}
    }
    const response = await atinaServerRpc('atina_v2_start_local_game', {
      p_game_mode: gameMode,
      p_difficulty: difficulty,
      p_category: category,
      p_timed_mode_seconds: Number.isFinite(duration) ? duration : 60,
      p_device_token: ['solo', 'mix'].includes(gameMode) && atinaCloudProfile
        ? atinaAccountSessionToken() : null
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
  const liveScore = $('atinaRoundScore');
  const liveStreak = $('atinaRoundStreak');
  const liveRound = $('atinaRoundNumber');
  const liveTotal = $('atinaRoundTotal');
  if (liveScore) liveScore.textContent = String(scores[mode === 'duel' || mode === 'party' ? player : 0] || 0);
  if (liveStreak) liveStreak.textContent = String(Number(atinaServerState?.correct_streak || atinaServerState?.streak || 0));
  if (liveRound) liveRound.textContent = String(Math.min(pos + 1, queue.length || 1));
  if (liveTotal) liveTotal.textContent = String(queue.length || 1);
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
    const selectedDifficulty = $('difficultyMode')?.value || 'medium';
    const difficulty = ['easy', 'medium', 'hard'].includes(selectedDifficulty) ? selectedDifficulty : 'medium';
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
  if (st.locked) atinaRecordChallengeCompletion('room:' + (networkRoom?.room_id || 'online') + ':' + st.pos);
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
  atinaRenderChallengeImageCredit(st.challenge_id);
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
function atinaOnlineCountBoot() {
  const header = document.querySelector('.brand');
  if (!header || document.getElementById('atinaOnlinePlayerCount')) return;
  const counter = document.createElement('div');
  counter.id = 'atinaOnlinePlayerCount';
  counter.setAttribute('role', 'status');
  counter.setAttribute('aria-live', 'polite');
  counter.style.cssText = 'display:inline-flex;align-items:center;gap:8px;margin-top:12px;padding:7px 11px;border:1px solid #39896c;border-radius:999px;background:#123c35;color:#b6f3d0;font-size:12px;font-weight:800;line-height:1.35';
  counter.textContent = '● A ligar presença…';
  counter.title = 'Pessoas com o ATINA aberto neste momento; não significa que estejam numa sala de jogo.';
  const adminButton = document.getElementById('adminOnlineButton');
  if (adminButton) header.insertBefore(counter, adminButton);
  else header.appendChild(counter);

  const presenceKey = 'atinaSitePresenceSessionV1';
  const getSessionId = () => {
    let id = '';
    try { id = window.localStorage.getItem(presenceKey) || ''; } catch (_) {}
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) return id;

    try {
      if (window.crypto && typeof window.crypto.randomUUID === 'function') {
        id = window.crypto.randomUUID();
      } else if (window.crypto && typeof window.crypto.getRandomValues === 'function') {
        const bytes = new Uint8Array(16);
        window.crypto.getRandomValues(bytes);
        bytes[6] = (bytes[6] & 15) | 64;
        bytes[8] = (bytes[8] & 63) | 128;
        const hex = Array.from(bytes, value => value.toString(16).padStart(2, '0')).join('');
        id = hex.slice(0,8)+'-'+hex.slice(8,12)+'-'+hex.slice(12,16)+'-'+hex.slice(16,20)+'-'+hex.slice(20);
      }
    } catch (_) {}
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
      id = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
        const r = Math.floor(Math.random() * 16);
        return (c === 'x' ? r : (r & 3) | 8).toString(16);
      });
    }
    try { window.localStorage.setItem(presenceKey, id); } catch (_) {}
    return id;
  };

  const sessionId = getSessionId();
  let inFlight = false;
  const refresh = async () => {
    if (inFlight) return;
    inFlight = true;
    try {
      const nickname = (localStorage.getItem('atinaProgressNicknameV1') || '').trim().slice(0, 40) || 'Visitante';
      await atinaServerRpc('atina_site_presence_heartbeat', { p_session_id: sessionId, p_nickname: nickname });
      const count = await atinaServerRpc('atina_online_player_count', {});
      const total = Math.max(0, Number(count) || 0);
      counter.textContent = '● ' + total + (total === 1 ? ' jogador online' : ' jogadores online');
      counter.dataset.count = String(total);
    } catch (error) {
      console.warn('ATINA: não foi possível atualizar a presença online.', error);
      counter.textContent = '● Presença online indisponível';
      delete counter.dataset.count;
    } finally {
      inFlight = false;
    }
  };

  refresh();
  window.setInterval(refresh, 15000);
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) refresh();
  });
}

// Aviso global de manutenção/alterações, controlado pela administração.
async function atinaNoticeRefresh() {
  const banner = document.getElementById('atinaUpdateNotice');
  const message = document.getElementById('atinaUpdateNoticeMessage');
  if (!banner || !message) return;

  let active = false;
  let noticeMessage = '';

  // O aviso manual do painel de administração tem prioridade.
  try {
    if (supabaseClient) {
      const { data, error } = await supabaseClient
        .from('atina_site_notice')
        .select('active,message,updated_at')
        .eq('id', 1)
        .maybeSingle();
      if (!error && data?.active && String(data.message || '').trim()) {
        active = true;
        noticeMessage = String(data.message).trim();
      }
    }
  } catch (error) {
    console.warn('Aviso manual ATINA indisponível:', error);
  }

  // Se não houver aviso manual ativo, consulta o aviso automático do GitHub.
  if (!active) {
    try {
      const response = await fetch('https://raw.githubusercontent.com/lufime/ATINA/main/atina-update-status.json?ts=' + Date.now(), { cache: 'no-store' });
      if (!response.ok) throw new Error('Não foi possível consultar o estado da atualização.');
      const data = await response.json();
      if (data?.active && String(data.message || '').trim()) {
        active = true;
        noticeMessage = String(data.message).trim();
      }
    } catch (error) {
      console.warn('Aviso automático ATINA indisponível:', error);
    }
  }

  message.textContent = active ? noticeMessage : '';
  banner.classList.toggle('hidden', !active);
}
async function atinaNoticeSave() {
  const status = document.getElementById('atinaNoticeStatus');
  const button = document.getElementById('atinaNoticeSave');
  if (!atinaUser || String(atinaUser.email || '').toLowerCase() !== 'lufime@gmail.com') {
    if (status) status.textContent = 'Apenas o administrador pode publicar avisos.';
    return;
  }
  const active = !!document.getElementById('atinaNoticeActive')?.checked;
  const message = String(document.getElementById('atinaNoticeMessage')?.value || '').trim();
  if (active && !message) {
    if (status) status.textContent = 'Escreve uma mensagem antes de ativar o aviso.';
    return;
  }
  if (button) button.disabled = true;
  if (status) status.textContent = 'A guardar…';
  try {
    const { error } = await supabaseClient.from('atina_site_notice').upsert({
      id: 1, active, message: message || 'Estamos a fazer melhorias no ATINA. Poderão ocorrer interrupções temporárias.',
      updated_at: new Date().toISOString()
    });
    if (error) throw error;
    if (status) status.textContent = active ? 'Aviso publicado para todos os jogadores.' : 'Aviso desativado.';
    await atinaNoticeRefresh();
  } catch (error) {
    if (status) status.textContent = 'Não foi possível guardar: ' + (error.message || 'erro desconhecido');
  } finally {
    if (button) button.disabled = false;
  }
}
function atinaNoticeBoot() {
  const save = document.getElementById('atinaNoticeSave');
  if (save) save.addEventListener('click', atinaNoticeSave);
  atinaNoticeRefresh();
  window.setInterval(atinaNoticeRefresh, 15000);
}

atinaNoticeBoot();
atinaProgressBoot();
// The public points ranking is visible to guests too; load it independently of login.
void atinaProgressLoadPointsLeaderboard();
atinaOnlineCountBoot();
(async function atinaServerBoot() {
  try {
    // Uma sessão individual nunca deve ser recuperada automaticamente ao abrir/atualizar a página.
    // Apagar a referência local impede que uma partida antiga volte a abrir o ecrã de jogo.
    localStorage.removeItem(ATINA_SERVER_SESSION_KEY);
    atinaServerSession = null;
    atinaServerState = null;
    atinaServerStopTimers();
    await networkRestoreSession();
    if (!networkRoom) screen('home');
  } catch (_) { screen('home'); }
})();
