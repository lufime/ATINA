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
    if (lineComment) { if (ch === '\n') lineComment = false; continue; }
    if (blockComment) { if (ch === '*' && next === '/') { blockComment = false; i++; } continue; }
    if (quote) {
      if (escaped) { escaped = false; continue; }
      if (ch === '\\') { escaped = true; continue; }
      if (ch === quote) quote = null;
      continue;
    }
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
      textContent: '', value: '',
      attributes: {},
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
    scores: [12], player: 0, correctStreak: 3, answeredCount: 0,
    xpTotal: 777, saveLocalProgress() {}, timerBeep() {}, playAtinaSound() {},
    update() {}, board() {}, end() {}, drawTimer() {},
    setInterval(fn) { const id = nextHandle++; activeIntervals.set(id, fn); return id; },
    clearInterval(id) { activeIntervals.delete(id); },
    setTimeout(fn) { const id = nextHandle++; return id; },
    clearTimeout() {},
    document: { getElementById: makeElement },
    $: makeElement
  };
  vm.createContext(context);
  vm.runInContext(snippets, context);
  return {
    context, element: makeElement,
    setNow(value) { now = value; },
    advance(ms) { now += ms; },
    intervals: activeIntervals
  };
}

test('report opening pauses immediately and preserves the exact remaining time', () => {
  const h = harness(), c = h.context;
  c.timeLeft = 60;
  c.timerDeadline = 100000 + 60000;
  c.timerInterval = h.setInterval(c.timerTick);
  h.advance(10000);
  c.timerTick();
  const before = c.timeLeft;
  assert.equal(before, 50);
  const score = c.scores.slice(), xp = c.xpTotal, streak = c.correctStreak;
  c.atinaSoloReportOpen();
  assert.equal(c.atinaSoloReportPaused, true);
  assert.equal(c.atinaSoloReportRemaining, 50);
  assert.equal(c.timerDeadline, 0);
  assert.equal(c.timerInterval, null);
  assert.equal(h.intervals.size, 0);
  h.advance(15000);
  c.timerTick();
  assert.equal(c.timeLeft, 50, 'time must not tick while the report is open');
  assert.deepEqual(c.scores, score);
  assert.equal(c.xpTotal, xp);
  assert.equal(c.correctStreak, streak);
});

test('resuming Solo rebuilds the deadline from preserved time, not elapsed pause time', () => {
  const h = harness(), c = h.context;
  c.timeLeft = 60;
  c.timerDeadline = 100000 + 60000;
  c.timerInterval = h.setInterval(c.timerTick);
  h.advance(12000);
  c.timerTick();
  c.atinaSoloReportOpen();
  assert.equal(c.atinaSoloReportRemaining, 48);
  h.advance(30000);
  c.atinaSoloReportResume();
  assert.equal(c.atinaSoloReportPaused, false);
  assert.equal(c.timeLeft, 48);
  assert.equal(c.timerDeadline, 142000 + 48000);
  assert.equal(h.intervals.size, 1);
  c.timerTick();
  assert.equal(c.timeLeft, 48);
});

test('untimed Solo can open and close report without starting a timer', () => {
  const h = harness(), c = h.context;
  c.timedMode = 0;
  c.timeLeft = 0;
  c.timerDeadline = 0;
  const score = c.scores.slice(), xp = c.xpTotal, streak = c.correctStreak;
  c.atinaSoloReportOpen();
  assert.equal(c.atinaSoloReportPaused, true);
  h.advance(60000);
  c.timerTick();
  c.atinaSoloReportResume();
  assert.equal(c.atinaSoloReportPaused, false);
  assert.equal(c.timerInterval, null);
  assert.equal(c.timerDeadline, 0);
  assert.deepEqual(c.scores, score);
  assert.equal(c.xpTotal, xp);
  assert.equal(c.correctStreak, streak);
});

test('timeout is only applied after resumed time expires, never while paused', () => {
  const h = harness(), c = h.context;
  c.timeLeft = 5;
  c.timerDeadline = 100000 + 5000;
  c.timerInterval = h.setInterval(c.timerTick);
  const startingScore = c.scores[0], startingXp = c.xpTotal;
  c.atinaSoloReportOpen();
  h.advance(30000);
  c.timerTick();
  assert.equal(c.scores[0], startingScore);
  assert.equal(c.answeredCount, 0);
  c.atinaSoloReportResume();
  h.advance(5000);
  c.timerTick();
  assert.equal(c.timeLeft, 0);
  assert.equal(c.scores[0], startingScore - 10, 'timeout penalty should occur only after the preserved time expires');
  assert.equal(c.answeredCount, 1);
  assert.equal(c.xpTotal, startingXp);
});
