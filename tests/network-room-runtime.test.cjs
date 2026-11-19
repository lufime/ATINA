const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('assets/network-room-runtime.js', 'utf8');

function harness() {
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) {
      elements.set(id, {
        value: '',
        disabled: false,
        innerHTML: '',
        textContent: '',
        classList: { toggle() {}, add() {}, remove() {} }
      });
    }
    return elements.get(id);
  };

  const context = {
    console,
    Date,
    Promise,
    setInterval: () => 1,
    clearInterval() {},
    document: { hidden: false },
    window: {},
    networkRoom: null,
    networkLobbyData: null,
    networkGameActive: false,
    networkGameHost: false,
    networkGameState: null,
    networkLastRevision: 0,
    networkAnsweredThisChallenge: true,
    networkPollHandle: null,
    networkClockHandle: null,
    networkIsTurnDriver: () => false,
    networkCanControlTurn: () => true,
    networkCanControlTurn() {
      const mine = String(context.networkLobbyData?.team || '').trim().toLocaleLowerCase('pt-PT');
      const active = String(context.networkGameState?.active_team || '').trim().toLocaleLowerCase('pt-PT');
      return !!mine && !!active && mine === active;
    },
    networkMessage() {},
    networkRefreshRoom: async () => {},
    networkCall: async () => {},
    ensureNetworkClock() {},
    $: element,
    networkReceiveState(state) {
      const previous = context.networkGameState;
      const sameChallenge = !!(previous && previous.pos === state.pos &&
        previous.challenge_id === state.challenge_id);
      const incomingRevision = Number(state.revision || 0);
      const currentRevision = Number(context.networkLastRevision || 0);
      const staleRevision = incomingRevision < currentRevision;
      const unchangedState = incomingRevision === currentRevision &&
        String(state.active_team || '') === String(previous?.active_team || '') &&
        !!state.locked === !!previous?.locked &&
        Number(state.revealed || 0) === Number(previous?.revealed || 0) &&
        String(state.feedback || '') === String(previous?.feedback || '');
      if (previous && sameChallenge && (staleRevision || unchangedState)) return;
      context.networkGameState = state;
      context.networkLastRevision = Number(state.revision || 0);
      context.networkRenderGameState();
    },
    networkRenderGameState() {
      element('answer').value = '';
    },
    networkHostReveal: async () => {},
    networkSubmitAnswer: async () => {},
    networkHostPass: async () => {},
    networkHostNext: async () => {},
    networkDrawClock() {},
    networkStartPolling() {},
    networkStartGame: async () => {},
    networkLeaveRoom: async () => {}
  };
  context.window = context;
  vm.createContext(context);
  return { context, element };
}

test('turn identity includes active team, not only challenge position', () => {
  const { context } = harness();
  const source = fs.readFileSync('assets/network-room-runtime.js', 'utf8');
  vm.runInContext(source, context);
  assert.equal(
    context.ATINARoomRuntime.turnKey({ pos: 3, challenge_id: 42, active_team: 'Equipa A' }),
    '3:42:Equipa A'
  );
  assert.notEqual(
    context.ATINARoomRuntime.turnKey({ pos: 3, challenge_id: 42, active_team: 'Equipa A' }),
    context.ATINARoomRuntime.turnKey({ pos: 3, challenge_id: 42, active_team: 'Equipa B' })
  );
});

test('automatic team assignment alternates Equipa A and Equipa B', () => {
  const { context } = harness();
  vm.runInContext(source, context);
  const assign = context.ATINARoomRuntime.teamForIndex;
  assert.deepEqual(
    [0, 1, 2, 3, 4, 5].map(assign),
    ['Equipa A', 'Equipa B', 'Equipa A', 'Equipa B', 'Equipa A', 'Equipa B']
  );
});

test('a team change in the same challenge unlocks the new team turn', () => {
  const { context, element } = harness();
  const source = fs.readFileSync('assets/network-room-runtime.js', 'utf8');
  vm.runInContext(source, context);

  context.networkReceiveState({
    pos: 1, challenge_id: 10, active_team: 'Equipa A',
    revision: 1, revealed: 1, mode: 'challenges'
  });
  context.networkAnsweredThisChallenge = true;
  element('answer').value = 'rascunho da equipa A';

  context.networkReceiveState({
    pos: 1, challenge_id: 10, active_team: 'Equipa B',
    revision: 2, revealed: 1, mode: 'challenges'
  });

  assert.equal(context.networkAnsweredThisChallenge, false);
  assert.equal(element('answer').value, '');
});


