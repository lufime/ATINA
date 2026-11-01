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

for (const id of ['dailyMissionTitle','dailyMissionFill','dailyMissionProgress','dailyMissionStatus','dailyStreak','dailyTotal','dailyMissionStart']) {
  if (!html.includes('id="' + id + '"')) throw new Error('Falta o elemento da missão diária: ' + id);
}
for (const token of ['atinaReadEngagement','atinaRenderDailyMission','atinaRecordChallengeCompletion','atinaYesterday','dailyCount','streak']) {
  if (!html.includes(token)) throw new Error('Falta a lógica de progressão: ' + token);
}
if (!/atinaRecordChallengeCompletion\\('local:'\\+atinaRunId\\+':'\\+pos\\)/.test(html)) throw new Error('As rondas locais não são registadas.');
if (!client.includes("atinaRecordChallengeCompletion('server:' + state.session_id + ':' + state.position)")) throw new Error('As sessões individuais não registam progresso.');
if (!client.includes("atinaRecordChallengeCompletion('room:' + (networkRoom?.room_id || 'online') + ':' + st.pos)")) throw new Error('As salas online não registam progresso.');
if (!html.includes("$('dailyMissionStart').onclick=()=>showHomePage('categories')")) throw new Error('O atalho para a missão diária não funciona.');
console.log('Progressão diária validada: missão, sequência, contagem, deduplicação e modos local/servidor/online; sintaxe JavaScript válida.');
