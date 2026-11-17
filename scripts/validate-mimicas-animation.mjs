#!/usr/bin/env node
import { readFileSync } from 'node:fs';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const forbidden = [
  'data-category="Mímicas"',
  'id="mimicaGame"',
  'id="networkStartMimicas"',
  'function networkRenderMimeState(',
  'function networkStartMimicas(',
  'function mimeStartGame(',
  'atina_v2_start_mime_round'
];
const found = forbidden.filter((marker) => html.includes(marker));
if (found.length) throw new Error('O jogo Mímicas ainda está presente: ' + found.join(', '));

console.log('Mímicas: interface local e online removida; os restantes modos mantêm-se.');
