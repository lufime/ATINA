#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const client = readFileSync(new URL('../atina-server-client.js', import.meta.url), 'utf8');
const start = html.indexOf('<script>') + 8;
const end = html.indexOf('</script><script src=', start);
if (start < 8 || end < 0) throw new Error('Não foi possível localizar o JavaScript principal.');
new vm.Script(html.slice(start, end), { filename: 'index.html inline script' });
new vm.Script(client, { filename: 'atina-server-client.js' });

for (const id of ['dailyMissionTitle','dailyMissionFill','dailyMissionProgress','dailyMissionStatus','dailyStreak','dailyTotal','dailyMissionStart','atinaXpValue','atinaLevelValue','atinaXpFill','atinaBadges']) {
  if (!html.includes('id="' + id + '"')) throw new Error('Falta o elemento da missão diária: ' + id);
}
for (const token of ['atinaReadEngagement','atinaRenderDailyMission','atinaRecordChallengeCompletion','atinaYesterday','dailyCount','streak','missions','rewardedDate','atinaDailyCategory','Math.floor(xp/250)+1','data.missions*50','data.total*10','Primeiros passos','Mente ativa','Persistente','Veterano','Lenda ATINA']) {
  if (!html.includes(token)) throw new Error('Falta a lógica de progressão: ' + token);
}
if (!html.includes("atinaRecordChallengeCompletion('local:'+atinaRunId+':'+pos)")) throw new Error('As rondas locais não são registadas.');
if (!client.includes("atinaRecordChallengeCompletion('server:' + state.session_id + ':' + state.position)")) throw new Error('As sessões individuais não registam progresso.');
if (!client.includes("atinaRecordChallengeCompletion('room:' + (networkRoom?.room_id || 'online') + ':' + st.pos)")) throw new Error('As salas online não registam progresso.');
if (!html.includes("$('dailyMissionStart').onclick=()=>{const category=atinaDailyCategory();if(category){showHomePage('play');start('solo',category);}};")) throw new Error('O atalho não inicia o desafio diário selecionado.');
if (!html.includes('count/3*100') || !html.includes("data.dailyCount>=3&&data.rewardedDate!==today")) throw new Error('A missão diária não recompensa a conclusão uma única vez.');
if (!/atinaRecordChallengeCompletion\\('mime-local:/.test(html)) throw new Error('As Mímicas locais não registam progresso.');
if (!html.includes("atinaRecordChallengeCompletion('room-mime:'")) throw new Error('As Mímicas online não registam progresso.');
console.log('Progressão validada: missão diária jogável, XP, níveis, conquistas, sequência, deduplicação e modos local/servidor/online; sintaxe JavaScript válida.');
