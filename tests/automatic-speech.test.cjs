'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const path = require('node:path');

const html = readFileSync(path.join(__dirname, '../index.html'), 'utf8');
const start = html.indexOf('let atinaSpeechQueue=[]');
const end = html.indexOf('function timerTick()', start);
assert.ok(start >= 0 && end > start, 'Bloco de síntese de voz encontrado no index.html');
const speechSource = html.slice(start, end);

function createClient(label) {
  const utterances = [];
  const timers = [];
  const feedback = { textContent: '' };
  class FakeUtterance {
    constructor(text) { this.text = text; utterances.push(this); }
  }
  const synth = {
    speaking: false, paused: false, calls: [],
    getVoices: () => [{ lang: 'pt-PT', name: 'Português' }],
    addEventListener() {},
    resume() { this.paused = false; },
    speak(utterance) { this.calls.push(utterance); this.speaking = true; }
  };
  const window = { speechSynthesis: synth, SpeechSynthesisUtterance: FakeUtterance };
  const context = {
    window, atinaClueSpeechEnabled: true,
    $: id => id === 'feedback' ? feedback : null,
    setTimeout: fn => { timers.push(fn); return timers.length; },
    console
  };
  vm.createContext(context);
  vm.runInContext(speechSource, context, { filename: 'atina-speech-runtime.js' });
  return { label, context, synth, utterances, timers, feedback };
}

for (const client of ['anfitrião', 'participante']) {
  test(`(${client}) só confirma ativação quando onstart chega`, () => {
    const c = createClient(client);
    assert.equal(c.context.atinaActivateAutomaticSpeech(), true);
    assert.match(c.feedback.textContent, /A preparar/);
    assert.doesNotMatch(c.feedback.textContent, /voz está ativa/i);
    c.utterances[0].onstart();
    assert.match(c.feedback.textContent, /voz está ativa/i);
  });

  test(`(${client}) onerror liberta a chave e permite nova tentativa`, () => {
    const c = createClient(client);
    let pending = '';
    let last = '';
    const key = 'sala-1:desafio-10:0:1';
    const queue = () => {
      if (key === last || key === pending) return false;
      const accepted = c.context.atinaSpeakClue('Pista de teste', true, {
        onStart: () => { last = key; pending = ''; },
        onError: () => { if (pending === key) pending = ''; if (last === key) last = ''; }
      });
      if (accepted) pending = key;
      return accepted;
    };
    assert.equal(queue(), true);
    assert.equal(queue(), false);
    c.synth.speaking = false;
    c.utterances[0].onerror({ error: 'not-allowed' });
    assert.equal(pending, '');
    assert.equal(last, '');
    assert.equal(queue(), true);
    assert.equal(c.synth.calls.length, 2);
  });

  test(`(${client}) atualizações repetidas não cancelam nem perdem a fila`, () => {
    const c = createClient(client);
    assert.equal(c.context.atinaSpeakClue('Primeira pista', true), true);
    assert.equal(c.context.atinaSpeakClue('Segunda pista', true), true);
    assert.equal(c.synth.calls.length, 1);
    c.utterances[0].onstart();
    // Simula vários renders da sala enquanto a primeira utterance continua ativa.
    for (let i = 0; i < 5; i++) {
      assert.equal(vm.runInContext('atinaSpeechQueue.length', c.context), 1);
      assert.equal(c.synth.calls.length, 1);
    }
    c.synth.speaking = false;
    c.utterances[0].onend();
    assert.equal(c.timers.length, 1);
    c.timers.shift()();
    assert.equal(c.synth.calls.length, 2);
    assert.equal(c.utterances[1].text, 'Segunda pista');
  });
}