test('a new team turn is accepted even if a concurrent response has an older revision', () => {
  const { context } = harness();
  vm.runInContext(source, context);

  context.networkReceiveState({
    pos: 1, challenge_id: 10, active_team: 'Equipa A',
    revision: 12, revealed: 2, mode: 'challenges'
  });
  context.networkAnsweredThisChallenge = true;

  context.networkReceiveState({
    pos: 1, challenge_id: 10, active_team: 'Equipa B',
    revision: 11, revealed: 2, mode: 'challenges'
  });

  assert.equal(context.networkGameState.active_team, 'Equipa B');
  assert.equal(context.networkAnsweredThisChallenge, false);
  assert.equal(context.networkLastRevision, 12, 'accepting the team switch must not lower the revision floor');

  // An older duplicate state must not overwrite the accepted team turn.
  context.networkReceiveState({
    pos: 1, challenge_id: 10, active_team: 'Equipa B',
    revision: 11, revealed: 1, mode: 'challenges'
  });
  assert.equal(context.networkGameState.active_team, 'Equipa B');
  assert.equal(context.networkLastRevision, 12);
});

test('passing a challenge is accepted even when the server revision is unchanged', () => {
  const { context } = harness();
  vm.runInContext(source, context);

  context.networkReceiveState({
    pos: 2, challenge_id: 20, active_team: 'Equipa A',
    revision: 7, revealed: 2, locked: false, feedback: '', mode: 'challenges'
  });
  context.networkReceiveState({
    pos: 2, challenge_id: 20, active_team: 'Equipa A',
    revision: 7, revealed: 2, locked: true, feedback: 'Desafio passado.', mode: 'challenges'
  });

  assert.equal(context.networkGameState.locked, true);
  assert.equal(context.networkGameState.feedback, 'Desafio passado.');
});

test('polling render preserves an unfinished answer within the same turn', () => {
  const { context, element } = harness();
  const source = fs.readFileSync('assets/network-room-runtime.js', 'utf8');
  vm.runInContext(source, context);

  context.networkReceiveState({
    pos: 1, challenge_id: 10, active_team: 'Equipa A',
    revision: 1, revealed: 1, mode: 'challenges'
  });
  element('answer').value = 'resposta ainda a escrever';

  context.networkReceiveState({
    pos: 1, challenge_id: 10, active_team: 'Equipa A',
    revision: 2, revealed: 2, mode: 'challenges'
  });

  assert.equal(element('answer').value, 'resposta ainda a escrever');
});

test('manual clue reveal is allowed during preparation countdown', async () => {
  const { context } = harness();
  const source = fs.readFileSync('assets/network-room-runtime.js', 'utf8');
  let calls = 0;
  context.networkRoom = { room_id: 'room' };
  context.networkGameActive = true;
  context.networkGameHost = true;
  context.networkGameState = {
    mode: 'challenges', prepare_until: Date.now() + 10000, revealed: 0
  };
  context.networkHostReveal = async () => { calls += 1; };
  vm.runInContext(source, context);

  await context.networkHostReveal();
  assert.equal(calls, 1);
});


test('countdown allows revealing the next clue but locks other actions', () => {
  const { context, element } = harness();
  vm.runInContext(source, context);
  context.networkGameActive = true;
  context.networkLobbyData = { team: 'Equipa A' };
  context.networkGameState = {
    mode: 'challenges', active_team: 'Equipa A',
    prepare_until: Date.now() + 10000, revealed: 0,
    total_clues: 5, locked: false
  };
  context.networkRenderGameState();
  assert.equal(element('nextClue').disabled, false, 'nextClue should be enabled during preparation');
  for (const id of ['answer', 'submit', 'voice', 'pass', 'continue']) {
    assert.equal(element(id).disabled, true, id + ' must stay disabled during preparation');
  }
});

test('a failed first reveal keeps the countdown state and backs off retries', async () => {
  const { context } = harness();
  let calls = 0;
  context.networkGameActive = true;
  context.networkRoom = { room_id: 'room' };
  context.networkIsTurnDriver = () => true;
  context.networkGameState = {
    mode: 'challenges', prepare_until: Date.now() - 1000, revealed: 0
  };
  context.networkCall = async () => { calls += 1; return { status: 'revealed' }; };
  // Simula a função original da página: a rotina automática deve passar
  // pelo mesmo caminho de revelação que o botão manual.
  context.networkHostReveal = async () => context.networkCall('atina_v2_reveal_room_clue', {});
  vm.runInContext(source, context);

  context.networkDrawClock();
  await new Promise(resolve => setTimeout(resolve, 0));

  assert.equal(calls, 1);
  assert.ok(Number(context.networkGameState.prepare_until) > 0);
  context.networkDrawClock();
  assert.equal(calls, 1);
});


