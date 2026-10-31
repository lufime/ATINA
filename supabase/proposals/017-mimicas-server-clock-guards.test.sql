BEGIN;
SELECT plan(6);
CREATE TEMP TABLE _host AS SELECT public.atina_create_room('Mime Clock Host',2) AS value;
CREATE TEMP TABLE _guest AS SELECT public.atina_join_room('Mime Clock Guest',(SELECT value->>'code' FROM _host)) AS value;
SELECT public.atina_set_room_ready((SELECT (value->>'room_id')::uuid FROM _guest),(SELECT value->>'token' FROM _guest),true);
SELECT public.atina_start_room((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host));
CREATE TEMP TABLE _mime AS SELECT public.atina_start_mime_round(
 (SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),0,
 (SELECT (value->>'player_id')::uuid FROM _host),60) AS value;
SELECT is((SELECT (value->>'started')::boolean FROM _mime),false,'preparing a round does not start the clock');
SELECT is((SELECT started_at IS NULL AND deadline_at IS NULL FROM private.atina_mime_rounds WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),true,'private clock remains unset before host action');
CREATE TEMP TABLE _started AS SELECT public.atina_publish_game_state(
 (SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),
 (SELECT value FROM _mime)||jsonb_build_object('started',true)) AS value;
SELECT is((SELECT (value->>'started')::boolean FROM _started),true,'host start action begins server clock');
SELECT ok((SELECT deadline_at>started_at FROM private.atina_mime_rounds WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),'deadline is created by server clock');
SELECT throws_ok(
 format('SELECT public.atina_start_mime_round(%L::uuid,%L,0,%L::uuid,60)',
 (SELECT value->>'room_id' FROM _host),(SELECT value->>'token' FROM _host),(SELECT value->>'player_id' FROM _host)),
 'P0001','A partida não está preparada para iniciar Mímicas.','cannot replace a different game mode with Mímicas'
);
SELECT throws_ok(
 format('SELECT public.atina_resolve_mime_round(%L::uuid,%L,true,5000,''correct'')',
 (SELECT value->>'room_id' FROM _host),(SELECT value->>'token' FROM _host)),
 'P0001','A ronda já terminou.','cannot resolve a round already locked'
);
SELECT * FROM finish();
ROLLBACK;
