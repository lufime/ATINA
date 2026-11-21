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

for (const client of ['anfitrião', 'participante']) {
  test(`(${client}) mantém a primeira leitura enquanto o navegador ainda não dispara onstart`, () => {
    const c = createClient(client);
    c.synth.speak = function (utterance) {
      this.calls.push(utterance);
      // Alguns motores demoram a atualizar speaking até ao evento onstart.
      this.speaking = false;
    };
    assert.equal(c.context.atinaSpeakClue('Primeira pista', true), true);
    assert.equal(c.synth.calls.length, 1);
    assert.equal(c.context.atinaSpeakClue('Segunda pista', true), true);
    assert.equal(c.synth.calls.length, 1);
    c.utterances[0].onstart();
    assert.equal(c.synth.calls.length, 1);
    c.synth.speaking = false;
    c.utterances[0].onend();
    c.timers.shift()();
    assert.equal(c.synth.calls.length, 2);
    assert.equal(c.utterances[1].text, 'Segunda pista');
  });
}


for (const client of ['anfitrião', 'participante']) {
  test(`(${client}) a Sala inicia diretamente a leitura da pista confirmada pelo servidor`, () => {
    assert.ok(html.includes("networkPendingSpokenClueState=spokenKey;const currentClue=String(clueSource[revealed-1]||g[2]?.[revealed-1]||'').trim();"));
    assert.ok(html.includes("atinaSpeakClue('Pista '+revealed+'. '+currentClue,false,atinaNetworkClueSpeechLifecycle)"));
    assert.ok(!html.includes("networkPendingSpokenClueState=spokenKey;$('listenCurrentClue')?.click();"));
  });
}


test('a leitura automática na sala respeita a opção de desligar', () => {
  assert.ok(html.includes("atinaSpeakClue('Pista '+revealed+'. '+currentClue,false,atinaNetworkClueSpeechLifecycle)"),
    'A leitura das pistas online deve respeitar a configuração de voz');
  assert.ok(!html.includes("atinaSpeakClue('Pista '+revealed+'. '+currentClue,true,atinaNetworkClueSpeechLifecycle)"),
    'A sala não deve forçar a voz quando o jogador a desligou');
});

test('o relógio de tempo ativo pausa antes da transição entre desafios', () => {
  const nextStart = html.indexOf('async function next(){');
  const nextEnd = html.indexOf('async function activateLandscapePresentation()', nextStart);
  assert.ok(nextStart >= 0 && nextEnd > nextStart, 'Função next() encontrada');
  const nextSource = html.slice(nextStart, nextEnd);
  const stopPosition = nextSource.indexOf('raceStop();');
  const pausePosition = nextSource.indexOf('await challengePause');
  assert.ok(stopPosition >= 0 && pausePosition > stopPosition,
    'raceStop deve ocorrer antes da pausa de transição, para não contar os 10 segundos entre desafios');
  const revealStart = html.indexOf('function reveal(){');
  const revealEnd = html.indexOf('function atinaRenderRevealedAnswer', revealStart);
  const revealSource = html.slice(revealStart, revealEnd);
  assert.ok(revealSource.includes('raceStart();startTimer();'),
    'Relógio de tempo ativo e cronómetro do desafio devem arrancar na primeira pista');
});
