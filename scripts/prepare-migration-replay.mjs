#!/usr/bin/env node
import { readdirSync, renameSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = fileURLToPath(new URL('../supabase/migrations/', import.meta.url));
const files = readdirSync(directory).filter(name => /^\d{14}_.+\.sql$/.test(name)).sort();
const groups = new Map();
for (const name of files) {
  const version = name.slice(0, 14);
  if (!groups.has(version)) groups.set(version, []);
  groups.get(version).push(name);
}
const used = new Set(groups.keys());
const renames = [];
for (const [version, duplicates] of groups) {
  if (duplicates.length < 2) continue;
  for (const name of duplicates.slice(1)) {
    let candidate = BigInt(version) + 1n;
    while (used.has(candidate.toString().padStart(14, '0'))) candidate++;
    const nextVersion = candidate.toString().padStart(14, '0');
    const nextName = nextVersion + name.slice(14);
    if (readdirSync(directory).includes(nextName)) {
      throw new Error('ID temporário já existe: ' + nextName);
    }
    renameSync(join(directory, name), join(directory, nextName));
    used.add(nextVersion);
    renames.push({from:name,to:nextName});
  }
}
const finalFiles = readdirSync(directory).filter(name => /^\d{14}_.+\.sql$/.test(name));
const finalVersions = finalFiles.map(name => name.slice(0,14));
if (new Set(finalVersions).size !== finalVersions.length) {
  throw new Error('Continuam a existir versões de migration duplicadas no replay local.');
}
for (const item of renames) console.log('ID temporário de replay: ' + item.from + ' -> ' + item.to);
console.log('Replay local preparado: ' + finalFiles.length + ' migrations com IDs únicos. Os nomes originais do repositório não são alterados.');
