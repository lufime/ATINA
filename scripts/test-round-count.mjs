import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
const queueHelper = html.match(/function atinaBuildRoundQueue\(eligible,count\)\{[^}]+\}/)?.[0];
const nextHelper = html.match(/function atinaRoundHasNext\(currentPos,roundQueue\)\{[^}]+\}/)?.[0];
assert.ok(queueHelper, 'configured round queue builder exists');
assert.ok(nextHelper, 'round boundary helper exists');

const queueRuntime = new Function('shuffle', queueHelper + ';return atinaBuildRoundQueue;')((items) => items.slice().reverse());
const hasNextRuntime = new Function(nextHelper + ';return atinaRoundHasNext;')();
const eligible = Array.from({ length: 25 }, (_, i) => i);
for (const count of [1, 2, 10, 25]) {
  const queue = queueRuntime(eligible, count);
  assert.equal(queue.length, count, 'selected number is respected');
  assert.equal(new Set(queue).size, count, 'queue does not duplicate challenges');
}
assert.deepEqual(queueRuntime(eligible, 10), eligible.slice().reverse().slice(0, 10), 'shuffle order is respected');
assert.deepEqual(queueRuntime(eligible, 0), [], 'invalid count produces no challenges');

assert.equal(hasNextRuntime(0, [0]), false, 'one challenge round ends after challenge one');
assert.equal(hasNextRuntime(0, Array.from({ length: 10 }, (_, i) => i)), true, 'ten challenge round advances after challenge one');
assert.equal(hasNextRuntime(8, Array.from({ length: 10 }, (_, i) => i)), true, 'ten challenge round advances through challenge nine');
assert.equal(hasNextRuntime(9, Array.from({ length: 10 }, (_, i) => i)), false, 'ten challenge round stops after challenge ten');

const startSection = html.slice(html.indexOf('function start(m,chosen=null){'), html.indexOf('function mixDraw(){'));
assert.ok(startSection.includes('const requestedCount=atinaChallengeCount'), 'game start captures the selected count');
assert.ok(startSection.includes('queue=atinaBuildRoundQueue(eligible,requestedCount)'), 'all game modes build a queue with the selected count');
assert.ok(startSection.includes('queue.length!==requestedCount'), 'game start rejects an incomplete queue instead of silently playing fewer challenges');

const nextSection = html.slice(html.indexOf('async function next(){'), html.indexOf('async function activateLandscapePresentation'));
assert.ok(nextSection.includes('if(!atinaRoundHasNext(pos,queue)){finishRace(null);return;}'), 'round ends at the configured challenge limit');
assert.ok(!nextSection.includes('queue=shuffle(queue);pos=0;'), 'round no longer loops/restarts the selected queue');
assert.ok(html.includes('🏁 Ronda concluída — '+ ' '+ ' desafios') || html.includes('🏁 Ronda concluída — '+ ' challenges') || html.includes('🏁 Ronda concluída — '+ ' challenges'), 'results label is updated for count-based round completion');
console.log('Round challenge-count tests passed.');
