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
    networkGameState: null,
    networkLastRevision: 0,
    networkAnsweredThisChallenge: true,
    networkPollHandle: null,
    networkClockHandle: null,
    networkIsTurnDriver: () => false,
    networkMessage() {},
    networkRefreshRoom: async () => {},
    networkCall: async () => {},
    ensureNetworkClock() {},
    $: element,
    networkReceiveState(state) {
      context.networkGameState = state;
      context.networkLastRevision = Number(state.revision || 0);
      context.networkRenderGameState();
    },
    networkRenderGameState() {
      element('answer').value = '';
    },
    networkHostReveal: async () => {},
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

test('manual clue reveal is blocked until the server countdown ends', async () => {
  const { context } = harness();
  const source = fs.readFileSync('assets/network-room-runtime.js', 'utf8');
  let calls = 0;
  context.networkRoom = { room_id: 'room' };
  context.networkGameActive = true;
  context.networkGameState = {
    mode: 'challenges', prepare_until: Date.now() + 10000, revealed: 0
  };
  context.networkHostReveal = async () => { calls += 1; };
  vm.runInContext(source, context);

  await context.networkHostReveal();
  assert.equal(calls, 0);
});


test('countdown locks every game action until it expires', () => {
  const { context, element } = harness();
  vm.runInContext(source, context);
  context.networkGameActive = true;
  context.networkGameState = {
    mode: 'challenges', prepare_until: Date.now() + 10000, revealed: 0
  };
  context.networkDrawClock();
  for (const id of ['nextClue', 'answer', 'submit', 'voice', 'pass', 'continue']) {
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
  context.networkHostReveal = async () => { calls += 1; };
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
