import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const sql = await readFile(new URL('../supabase/migrations/20261122230000_atina_smart_challenge_selection.sql', import.meta.url), 'utf8');
assert.match(sql, /p_challenge_count integer default 10/);
assert.match(sql, /p_device_token text default null/);
assert.match(sql, /limit p_challenge_count/);
assert.match(sql, /atina_challenge_exposures e/);
assert.match(sql, /e\.challenge_id=c\.challenge_id/);
assert.match(sql, /when p_category is not null and c\.category=p_category then 1/);
assert.match(sql, /when p_category is not null and c\.category=p_category/);
assert.match(sql, /when p_game_mode='mix' or p_difficulty='mixed'\s+or c.difficulty=p_difficulty then 2/);
assert.match(sql, /insert into private\.atina_challenge_exposures/);
assert.match(sql, /Parabéns! Já completaste todos os desafios disponíveis/);
assert.match(sql, /public\.atina_v2_start_local_game\(text,text,text,integer,integer,text\)/);
console.log('Smart challenge selection migration checks passed.');
