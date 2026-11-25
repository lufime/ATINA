const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const csv = fs.readFileSync('.atina-interno/classificacao-tematica-desafios.csv', 'utf8');
const migration = fs.readFileSync('supabase/migrations/20261125120000_atina_challenge_geographic_scope.sql', 'utf8');
const game = fs.readFileSync('index.html', 'utf8');

function parseCsv(source) {
  const rows = [];
  let row = [], value = '', quoted = false;
  for (let i = 0; i < source.length; i++) {
    const char = source[i];
    if (quoted) {
      if (char === '"' && source[i + 1] === '"') { value += '"'; i++; }
      else if (char === '"') quoted = false;
      else value += char;
    } else if (char === '"') quoted = true;
    else if (char === ',') { row.push(value); value = ''; }
    else if (char === '\n') { row.push(value.replace(/\r$/, '')); rows.push(row); row = []; value = ''; }
    else value += char;
  }
  if (value || row.length) { row.push(value.replace(/\r$/, '')); rows.push(row); }
  const headers = rows.shift();
  return rows.filter(item => item.length === headers.length)
    .map(item => Object.fromEntries(headers.map((header, index) => [header, item[index]])));
}

test('geographic classification source contains all 1,089 unique reviewed challenge IDs', () => {
  const rows = parseCsv(csv);
  assert.equal(rows.length, 1089);
  assert.equal(new Set(rows.map(row => row.challenge_id)).size, 1089);
  assert.ok(rows.every(row => ['Portugal', 'Internacional', 'Universal'].includes(row.classification)));
  assert.ok(rows.every(row => row.review_status === 'Revisão textual efetuada; validação editorial concluída'));
});

test('database migration maps every source classification and validates completeness', () => {
  const rows = parseCsv(csv);
  for (const row of rows) {
    assert.ok(migration.includes(`(${Number(row.challenge_id)}, '${row.classification}')`), `missing classification for challenge ${row.challenge_id}`);
  }
  assert.match(migration, /v_total > 0 and v_classified <> v_total/);
  assert.match(migration, /atina_challenges_geographic_scope_check/);
  assert.match(migration, /atina_public_challenge_geographic_scopes/);
  assert.match(migration, /grant execute .* to anon, authenticated/s);
});

test('game loads geographic metadata and applies the selected scope to Solo and Mix queues', () => {
  assert.match(game, /atina_public_challenge_geographic_scopes/);
  assert.match(game, /rows\.length===0/);
  assert.match(game, /id="atinaGeographicScope"/);
  assert.match(game, /function start\(m,chosen=null,geographicScope="Todos"\)/);
  assert.match(game, /matchesGeographicScope\(x\.i\)/);
  assert.match(game, /start\(mode,category,scopeSelect\.value\|\|'Todos'\)/);
  assert.match(game, /void refreshGeographicScopes\(\)/);
});

test('all inline game scripts parse after geographic filtering changes', () => {
  let cursor = 0, scripts = 0;
  while (true) {
    const opening = game.indexOf('<script', cursor);
    if (opening < 0) break;
    const tagEnd = game.indexOf('>', opening);
    const closing = game.indexOf('</script>', tagEnd + 1);
    assert.ok(tagEnd >= 0 && closing > tagEnd, 'script tags should be well formed');
    const attributes = game.slice(opening, tagEnd + 1).toLowerCase();
    const source = game.slice(tagEnd + 1, closing);
    cursor = closing + 9;
    if (attributes.includes(' src=') || attributes.includes('application/json') || attributes.includes('application/ld+json') || !source.trim()) continue;
    assert.doesNotThrow(() => new vm.Script(source, { filename: 'index-inline-script.js' }));
    scripts++;
  }
  assert.ok(scripts > 0);
});
