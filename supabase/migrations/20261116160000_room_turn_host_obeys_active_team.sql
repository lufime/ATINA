-- The room host is a regular player for turn ownership.
-- Passing and advancing a challenge must be restricted to the currently active team,
-- exactly like the client-side controls and answer submission.

DO $migration$
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
$migration$;

-- Verify that neither turn-changing RPC grants the host a turn bypass.
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
END
$verification$;
