#!/usr/bin/env node
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../supabase/proposals/pseudonym-xp-cloud-progression.sql', import.meta.url), 'utf8');
const required = [
  'private.atina_players',
  'private.atina_xp_events',
  'device_token_hash bytea not null unique',
  'alter table private.atina_players enable row level security',
  'alter table private.atina_xp_events enable row level security',
  'security definer',
  'set search_path = \'\'',
  'private.atina_v2_local_sessions',
  "last_result ->> 'outcome' = 'correct'",
  'unique (player_id, session_id, challenge_position)',
  'on conflict (player_id, session_id, challenge_position) do nothing',
  'grant execute on function public.atina_progress_register(text, text) to anon',
  'grant execute on function public.atina_progress_claim_local(text, uuid, integer) to anon',
  'grant execute on function public.atina_progress_leaderboard(integer) to anon'
];
for (const token of required) {
  if (!sql.includes(token)) throw new Error('Falta salvaguarda de progressão: ' + token);
}
if (/grant\s+execute\s+on\s+function\s+public\.atina_progress_[^(]+\([^;]+\)\s+to\s+public/i.test(sql)) {
  throw new Error('Uma RPC de progressão não pode ser executável por PUBLIC.');
}
if (/p_xp\s+integer|p_points\s+integer/i.test(sql)) {
  throw new Error('O cliente não pode indicar diretamente a quantidade de XP.');
}
console.log('Proposta de XP validada: pseudónimo sem Auth, token de dispositivo em hash, RLS, XP confirmado pelo servidor, eventos idempotentes e RPCs apenas para anon.');
