const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const branchFiles = [
  'supabase/migrations/202611200002_atina_quick_match_bot_fallback.sql',
  'supabase/migrations/202611200003_atina_quick_match_cancel_fallback_race.sql',
  'index.html'
];

test('fallback room is recorded by ticket in the same migration function', () => {
  const sql = fs.readFileSync(branchFiles[0], 'utf8');
  assert.match(sql, /INSERT INTO private\\.atina_v2_quickmatch_bot_fallbacks\\(ticket_hash,room_id\\)/);
  assert.match(sql, /VALUES\\(v_hash,\\(v_result->>'room_id'\\)::uuid\\)/);
});

test('cancel migration removes a tracked bot room and tracking row', () => {
  const sql = fs.readFileSync(branchFiles[1], 'utf8');
  assert.match(sql, /SELECT room_id INTO v_bot_room[\\s\\S]*?FROM private\\.atina_v2_quickmatch_bot_fallbacks[\\s\\S]*?WHERE ticket_hash=v_hash FOR UPDATE/);
  assert.match(sql, /DELETE FROM public\\.atina_v2_rooms WHERE id=v_bot_room/);
  assert.match(sql, /DELETE FROM private\\.atina_v2_quickmatch_bot_fallbacks WHERE ticket_hash=v_hash/);
});

test('client ignores matchmaking/fallback responses for a cancelled ticket', () => {
  const html = fs.readFileSync(branchFiles[2], 'utf8');
  assert.match(html, /quickMatchTicket!==ticket\\|\\|!quickMatchBusy\)return;/);
  assert.match(html, /quickMatchTryBotFallback[\\s\\S]*?quickMatchTicket!==ticket\\|\\|!quickMatchBusy\)return;/);
});
