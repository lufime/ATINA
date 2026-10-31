#!/usr/bin/env node
/**
 * Gera uma carga SQL PRIVADA a partir do index.html original.
 *
 * IMPORTANTE:
 * - O ficheiro de saída contém respostas e alternativas. Nunca o adicionar ao Git.
 * - Executar numa máquina de confiança e guardar fora do repositório, com permissões 0600.
 * - A carga destina-se apenas a uma base Supabase de desenvolvimento.
 *
 * Uso:
 *   node scripts/generate-private-challenge-seed.mjs /caminho/absoluto/atina-private-seed.sql
 *
 * A fonte é index.html; o catálogo público é usado para validar IDs e pistas.
 */
import { readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { resolve, relative, isAbsolute, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const checkOnly = process.argv[2] === '--check';
const outputArg = checkOnly ? null : process.argv[2];
let outputPath = null;
if (!checkOnly) {
  if (!outputArg || !isAbsolute(outputArg)) {
    console.error('Indica um caminho absoluto fora do repositório para o SQL privado.');
    process.exit(2);
  }
  outputPath = resolve(outputArg);
  const rel = relative(repoRoot, outputPath);
  if (rel === '' || (!rel.startsWith('..') && !isAbsolute(rel))) {
    console.error('Por segurança, o ficheiro SQL privado tem de ficar fora do repositório.');
    process.exit(2);
  }
}

const source = readFileSync(resolve(repoRoot, 'index.html'), 'utf8');
const publicCatalog = JSON.parse(readFileSync(resolve(repoRoot, 'supabase/proposals/public-challenges.json'), 'utf8'));
const marker = 'const games=[';
const markerAt = source.indexOf(marker);
if (markerAt < 0) throw new Error('Não foi encontrada a declaração original const games=[.');
const arrayStart = source.indexOf('[', markerAt);
let depth = 0, quote = null, escaped = false, arrayEnd = -1;
for (let i = arrayStart; i < source.length; i++) {
  const ch = source[i];
  if (quote) {
    if (escaped) escaped = false;
    else if (ch === '\\') escaped = true;
    else if (ch === quote) quote = null;
    continue;
  }
  if (ch === '"' || ch === "'" || ch === '`') { quote = ch; continue; }
  if (ch === '[') depth++;
  else if (ch === ']') {
    depth--;
    if (depth === 0) { arrayEnd = i; break; }
  }
}
if (arrayEnd < 0) throw new Error('Não foi possível delimitar o array games.');
const games = JSON.parse(source.slice(arrayStart, arrayEnd + 1));
const publicById = new Map(publicCatalog.challenges.map(c => [c.id, c]));
const norm = s => String(s ?? '').toLocaleLowerCase('pt-PT').normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9 ]/g, '').trim();

function difficultyScore(index) {
  const g = games[index], clues = (g?.[2] || []).map(x => String(x));
  const answer = norm(g?.[3] || ''), category = String(g?.[0] || '');
  const all = clues.join(' ').toLocaleLowerCase('pt-PT');
  const early = clues.slice(0, 2).join(' ').toLocaleLowerCase('pt-PT');
  const familiar = new Set(['agua','paz','chave','lisboa','portugal','sol','lua','arvore','fogo','gelo','coracao','amor','amizade','livro','telefone','computador','bicicleta','futebol','guitarra','pizza','casa','cao','gato','elefante','oceano','montanha','rio','flor','mae','pai','escola','medico','professor','bombeiro','cozinheiro','policia','aviao','comboio','carro','relogio','dinheiro','musica','cinema','teatro','bola','arco iris','chuva','neve']);
  const specialist = /\b(nobel|quântico|relatividade|fotossíntese|mitocôndria|constituição|dinastia|teorema|parlamento|revolução|império|átomo|equação|arqueológ|geológ|astronóm|biológ|matemátic|literári|mitológ|termodinâm|metabol|sintaxe|jurisprud|isótop|fotão|algoritm|proporção|inércia|soberania|feudal|renascimento|barroco)\w*/i.test(all);
  const inference = /\b(ao contrário|apesar de|no entanto|deduz|conclui|contradição|inconsist|sequência|padrão|hipótese|vestígio|prova|testemunh|álibi|registo|evidência|não pode|apenas um|exatamente|qual é a lógica)\w*/i.test(all);
  const abstract = /\b(liberdade|democracia|justiça|consciência|identidade|paradoxo|metáfora|ética|existência|memória|relatividade|infinito|probabilidade)\w*/i.test(all);
  const directEarly = /\b(chamo-me|sou a capital|sou o país|sou um animal|sou uma cidade|o meu nome é|fui inventad[oa] por|nasci em|localizo-me em)\b/i.test(early);
  const longEarly = clues.slice(0, 2).filter(x => x.length > 110).length;
  let score = 0;
  if (familiar.has(answer)) score -= 3;
  else if (answer.split(' ').length >= 2 || answer.length >= 16) score += 1.5;
  if (specialist) score += 2.5;
  if (inference) score += 2.5;
  if (abstract) score += 1.5;
  if (directEarly) score -= 2.5;
  score += longEarly * .7;
  if (category === 'Lógica e números' || category === 'Ilusões e truques mentais') score += 2;
  if (category === 'Detetive') score += 1.5;
  if (category === 'Imagem misteriosa') score += 1;
  if (clues.length < 5) score += .5;
  const calibration = {'Onde estou?':1.5,'O que sou?':1.5,'Palavras escondidas':1.5,'Música e sons':1.5,'Ilusões e truques mentais':-2.5,'Detetive':-2};
  score += calibration[category] || 0;
  return score;
}

