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

const localNext = html.match(/async function next\(\)\{([^]*?)\}\s*async function activateLandscapePresentation/);
if (!localNext || !localNext[1].includes('await mixDraw()')) throw new Error('A transição local não anima todos os desafios.');
const localStart = html.match(/function start\(m,chosen=null\)\{([^]*?)\}\s*async function mixDraw/);
if (!localStart || !localStart[1].includes('mixDraw().then')) throw new Error('O início local não apresenta a animação.');

const drawStart = html.indexOf('async function mixDraw(finalGameOverride=null,finalDifficultyOverride=null)');
if (drawStart < 0 || !html.slice(drawStart, drawStart + 14000).includes('finalGameOverride||games[finalIndex]')) throw new Error('A animação não suporta desafios fornecidos pelo servidor.');
if (!html.includes("let networkAnimatedChallengeKey=''")) throw new Error('Falta a chave de deduplicação da animação online.');
const networkRender = html.match(/function networkRenderGameState\(\)\{([^]*?)\}\s*document\.addEventListener\('visibilitychange'/);
if (!networkRender || !networkRender[1].includes('animationKey!==networkAnimatedChallengeKey') || !networkRender[1].includes('mixDraw()')) throw new Error('O multiplayer não anima uma vez por novo desafio.');

const applyState = client.match(/function atinaServerApplyState\(state, announce = false\)\s*\{([^]*?)\n\}\nasync function atinaServerRefresh/);
if (!applyState || !applyState[1].includes('mixDraw(finalGame, state.difficulty') || !applyState[1].includes('if (sameChallenge)')) throw new Error('O cliente server-authoritative não anima apenas em mudanças de desafio.');
if (!applyState[1].includes('mixDraw(finalGame, state.difficulty || difficultyMode).finally')) throw new Error('O relógio do desafio não aguarda a animação inicial/transição.');

console.log('Animações globais: início e transições locais, multiplayer deduplicado e cliente server-authoritative validados; sintaxe JavaScript válida.');
