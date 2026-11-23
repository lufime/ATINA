import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const helperStart = html.indexOf("const ATINA_CORRECT_CHALLENGES_KEY='atinaCorrectChallengesV1';");
const startIndex = html.indexOf('function start(m,chosen=null){');
assert.ok(helperStart >= 0 && startIndex > helperStart, 'Persisted correct-answer history helper is present');
const helperCode = html.slice(helperStart, startIndex);
const store = new Map();
const context = { localStorage: {
  getItem: key => store.has(key) ? store.get(key) : null,
  setItem: (key, value) => store.set(key, String(value))
}};
vm.createContext(context);
vm.runInContext(helperCode, context);
assert.equal(context.atinaReadCorrectChallenges().size, 0);
context.atinaRememberCorrectChallenge(12);
assert.deepEqual([...context.atinaReadCorrectChallenges()], [12]);
context.atinaRememberCorrectChallenge(12);
assert.deepEqual([...context.atinaReadCorrectChallenges()], [12], 'duplicate ids are deduplicated');
context.atinaRememberCorrectChallenge(27);
assert.deepEqual([...context.atinaReadCorrectChallenges()].sort((a,b)=>a-b), [12,27]);

const startCode = html.slice(startIndex, html.indexOf('function mixDraw()', startIndex));
assert.match(startCode, /!atinaReadCorrectChallenges\(\)\.has\(x\.i\)/, 'all classic modes exclude answered IDs');
const endIndex = html.indexOf("const isCorrect=message.startsWith('Certo!'),isTimeout=message.includes('Tempo esgotado');");
assert.ok(endIndex >= 0);
assert.match(html.slice(endIndex, endIndex+260), /if\(isCorrect\)atinaRememberCorrectChallenge\(queue\[pos\]\);/, 'only correct answers persist as completed');
console.log('Correct-answer exclusion checks passed.');