const groups = new Map();
games.forEach((g, i) => {
  if (!g) return;
  const list = groups.get(g[0]) || [];
  list.push(i);
  groups.set(g[0], list);
});
const difficultyById = new Map();
for (const [category, indices] of groups) {
  indices.sort((a, b) => difficultyScore(a) - difficultyScore(b) || a - b);
  const n = indices.length;
  indices.forEach((index, rank) => {
    const percentile = (rank + .5) / n;
    difficultyById.set(index, percentile < .30 ? 'easy' : percentile < .75 ? 'medium' : 'hard');
  });
}

const rows = [];
for (let id = 0; id < games.length; id++) {
  const g = games[id];
  if (!g) continue;
  if (!Array.isArray(g) || g.length < 5 || !Array.isArray(g[2]) || !Array.isArray(g[4])) {
    throw new Error(`Estrutura inesperada no desafio ${id}.`);
  }
  const pub = publicById.get(id);
  if (!pub) throw new Error(`ID ${id} não existe no catálogo público.`);
  if (pub.category !== g[0] || pub.emoji !== g[1] || JSON.stringify(pub.clues) !== JSON.stringify(g[2])) {
    throw new Error(`Os campos públicos do desafio ${id} não coincidem com a fonte original.`);
  }
  if ((pub.image_url || null) !== (g[5] || null)) {
    throw new Error(`A imagem pública do desafio ${id} não coincide com a fonte original.`);
  }
  if (typeof g[3] !== 'string' || !g[3].trim() || !g[4].length) {
    throw new Error(`Resposta ou alternativas em falta no desafio ${id}.`);
  }
  rows.push({
    id, category:g[0], emoji:g[1], clues:g[2], answer:g[3],
    accepted:g[4], image_url:g[5] || null, difficulty:difficultyById.get(id)
  });
}
if (rows.length !== 753 || rows.length !== publicCatalog.challenge_count) {
  throw new Error(`Contagem inesperada: ${rows.length} desafios privados.`);
}

const q = value => value === null ? 'null' : "'" + String(value).replace(/'/g, "''") + "'";
const json = value => q(JSON.stringify(value)) + '::jsonb';
const statements = [
  '-- FICHEIRO PRIVADO: contém respostas ATINA. Não commitar nem partilhar.',
  '-- Executar apenas numa base Supabase de desenvolvimento, após rever as migrations 001 e 004.',
  'begin;',
  "alter table private.atina_challenges add column if not exists difficulty text check (difficulty in ('easy','medium','hard'));",
  'insert into private.atina_challenges (challenge_id, category, emoji, clues, answer, accepted_answers, image_url, difficulty, active)',
  'values'
];
rows.forEach((r, i) => {
  statements.push(`(${r.id}, ${q(r.category)}, ${q(r.emoji)}, ${json(r.clues)}, ${q(r.answer)}, ${json(r.accepted)}, ${q(r.image_url)}, ${q(r.difficulty)}, true)${i === rows.length - 1 ? '' : ','}`);
});
statements.push('on conflict (challenge_id) do update set category=excluded.category, emoji=excluded.emoji, clues=excluded.clues, answer=excluded.answer, accepted_answers=excluded.accepted_answers, image_url=excluded.image_url, difficulty=excluded.difficulty, active=true;');
statements.push('commit;');
if (checkOnly) {
  const counts = rows.reduce((acc, row) => {
    acc[row.difficulty] = (acc[row.difficulty] || 0) + 1;
    return acc;
  }, {});
  console.log(`Verificação OK: ${rows.length} desafios; easy=${counts.easy || 0}, medium=${counts.medium || 0}, hard=${counts.hard || 0}. Nenhum segredo foi exportado.`);
} else {
  writeFileSync(outputPath, statements.join('\n') + '\n', { mode: 0o600, flag: 'wx' });
  chmodSync(outputPath, 0o600);
  console.log(`Gerados ${rows.length} registos privados com dificuldade calculada. SQL guardado fora do repositório: ${outputPath}`);
  console.log('Não executar em produção. Rever e aplicar apenas numa instância de desenvolvimento.');
}
