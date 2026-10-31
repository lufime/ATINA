BEGIN;
SELECT plan(11);
CREATE TEMP TABLE _host AS SELECT public.atina_create_room('Host Team 01',4) AS value;
CREATE TEMP TABLE _guest1 AS SELECT public.atina_join_room('Guest Team 1',(SELECT value->>'code' FROM _host)) AS value;
CREATE TEMP TABLE _guest2 AS SELECT public.atina_join_room('Guest Team 2',(SELECT value->>'code' FROM _host)) AS value;

SELECT public.atina_set_room_team(
 (SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),
 (SELECT (value->>'player_id')::uuid FROM _guest1),'Azuis');
SELECT public.atina_set_room_team(
 (SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),
 (SELECT (value->>'player_id')::uuid FROM _guest2),'Vermelhos');
SELECT public.atina_set_room_ready((SELECT (value->>'room_id')::uuid FROM _guest1),(SELECT value->>'token' FROM _guest1),true);
SELECT public.atina_set_room_ready((SELECT (value->>'room_id')::uuid FROM _guest2),(SELECT value->>'token' FROM _guest2),true);
SELECT public.atina_start_room((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host));
SELECT public.atina_start_room_challenges((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),'medium',60,NULL);

UPDATE public.atina_room_players SET score=100
WHERE id IN ((SELECT (value->>'player_id')::uuid FROM _host),(SELECT (value->>'player_id')::uuid FROM _guest1));

CREATE TEMP TABLE _wrong AS
SELECT public.atina_submit_team_proposal(
 (SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),
 0,'resposta deliberadamente errada',true,9999
) AS value;
SELECT is((SELECT value->>'status' FROM _wrong),'pending','team proposal is pending and ignores client correctness and points');

SELECT throws_ok(
 format('SELECT public.atina_vote_team_proposal(%L::uuid,%L,%L::uuid,true)',
  (SELECT value->>'room_id' FROM _host),(SELECT value->>'token' FROM _guest2),
  (SELECT value->>'proposal_id' FROM _wrong)),
 'P0001','Só os membros da equipa podem votar.','other team cannot vote'
);

SELECT is((SELECT value->>'status' FROM (
 SELECT public.atina_vote_team_proposal(
  (SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _guest1),
  (SELECT (value->>'proposal_id')::uuid FROM _wrong),true
 ) AS value
) x),'rejected','unanimous approval does not make an incorrect answer correct');
SELECT is((SELECT resolution_reason FROM public.atina_room_team_proposals WHERE id=(SELECT (value->>'proposal_id')::uuid FROM _wrong)),'incorrect_answer','server records incorrect answer reason');
SELECT is((SELECT score FROM public.atina_room_players WHERE id=(SELECT (value->>'player_id')::uuid FROM _host)),90,'incorrect team answer penalizes proposer');
SELECT is((SELECT score FROM public.atina_room_players WHERE id=(SELECT (value->>'player_id')::uuid FROM _guest1)),90,'incorrect team answer penalizes teammate');

CREATE TEMP TABLE _roomstate AS
SELECT public.atina_room_state((SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host)) AS value;
CREATE TEMP TABLE _right AS
SELECT public.atina_submit_team_proposal(
 (SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _host),
 0,(SELECT answer FROM private.atina_challenges WHERE challenge_id=(SELECT (value->'game_state'->>'challenge_id')::integer FROM _roomstate)),
 false,0
) AS value;
SELECT is((SELECT value->>'status' FROM _right),'pending','correct answer awaits teammate vote');

CREATE TEMP TABLE _accepted AS
SELECT public.atina_vote_team_proposal(
 (SELECT (value->>'room_id')::uuid FROM _host),(SELECT value->>'token' FROM _guest1),
 (SELECT (value->>'proposal_id')::uuid FROM _right),true
) AS value;
SELECT is((SELECT value->>'status' FROM _accepted),'accepted','server accepts correct answer after unanimous vote');

SELECT ok((SELECT (value->>'points_per_player')::integer BETWEEN 1 AND 100 FROM _accepted),'server calculates points independently of forged client points');
SELECT is((SELECT count(*)::integer FROM public.atina_room_answers
 WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host)
 AND challenge_index=0 AND is_correct),2,'server records one correct ledger entry per teammate');
SELECT is((SELECT count(*)::integer FROM public.atina_room_players
 WHERE room_id=(SELECT (value->>'room_id')::uuid FROM _host) AND team_label='Azuis' AND score>90),2,'server awards points to both teammates');
SELECT * FROM finish();
ROLLBACK;
