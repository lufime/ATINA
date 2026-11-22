import assert from 'node:assert/strict';
import fs from 'node:fs';

const html=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');
const helperStart=html.indexOf('let atinaMixedDifficultyCache={};');
const helperEnd=html.indexOf('function difficultyLabel(level)',helperStart);
assert(helperStart>=0&&helperEnd>helperStart,'difficulty cache helper exists');
const helper=html.slice(helperStart,helperEnd);
const randomFn=helper.match(/function atinaRandomChallengeDifficulty\(index\)\{[\s\S]*?\}/)?.[0];
assert(randomFn,'random per-challenge function exists');
const runtime=new Function(randomFn+';let atinaMixedDifficultyCache={};return atinaRandomChallengeDifficulty;')();
const choices=['easy','medium','hard'];
const original=Math.random;
try{
  Math.random=()=>0;
  assert.equal(runtime(7),'easy','random result is within the difficulty options');
  Math.random=()=>0.5;
  assert.equal(runtime(7),'easy','a challenge keeps its chosen difficulty during a run');
  assert.equal(runtime(8),'medium','different challenges receive independent choices');
  Math.random=()=>0.999999;
  assert.equal(runtime(9),'hard','random selection covers the upper choice');
}finally{Math.random=original;}
assert(html.includes('atinaMixedDifficultyCache,feedback:'),'mixed difficulty cache is persisted with local progress');
assert(html.includes('atinaMixedDifficultyCache={};if(mode===' + "'mix'" + ')'),'difficulty cache resets when a new game starts');
assert(html.includes('queue=queue.slice(0,atinaChallengeCount)'),'configured challenge count limits local queues');
assert(html.includes("'easy','medium','hard'"),'random difficulty remains within existing implemented scoring levels');
console.log('Pre-match difficulty regression checks passed.');
