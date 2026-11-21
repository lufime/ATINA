const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('index.html', 'utf8');

function extractFunction(name) {
  const start = html.indexOf('function ' + name + '(');
  assert.notEqual(start, -1, name + ' must exist in index.html');
  const open = html.indexOf('{', start);
  let depth = 0, quote = null, escaped = false, lineComment = false, blockComment = false;
  for (let i = open; i < html.length; i++) {
    const ch = html[i], next = html[i + 1];
    if (lineComment) { if (ch === '\\n') lineComment = false; continue; }
    if (blockComment) { if (ch === '*' && next === '/') { blockComment = false; i++; } continue; }
    if (quote) { if (escaped) { escaped = false; continue; } if (ch === '\\') { escaped = true; continue; } if (ch === quote) quote = null; continue; }
    if (ch === '/' && next === '/') { lineComment = true; i++; continue; }
    if (ch === '/' && next === '*') { blockComment = true; i++; continue; }
    if (ch === "'" || ch === '"' || ch === '`') { quote = ch; continue; }
    if (ch === '{') depth++;
    if (ch === '}' && --depth === 0) return html.slice(start, i + 1);
  }
  throw new Error('Could not parse function ' + name);
}

const snippets = ['timerTick', 'atinaSoloReportOpen', 'atinaSoloReportResume'].map(extractFunction).join('\n');

function harness() {
  let now = 100000;
  let nextHandle = 1;
  const activeIntervals = new Map();
  const elements = new Map();
  const makeElement = id => {
    if (!elements.has(id)) elements.set(id, {
      textContent: '', value: '', attributes: {},
      classList: { add() {}, remove() {}, toggle() {} },
      setAttribute(k, v) { this.attributes[k] = v; }
    });
    return elements.get(id);
  };
  class FakeDate extends Date { static now() { return now; } }
  const context = {
    Date: FakeDate, console, Math,
    mode: 'solo', networkRoom: null, locked: false, timePenaltyApplied: false,
    atinaSoloReportPaused: false, atinaSoloReportRemaining: 0,
    autoNextTimeout: null, autoRevealTimeout: null, autoRevealInterval: null,
    timerDeadline: 0, timeLeft: 60, timedMode: 60, timerInterval: null,
    scores: [12], player: 0, correctStreak: 3, answeredCount: 0, lastTimerBeepAt: 0,
    games: [['Categoria', [], [], 'Resposta correta']], queue: [0], pos: 0,
    xpTotal: 777, saveLocalProgress() {}, timerBeep() {}, playAtinaSound() {},
    update() {}, board() {}, end() {}, drawTimer() {},
    setInterval(fn) { const id = nextHandle++; activeIntervals.set(id, fn); return id; },
    clearInterval(id) { activeIntervals.delete(id); },
    setTimeout(fn) { return nextHandle++; }, clearTimeout() {},
    document: { getElementById(id) { return id === 'atinaSpecialCardPopup' ? null : makeElement(id); } },
    $: makeElement
  };
  vm.createContext(context);
  vm.runInContext(snippets, context);
  return { context, setNow(value) { now = value; }, advance(ms) { now += ms; }, intervals: activeIntervals };
}

test('reporting an error does not pause or reset the timer', () => {
  const h = harness(), c = h.context;
  c.timeLeft = 60;
  c.timerDeadline = 100000 + 60000;
  c.timerInterval = c.setInterval(c.timerTick);
  h.advance(10000);
  c.timerTick();
  assert.equal(c.timeLeft, 50);
  const deadline = c.timerDeadline, interval = c.timerInterval;
  c.atinaSoloReportOpen();
  assert.equal(c.atinaSoloReportPaused, true, 'report panel is open');
  assert.equal(c.timerDeadline, deadline, 'report opening must not rebuild the deadline');
  assert.equal(c.timerInterval, interval, 'report opening must not stop the interval');
  h.advance(15000);
  c.timerTick();
  assert.equal(c.timeLeft, 35, 'elapsed report time must count against the player');
  assert.equal(c.timerDeadline, deadline, 'deadline remains unchanged while reporting');
});

test('closing report keeps timer continuously running without granting extra time', () => {
  const h = harness(), c = h.context;
  c.timeLeft = 60;
  c.timerDeadline = 100000 + 60000;
  c.timerInterval = c.setInterval(c.timerTick);
  h.advance(12000);
  c.timerTick();
  assert.equal(c.timeLeft, 48);
  const deadline = c.timerDeadline, interval = c.timerInterval;
  c.atinaSoloReportOpen();
  h.advance(30000);
  c.timerTick();
  assert.equal(c.timeLeft, 18);
  c.atinaSoloReportResume();
  assert.equal(c.atinaSoloReportPaused, false);
  assert.equal(c.timerDeadline, deadline);
  assert.equal(c.timerInterval, interval);
  h.advance(1000);
  c.timerTick();
  assert.equal(c.timeLeft, 17);
});

test('reporting does not change score, XP or streak while clock continues', () => {
  const h = harness(), c = h.context;
  c.timeLeft = 25;
  c.timerDeadline = 100000 + 25000;
  c.timerInterval = c.setInterval(c.timerTick);
  const score = c.scores.slice(), xp = c.xpTotal, streak = c.correctStreak;
  c.atinaSoloReportOpen();
  h.advance(5000);
  c.timerTick();
  assert.equal(c.timeLeft, 20);
  assert.deepEqual(c.scores, score);
  assert.equal(c.xpTotal, xp);
  assert.equal(c.correctStreak, streak);
});
