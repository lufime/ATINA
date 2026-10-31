BEGIN;
SELECT plan(18);
CREATE TEMP TABLE _host AS SELECT public.atina_create_room('Mime Host',4) AS value;
CREATE TEMP TABLE _guest1 AS SELECT public.atina_join_room('Mime Guest 1',(SELECT value->>'code' FROM _host)) AS value;
CREATE TEMP TABLE _guest2 AS SELECT public.atina_join_room('Mime Guest 2',(SELECT value->>'code' FROM _host)) AS value;
SELECT public.atina_set_room_team((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),(SELECT (value->>'player_id')::uuid FROM _host),'Azuis');
SELECT public.atina_set_room_team((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),(SELECT (value->>'player_id')::uuid FROM _guest1),'Azuis');
SELECT public.atina_set_room_ready((SELECT (value->>'room_id')::uuid FROM _guest1),(SELECT value->>'token' FROM _guest1),true);
SELECT public.atina_set_room_ready((SELECT (value->>'room_id')::uuid FROM _guest2),(SELECT value->>'token' FROM _guest2),true);
SELECT public.atina_start_room((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host));

CREATE TEMP TABLE _mime AS
SELECT public.atina_start_mime_round((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),0,(SELECT (value->>'player_id')::uuid FROM _host),0) AS value;
SELECT is((SELECT value->>'mode' FROM _mime),'mimicas','server starts Mímicas round');
SELECT ok((SELECT (value->'clues') IS NOT NULL AND jsonb_array_length(value->'clues')=1 FROM _mime),'only first visual clue is public initially');
SELECT ok((SELECT NOT (value ? 'answer') FROM _mime),'public state does not reveal secret word');
SELECT is((SELECT (value->>'started')::boolean FROM _mime),false,'round clock waits for explicit host start');
SELECT is((SELECT value->>'word' FROM (
 SELECT public.atina_get_mime_secret((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host)) AS value
) x) IS NOT NULL,true,'representative can retrieve secret');
SELECT throws_ok(
 format('SELECT public.atina_get_mime_secret(%L::uuid,%L)',(SELECT value->>'room_id' FROM _host),(SELECT value->>'token' FROM _guest1)),
 'P0001','Só o representante desta ronda pode ver a palavra secreta.','non-representative cannot retrieve secret'
);
CREATE TEMP TABLE _clock_started AS SELECT public.atina_publish_game_state(
 (SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),
 (SELECT value FROM _mime)||jsonb_build_object('started',true)
) AS value;
SELECT is((SELECT (value->>'started')::boolean FROM _clock_started),true,'server starts clock on host action');
SELECT public.atina_publish_game_state(
 (SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),
 (SELECT value FROM _mime)||jsonb_build_object('clue_index',1)
);
SELECT is((SELECT clue_index FROM private.atina_mime_rounds WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host) AND round_number=0),1,'host can reveal exactly one additional clue through constrained state transition');
SELECT throws_ok(
 format('SELECT public.atina_publish_game_state(%L::uuid,%L,%L::jsonb)',
  (SELECT value->>'room_id' FROM _host),(SELECT value->>'token' FROM _host),
  '{"mode":"mimicas","locked":true,"answer":"forged","points_awarded":9999}'),
 'P0001','Transição de Mímicas inválida.','host cannot publish arbitrary result or score'
);
CREATE TEMP TABLE _resolved AS
SELECT public.atina_resolve_mime_round(
 (SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),true,999999,'correct'
) AS value;
SELECT is((SELECT (value->>'points_awarded')::integer FROM _resolved),16,'server calculates points from revealed clue index and ignores client points');
SELECT is((SELECT score FROM public.atina_room_players WHERE id=(SELECT (value->>'player_id')::uuid FROM _host)),16,'team representative receives team points');
SELECT is((SELECT score FROM public.atina_room_players WHERE id=(SELECT (value->>'player_id')::uuid FROM _guest1)),16,'teammate receives server-awarded points');
SELECT ok((SELECT (value->>'locked')::boolean FROM _resolved),'server locks resolved mime round');
SELECT ok(NOT has_table_privilege('anon','private.atina_mime_cards','select'),'anon cannot read private Mímicas cards');
SELECT ok(NOT has_table_privilege('authenticated','private.atina_mime_rounds','select'),'authenticated cannot read private Mímicas rounds');

CREATE TEMP TABLE _host2 AS SELECT public.atina_create_room('Mime Host 2',2) AS value;
CREATE TEMP TABLE _guest3 AS SELECT public.atina_join_room('Mime Guest 3',(SELECT value->>'code' FROM _host2)) AS value;
SELECT public.atina_set_room_ready((SELECT (value->>'room_id')::uuid FROM _guest3),(SELECT value->>'token' FROM _guest3),true);
SELECT public.atina_start_room((SELECT (value->>'room_id')::uuid FROM _host2),(SELECT value->>'token' FROM _host2));
SELECT public.atina_start_mime_round((SELECT (value->>'room_id')::uuid FROM _host2),(SELECT value->>'token' FROM _host2),0,(SELECT (value->>'player_id')::uuid FROM _host2),60);
UPDATE private.atina_mime_rounds SET deadline_at=clock_timestamp()-interval '1 second'
WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host2) AND round_number=0;
CREATE TEMP TABLE _expired AS
SELECT public.atina_room_state((SELECT (value->>'room_id')::uuid FROM _host2),(SELECT value->>'token' FROM _host2)) AS value;
SELECT ok((SELECT (value->'game_state'->>'locked')::boolean FROM _expired),'polling closes an expired Mímicas round');
SELECT is((SELECT outcome FROM private.atina_mime_rounds WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host2) AND round_number=0),'timeout','server records timeout outcome during polling');
SELECT ok((SELECT value->'game_state' ? 'answer' FROM _expired),'solution is revealed only after server timeout lock');
SELECT * FROM finish();
ROLLBACK;
