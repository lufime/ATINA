const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('index.html', 'utf8');
const source = fs.readFileSync('assets/atina-global-error-report.js', 'utf8');

test('transversal report component is mounted in the game entry page', () => {
  assert.match(html, /assets\/atina-global-error-report\.js/);
  assert.match(source, /atinaGlobalReportButton/);
  assert.match(source, /role="dialog"/);
  assert.match(source, /gameContext\(\)/);
  assert.match(source, /contextText\(ctx\)/);
  assert.match(source, /game_area:ctx\.screen\+' · '\+ctx\.mode/);
});

test('report is available globally and offers screenshot upload/capture', () => {
  assert.match(source, /position:fixed/);
  assert.match(source, /image\/png,image\/jpeg,image\/webp/);
  assert.match(source, /getDisplayMedia/);
  assert.match(source, /3\*1024\*1024/);
  assert.match(source, /stream\?\.getTracks\(\)\.forEach\(t=>t\.stop\(\)\)/);
  assert.match(source, /screenshot\s*\}\)/);
});

test('Solo clock pauses via existing pause routine and resumes on modal close/success', () => {
  assert.match(source, /atinaSoloReportOpen\(\)/);
  assert.match(source, /atinaSoloReportResume\(\)/);
  assert.match(source, /function close\(\).*resumeSolo/s);
  assert.match(source, /setTimeout\(close,500\)/);
});

test('submission preserves text on failure and uses the existing report endpoint', () => {
  assert.match(source, /atina-error-reports-submit/);
  assert.match(source, /description,game_area:ctx\.screen/);
  assert.match(source, /catch\(err\).*Falha no envio/s);
  assert.match(source, /user.length<20/);
});

test('component script parses and HTML closes the style/body/html tags', () => {
  assert.doesNotThrow(() => new vm.Script(source, {filename:'atina-global-error-report.js'}));
  assert.match(html, /<\/style>\s*<script src="\.\/assets\/atina-global-error-report\.js"><\/script>\s*<\/body>\s*<\/html>/);
});
