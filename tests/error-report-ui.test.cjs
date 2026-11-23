const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const game = fs.readFileSync('index.html', 'utf8');
const admin = fs.readFileSync('admin-images.html', 'utf8');
const globalReport = fs.readFileSync('assets/atina-global-error-report.js', 'utf8');

test('game report supports optional uploaded or directly captured screenshots', () => {
  assert.match(game, /atina-error-reports-submit/);
  assert.match(game, /nickname:getNickname\(\),category:/);
  assert.match(game, /description,screenshot:screenshotPayload/);
  assert.match(game, /atinaSoloReportScreenshot/);
  assert.match(game, /atinaSoloReportCapture/);
  assert.match(game, /getDisplayMedia/);
  assert.match(game, /Capturar screenshot do jogo/);
  assert.match(game, /3\s*\*\s*1024\s*\*\s*1024/);
  assert.match(game, /readAsDataURL\(file\)/);
  assert.match(game, /screenshotPayload\s*=\s*\{content_type:file\.type,base64:/);
  assert.doesNotMatch(game.slice(game.indexOf('setupSoloReportSubmission'), game.indexOf('const ATINA_PROGRESS_KEY')), /player_id|session_id|room_id|email|ip_address/i);
});

test('successful Solo report automatically resumes the paused clock', () => {
  assert.match(game, /Report enviado com sucesso\. O relógio foi retomado automaticamente/);
  assert.match(game, /atinaSoloReportResume\(\)/);
  assert.match(game, /atinaSoloReportRemaining/);
});

test('admin report UI previews screenshots and provides guarded deletion', () => {
  assert.match(admin, /data-admin-tab="reports"/);
  assert.match(admin, /id="reportsPanel"/);
  assert.match(admin, /atina-error-reports-admin/);
  assert.match(admin, /reportNicknameFilter/);
  assert.match(admin, /Guardar alterações/);
  assert.match(admin, /Abrir screenshot em tamanho completo/);
  assert.match(admin, /Apagar report/);
  assert.match(admin, /method:"DELETE"/);
  assert.match(admin, /report\.screenshot_url/);
});

test('admin renders screenshots from signed URLs without requiring the hidden storage path', () => {
  const start = admin.indexOf('function renderReports()');
  const end = admin.indexOf('function messageStatus', start);
  assert.ok(start >= 0 && end > start);
  const render = admin.slice(start, end);
  assert.match(render, /if\(report\.screenshot_url\)/);
  assert.match(render, /else if\(report\.screenshot_error\)/);
  assert.doesNotMatch(render, /report\.screenshot_path/);
  assert.match(render, /Ilustração de screenshot em falta/);
});

test('report contents are rendered through textContent and DOM nodes', () => {
  const start = admin.indexOf('function renderReports()');
  const end = admin.indexOf('function messageStatus', start);
  assert.ok(start >= 0 && end > start);
  const render = admin.slice(start, end);
  assert.match(render, /desc\.textContent=report\.description/);
  assert.match(render, /title\.textContent=/);
  assert.match(render, /image\.src=report\.screenshot_url/);
  assert.doesNotMatch(render, /innerHTML.*report\.(nickname|description|internal_note)/);
});

test('screenshot capture handles unsupported browsers, enforces size, and stops media tracks', () => {
  const capture = game.slice(game.indexOf('const captureButton=$("atinaSoloReportCapture")'), game.indexOf('remove?.addEventListener', game.indexOf('const captureButton=$("atinaSoloReportCapture")')));
  assert.match(capture, /getDisplayMedia/);
  assert.match(capture, /track/);
  assert.match(capture, /blob\.size>ATINA_REPORT_SCREENSHOT_MAX_BYTES/);
  assert.match(capture, /stream\?\.getTracks\(\)\.forEach\(track=>track\.stop\(\)\)/);
  assert.match(capture, /canvas\.toBlob/);
  assert.match(capture, /catch\(error\)/);
});
test('clock resumes only after successful report and failed submission keeps description', () => {
  const start=game.indexOf('form.addEventListener(\'submit\',async event=>');
  const end=game.indexOf('});\n})();',start);
  assert.ok(start>=0&&end>start);
  const submitFlow=game.slice(start,end);
  assert.match(submitFlow,/if\(!response\.ok\|\|!data\.success\)throw/);
  assert.match(submitFlow,/atinaSoloReportResume\(\)/);
  assert.match(submitFlow,/catch\(error\)/);
  assert.doesNotMatch(submitFlow,/catch\(error\)[\s\S]*atinaSoloReportResume\(\)/);
  assert.match(submitFlow,/finally\{submit\.disabled=false;/);
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


test('global report screenshot remove action is hidden until a valid preview loads', () => {
  assert.match(globalReport, /id="atinaGlobalReportRemoveScreenshot" hidden/);
  assert.match(globalReport, /function clearImage\(\)[\s\S]*atinaGlobalReportRemoveScreenshot'\)\.hidden=true/);
  assert.match(globalReport, /preview\.onload=\(\)=>\{preview\.hidden=false;\$\('atinaGlobalReportRemoveScreenshot'\)\.hidden=false/);
  assert.match(globalReport, /preview\.onerror=\(\)=>\{preview\.hidden=true;\$\('atinaGlobalReportRemoveScreenshot'\)\.hidden=true/);
});


test('global report preview CSS respects the hidden attribute', () => {
  assert.match(globalReport, /#atinaGlobalReportPreview:not\(\[hidden\]\)\{display:block/);
  assert.doesNotMatch(globalReport, /#atinaGlobalReportPreview\{display:block/);
});


test('global report explains native screenshot attachment on mobile browsers', () => {
  assert.match(globalReport, /captura direta do ecrã não é suportada neste navegador móvel/i);
  assert.match(globalReport, /screenshot com os botões do iPhone\/Android/i);
  assert.match(globalReport, /anexa-a através de Escolher ficheiro/i);
});

test('player report form has no ChatGPT share button; sharing is handled in admin', () => {
  assert.doesNotMatch(globalReport, /atinaGlobalReportShare|Partilhar com o ChatGPT|navigator\.share\\(shareData\\)/);
  assert.doesNotMatch(globalReport, /shareData\.files=\\[file\\]/);
  const start = admin.indexOf('function renderReports()');
  const end = admin.indexOf('function messageStatus', start);
  assert.ok(start >= 0 && end > start);
  const render = admin.slice(start, end);
  assert.match(render, /aiReview\.textContent="Partilhar report com ChatGPT"/);
  assert.match(render, /navigator\.share\\(/);
  assert.match(render, /Copiar contexto/);
  assert.match(render, /Abrir ChatGPT/);
});

test('ChatGPT report sharing is prominent at the top of admin report cards without changing player sharing', () => {
  assert.doesNotMatch(globalReport, /atinaGlobalReportOpenChatGPT|Copiar reporte e abrir ChatGPT/);
  const start = admin.indexOf('function renderReports()');
  const end = admin.indexOf('function messageStatus', start);
  assert.ok(start >= 0 && end > start);
  const render = admin.slice(start, end);
  assert.match(render, /aiReview\.textContent="Partilhar report com ChatGPT"/);
  assert.match(render, /sharePrompt\.textContent="Partilhar contexto"/);
  assert.match(render, /Copiar contexto/);
  assert.match(render, /Abrir ChatGPT/);
  const shareAction = render.indexOf('const aiReview=');
  assert.ok(shareAction > render.indexOf('card.appendChild(meta);'), 'share action follows report title and metadata');
  assert.ok(shareAction < render.indexOf('const desc='), 'share action is before report description and screenshot');
});
