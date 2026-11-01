#!/usr/bin/env node
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../supabase/migrations/20261101190000_atina_v2_pseudonym_cloud_progression.sql', import.meta.url), 'utf8');
const checks = [
  ['private player table', /create table private\.atina_v2_players/i],
  ['hashed player token', /token_hash bytea not null unique/i],
  ['no Auth dependency', !/auth\.users|auth\.uid\(|auth\.signUp|auth\.signIn/i.test(sql)],
  ['server-side answer verification', /last_result\s*->>\s*'outcome'\s*<>\s*'correct'/i],
  ['no client-supplied XP', !/p_xp|p_points|p_score/i.test(sql)],
  ['idempotent event key', /unique \(player_id, session_id, position\)/i],
  ['daily reward once', /rewarded_date is distinct from v_today/i],
  ['private RLS', /enable row level security/i.test(sql) && /revoke all on private\.atina_v2_players from public, anon, authenticated/i.test(sql)],
  ['restricted RPC grants', /revoke all on function public\.atina_v2_player_profile\(text, text\) from public/i.test(sql) && /grant execute on function public\.atina_v2_record_local_progress\(uuid, text, text\) to anon, authenticated/i.test(sql)],
  ['fixed search_path', (sql.match(/set search_path = ''/g) || []).length >= 2],
];
let failed = false;
for (const [name, pass] of checks) {
  console.log((pass ? 'PASS ' : 'FAIL ') + name);
  if (!pass) failed = true;
}
if (failed) process.exit(1);
console.log('Proposta validada estaticamente. Não substitui testes SQL transacionais nem revisão antes da migração.');
