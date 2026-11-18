#!/usr/bin/env node
import { readFileSync, readdirSync, renameSync, writeFileSync } from 'node:fs';
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

// The historical leaderboard migration references an optional legacy V2 table.
// In a clean replay that table is absent, although it may exist in upgraded
// installations. Patch only this disposable CI checkout; never rewrite the
// committed migration or any remote database.
const leaderboardMigration = '20261116232227_atina_v2_bot_simulated_competition.sql';
const leaderboardPath = join(directory, leaderboardMigration);
let leaderboardSql = readFileSync(leaderboardPath, 'utf8');
const leaderboardPattern = /create or replace function public\.atina_progress_leaderboard\([\s\S]*?\$function\$;/i;
const existingLeaderboard = leaderboardSql.match(leaderboardPattern);
if (!existingLeaderboard) {
  throw new Error('Não foi possível localizar a definição esperada de atina_progress_leaderboard em ' + leaderboardMigration);
}
const safeLeaderboard = `create or replace function public.atina_progress_leaderboard(p_limit integer default 50)
returns table(nickname text, xp integer, level integer, challenges integer)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if to_regclass('private.atina_v2_players') is not null then
    return query
      select all_players.nickname, all_players.xp, all_players.level, all_players.challenges
        from (
          select p.nickname, p.total_xp as xp,
                 private.atina_level_for_xp(p.total_xp) as level,
                 p.total_challenges as challenges, p.created_at
            from private.atina_players p
          union all
          select p.nickname, p.xp,
                 private.atina_level_for_xp(p.xp),
                 p.total_challenges, p.created_at
            from private.atina_v2_players p
        ) all_players
       order by all_players.xp desc, all_players.challenges desc, all_players.created_at asc
       limit least(greatest(coalesce(p_limit,50),1),100);
  else
    return query
      select p.nickname, p.total_xp,
             private.atina_level_for_xp(p.total_xp),
             p.total_challenges
        from private.atina_players p
       order by p.total_xp desc, p.total_challenges desc, p.created_at asc
       limit least(greatest(coalesce(p_limit,50),1),100);
  end if;
end;
$function$;`;
leaderboardSql = leaderboardSql.replace(leaderboardPattern, safeLeaderboard);
writeFileSync(leaderboardPath, leaderboardSql);
console.log('Compatibilidade local: leaderboard ignora a tabela V2 opcional quando ausente; migration original preservada.');

// pg_cron is not enabled in the disposable Supabase stack by default.
// Strip cron.schedule/cron.unschedule statements from every temporary migration
// copy. Keep all committed migrations untouched; hosted scheduling is verified
// separately. A line scanner avoids fragile multiline SQL regular expressions.
let cronStatementsRemoved = 0;
for (const name of readdirSync(directory).filter(name => /^\d{14}_.+\.sql$/.test(name))) {
  const path = join(directory, name);
  const lines = readFileSync(path, 'utf8').split(/\r?\n/);
  const output = [];
  let skippingCron = false;
  for (const line of lines) {
    if (!skippingCron && /cron\.(?:schedule|unschedule)\s*\(/i.test(line)) {
      output.push('-- pg_cron statement omitted only in disposable migration replay.');
      cronStatementsRemoved++;
      skippingCron = !/;\s*(?:--.*)?$/.test(line);
      continue;
    }
    if (skippingCron) {
      if (/;\s*(?:--.*)?$/.test(line)) skippingCron = false;
      continue;
    }
    output.push(line);
  }
  if (skippingCron) {
    throw new Error('Instrução pg_cron sem terminador em ' + name);
  }
  if (output.length !== lines.length) {
    writeFileSync(path, output.join('\n'));
    console.log('Compatibilidade local: instruções pg_cron omitidas em ' + name + '.');
  }
}
if (cronStatementsRemoved === 0) {
  throw new Error('Não foi encontrada nenhuma instrução pg_cron para omitir no replay local.');
}
console.log('Compatibilidade local: ' + cronStatementsRemoved + ' instrução(ões) pg_cron omitida(s); migrations originais preservadas.');


const finalFiles = readdirSync(directory).filter(name => /^\d{14}_.+\.sql$/.test(name));
const finalVersions = finalFiles.map(name => name.slice(0,14));
if (new Set(finalVersions).size !== finalVersions.length) {
  throw new Error('Continuam a existir versões de migration duplicadas no replay local.');
}
for (const item of renames) console.log('ID temporário de replay: ' + item.from + ' -> ' + item.to);
console.log('Replay local preparado: ' + finalFiles.length + ' migrations com IDs únicos. Os nomes originais do repositório não são alterados.');
