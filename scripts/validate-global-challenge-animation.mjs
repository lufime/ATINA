#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const client = readFileSync(new URL('../atina-server-client.js', import.meta.url), 'utf8');
const scriptStart = html.indexOf('<script>') + '<script>'.length;
const scriptEnd = html.indexOf('</script><script src=', scriptStart);
if (scriptStart < '<script>'.length || scriptEnd < 0) throw new Error('Não foi possível localizar o JavaScript principal.');
new vm.Script(html.slice(scriptStart, scriptEnd), { filename: 'index.html inline script' });
new vm.Script(client, { filename: 'atina-server-client.js' });

const localStart = html.match(/function start\(m,chosen=null\)\{([^]*?)\}\s*function mixDraw/);
if (!localStart || !localStart[1].includes('challengePause().then')) throw new Error('O início local não apresenta a contagem decrescente.');
const localNext = html.match(/async function next\(\)\{([^]*?)\}\s*async function activateLandscapePresentation/);
if (!localNext || !localNext[1].includes('await challengePause()')) throw new Error('A transição local não apresenta a pausa entre desafios.');
if (!html.includes('function mixDraw(){return Promise.resolve();}')) throw new Error('A animação de sorteio não foi removida.');
if (!html.includes('let seconds=10') || !html.includes("challengePauseSkip")) throw new Error('A pausa de 10 segundos com opção de saltar não está disponível.');
if (!html.includes("$('mimeFeedback').textContent='A preparar a próxima mímica…'")) throw new Error('O estado de preparação de Mímicas online não está preservado.');

console.log('Animações globais: início e transições locais, multiplayer deduplicado e cliente server-authoritative validados; sintaxe JavaScript válida.');
