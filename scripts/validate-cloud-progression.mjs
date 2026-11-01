#!/usr/bin/env node
import { readFileSync } from 'node:fs';

const sql = readFileSync(
  new URL('../supabase/proposals/pseudonym-xp-cloud-progression.sql', import.meta.url),
  'utf8'
);

const required = [
  'create table if not exists private.atina_players',
  'create table if not exists private.atina_xp_events',
  'device_token_hash bytea not null unique',
  'alter table private.atina_players enable row level security',
  'alter table private.atina_xp_events enable row level security',
  'security definer',
  "set search_path = ''",
  'private.atina_v2_local_sessions',
  "extensions.digest(convert_to(p_session_token, 'UTF8'), 'sha256')",
  "v_session.last_result ->> 'outcome' <> 'correct'",
  'constraint atina_xp_events_once_per_challenge',
  'on conflict (player_id, session_id, challenge_position) do nothing',
  'grant execute on function public.atina_progress_register(text, text) to anon',
  'grant execute on function public.atina_progress_claim_local(text, uuid, text, integer) to anon',
  'grant execute on function public.atina_progress_leaderboard(integer) to anon'
];

for (const token of required) {
  if (!sql.includes(token)) {
    throw new Error('Falta salvaguarda de progressão: ' + token);
  }
}

const claimMatch = sql.match(
  /create or replace function public\.atina_progress_claim_local\(([\s\S]*?)\)\s*returns jsonb/i
);
if (!claimMatch) throw new Error('RPC de atribuição de XP não encontrada.');

const claimSignature = claimMatch[1].replace(/\s+/g, ' ').trim();
if (claimSignature !==
    'p_device_token text, p_session_id uuid, p_session_token text, p_position integer') {
  throw new Error('Assinatura inesperada da RPC de atribuição de XP.');
}

if (/grant\s+execute\s+on\s+function\s+public\.atina_progress_[^(]+\([^;]+\)\s+to\s+public/i.test(sql)) {
  throw new Error('Uma RPC de progressão não pode ser executável por PUBLIC.');
}
if (/p_xp\s+integer|p_points\s+integer/i.test(sql)) {
  throw new Error('O cliente não pode indicar diretamente a quantidade de XP.');
}
if (/revoke\s+all\s+on\s+schema\s+private/i.test(sql)) {
  throw new Error('Não revogar globalmente o acesso ao schema private.');
}

const functionNames = [
  'atina_progress_register',
  'atina_progress_claim_local',
  'atina_progress_leaderboard'
];
for (const name of functionNames) {
  const occurrences = sql.match(new RegExp('create or replace function public\\.' + name + '\\b', 'gi')) ?? [];
  if (occurrences.length !== 1) {
    throw new Error('Esperada exatamente uma definição para ' + name + '.');
  }
}

console.log(
  'Proposta validada estaticamente: pseudónimo sem Auth, tokens em hash, RLS, ' +
  'XP confirmado pelo servidor, idempotência, RPCs restritas e sem revogação global do schema.'
);
