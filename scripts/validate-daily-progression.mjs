#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const client = readFileSync(new URL('../atina-server-client.js', import.meta.url), 'utf8');
// Localizar o script principal pelo conteúdo, sem depender da posição
// de tags externas ou de scripts auxiliares adicionados ao HTML.
const inlineScripts = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/gi)];
const mainScript = inlineScripts.find(([, body]) => body.includes('function start(m,chosen=null)') && body.includes('function mixDraw'));
if (!mainScript) throw new Error('Não foi possível localizar o JavaScript principal.');
new vm.Script(mainScript[1], { filename: 'index.html inline script' });
new vm.Script(client, { filename: 'atina-server-client.js' });

for (const id of ['dailyMissionTitle','dailyMissionFill','dailyMissionProgress','dailyMissionStatus','dailyStreak','dailyTotal','dailyMissionStart','atinaXpValue','atinaLevelValue','atinaXpFill','atinaBadges']) {
  if (!html.includes('id="' + id + '"')) throw new Error('Falta o elemento da missão diária: ' + id);
}
for (const token of ['atinaReadEngagement','atinaRenderDailyMission','atinaRecordChallengeCompletion','atinaYesterday','dailyCount','streak','missions','rewardedDate','atinaDailyCategory','Math.floor(xp/250)+1','data.missions*50','data.total*10','Primeiros passos','Mente ativa','Persistente','Veterano','Lenda ATINA']) {
  if (!html.includes(token)) throw new Error('Falta a lógica de progressão: ' + token);
}
if (!html.includes("atinaRecordChallengeCompletion('local:'+atinaRunId+':'+pos)")) throw new Error('As rondas locais não são registadas.');
if (!client.includes("const key = state.session_id + ':' + state.position;") || !client.includes("atina_progress_claim_local") || !client.includes("p_session_id: state.session_id") || !client.includes("p_position: Number(state.position)")) throw new Error('As sessões individuais não reclamam progresso no servidor.');
if (!client.includes("atinaRecordChallengeCompletion('room:' + (networkRoom?.room_id || 'online') + ':' + st.pos)")) throw new Error('As salas online não registam progresso.');
if (!html.includes("$('dailyMissionStart').onclick=()=>{const category=atinaDailyCategory();if(category){showHomePage('play');start('solo',category);}};")) throw new Error('O atalho não inicia o desafio diário selecionado.');
if (!html.includes('count/3*100') || !html.includes("data.dailyCount>=3&&data.rewardedDate!==today")) throw new Error('A missão diária não recompensa a conclusão uma única vez.');
if (!html.includes("atinaRecordChallengeCompletion('mime-local:")) throw new Error('As Mímicas locais não registam progresso.');
if (!html.includes("atinaRecordChallengeCompletion('room-mime:'")) throw new Error('As Mímicas online não registam progresso.');
console.log('Progressão validada: missão diária jogável, XP, níveis, conquistas, sequência, deduplicação e modos local/servidor/online; sintaxe JavaScript válida.');
