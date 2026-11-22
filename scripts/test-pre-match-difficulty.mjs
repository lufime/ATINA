import assert from 'node:assert/strict';
import fs from 'node:fs';

const html=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');

// Exercise the real random-difficulty helper in isolation.
const helperStart=html.indexOf('let atinaMixedDifficultyCache={};');
const helperEnd=html.indexOf('function difficultyLabel(level)',helperStart);
assert(helperStart>=0&&helperEnd>helperStart,'difficulty cache helper exists');
const helper=html.slice(helperStart,helperEnd);
const randomFn=helper.match(/function atinaRandomChallengeDifficulty\(index\)\{[\s\S]*?\}/)?.[0];
assert(randomFn,'random per-challenge function exists');
const randomRuntime=new Function(randomFn+';let atinaMixedDifficultyCache={};return atinaRandomChallengeDifficulty;')();
const originalRandom=Math.random;
try{
  Math.random=()=>0;
  assert.equal(randomRuntime(7),'easy','random selection includes easy');
  Math.random=()=>0.5;
  assert.equal(randomRuntime(7),'easy','the same challenge retains its difficulty');
  assert.equal(randomRuntime(8),'medium','different challenge indexes get independent choices');
  Math.random=()=>0.999999;
  assert.equal(randomRuntime(9),'hard','random selection includes hard');
}finally{Math.random=originalRandom;}

// Verify challenge-count validation against the actual reader function.
const countFn=html.match(/function atinaReadChallengeCount\(\)\{try\{[\s\S]*?\}catch\(e\)\{return 10;\}\}/)?.[0];
assert(countFn,'challenge-count reader exists');
assert(html.includes('id="atinaPregameStart" disabled'),'start is initially disabled until valid configuration');
assert(html.includes('function validateConfig()')||html.includes('function validate()'),'configuration validates automatically');
assert(html.includes('id="atinaPregameModes"'),'configuration exposes mode selection');
assert(html.includes('id="atinaSoloCategoryPicker"'),'Solo category picker exists');
assert(html.includes('id="atinaSoloCategory"'),'Solo category selection control exists');

const countRuntime=new Function('localStorage',"const ATINA_CHALLENGE_COUNT_KEY='atinaChallengeCount';"+countFn+';return atinaReadChallengeCount;');
function readCount(value,throws=false){
  const storage={getItem(){if(throws)throw new Error('storage unavailable');return value;}};
  return countRuntime(storage)();
}
for(const value of ['1','10','1000'])assert.equal(readCount(value),Number(value),'valid integer bounds persist');
for(const value of ['0','1001','1.5','NaN','abc',''])assert.equal(readCount(value),10,'invalid settings safely fall back to default');
assert.equal(readCount(null),10,'missing setting uses default');
assert.equal(readCount('500',true),10,'storage errors use default');

// Guard integration points: count applies to local queue, cache survives restore, and resets on new game.
assert(html.includes('atinaMixedDifficultyCache,feedback:'),'random cache is serialized with local progress');
assert(html.includes('atinaMixedDifficultyCache={};let eligible=[];if(mode===' + "'mix'" + ')'),'random cache resets on a new game');
assert(html.includes('queue=atinaBuildRoundQueue(eligible,requestedCount)'),'configured count limits local queues');
assert(html.includes("['easy','medium','hard']"),'random difficulty uses existing score-supported levels');
assert(html.includes("Object.entries(p.atinaMixedDifficultyCache).filter(([k,v])=>Number.isInteger(Number(k))&&['easy','medium','hard'].includes(v))"),'restored cache filters invalid indexes and difficulty values');

assert(html.includes("!['solo','duel','mix'].includes(p.mode)"),'local progress restore accepts the Mix mode');

// Regression guard: quick-play Solo/Mix shortcuts must enter mode selection, not start directly.
const quickPlayLauncher=html.match(/document\.addEventListener\('click',function\(event\)\{[\s\S]*?\},false\);/)?.[0]||html.match(/document\.addEventListener\("click",function\(event\)\{[\s\S]*?\},false\);/)?.[0];
assert(html.includes('showHomePage("play");'),'quick-play shortcuts route to mode selection');
assert(html.includes('data-atina-launch')&&html.includes('showHomePage("play")'),'quick-play selection entry exists');
assert(html.includes("$('solo').onclick=()=>openConfig('solo',null)"),'Solo opens configuration and selection directly');
assert(!html.includes("$('solo').onclick=()=>showHomePage('categories')"),'Solo bypasses the intermediate categories page');
assert(html.includes("start('solo',b.dataset.category)"),'category selection starts Solo with the chosen category');

console.log('Pre-match selection regression checks passed.');
