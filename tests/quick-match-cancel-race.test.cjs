const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const fallbackSql = 'supabase/migrations/202611200002_atina_quick_match_bot_fallback.sql';
const cancelSql = 'supabase/migrations/202611200003_atina_quick_match_cancel_fallback_race.sql';
const clientHtml = 'index.html';

test('fallback room is recorded by ticket in the same migration function', () => {
  const sql = fs.readFileSync(fallbackSql, 'utf8');
  assert.ok(sql.includes('INSERT INTO private.atina_v2_quickmatch_bot_fallbacks(ticket_hash,room_id)'));
  assert.ok(sql.includes("VALUES(v_hash,(v_result->>'room_id')::uuid)"));
});

test('cancel migration removes a tracked bot room and tracking row', () => {
  const sql = fs.readFileSync(cancelSql, 'utf8');
  assert.ok(sql.includes('FROM private.atina_v2_quickmatch_bot_fallbacks'));
  assert.ok(sql.includes('DELETE FROM public.atina_v2_rooms WHERE id=v_bot_room'));
  assert.ok(sql.includes('DELETE FROM private.atina_v2_quickmatch_bot_fallbacks WHERE ticket_hash=v_hash'));
});

test('client ignores RPC responses when ticket was cancelled', () => {
  const html = fs.readFileSync(clientHtml, 'utf8');
  assert.ok(html.includes('quickMatchTicket!==ticket||!quickMatchBusy)return;'));
  assert.ok(html.includes("const sessionToken=quickMatchSessionToken;"));
});

test('initial status response does not schedule fallback after the ticket has matched or been cancelled', () => {
  const html = fs.readFileSync(clientHtml, 'utf8');
  assert.ok(html.includes('await quickMatchCheck();if(quickMatchTicket===ticket&&quickMatchBusy)quickMatchFallbackTimer=setTimeout(quickMatchTryBotFallback,8000);'));
});
