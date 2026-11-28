const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/20261128150000_retire_mimicas_mode.sql'), 'utf8');

test('Mímicas is absent from player-facing mode selectors', () => {
  assert.doesNotMatch(html, /data-category="Mímicas"/);
  assert.doesNotMatch(html, /id="networkStartMimicas"/);
  assert.doesNotMatch(html, /openConfig\('mime'/);
  assert.match(html, /function openConfig\(m,c\)\{if\(m==='mime'\)return;/);
});

test('server rejects new Mímicas games in legacy and V2 rooms', () => {
  assert.match(migration, /atina_disable_new_mimicas_legacy_insert/);
  assert.match(migration, /atina_disable_new_mimicas_v2_insert/);
  assert.match(migration, /feature_not_supported/);
  assert.match(migration, /OLD\.game_state->>'mode'/);
});
