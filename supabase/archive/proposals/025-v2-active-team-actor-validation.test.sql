BEGIN;

INSERT INTO private.atina_challenges
  (challenge_id,category,emoji,clues,answer,accepted_answers,difficulty,active)
VALUES
  (-990027,'__ci_v2_unassigned_turn__','🧪',
   '["pista um","pista dois","pista três"]'::jsonb,
   'Resposta Protegida 027','["resposta protegida 027"]'::jsonb,'medium',true);

SELECT plan(1);

CREATE TEMP TABLE _host AS
SELECT public.atina_v2_create_room('Host 027',3) AS value;
CREATE TEMP TABLE _guest1 AS
SELECT public.atina_v2_join_room('Guest 027 A',(SELECT value->>'code' FROM _host)) AS value;
CREATE TEMP TABLE _guest2 AS
SELECT public.atina_v2_join_room('Guest 027 B',(SELECT value->>'code' FROM _host)) AS value;

SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _host),'Equipa A');
SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _guest1),'Equipa B');
SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _guest2),'Equipa A');

SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),true);
SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _guest1),true);
SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _guest2),true);

SELECT public.atina_v2_start_room(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host));
SELECT public.atina_v2_start_room_challenges(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  'medium',0,'__ci_v2_unassigned_turn__');

-- Simulate a participant losing their team assignment after the game starts.
UPDATE public.atina_v2_room_players
   SET team_label=NULL
 WHERE id=(SELECT (value->>'player_id')::uuid FROM _guest2)
   AND room_id=(SELECT (value->>'room_id')::uuid FROM _host);

SELECT throws_ok(
  format(
    'SELECT public.atina_v2_submit_room_answer(%L::uuid,%L,%L)',
    (SELECT value->>'room_id' FROM _host),
    (SELECT value->>'token' FROM _guest2),
    'Resposta Protegida 027'
  ),
  'P0001','O jogador não pertence a uma equipa.',
  'a participant without a team cannot bypass the active-team turn gate'
);

SELECT * FROM finish();
ROLLBACK;
