#!/usr/bin/env node
import { readFileSync, realpathSync } from 'node:fs';
import { resolve, isAbsolute, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const sourceArg = process.env.ATINA_PRIVATE_SOURCE;
if (!sourceArg || !isAbsolute(sourceArg)) {
  console.error('Define ATINA_PRIVATE_SOURCE com o caminho absoluto para uma cópia privada do index.html original, guardada fora do repositório.');
  process.exit(2);
}
const realRoot = realpathSync(root);
const sourcePath = realpathSync(sourceArg);
if (sourcePath === realRoot || sourcePath.startsWith(realRoot + sep)) {
  console.error('Por segurança, a fonte privada tem de ficar fora do repositório (incluindo caminhos com symlinks).');
  process.exit(2);
}
const html = readFileSync(sourcePath, 'utf8');
// A declaração é seguida por um comentário que preserva os índices originais.
// Não acoplar a extração à declaração seguinte (que pode mudar sem alterar os dados).
const match = html.match(/const games\s*=\s*(\[[\s\S]*?\]);\s*\n\/\/ Preserva os índices originais/);

if (!match) {
  console.error('ERRO: não foi possível localizar o array games em index.html.');
  process.exit(1);
}

let games;
try {
  games = vm.runInNewContext(`(${match[1]})`, Object.create(null), { timeout: 1000 });
} catch (error) {
  console.error('ERRO: o banco de desafios não é um array JavaScript válido.');
  console.error(error.message);
  process.exit(1);
}

const normalize = (value) => String(value ?? '')
  .toLocaleLowerCase('pt-PT')
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .replace(/[^a-z0-9 ]/g, '')
  .trim();

const errors = [];
const warnings = [];
const counts = new Map();
const seenAnswers = new Map();
let imageCount = 0;

games.forEach((challenge, index) => {
  // O catálogo mantém posições históricas vazias (null) para preservar IDs.
  if (challenge === null || challenge === undefined) return;
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

  if (Array.isArray(clues)) {
    const answerText = normalize(answer);
    clues.forEach((clue, clueIndex) => {
      const clueText = normalize(clue);
      const explicitReveal = /^(sou|somos|a resposta e|a resposta correta e|o seu nome e|a palavra e|chamo me|chama se)\b/.test(clueText)
        && answerText.length > 2 && clueText.includes(answerText);
      const fillerReveal = /pista adicional sobre/.test(clueText);
      if (explicitReveal || fillerReveal) {
        errors.push(`${label}, pista #${clueIndex + 1}: formulação que revela diretamente a resposta ou usa texto genérico.`);
      }
    });
  }

  counts.set(category, (counts.get(category) ?? 0) + 1);
  if (category === 'Imagem misteriosa') {
    imageCount += 1;
    if (typeof imageUrl !== 'string' || !/^https:\/\//.test(imageUrl)) {
      warnings.push(`${label}: imagem sem URL HTTPS válida.`);
    }
  }

  // Nomes de suspeitos repetem-se intencionalmente em casos distintos de Detetive.
  const key = `${category}|${normalize(answer)}`;
  if (category !== 'Detetive' && answer && seenAnswers.has(key)) {
    warnings.push(`Resposta repetida em "${category}": "${answer}" (desafios #${seenAnswers.get(key)} e #${index + 1}).`);
  } else if (category !== 'Detetive' && answer) {
    seenAnswers.set(key, index + 1);
  }
});

const categories = [...counts.entries()].sort(([a], [b]) => a.localeCompare(b, 'pt-PT'));
const total = games.filter(Array.isArray).length;
const targetPerCategory = 50;
const target = categories.length * targetPerCategory;
const percent = target ? Math.round((total / target) * 100) : 0;
const duplicates = warnings.filter((warning) => warning.startsWith('Resposta repetida')).length;

console.log('ATINA — auditoria do banco de desafios');
console.log(`Total: ${total} desafios · ${categories.length} modalidades · ${imageCount} desafios com imagem`);
console.log(`Meta: ${target} desafios (${targetPerCategory} por modalidade) · faltam ${Math.max(0, target - total)} · ${percent}% concluído`);
for (const [category, count] of categories) console.log(`- ${category}: ${count}/${targetPerCategory}`);
if (duplicates) console.warn(`\nAvisos: ${duplicates} respostas principais repetidas na mesma modalidade.`);
for (const warning of warnings) console.warn(`AVISO: ${warning}`);
for (const error of errors) console.error(`ERRO: ${error}`);

if (errors.length || (process.argv.includes('--strict') && warnings.length)) {
  process.exitCode = 1;
} else {
  console.log('\nEstrutura do banco: válida.');
  if (warnings.length) console.log('Há avisos editoriais a resolver antes de declarar o conteúdo sem duplicações.');
}
