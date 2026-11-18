BEGIN;

INSERT INTO private.atina_challenges
  (challenge_id,category,emoji,clues,answer,accepted_answers,difficulty,active)
VALUES
  (-990025,'__ci_v2_timeout__','⏱️',
   '["pista um","pista dois","pista três","pista quatro","pista cinco"]'::jsonb,
   'Resposta Timeout 025','["resposta timeout 025"]'::jsonb,'medium',true),
  (-990026,'__ci_v2_timeout__','⏱️',
   '["pista um","pista dois","pista três","pista quatro","pista cinco"]'::jsonb,
   'Resposta Timeout 026','["resposta timeout 026"]'::jsonb,'medium',true);

SELECT plan(4);

CREATE TEMP TABLE _host AS
SELECT public.atina_v2_create_room('Host Timeout 024',2) AS value;
CREATE TEMP TABLE _guest AS
SELECT public.atina_v2_join_room('Guest Timeout 024',(SELECT value->>'code' FROM _host)) AS value;

SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _host),'Equipa A');
SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _guest),'Equipa B');
SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),true);
SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _guest),true);
SELECT public.atina_v2_start_room(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host));
SELECT public.atina_v2_start_room_challenges(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  'medium',60,'__ci_v2_timeout__');

UPDATE private.atina_v2_room_game_state
   SET deadline_at=clock_timestamp()-interval '1 second',
       round_locked=false,team_turn_advanced=false
 WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host);

SELECT public.atina_v2_room_state(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host));

SELECT ok((SELECT round_locked AND NOT team_turn_advanced
  FROM private.atina_v2_room_game_state
  WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),
  'timeout locks the current round without marking a correct answer');

DO $seed$
DECLARE
  v_i integer;
  v_seed double precision;
  v_first_roll double precision;
BEGIN
  FOR v_i IN 0..100 LOOP
    v_seed:=-1+(v_i*0.02);
    PERFORM setseed(v_seed);
    v_first_roll:=random();
    IF v_first_roll>=0.20 THEN
      PERFORM setseed(v_seed);
      RETURN;
    END IF;
  END LOOP;
  RAISE EXCEPTION 'Could not select a deterministic no-card test seed.';
END;
$seed$;

CREATE TEMP TABLE _next AS
SELECT public.atina_v2_next_room_challenge(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host)
) AS value;

SELECT is((SELECT value->>'status' FROM _next),'next',
  'the active team can advance after the timeout');
SELECT is((SELECT value->'state'->>'active_team' FROM _next),'Equipa B',
  'timeout advancement rotates to the next team');
SELECT throws_ok(
  format('SELECT public.atina_v2_next_room_challenge(%L::uuid,%L)',
    (SELECT value->>'room_id' FROM _host),
    (SELECT value->>'token' FROM _host)),
  'P0001','Só a equipa ativa pode avançar o desafio.',
  'the previous team cannot advance the same timeout twice');

SELECT * FROM finish();
ROLLBACK;
