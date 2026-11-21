-- Ephemeral PostgreSQL smoke test for the voluntary Push reminder migrations.
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS private;

CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;

CREATE OR REPLACE FUNCTION private.atina_social_player_from_session(p_token text)
RETURNS uuid
LANGUAGE sql
AS $$ SELECT '11111111-1111-1111-1111-111111111111'::uuid $$;

\i supabase/migrations/20261120200000_atina_push_subscriptions.sql
\i supabase/migrations/20261121110000_atina_push_reminder_activity.sql
\i supabase/migrations/20261121113000_atina_push_reminder_claims.sql

DO $$
DECLARE
  v_cols integer;
  v_claims integer;
  v_activity jsonb;
BEGIN
  SELECT count(*) INTO v_cols
  FROM information_schema.columns
  WHERE table_schema='public' AND table_name='atina_push_subscriptions'
    AND column_name IN ('last_activity_at','last_reminded_at','last_attempt_at');
  IF v_cols <> 3 THEN RAISE EXCEPTION 'Expected all reminder columns; got %', v_cols; END IF;

  INSERT INTO public.atina_push_subscriptions(player_id,endpoint,subscription,last_activity_at)
  VALUES ('11111111-1111-1111-1111-111111111111',
    'not-a-url',
    '{"endpoint":"not-a-url","keys":{"p256dh":"p","auth":"a"}}',
    now() - interval '49 hours');

  v_activity := public.atina_push_subscription_activity('test-session','not-a-url');
  IF v_activity->>'ok' <> 'true' OR (v_activity->>'updated')::int <> 1 THEN
    RAISE EXCEPTION 'Activity RPC did not update own subscription: %', v_activity;
  END IF;

  UPDATE public.atina_push_subscriptions
  SET last_activity_at=now()-interval '49 hours'
  WHERE endpoint='not-a-url';

  SELECT count(*) INTO v_claims FROM public.atina_push_reminders_claim(10);
  IF v_claims <> 1 THEN RAISE EXCEPTION 'Expected first atomic claim to return one row; got %', v_claims; END IF;

  SELECT count(*) INTO v_claims FROM public.atina_push_reminders_claim(10);
  IF v_claims <> 0 THEN RAISE EXCEPTION 'Expected cooldown to prevent immediate duplicate claim; got %', v_claims; END IF;

  IF NOT has_function_privilege('service_role','public.atina_push_reminders_claim(integer)','EXECUTE') THEN
    RAISE EXCEPTION 'service_role missing claim function execute privilege';
  END IF;
  IF has_function_privilege('anon','public.atina_push_reminders_claim(integer)','EXECUTE') THEN
    RAISE EXCEPTION 'anon must not execute claim function';
  END IF;
END $$;

\echo 'Push reminder SQL smoke tests passed'
