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

CREATE TABLE private.atina_players(id uuid PRIMARY KEY, nickname text);
CREATE TABLE public.atina_v2_rooms(id uuid PRIMARY KEY, code text);
CREATE TABLE public.atina_friend_requests(id uuid PRIMARY KEY, sender_player_id uuid, recipient_player_id uuid, status text);
CREATE TABLE public.atina_game_invites(id uuid PRIMARY KEY, inviter_player_id uuid, recipient_player_id uuid, room_id uuid, status text);

\i supabase/migrations/20261120190000_atina_notifications_inbox_and_triggers.sql
\i supabase/migrations/20261120200000_atina_push_subscriptions.sql
\i supabase/migrations/20261121110000_atina_push_reminder_activity.sql
\i supabase/migrations/20261121113000_atina_push_reminder_claims.sql

DO $$
DECLARE
  v_cols integer;
  v_claims integer;
  v_activity jsonb;
BEGIN
  -- Verify notification migration triggers and RPC permissions.
  INSERT INTO private.atina_players(id,nickname) VALUES
    ('11111111-1111-1111-1111-111111111111','Teste A'),
    ('22222222-2222-2222-2222-222222222222','Teste B');
  INSERT INTO public.atina_friend_requests(id,sender_player_id,recipient_player_id,status)
    VALUES ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222','pending');
  IF NOT EXISTS (SELECT 1 FROM public.atina_notifications WHERE dedupe_key='friend-request-in:33333333-3333-3333-3333-333333333333') THEN
    RAISE EXCEPTION 'Friend request trigger did not create inbox notification';
  END IF;
  INSERT INTO public.atina_v2_rooms(id,code) VALUES ('44444444-4444-4444-4444-444444444444','ROOM');
  INSERT INTO public.atina_game_invites(id,inviter_player_id,recipient_player_id,room_id,status)
    VALUES ('55555555-5555-5555-5555-555555555555','11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222','44444444-4444-4444-4444-444444444444','pending');
  IF NOT EXISTS (SELECT 1 FROM public.atina_notifications WHERE dedupe_key='game-invite-in:55555555-5555-5555-5555-555555555555') THEN
    RAISE EXCEPTION 'Game invite trigger did not create inbox notification';
  END IF;
  IF NOT has_function_privilege('anon','public.atina_notification_list(text)','EXECUTE') THEN
    RAISE EXCEPTION 'anon missing notification list RPC privilege';
  END IF;
  IF has_function_privilege('anon','public.atina_notification_friend_event()','EXECUTE') THEN
    RAISE EXCEPTION 'anon must not execute trigger function';
  END IF;

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
