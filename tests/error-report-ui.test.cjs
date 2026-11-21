const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const game = fs.readFileSync('index.html', 'utf8');
const admin = fs.readFileSync('admin-images.html', 'utf8');

test('game report form submits only pseudonym, category and description to report endpoint', () => {
  assert.match(game, /atina-error-reports-submit/);
  assert.match(game, /nickname:getNickname\(\),category:/);
  assert.match(game, /description\}\)/);
  assert.doesNotMatch(game.slice(game.indexOf('setupSoloReportSubmission'), game.indexOf('const ATINA_PROGRESS_KEY')), /player_id|session_id|room_id|email|ip_address/i);
});

test('solo report keeps the timer paused until explicit resume', () => {
  assert.match(game, /Report enviado com sucesso\. O relógio continua pausado até voltares ao jogo/);
  assert.match(game, /atinaSoloReportResume/);
});

test('admin reports UI is integrated in existing admin-images page', () => {
  assert.match(admin, /data-admin-tab="reports"/);
  assert.match(admin, /id="reportsPanel"/);
  assert.match(admin, /atina-error-reports-admin/);
  assert.match(admin, /reportNicknameFilter/);
  assert.match(admin, /Guardar alterações/);
});

test('report contents are rendered through textContent and DOM nodes', () => {
  const start = admin.indexOf('function renderReports()');
  const end = admin.indexOf('function messageStatus', start);
  assert.ok(start >= 0 && end > start);
  const render = admin.slice(start, end);
  assert.match(render, /desc\.textContent=report\.description/);
  assert.match(render, /title\.textContent=/);
  assert.doesNotMatch(render, /innerHTML.*report\.(nickname|description|internal_note)/);
});

test('embedded JavaScript scripts parse without syntax errors', () => {
  const scripts = [];
  let cursor = 0;
  while (true) {
    const opening = admin.indexOf('<script', cursor);
    if (opening < 0) break;
    const tagEnd = admin.indexOf('>', opening);
    const closing = admin.indexOf('</script>', tagEnd + 1);
    assert.ok(tagEnd >= 0 && closing > tagEnd, 'script tags should be well formed');
    const attributes = admin.slice(opening, tagEnd + 1).toLowerCase();
    const source = admin.slice(tagEnd + 1, closing);
    cursor = closing + 9;
    if (attributes.includes(' src=') || attributes.includes(' type="application/json"') || attributes.includes(" type='application/json'")) continue;
    if (!source.trim()) continue;
    assert.doesNotThrow(() => new vm.Script(source, { filename: 'admin-images-inline-script.js' }), 'inline script should parse');
    scripts.push(source);
  }
  assert.ok(scripts.length > 0, 'expected at least one inline JavaScript block to parse');
});
