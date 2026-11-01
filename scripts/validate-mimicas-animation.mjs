#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const scriptStart = html.indexOf('<script>') + '<script>'.length;
const scriptEnd = html.indexOf('</script><script src=', scriptStart);
if (scriptStart < '<script>'.length || scriptEnd < 0) throw new Error('Não foi possível localizar o JavaScript principal.');
new vm.Script(html.slice(scriptStart, scriptEnd), { filename: 'index.html inline script' });

const body = (name, async = false) => {
  const start = html.indexOf(`${async ? 'async ' : ''}function ${name}(`);
  if (start < 0) throw new Error(`Função em falta: ${name}`);
  const candidates = [html.indexOf('\nfunction ', start + 1), html.indexOf('\nasync function ', start + 1)].filter((n) => n >= 0);
  return html.slice(start, candidates.length ? Math.min(...candidates) : html.length);
};

const reveal = body('mimeRevealWord');
if (!reveal.includes("classList.remove('draw-result')") || !reveal.includes("classList.add('draw-result')")) throw new Error('A função comum não reinicia a animação de revelação.');
if (!html.includes('#mimeWord.draw-result')) throw new Error('O CSS da animação de revelação está em falta.');
if (!body('mimeShowNext').includes('mimeRevealWord(card[0])')) throw new Error('O modo local não usa a função comum de revelação.');

const onlineRender = body('networkRenderMimeState', true);
if (onlineRender.includes('mimeStop()')) throw new Error('A renderização online está a cancelar a animação em cada atualização de estado.');
if (!onlineRender.includes('mimeRevealWord(')) throw new Error('O modo online não ativa a animação ao revelar a palavra.');
if (!body('networkDrawClock').includes('mimeRevealWord(')) throw new Error('O relógio online não ativa a revelação após o sorteio.');
if (!body('networkStartMimicas', true).includes('mimeStop()')) throw new Error('A limpeza do modo local deve ocorrer ao iniciar uma partida online.');

console.log('Mímicas: sintaxe JavaScript válida; animação local e online ligada; renderização online não cancela a animação.');
