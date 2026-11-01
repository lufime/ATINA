#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const inline = html.match(/<script>([\\s\\S]*?)<\\/script><script src=/);
if (!inline) throw new Error('Não foi possível localizar o JavaScript principal.');
new vm.Script(inline[1], { filename: 'index.html inline script' });

const functionBody = (name) => {
  const start = html.indexOf(`function ${name}(`);
  if (start < 0) throw new Error(`Função em falta: ${name}`);
  const next = html.indexOf('\\nfunction ', start + 1);
  return html.slice(start, next < 0 ? html.length : next);
};
const asyncFunctionBody = (name) => {
  const start = html.indexOf(`async function ${name}(`);
  if (start < 0) throw new Error(`Função em falta: ${name}`);
  const next = html.indexOf('\\nasync function ', start + 1);
  const nextSync = html.indexOf('\\nfunction ', start + 1);
  const ends = [next, nextSync].filter((n) => n >= 0);
  return html.slice(start, ends.length ? Math.min(...ends) : html.length);
};

const reveal = functionBody('mimeRevealWord');
if (!reveal.includes("classList.remove('draw-result')") || !reveal.includes("classList.add('draw-result')")) {
  throw new Error('A função comum não reinicia a animação de revelação.');
}
if (!html.includes('#mimeWord.draw-result')) throw new Error('O CSS da animação de revelação está em falta.');

const local = functionBody('mimeShowNext');
if (!local.includes('mimeRevealWord(card[0])')) throw new Error('O modo local não usa a função comum de revelação.');

const onlineRender = asyncFunctionBody('networkRenderMimeState');
if (onlineRender.includes('mimeStop()')) throw new Error('A renderização online está a cancelar a animação em cada atualização de estado.');
if (!onlineRender.includes('mimeRevealWord(')) throw new Error('O modo online não ativa a animação ao revelar a palavra.');

const onlineClock = functionBody('networkDrawClock');
if (!onlineClock.includes('mimeRevealWord(')) throw new Error('O relógio online não ativa a revelação após o sorteio.');
const onlineStart = asyncFunctionBody('networkStartMimicas');
if (!onlineStart.includes('mimeStop()')) throw new Error('A limpeza do modo local deve ocorrer ao iniciar uma partida online.');

console.log('Mímicas: sintaxe JavaScript válida; animação local e online ligada; renderização online não cancela a animação.');
