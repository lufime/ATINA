-- The room host is a regular player for turn ownership and clue control.
-- PASSAR, CONTINUAR and REVELAR PISTA must all respect the currently active team.

DO $turn_actions$
DECLARE
  v_signature regprocedure;
  v_definition text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.atina_v2_pass_room_challenge(uuid,text)'::regprocedure,
    'public.atina_v2_next_room_challenge(uuid,text)'::regprocedure
  ]
  LOOP
    v_definition := pg_get_functiondef(v_signature);

    IF v_definition !~* 'if not v_player\.is_host and \(' THEN
      RAISE EXCEPTION 'Expected host turn bypass not found in %', v_signature;
    END IF;

    v_definition := regexp_replace(
      v_definition,
      'if not v_player\.is_host and \(',
      'if (',
      'gi'
    );

    EXECUTE v_definition;
  END LOOP;
END
$turn_actions$;

DO $clue_action$
DECLARE
  v_signature regprocedure := 'public.atina_v2_reveal_room_clue(uuid,text)'::regprocedure;
  v_definition text;
  v_host_check text := 'IF NOT FOUND OR NOT v_player.is_host THEN RAISE EXCEPTION ''Só o anfitrião pode revelar pistas.''; END IF;';
  v_session_check text := 'IF NOT FOUND THEN RAISE EXCEPTION ''Sessão da sala inválida.''; END IF;';
  v_game_check text := 'IF NOT FOUND OR v_game.status<>''active'' OR v_game.round_locked THEN
    RAISE EXCEPTION ''A ronda não está ativa.'';
  END IF;';
  v_team_check text := 'IF v_player.team_label IS NULL OR cardinality(v_game.team_order)=0
    OR v_player.team_label IS DISTINCT FROM v_game.team_order[v_game.active_team_index] THEN
    RAISE EXCEPTION ''Só a equipa que tem a vez pode revelar pistas.'';
  END IF;';
BEGIN
  v_definition := pg_get_functiondef(v_signature);

  IF position(v_host_check in v_definition)=0 THEN
    RAISE EXCEPTION 'Expected host-only clue guard not found in %', v_signature;
  END IF;
  IF position(v_game_check in v_definition)=0 THEN
    RAISE EXCEPTION 'Expected active game guard not found in %', v_signature;
  END IF;

  v_definition := replace(v_definition, v_host_check, v_session_check);
  v_definition := replace(v_definition, v_game_check, v_game_check || E'\n  ' || v_team_check);

  EXECUTE v_definition;
END
$clue_action$;

-- Verify all turn controls now use active-team authorization, never host status.
DO $verification$
DECLARE
  v_signature regprocedure;
  v_definition text;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.atina_v2_pass_room_challenge(uuid,text)'::regprocedure,
    'public.atina_v2_next_room_challenge(uuid,text)'::regprocedure
  ]
  LOOP
    v_definition := pg_get_functiondef(v_signature);
    IF v_definition ~* 'if not v_player\.is_host and \(' THEN
      RAISE EXCEPTION 'Host turn bypass remains in %', v_signature;
    END IF;
  END LOOP;

  v_definition := pg_get_functiondef('public.atina_v2_reveal_room_clue(uuid,text)'::regprocedure);
  IF v_definition ~* 'not v_player\.is_host' OR
     v_definition !~* 'Só a equipa que tem a vez pode revelar pistas' THEN
    RAISE EXCEPTION 'Clue reveal is not restricted to the active team';
  END IF;
END
$verification$;
