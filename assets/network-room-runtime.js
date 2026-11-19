/* ATINA — runtime dedicado para salas multiplayer.
 * Mantém o servidor como autoridade e corrige identidade do turno, countdown e polling.
 */
(function installAtinaNetworkRoomRuntime() {
  'use strict';

  const runtime = {
    lastPollAt: 0,
    pollInFlight: false,
    revealInFlight: false,
    nextRevealAttemptAt: 0,
    renderedTurnKey: ''
  };

  const originalReceiveState = networkReceiveState;
  const originalRenderGameState = networkRenderGameState;
  const originalHostReveal = networkHostReveal;
  const originalSubmitAnswer = networkSubmitAnswer;
  const originalHostPass = networkHostPass;
  const originalHostNext = networkHostNext;
  const originalNetworkCall = networkCall;
  const originalDrawClock = networkDrawClock;
  const originalStartGame = networkStartGame;
  const originalLeaveRoom = networkLeaveRoom;

  function teamForIndex(index) {
    return Number(index) % 2 === 0 ? 'Equipa A' : 'Equipa B';
  }

  function turnKey(state) {
    if (!state) return '';
    return [
      String(state.pos ?? ''),
      String(state.challenge_id ?? ''),
      String(state.active_team ?? '')
    ].join(':');
  }

  function setCountdownControlsDisabled(disabled) {
    ['nextClue', 'answer', 'submit', 'voice', 'pass', 'continue'].forEach(id => {
      const control = $(id);
      if (control) control.disabled = !!disabled;
    });
  }

  function reset() {
    runtime.lastPollAt = 0;
    runtime.pollInFlight = false;
    runtime.revealInFlight = false;
    runtime.nextRevealAttemptAt = 0;
    runtime.renderedTurnKey = '';
  }

  // Uma mudança de equipa no mesmo desafio é um turno novo.
  // Não aceitar estados antigos e limpar apenas a resposta do turno anterior.
  networkReceiveState = function networkReceiveStateV2(state) {
    if (!state) return originalReceiveState(state);

    const previous = networkGameState;
    const sameChallenge = !!(
      previous &&
      previous.pos === state.pos &&
      previous.challenge_id === state.challenge_id
    );
    const incomingRevision = Number(state.revision || 0);
    const revisionFloorBeforeReceive = Number(networkLastRevision || 0);
    const teamChanged = !!(
      previous &&
      sameChallenge &&
      String(previous.active_team || '') !== String(state.active_team || '')
    );
    if (
      previous &&
      sameChallenge &&
      incomingRevision < Number(networkLastRevision || 0) &&
      !teamChanged
    ) {
      return;
    }

    const nextTurnKey = turnKey(state);
    const turnChanged = !!previous && turnKey(previous) !== nextTurnKey;
    if (turnChanged) {
      networkAnsweredThisChallenge = false;
      const answer = $('answer');
      if (answer) answer.value = '';
      runtime.renderedTurnKey = nextTurnKey;

      // Uma alteração de equipa no mesmo desafio é uma nova vez.
      // A resposta do servidor prevalece sobre uma revisão antiga recebida
      // por uma chamada concorrente; sem isto, o turno novo pode ficar preso.
      if (String(previous.active_team || '') !== String(state.active_team || '')) {
        networkLastRevision = Math.min(
          Number(networkLastRevision || 0),
          Number(state.revision || 0) - 1
        );
      }
    }

    const result = originalReceiveState(state);

    // Uma revisão atrasada pode representar uma mudança de equipa legítima,
    // mas não deve baixar o marcador de revisão e permitir estados antigos
    // subsequentes. Mantém o maior revision já observada.
    if (teamChanged && incomingRevision < revisionFloorBeforeReceive) {
      networkLastRevision = revisionFloorBeforeReceive;
    }
    return result;
  };


  // Restaurar sempre os controlos a partir do estado autoritativo da sala.
  // Evita reativar a resposta de uma equipa quando o turno já passou para outra.
  function syncTurnControls() {
    const state = networkGameState;
    if (!state || state.mode === 'mimicas') return;
    const active = state.active_team ? networkCanControlTurn() : !!networkGameHost;
    const locked = !!state.locked;
    const paused = !!(state.pause && Date.parse(state.pause.ends_at) > Date.now());
    const preparing = Number(state.prepare_until) > Date.now() &&
      Number(state.revealed || 0) === 0;
    const unavailable = !networkGameActive || !active || paused;
    const total = Number(state.total_clues) ||
      (Number(state.queue?.[state.pos]) >= 0 &&
       typeof isImageChallenge === 'function' &&
       isImageChallenge(state.queue[state.pos]) ? 6 : 5);
    const revealed = Number(state.revealed || 0);
    const setDisabled = (id, disabled) => {
      const control = $(id);
      if (control) control.disabled = !!disabled;
    };
    // A preparação é apenas visual: a equipa da vez pode revelar a primeira pista.
    // Resposta, PASSO e avanço continuam bloqueados até terminar a preparação.
    setDisabled('nextClue', unavailable || locked || revealed >= total);
    setDisabled('answer', unavailable || preparing || locked || networkAnsweredThisChallenge);
    setDisabled('submit', unavailable || preparing || locked || networkAnsweredThisChallenge);
    setDisabled('voice', unavailable || preparing || locked);
    setDisabled('pass', unavailable || preparing || locked);
    setDisabled('continue', unavailable || preparing || !locked);
  }

  networkSubmitAnswer = async function networkSubmitAnswerV2() {
    if (!networkRoom || !networkGameActive || !networkGameState ||
        networkGameState.mode === 'mimicas' || !networkCanControlTurn()) {
      syncTurnControls();
      return;
    }
    try {
      return await originalSubmitAnswer.apply(this, arguments);
    } finally {
      syncTurnControls();
    }
  };

  networkHostPass = async function networkHostPassV2() {
    try {
      return await originalHostPass.apply(this, arguments);
    } finally {
      syncTurnControls();
    }
  };

  networkHostNext = async function networkHostNextV2() {
    try {
      return await originalHostNext.apply(this, arguments);
    } finally {
      syncTurnControls();
    }
  };

  // Se o servidor já mudou o turno, sincronizar antes de devolver o erro à UI.
  // Isto evita deixar os botões presos num estado antigo durante o polling seguinte.
  networkCall = async function networkCallV2(name, args) {
    try {
      return await originalNetworkCall(name, args);
    } catch (error) {
      const message = String(error?.message || error || '');
      const turnConflict = /Só a equipa que tem a vez|Ainda não é a vez da tua equipa|Só a equipa que tem a vez pode/i.test(message);
      if (turnConflict) {
        try { await networkRefreshRoom(); } catch (_) {}
        const syncError = new Error('O turno mudou. A sala foi sincronizada; aguarda a tua vez.');
        syncError.code = 'ATINA_STALE_TURN';
        throw syncError;
      }
      throw error;
    }
  };

  // O polling não pode apagar texto que o jogador ainda está a escrever.
  networkRenderGameState = function networkRenderGameStateV2() {
    const state = networkGameState;
    if (!state) return originalRenderGameState();

    const key = turnKey(state);
    const answer = $('answer');
    const sameTurn = runtime.renderedTurnKey === key;
    const draft = sameTurn && !state.locked && answer ? answer.value : '';

    const result = originalRenderGameState();

    if (answer) {
      if (sameTurn && !state.locked) answer.value = draft;
      else answer.value = '';
    }

    runtime.renderedTurnKey = key;
    syncTurnControls();

    return result;
  };

  // Envolver a implementação original sem a substituir: esta também é usada
  // pelo fluxo automático que inicia a primeira pista após a contagem decrescente.
  // O bloqueio evita duplo clique e o finally recupera sempre o controlo visual.
  networkHostReveal = async function networkHostRevealV2() {
    const button = $('nextClue');

    if (runtime.revealInFlight) {
      networkMessage('feedback', 'A pista já está a ser carregada. Aguarda um instante.');
      return;
    }
    runtime.revealInFlight = true;
    if (button) {
      button.disabled = true;
      button.textContent = 'A revelar pista…';
    }
    try {
      return await originalHostReveal.apply(this, arguments);
    } catch (error) {
      networkMessage('feedback', error?.message || 'Não foi possível revelar a próxima pista. Tenta novamente.');
    } finally {
      runtime.revealInFlight = false;
      if (button) {
        const state = networkGameState;
        const total = Number(state?.total_clues) ||
          (Number(state?.queue?.[state?.pos]) >= 0 &&
           typeof isImageChallenge === 'function' &&
           isImageChallenge(state.queue[state.pos]) ? 6 : 5);
        button.textContent = state?.locked || Number(state?.revealed || 0) >= total
          ? 'Todas as pistas reveladas'
          : 'Revelar próxima pista';
      }
      syncTurnControls();
    }
  };

  // O contador só sai do estado de preparação quando o servidor confirma
  // a primeira pista. Uma falha não apaga o countdown nem bloqueia a sala.
  networkDrawClock = function networkDrawClockV2() {
    if (!networkGameState || !networkGameActive) return originalDrawClock();

    const state = networkGameState;
    const prepareUntil = Number(state.prepare_until) || 0;

    if (prepareUntil && Number(state.revealed || 0) === 0) {
      const left = Math.max(0, Math.ceil((prepareUntil - Date.now()) / 1000));
      $('timerDisplay').innerHTML =
        'PREPARA-TE<br><span>00:' + String(left).padStart(2, '0') + '</span>';
      $('timerDisplay').classList.toggle('urgent', left <= 3);
      $('clueProgress').textContent = left > 0
        ? 'A partida começa em ' + left + ' segundos'
        : 'A iniciar o desafio…';
      // O countdown não bloqueia a primeira pista; os restantes controlos mantêm-se fechados.
      syncTurnControls();

      if (
        left === 0 &&
        networkIsTurnDriver() &&
        !state._startingChallenge &&
        Date.now() >= runtime.nextRevealAttemptAt
      ) {
        state._startingChallenge = true;
        const before = Number(state.revealed || 0);

        Promise.resolve(networkHostReveal({ automatic: true })).then(() => {
          const current = networkGameState;
          const after = Number(current?.revealed || 0);

          if (after > before) {
            runtime.nextRevealAttemptAt = 0;
            if (current) current.prepare_until = 0;
          } else {
            runtime.nextRevealAttemptAt = Date.now() + 1200;
          }
        }).catch(error => {
          runtime.nextRevealAttemptAt = Date.now() + 1500;
          networkMessage(
            'feedback',
            error?.message || 'Não foi possível iniciar o desafio. A tentar novamente.'
          );
        }).finally(() => {
          if (networkGameState) networkGameState._startingChallenge = false;
          if (networkGameActive) networkDrawClock();
        });
      }
      return;
    }

    if (prepareUntil && Number(state.revealed || 0) > 0) {
      state.prepare_until = 0;
    }
    return originalDrawClock();
  };

  // Um único ciclo de polling, sem pedidos sobrepostos. Mantém intervalos
  // moderados para não saturar o RPC nem atrasar a sincronização dos turnos.
  networkStartPolling = function networkStartPollingV2() {
    if (networkPollHandle) clearInterval(networkPollHandle);
    runtime.lastPollAt = 0;
    runtime.pollInFlight = false;

    networkPollHandle = setInterval(() => {
      if (!networkRoom || runtime.pollInFlight) return;

      const delay = document.hidden ? 15000 : (networkGameActive ? 1000 : 6000);
      const now = Date.now();
      if (now - runtime.lastPollAt < delay) return;

      runtime.lastPollAt = now;
      runtime.pollInFlight = true;
      Promise.resolve(networkRefreshRoom())
        .catch(() => {})
        .finally(() => { runtime.pollInFlight = false; });
    }, 250);
  };

  networkStartGame = async function networkStartGameV2() {
    reset();
    return originalStartGame.apply(this, arguments);
  };

  networkLeaveRoom = async function networkLeaveRoomV2() {
    try {
      return await originalLeaveRoom.apply(this, arguments);
    } finally {
      reset();
    }
  };

  // Os handlers onclick guardavam referências às funções antigas.
  if ($('networkStartGame')) $('networkStartGame').onclick = networkStartGame;
  if ($('leaveNetworkRoom')) $('leaveNetworkRoom').onclick = networkLeaveRoom;

  // Substituir callbacks de relógio/polling que possam ter sido criados durante
  // o arranque da página antes de este runtime dedicado ser carregado.
  if (networkPollHandle) {
    clearInterval(networkPollHandle);
    networkPollHandle = null;
  }
  if (networkClockHandle) {
    clearInterval(networkClockHandle);
    networkClockHandle = null;
  }
  if (networkRoom) networkStartPolling();
  if (networkGameActive) ensureNetworkClock();

  window.ATINARoomRuntime = Object.freeze({ turnKey, teamForIndex, reset, syncTurnControls });
})();