test('a server-side turn conflict refreshes the room before returning', async () => {
  const { context } = harness();
  let refreshes = 0;
  context.networkRefreshRoom = async () => { refreshes += 1; };
  context.networkCall = async () => {
    throw new Error('Só a equipa que tem a vez pode passar este desafio.');
  };
  vm.runInContext(source, context);

  await assert.rejects(
    context.networkCall('atina_v2_pass_room_challenge', {}),
    /O turno mudou\. A sala foi sincronizada/
  );
  assert.equal(refreshes, 1);
});


test('answer controls stay disabled when the turn changes during submit', async () => {
  const { context, element } = harness();
  let submissions = 0;
  context.networkRoom = { room_id: 'room' };
  context.networkGameActive = true;
  context.networkLobbyData = { team: 'Equipa A' };
  context.networkGameState = {
    mode: 'challenges', pos: 1, challenge_id: 10,
    active_team: 'Equipa A', revision: 1, revealed: 2,
    total_clues: 5, locked: false
  };
  context.networkSubmitAnswer = async () => {
    submissions += 1;
    context.networkGameState = {
      ...context.networkGameState,
      active_team: 'Equipa B', revision: 2
    };
    element('answer').disabled = false;
    element('submit').disabled = false;
  };
  vm.runInContext(source, context);
  await context.networkSubmitAnswer();
  assert.equal(submissions, 1);
  assert.equal(element('answer').disabled, true);
  assert.equal(element('submit').disabled, true);
  assert.equal(element('nextClue').disabled, true);
  assert.equal(element('pass').disabled, true);
});

test('inactive team cannot submit even if a stale button is enabled', async () => {
  const { context, element } = harness();
  let submissions = 0;
  context.networkRoom = { room_id: 'room' };
  context.networkGameActive = true;
  context.networkLobbyData = { team: 'Equipa A' };
  context.networkGameState = {
    mode: 'challenges', pos: 1, challenge_id: 10,
    active_team: 'Equipa B', revision: 2, revealed: 2,
    total_clues: 5, locked: false
  };
  context.networkSubmitAnswer = async () => { submissions += 1; };
  vm.runInContext(source, context);
  element('answer').disabled = false;
  element('submit').disabled = false;
  await context.networkSubmitAnswer();
  assert.equal(submissions, 0);
  assert.equal(element('answer').disabled, true);
  assert.equal(element('submit').disabled, true);
});


test('manual next-clue button calls the original room action and restores its state', async () => {
  const { context, element } = harness();
  let calls = 0;
  context.networkGameActive = true;
  context.networkRoom = { room_id: 'room-1', token: 'token-1' };
  context.networkGameState = { mode: 'challenges', revealed: 1, locked: false };
  context.networkLobbyData = { team: 'Equipa A' };
  context.networkGameState.active_team = 'Equipa A';
  context.networkHostReveal = async () => { calls += 1; };
  vm.runInContext(source, context);
  await context.networkHostReveal();
  assert.equal(calls, 1);
  assert.equal(element('nextClue').textContent, 'Revelar próxima pista');
  assert.equal(element('nextClue').disabled, false);
});

test('manual next-clue button reports server errors and becomes usable again', async () => {
  const { context, element } = harness();
  context.networkRoom = { room_id: 'room-1', token: 'token-1' };
  context.networkGameActive = true;
  context.networkGameState = {
    mode: 'challenges', pos: 0, challenge_id: 55, active_team: 'Equipa A',
    revealed: 1, total_clues: 5, locked: false, revision: 1
  };
  context.networkLobbyData = { team: 'Equipa A' };
  let message = '';
  context.networkMessage = (id, value) => { if (id === 'feedback') message = value; };
  context.networkHostReveal = async () => { throw new Error('Falha simulada do servidor.'); };
  context.networkRefreshRoom = async () => {};
  vm.runInContext(source, context);
  await context.networkHostReveal();
  assert.match(message, /Falha simulada do servidor/);
  assert.equal(element('nextClue').textContent, 'Revelar próxima pista');
  assert.equal(element('nextClue').disabled, false);
});


test('final clue reveal keeps the terminal button label after wrapper cleanup', async () => {
  const { context, element } = harness();
  context.networkGameActive = true;
  context.networkRoom = { room_id: 'room-1', token: 'token-1' };
  context.networkLobbyData = { team: 'Equipa A' };
  context.networkGameState = {
    mode: 'challenges', pos: 0, challenge_id: 10,
    active_team: 'Equipa A', revealed: 4, total_clues: 5, locked: false
  };
  context.networkHostReveal = async () => {
    context.networkGameState = { ...context.networkGameState, revealed: 5 };
    element('nextClue').textContent = 'Todas as pistas reveladas';
    element('nextClue').disabled = true;
  };
  vm.runInContext(source, context);
  await context.networkHostReveal();
  assert.equal(element('nextClue').textContent, 'Todas as pistas reveladas');
  assert.equal(element('nextClue').disabled, true);
});


