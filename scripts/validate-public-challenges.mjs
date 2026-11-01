import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const catalog = JSON.parse(readFileSync(resolve('supabase/proposals/public-challenges.json'), 'utf8'));
const errors = [];
if (catalog.challenge_count !== catalog.challenges.length) errors.push('Contagem declarada diferente da contagem real.');
if (catalog.challenges.length !== 753) errors.push(`Esperados 753 desafios válidos; encontrados ${catalog.challenges.length}.`);
const ids = new Set();
for (const item of catalog.challenges) {
  if (!Number.isInteger(item.id) || ids.has(item.id)) errors.push(`ID inválido ou duplicado: ${item.id}`);
  ids.add(item.id);
  if (!item.category || !item.emoji || !Array.isArray(item.clues)) errors.push(`Desafio ${item.id}: campos públicos incompletos.`);
  const expected = item.category === 'Imagem misteriosa' ? 6 : 5;
  if (item.clues?.length !== expected || item.clues.some(x => typeof x !== 'string' || !x.trim())) errors.push(`Desafio ${item.id}: pistas inválidas.`);
  for (const forbidden of ['answer', 'accepted', 'accepted_answers', 'solution', 'correct']) {
    if (Object.hasOwn(item, forbidden)) errors.push(`Desafio ${item.id}: campo secreto exposto (${forbidden}).`);
  }
}
if (errors.length) { console.error(errors.join('\\n')); process.exit(1); }
console.log(`Catálogo público válido: ${catalog.challenges.length} desafios; sem campos de resposta.`);
