import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync('index.html', 'utf8');
const client = readFileSync('atina-server-client.js', 'utf8');
const pagesConfig = readFileSync('_config.yml', 'utf8');
const localCompatibility = readFileSync('supabase/migrations/20261101120000_atina_ranking_v2_local_sessions.sql', 'utf8');
const multiplayerCompatibility = readFileSync('supabase/migrations/20261101130000_atina_ranking_v2_multiplayer_mimicas.sql', 'utf8');
const errors = [];

const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)]
  .map(match => match[1])
  .filter(source => source.trim());

if (!scripts.length) errors.push('Não foi encontrado JavaScript inline.');
for (let i = 0; i < scripts.length; i++) {
  try { new vm.Script(scripts[i], { filename: 'index.inline.' + (i + 1) + '.js' }); }
  catch (error) { errors.push('JavaScript inline ' + (i + 1) + ': ' + error.message); }
}
try { new vm.Script(client, { filename: 'atina-server-client.js' }); }
catch (error) { errors.push('Cliente seguro: ' + error.message); }

const marker = 'const games=';
const source = scripts.join('\n');
const markerIndex = source.indexOf(marker);
if (markerIndex < 0) {
  errors.push('Catálogo games não encontrado no cliente.');
} else {
  const start = markerIndex + marker.length;
  let depth = 0, quote = null, escaped = false, end = -1;
  for (let i = start; i < source.length; i++) {
    const ch = source[i];
    if (quote) {
      if (escaped) escaped = false;
      else if (ch === '\\') escaped = true;
      else if (ch === quote) quote = null;
      continue;
    }
    if (ch === "'" || ch === '"' || ch === '\`') { quote = ch; continue; }
    if (ch === '[') depth++;
    else if (ch === ']' && --depth === 0) { end = i + 1; break; }
  }
  if (end < 0) errors.push('Não foi possível delimitar o catálogo games.');
  else {
    let games;
    try { games = JSON.parse(source.slice(start, end).replace(/,\s*([\]}])/g, '$1')); }
    catch (error) { errors.push('Catálogo games inválido: ' + error.message); }
    if (games) {
      if (games.length !== 802) errors.push('Esperados 802 slots históricos; encontrados ' + games.length + '.');
      const valid = games.filter(Boolean);
      if (valid.length !== 753) errors.push('Esperados 753 desafios; encontrados ' + valid.length + '.');
      for (let i = 0; i < games.length; i++) {
        const item = games[i];
        if (item && (item[3] !== null || !Array.isArray(item[2]) || item[2].length !== 0 || !Array.isArray(item[4]) || item[4].length !== 0)) {
          errors.push('Desafio no índice ' + i + ': pistas, resposta ou alternativas ainda presentes no cliente.');
          break;
        }
      }
    }
  }
}

if (!/const mimeCards=\[\s*\]/.test(html)) errors.push('O catálogo secreto de Mímicas não está vazio no cliente.');
if (!html.includes('function answerMatches(){return false;}')) errors.push('O validador legado de respostas continua ativo.');
if (!html.includes('function submit(){throw new Error')) errors.push('O envio local legado ainda permite validação no cliente.');
if (!html.includes('async function networkSubmitAnswer(){throw new Error')) errors.push('O envio multiplayer legado ainda permite validação no cliente.');
if (!html.includes('<script src="./atina-server-client.js"></script>')) errors.push('O cliente server-authoritative não está incluído.');
if (!/^\s+- supabase$/m.test(pagesConfig) || !/^\s+- scripts$/m.test(pagesConfig)) errors.push('Pastas privadas/de ferramentas não estão excluídas da publicação GitHub Pages.');
if (!client.includes("'atina_v2_local_submit_answer'")) errors.push('A RPC local de validação do servidor não está ligada.');
if (!client.includes("'atina_v2_submit_room_answer'")) errors.push('A RPC multiplayer de validação do servidor não está ligada.');
if (!client.includes("'atina_v2_submit_team_proposal'")) errors.push('A proposta de equipa segura não está ligada.');
if (!client.includes("'atina_v2_resolve_mime_round'")) errors.push('A resolução de Mímicas no servidor não está ligada.');


const localRpcs = [
  'atina_v2_start_local_game', 'atina_v2_local_game_state',
  'atina_v2_local_reveal_clue', 'atina_v2_local_submit_answer',
  'atina_v2_local_pass_challenge', 'atina_v2_local_next_challenge'
];
for (const rpc of localRpcs) {
  if (!localCompatibility.includes('function public.' + rpc + '(')) errors.push('RPC local v2 em falta: ' + rpc + '.');
  if (!client.includes("'" + rpc + "'")) errors.push('Cliente local não chama ' + rpc + '.');
}
const networkRpcs = [
  'atina_v2_create_room', 'atina_v2_join_room', 'atina_v2_leave_room',
  'atina_v2_room_state', 'atina_v2_set_room_ready', 'atina_v2_set_room_team',
  'atina_v2_start_room', 'atina_v2_start_room_challenges',
  'atina_v2_reveal_room_clue', 'atina_v2_submit_room_answer',
  'atina_v2_pass_room_challenge', 'atina_v2_next_room_challenge',
  'atina_v2_submit_team_proposal', 'atina_v2_vote_team_proposal',
  'atina_v2_start_mime_round', 'atina_v2_get_mime_secret',
  'atina_v2_publish_game_state', 'atina_v2_resolve_mime_round',
  'atina_v2_finish_mime_room', 'atina_v2_request_timeout'
];
for (const rpc of networkRpcs) {
  if (!multiplayerCompatibility.includes('function public.' + rpc + '(')) errors.push('RPC multiplayer v2 em falta: ' + rpc + '.');
  if (!html.includes("'" + rpc + "'") && !client.includes("'" + rpc + "'")) errors.push('Frontend não chama ' + rpc + '.');
}
if (!multiplayerCompatibility.includes('private.atina_mime_cards')) errors.push('A camada v2 não reutiliza o catálogo existente de Mímicas.');
if (/insert\s+into\s+private\.atina_mime_cards/i.test(multiplayerCompatibility)) errors.push('A migração v2 tenta voltar a inserir cartas de Mímicas.');
if (multiplayerCompatibility.includes('private.atina_v2_mime_cards')) errors.push('A migração v2 referencia uma tabela de cartas inexistente.');
if (multiplayerCompatibility.includes('private.atina_v2_challenges')) errors.push('A migração v2 deve reutilizar private.atina_challenges.');
if (/create\s+or\s+replace\s+function\s+public\.atina_(?!v2_)(?:create_room|join_room|leave_room|room_state|set_room_ready|set_room_team|start_room|start_room_challenges|reveal_room_clue|submit_room_answer|pass_room_challenge|next_room_challenge|submit_team_proposal|vote_team_proposal|start_mime_round|get_mime_secret|publish_game_state|resolve_mime_round|finish_mime_room|request_timeout)\b/i.test(multiplayerCompatibility)) {
  errors.push('A migração v2 redefine uma RPC legada em vez de usar o namespace v2.');
}

if (errors.length) {
  console.error(errors.join('\n'));
  process.exit(1);
}
console.log('Cliente seguro válido: JavaScript sintaticamente correto; 802 slots/753 desafios sem pistas, respostas ou alternativas; Mímicas sem palavras secretas no browser; submissões encaminhadas para RPCs do servidor.');