test('room mode does not start the solo first-clue countdown', () => {
  const html = fs.readFileSync('index.html', 'utf8');
  const line = html.split('\n').find(value => value.includes('function atinaScheduleAutoReveal()'));
  assert.ok(line, 'automatic clue scheduler must exist');
  let intervals = 0;
  const context = {
    networkGameActive: true,
    autoRevealTimeout: null,
    autoRevealInterval: null,
    locked: false,
    revealed: 0,
    document: { getElementById: () => null },
    clearTimeout() {},
    clearInterval() {},
    setInterval() { intervals += 1; return 1; },
    $: () => ({ textContent: '' })
  };
  vm.createContext(context);
  vm.runInContext(line, context);
  context.atinaScheduleAutoReveal();
  assert.equal(intervals, 0, 'room mode must use the server-controlled countdown');
});


test('visible clues suppress the solo first-clue countdown even if local state is stale', () => {
  const html = fs.readFileSync('index.html', 'utf8');
  const line = html.split('\n').find(value => value.includes('function atinaScheduleAutoReveal()'));
  assert.ok(line, 'automatic clue scheduler must exist');
  let intervals = 0;
  const clueNodes = [
    { textContent: 'Pista 1: arte marcial japonesa' },
    { textContent: 'Pista 2: ainda escondida' }
  ];
  const context = {
    networkGameActive: false,
    autoRevealTimeout: null,
    autoRevealInterval: null,
    locked: false,
    revealed: 0,
    document: { getElementById: () => null },
    clearTimeout() {},
    clearInterval() {},
    setInterval() { intervals += 1; return 1; },
    $: id => id === 'clues' ? { children: clueNodes } : { textContent: '' }
  };
  vm.createContext(context);
  vm.runInContext(line, context);
  context.atinaScheduleAutoReveal();
  assert.equal(intervals, 0, 'a visible clue must prevent a duplicate countdown');
});


test('locked room result uses the resolved answer and server solution image', () => {
 const html=fs.readFileSync('index.html','utf8');
 assert.ok(html.includes("const correctAnswer=String(st.answer||st.correct_answer||st.solution||g[3]||'').trim();"));
 assert.ok(html.includes("atinaShowSolutionImage(correctAnswer,g[0],'solutionImage',clueSource,st.solution_image_url||null"));
});

test('room ranking initializes every server-declared team from authoritative scores', () => {
 const html=fs.readFileSync('index.html','utf8');
 assert.ok(html.includes("const teamOrder=Array.isArray(st.team_order)?st.team_order:[];"));
 assert.ok(html.includes("const authoritativeTeamScores=Array.isArray(st.scores)?st.scores:[];"));
 assert.ok(html.includes("teamTotals[team]=Number(authoritativeTeamScores[index]??0);"));
 assert.ok(html.includes("Number(p.score||0)"));
});

 
test('room team ranking uses authoritative server team scores and never renders empty lists', () => {
 const html=fs.readFileSync('index.html','utf8');
 assert.ok(html.includes("const authoritativeTeamScores=Array.isArray(st.scores)?st.scores:[];"));
 assert.ok(html.includes("teamTotals[team]=Number(authoritativeTeamScores[index]??0);"));
 assert.ok(html.includes("Pontuações das equipas indisponíveis."));
 assert.ok(html.includes("Classificação individual indisponível."));
});


test('manual room clue playback speaks the clue text already resolved from visible UI or room state', () => {
 const html=fs.readFileSync('index.html','utf8');
 assert.ok(html.includes("const ok=atinaSpeakClue(clueText,true,lifecycle);"));
 assert.ok(!html.includes("const ok=atinaSpeakVisibleCurrentClue(true,lifecycle);"));
});
test('automatic room speech selects the last revealed clue, not the last item in the full clue array', () => {
 const html=fs.readFileSync('index.html','utf8');
 assert.ok(html.includes("const currentClue=String(clueSource[revealed-1]||g[2]?.[revealed-1]||'').trim();"));
});
test('room final solution uses the same answer renderer and solution description fallback as Solo', () => {
 const html=fs.readFileSync('index.html','utf8');
 assert.ok(html.includes("atinaRenderRevealedAnswer('feedback',revealedFeedback);"));
 assert.ok(html.includes("String(st.solution_description||'').trim()||atinaBuildSolutionVisualDescription(g)"));
 assert.ok(html.includes("hasAnswerInFeedback=/resposta\\s*:/i"));
});


test('room countdown formats durations beyond one minute correctly', () => {
  const { context } = harness();
  vm.runInContext(source, context);
  const format = context.ATINARoomRuntime.formatCountdown;
  assert.equal(format(0), '00:00');
  assert.equal(format(59), '00:59');
  assert.equal(format(60), '01:00');
  assert.equal(format(125), '02:05');
  assert.equal(format(3600), '60:00');
});
