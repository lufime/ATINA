BEGIN;

INSERT INTO private.atina_challenges
  (challenge_id,category,emoji,clues,answer,accepted_answers,difficulty,active)
VALUES
  (-990023,'__ci_v2_team_vote__','🧪',
   '["pista um","pista dois","pista três","pista quatro","pista cinco"]'::jsonb,
   'Resposta V2 023 A','["resposta v2 023 a"]'::jsonb,'medium',true),
  (-990024,'__ci_v2_team_vote__','🧪',
   '["pista um","pista dois","pista três","pista quatro","pista cinco"]'::jsonb,
   'Resposta V2 023 B','["resposta v2 023 b"]'::jsonb,'medium',true);

SELECT plan(7);

CREATE TEMP TABLE _host AS
SELECT public.atina_v2_create_room('Host Vote 023',4) AS value;
CREATE TEMP TABLE _guest1 AS
SELECT public.atina_v2_join_room('Guest Vote 023 A',(SELECT value->>'code' FROM _host)) AS value;
CREATE TEMP TABLE _guest2 AS
SELECT public.atina_v2_join_room('Guest Vote 023 B',(SELECT value->>'code' FROM _host)) AS value;
CREATE TEMP TABLE _guest3 AS
SELECT public.atina_v2_join_room('Guest Vote 023 C',(SELECT value->>'code' FROM _host)) AS value;

SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _host),'Equipa A');
SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _guest1),'Equipa A');
SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _guest2),'Equipa B');
SELECT public.atina_v2_set_room_team(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  (SELECT (value->>'player_id')::uuid FROM _guest3),'Equipa C');

SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),true);
SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _guest1),true);
SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _guest2),true);
SELECT public.atina_v2_set_room_ready(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _guest3),true);

SELECT public.atina_v2_start_room(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host));
SELECT public.atina_v2_start_room_challenges(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  'medium',0,'__ci_v2_team_vote__');

UPDATE private.atina_v2_room_game_state
   SET special_card='{"id":"double_points","multiplier":3,"bonus":0}'::jsonb
 WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host);

CREATE TEMP TABLE _proposal AS
SELECT public.atina_v2_submit_team_proposal(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host),
  0,
  (SELECT c.answer FROM private.atina_challenges c
    JOIN private.atina_v2_room_game_state g
      ON c.challenge_id=g.challenge_queue[g.position]
   WHERE g.room_id=(SELECT (value->>'room_id')::uuid FROM _host)),
  true,9999
) AS value;

SELECT is((SELECT value->>'status' FROM _proposal),'pending',
  'team answer awaits the other member vote');

CREATE TEMP TABLE _accepted AS
SELECT public.atina_v2_vote_team_proposal(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _guest1),
  (SELECT (value->>'proposal_id')::uuid FROM _proposal),
  true
) AS value;

SELECT is((SELECT value->>'status' FROM _accepted),'accepted',
  'unanimous team vote accepts the server-verified answer');
SELECT is((SELECT (value->>'points_per_player')::integer FROM _accepted),60,
  'team voting applies the same server-side special-card multiplier');
SELECT ok((SELECT round_locked AND team_turn_advanced
  FROM private.atina_v2_room_game_state
  WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)),
  'a correct team vote closes and completes the active turn');

CREATE TEMP TABLE _next AS
SELECT public.atina_v2_next_room_challenge(
  (SELECT (value->>'room_id')::uuid FROM _host),
  (SELECT value->>'token' FROM _host)
) AS value;

SELECT is((SELECT value->>'status' FROM _next),'next',
  'the active team advances after unanimous approval');
SELECT ok((SELECT value->'state'->>'active_team' <> 'Equipa A' FROM _next),
  'the turn rotates away from the team that just completed its turn');

SELECT throws_ok(
  format('SELECT public.atina_v2_next_room_challenge(%L::uuid,%L)',
    (SELECT value->>'room_id' FROM _host),
    (SELECT value->>'token' FROM _host)),
  'P0001','Só a equipa ativa pode avançar o desafio.',
  'the previous team cannot advance again after its turn has rotated');

SELECT * FROM finish();
ROLLBACK;
