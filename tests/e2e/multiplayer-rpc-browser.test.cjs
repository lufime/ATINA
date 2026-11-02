const { test } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;

test('two isolated browser contexts exercise real multiplayer and Mímicas RPCs', async () => {
  assert.ok(SUPABASE_URL, 'SUPABASE_URL must point to the disposable local Supabase stack');
  assert.ok(SUPABASE_ANON_KEY, 'SUPABASE_ANON_KEY must be the local public anon key');
  assert.match(SUPABASE_URL, /^http:\/\/(127\.0\.0\.1|localhost):\d+$/, 'Refusing to run unless Supabase URL is localhost');

  const browser = await chromium.launch({ headless: true });
  const contexts = [];
  const rooms = [];
  async function makePlayer(nickname) {
    const context = await browser.newContext();
    contexts.push(context);
    const page = await context.newPage();
    await page.setContent('<!doctype html><html><head><title>ATINA local RPC test</title></head><body></body></html>');
    await page.addScriptTag({ url: 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2' });
    await page.evaluate(({ url, key }) => {
      window.atinaTestClient = window.supabase.createClient(url, key, {
        auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
      });
      window.atinaRpc = async (name, args) => {
        const { data, error } = await window.atinaTestClient.rpc(name, args);
        return {
          data,
          error: error ? { message: error.message, code: error.code } : null
        };
      };
    }, { url: SUPABASE_URL, key: SUPABASE_ANON_KEY });
    return {
      page,
      async rpc(name, args) {
        return page.evaluate(({ name, args }) => window.atinaRpc(name, args), { name, args });
      }
    };
  }
  async function createPair(suffix) {
    const host = await makePlayer('Host-' + suffix);
    const guest = await makePlayer('Guest-' + suffix);
    const created = await host.rpc('atina_v2_create_room', { p_nickname: 'Host-' + suffix, p_max_players: 4 });
    assert.equal(created.error, null, created.error?.message);
    assert.ok(created.data?.room_id && created.data?.token && created.data?.player_id);
    rooms.push({ player: host, room_id: created.data.room_id, token: created.data.token });
    const joined = await guest.rpc('atina_v2_join_room', { p_nickname: 'Guest-' + suffix, p_code: created.data.code });
    assert.equal(joined.error, null, joined.error?.message);
    assert.ok(joined.data?.token && joined.data?.player_id);
    rooms.push({ player: guest, room_id: joined.data.room_id, token: joined.data.token });
    return {
      host, guest,
      hostRoom: created.data,
      guestRoom: joined.data
    };
  }
  async function readyAndStart(pair) {
    const ready = await pair.guest.rpc('atina_v2_set_room_ready', {
      p_room_id: pair.hostRoom.room_id, p_token: pair.guestRoom.token, p_ready: true
    });
    assert.equal(ready.error, null, ready.error?.message);
    const start = await pair.host.rpc('atina_v2_start_room', {
      p_room_id: pair.hostRoom.room_id, p_token: pair.hostRoom.token
    });
    assert.equal(start.error, null, start.error?.message);
    assert.equal(start.data.status, 'playing');
  }

  try {
    // Challenge flow: all mutations below are real RPCs against local Postgres.
    const challenge = await createPair('MP');
    await readyAndStart(challenge);
    const started = await challenge.host.rpc('atina_v2_start_room_challenges', {
      p_room_id: challenge.hostRoom.room_id,
      p_token: challenge.hostRoom.token,
      p_difficulty: 'easy',
      p_duration_seconds: 0,
      p_category: null
    });
    assert.equal(started.error, null, started.error?.message);
    assert.equal(started.data.status, 'started');
    assert.ok(started.data.state?.challenge_id);

    const guestState = await challenge.guest.rpc('atina_v2_room_state', {
      p_room_id: challenge.hostRoom.room_id, p_token: challenge.guestRoom.token
    });
    assert.equal(guestState.error, null, guestState.error?.message);
    assert.equal(guestState.data.game_state.mode, 'challenges');
    assert.equal(Object.hasOwn(guestState.data.game_state, 'answer'), false,
      'answer key must not be exposed while the round is active');

    const wrong = await challenge.guest.rpc('atina_v2_submit_room_answer', {
      p_room_id: challenge.hostRoom.room_id,
      p_token: challenge.guestRoom.token,
      p_answer: 'resposta-e2e-deliberadamente-incorreta'
    });
    assert.equal(wrong.error, null, wrong.error?.message);
    assert.equal(wrong.data.status, 'wrong');

    const pass = await challenge.host.rpc('atina_v2_pass_room_challenge', {
      p_room_id: challenge.hostRoom.room_id, p_token: challenge.hostRoom.token
    });
    assert.equal(pass.error, null, pass.error?.message);
    assert.equal(pass.data.state.locked, true);
    assert.ok(pass.data.state.answer, 'solution is only returned after the round is locked');

    const next = await challenge.host.rpc('atina_v2_next_room_challenge', {
      p_room_id: challenge.hostRoom.room_id, p_token: challenge.hostRoom.token
    });
    assert.equal(next.error, null, next.error?.message);
    assert.equal(next.data.status, 'next');
    assert.equal(next.data.state.pos, 1);

    // Mímicas flow: the secret is available to the representative only.
    const mime = await createPair('MM');
    await readyAndStart(mime);
    const mimeStart = await mime.host.rpc('atina_v2_start_mime_round', {
      p_room_id: mime.hostRoom.room_id,
      p_token: mime.hostRoom.token,
      p_round_number: 0,
      p_representative_id: mime.hostRoom.player_id,
      p_duration_seconds: 0
    });
    assert.equal(mimeStart.error, null, mimeStart.error?.message);
    assert.equal(mimeStart.data.mode, 'mimicas');

    const secret = await mime.host.rpc('atina_v2_get_mime_secret', {
      p_room_id: mime.hostRoom.room_id, p_token: mime.hostRoom.token
    });
    assert.equal(secret.error, null, secret.error?.message);
    assert.ok(secret.data.word);

    const denied = await mime.guest.rpc('atina_v2_get_mime_secret', {
      p_room_id: mime.hostRoom.room_id, p_token: mime.guestRoom.token
    });
    assert.ok(denied.error, 'non-representative must be denied the secret');

    const observerState = await mime.guest.rpc('atina_v2_room_state', {
      p_room_id: mime.hostRoom.room_id, p_token: mime.guestRoom.token
    });
    assert.equal(observerState.error, null, observerState.error?.message);
    assert.equal(observerState.data.game_state.mode, 'mimicas');
    assert.equal(Object.hasOwn(observerState.data.game_state, 'answer'), false);
    assert.equal(JSON.stringify(observerState.data.game_state).includes(secret.data.word), false,
      'secret word must not appear in observer state before round resolution');

    const clock = await mime.host.rpc('atina_v2_publish_game_state', {
      p_room_id: mime.hostRoom.room_id,
      p_token: mime.hostRoom.token,
      p_state: { started: true }
    });
    assert.equal(clock.error, null, clock.error?.message);
    assert.equal(clock.data.started, true);

    const resolved = await mime.host.rpc('atina_v2_resolve_mime_round', {
      p_room_id: mime.hostRoom.room_id,
      p_token: mime.hostRoom.token,
      p_correct: false,
      p_points: 0,
      p_reason: 'pass'
    });
    assert.equal(resolved.error, null, resolved.error?.message);
    assert.equal(resolved.data.locked, true);
  } finally {
    // Best-effort cleanup; each run uses a disposable local database regardless.
    for (const room of rooms) {
      try {
        await room.player.rpc('atina_v2_leave_room', { p_room_id: room.room_id, p_token: room.token });
      } catch (_) {}
    }
    await Promise.all(contexts.map(context => context.close()));
    await browser.close();
  }
});
