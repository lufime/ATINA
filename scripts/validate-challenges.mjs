#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const html = readFileSync(resolve(root, 'index.html'), 'utf8');
const match = html.match(/const games\s*=\s*(\[[\s\S]*?\]);\s*\nconst \$\s*=/);

if (!match) {
  console.error('ERRO: não foi possível localizar o array games em index.html.');
  process.exit(1);
}

let games;
try {
  // O bloco é um literal de dados do próprio jogo; não executa o restante da página.
  games = vm.runInNewContext(`(${match[1]})`, Object.create(null), { timeout: 1000 });
} catch (error) {
  console.error('ERRO: o banco de desafios não é um array JavaScript válido.');
  console.error(error.message);
  process.exit(1);
}

const normalize = (value) => String(value ?? '')
  .toLocaleLowerCase('pt-PT')
  .normalize('NFD')
  .replace(/[\\u0300-\\u036f]/g, '')
  .replace(/[^a-z0-9 ]/g, '')
  .trim();

const errors = [];
const warnings = [];
const counts = new Map();
const seenAnswers = new Map();
let imageCount = 0;

games.forEach((challenge, index) => {
  const label = `Desafio #${index + 1}`;
  if (!Array.isArray(challenge) || challenge.length < 5) {
    errors.push(`${label}: estrutura incompleta.`);
    return;
  }

  const [category, emoji, clues, answer, accepted, imageUrl] = challenge;
  if (typeof category !== 'string' || !category.trim()) errors.push(`${label}: modalidade em falta.`);
  if (typeof emoji !== 'string' || !emoji.trim()) errors.push(`${label}: ícone em falta.`);
  if (!Array.isArray(clues) || clues.length !== (category === 'Imagem misteriosa' ? 6 : 5)) {
    errors.push(`${label}: número de pistas inválido.`);
  } else if (clues.some((clue) => typeof clue !== 'string' || !clue.trim())) {
    errors.push(`${label}: existe uma pista vazia ou inválida.`);
  }
  if (typeof answer !== 'string' || !answer.trim()) errors.push(`${label}: resposta principal em falta.`);
  if (!Array.isArray(accepted) || accepted.length === 0 || accepted.some((item) => typeof item !== 'string' || !item.trim())) {
    errors.push(`${label}: lista de respostas aceites inválida.`);
  } else if (answer && !accepted.some((item) => normalize(item) === normalize(answer))) {
    warnings.push(`${label}: a resposta principal não aparece na lista de respostas aceites.`);
  }

  counts.set(category, (counts.get(category) ?? 0) + 1);
  if (category === 'Imagem misteriosa') {
    imageCount += 1;
    if (typeof imageUrl !== 'string' || !/^https:\/\//.test(imageUrl)) {
      warnings.push(`${label}: imagem sem URL HTTPS válida.`);
    }
  }

  const key = `${category}|${normalize(answer)}`;
  if (answer && seenAnswers.has(key)) {
    warnings.push(`Resposta repetida em "${category}": "${answer}" (desafios #${seenAnswers.get(key)} e #${index + 1}).`);
  } else if (answer) {
    seenAnswers.set(key, index + 1);
  }
});

const categories = [...counts.entries()].sort(([a], [b]) => a.localeCompare(b, 'pt-PT'));
const total = games.length;
const targetPerCategory = 50;
const target = categories.length * targetPerCategory;
const duplicates = warnings.filter((warning) => warning.startsWith('Resposta repetida')).length;

console.log('ATINA — auditoria do banco de desafios');
console.log(`Total: ${total} desafios · ${categories.length} modalidades · ${imageCount} desafios com imagem`);
console.log(`Meta: ${target} desafios (${targetPerCategory} por modalidade) · faltam ${Math.max(0, target - total)}`);
for (const [category, count] of categories) {
  console.log(`- ${category}: ${count}/${targetPerCategory}`);
}
if (duplicates) console.warn(`\nAvisos: ${duplicates} respostas principais repetidas na mesma modalidade.`);
for (const warning of warnings) console.warn(`AVISO: ${warning}`);
for (const error of errors) console.error(`ERRO: ${error}`);

if (errors.length || (process.argv.includes('--strict') && warnings.length)) {
  process.exitCode = 1;
} else {
  console.log('\nEstrutura do banco: válida.');
  if (warnings.length) console.log('Há avisos editoriais a resolver antes de declarar o conteúdo sem duplicações.');
}
