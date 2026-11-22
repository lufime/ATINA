const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const server = fs.readFileSync('atina-server-client.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

test('Solo session is preserved at boot and retake is an explicit user action', () => {
  const boot = server.slice(server.indexOf('(async function atinaServerBoot()'), server.indexOf('})();', server.indexOf('(async function atinaServerBoot()')) + 4);
  assert.match(boot, /atinaServerResumeCardRefresh\(\)/);
  assert.doesNotMatch(boot, /localStorage\.removeItem\(ATINA_SERVER_SESSION_KEY\)/);
  assert.match(html, /id="atinaResumeSessionCard" hidden/);
  assert.match(html, /id="atinaResumeSessionBtn"/);
  assert.match(server, /async function atinaServerResumeSavedSession\(\)/);
  assert.match(server, /atinaServerResumeSavedSession/);
});

test('manual resume applies server state before switching to game screen', () => {
  const fnStart = server.indexOf('async function atinaServerRestoreSession()');
  const fnEnd = server.indexOf('\nfunction atinaServerResumeCardRefresh()', fnStart);
  const restore = server.slice(fnStart, fnEnd);
  assert.ok(fnStart >= 0 && fnEnd > fnStart, 'restore function boundaries found');
  assert.ok(restore.indexOf('atinaServerApplyState(state)') < restore.indexOf("screen('game')"), 'state applied before showing game');
  assert.match(restore, /atina_v2_local_game_state/);
  assert.match(restore, /atinaServerIsInvalidSession/);
  assert.match(restore, /localStorage\.removeItem\(ATINA_SERVER_SESSION_KEY\)/);
});
