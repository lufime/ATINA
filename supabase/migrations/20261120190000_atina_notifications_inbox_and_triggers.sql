-- ATINA persistent notifications inbox and event triggers
CREATE TABLE IF NOT EXISTS public.atina_notifications (
  id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
  recipient_player_id uuid NOT NULL,
  notification_type text NOT NULL CHECK (notification_type IN ('friend_request','friend_accepted','friend_declined','game_invite','game_invite_accepted','game_invite_declined','game_invite_expired')),
  title text NOT NULL,
  body text NOT NULL,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  dedupe_key text UNIQUE
);
CREATE INDEX IF NOT EXISTS atina_notifications_recipient_created_idx ON public.atina_notifications(recipient_player_id, created_at DESC);
CREATE INDEX IF NOT EXISTS atina_notifications_unread_idx ON public.atina_notifications(recipient_player_id, created_at DESC) WHERE read_at IS NULL;
ALTER TABLE public.atina_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.atina_notifications FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.atina_notification_list(p_session_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_player uuid;
BEGIN
  v_player := private.atina_social_player_from_session(p_session_token);
  RETURN jsonb_build_object(
    'unread_count', (SELECT count(*) FROM public.atina_notifications n WHERE n.recipient_player_id=v_player AND n.read_at IS NULL),
    'notifications', (SELECT coalesce(jsonb_agg(jsonb_build_object('id',n.id,'type',n.notification_type,'title',n.title,'body',n.body,'data',n.data,'created_at',n.created_at,'read_at',n.read_at) ORDER BY n.created_at DESC),'[]'::jsonb) FROM (SELECT * FROM public.atina_notifications WHERE recipient_player_id=v_player ORDER BY created_at DESC LIMIT 40) n)
  );
END;
$function$;
CREATE OR REPLACE FUNCTION public.atina_notification_mark_read(p_session_token text, p_notification_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_player uuid; v_count integer;
BEGIN
  v_player := private.atina_social_player_from_session(p_session_token);
  IF p_notification_id IS NULL THEN
    UPDATE public.atina_notifications SET read_at=coalesce(read_at,now()) WHERE recipient_player_id=v_player AND read_at IS NULL;
  ELSE
    UPDATE public.atina_notifications SET read_at=coalesce(read_at,now()) WHERE recipient_player_id=v_player AND id=p_notification_id;
  END IF;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('ok',true,'updated',v_count);
END;
$function$;
CREATE OR REPLACE FUNCTION public.atina_notification_clear(p_session_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_player uuid; v_count integer;
BEGIN
  v_player := private.atina_social_player_from_session(p_session_token);
  DELETE FROM public.atina_notifications WHERE recipient_player_id=v_player;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('ok',true,'deleted',v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.atina_notification_friend_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_nickname text; v_type text; v_title text; v_body text; v_key text;
BEGIN
  IF TG_OP='INSERT' AND NEW.status='pending' THEN
    SELECT nickname INTO v_nickname FROM private.atina_players WHERE id=NEW.sender_player_id;
    INSERT INTO public.atina_notifications(recipient_player_id,notification_type,title,body,data,dedupe_key)
    VALUES(NEW.recipient_player_id,'friend_request','Novo pedido de amizade',coalesce(v_nickname,'Um jogador')||' enviou-te um pedido de amizade.',jsonb_build_object('request_id',NEW.id,'player_id',NEW.sender_player_id),'friend-request-in:'||NEW.id::text)
    ON CONFLICT (dedupe_key) DO NOTHING;
  ELSIF TG_OP='UPDATE' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN ('accepted','declined') THEN
    SELECT nickname INTO v_nickname FROM private.atina_players WHERE id=NEW.recipient_player_id;
    v_type := CASE WHEN NEW.status='accepted' THEN 'friend_accepted' ELSE 'friend_declined' END;
    v_title := CASE WHEN NEW.status='accepted' THEN 'Pedido de amizade aceite' ELSE 'Pedido de amizade recusado' END;
    v_body := CASE WHEN NEW.status='accepted' THEN coalesce(v_nickname,'Um jogador')||' aceitou o teu pedido de amizade.' ELSE coalesce(v_nickname,'Um jogador')||' respondeu ao teu pedido de amizade.' END;
    v_key := 'friend-request-out:'||NEW.id::text||':'||NEW.status;
    INSERT INTO public.atina_notifications(recipient_player_id,notification_type,title,body,data,dedupe_key)
    VALUES(NEW.sender_player_id,v_type,v_title,v_body,jsonb_build_object('request_id',NEW.id,'player_id',NEW.recipient_player_id),v_key)
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS atina_notification_friend_event_trigger ON public.atina_friend_requests;
CREATE TRIGGER atina_notification_friend_event_trigger AFTER INSERT OR UPDATE OF status ON public.atina_friend_requests FOR EACH ROW EXECUTE FUNCTION public.atina_notification_friend_event();

CREATE OR REPLACE FUNCTION public.atina_notification_game_invite_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_nickname text; v_room_code text; v_type text; v_title text; v_body text; v_key text;
BEGIN
  IF TG_OP='INSERT' AND NEW.status='pending' THEN
    SELECT nickname INTO v_nickname FROM private.atina_players WHERE id=NEW.inviter_player_id;
    SELECT code INTO v_room_code FROM public.atina_v2_rooms WHERE id=NEW.room_id;
    INSERT INTO public.atina_notifications(recipient_player_id,notification_type,title,body,data,dedupe_key)
    VALUES(NEW.recipient_player_id,'game_invite','Convite para jogar',coalesce(v_nickname,'Um amigo')||' convidou-te para jogar na sala '||coalesce(v_room_code,'')||'.',jsonb_build_object('invite_id',NEW.id,'room_id',NEW.room_id,'room_code',v_room_code,'player_id',NEW.inviter_player_id),'game-invite-in:'||NEW.id::text)
    ON CONFLICT (dedupe_key) DO NOTHING;
  ELSIF TG_OP='UPDATE' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.status IN ('accepted','declined','expired') THEN
    SELECT nickname INTO v_nickname FROM private.atina_players WHERE id=NEW.recipient_player_id;
    v_type := CASE NEW.status WHEN 'accepted' THEN 'game_invite_accepted' WHEN 'declined' THEN 'game_invite_declined' ELSE 'game_invite_expired' END;
    v_title := CASE NEW.status WHEN 'accepted' THEN 'Convite aceite' WHEN 'declined' THEN 'Convite recusado' ELSE 'Convite expirado' END;
    v_body := CASE NEW.status WHEN 'accepted' THEN coalesce(v_nickname,'Um amigo')||' aceitou o teu convite para jogar.' WHEN 'declined' THEN coalesce(v_nickname,'Um amigo')||' respondeu ao teu convite para jogar.' ELSE 'O teu convite para jogar expirou.' END;
    v_key := 'game-invite-out:'||NEW.id::text||':'||NEW.status;
    INSERT INTO public.atina_notifications(recipient_player_id,notification_type,title,body,data,dedupe_key)
    VALUES(NEW.inviter_player_id,v_type,v_title,v_body,jsonb_build_object('invite_id',NEW.id,'room_id',NEW.room_id,'room_code',(SELECT code FROM public.atina_v2_rooms WHERE id=NEW.room_id),'player_id',NEW.recipient_player_id),v_key)
    ON CONFLICT (dedupe_key) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS atina_notification_game_invite_event_trigger ON public.atina_game_invites;
CREATE TRIGGER atina_notification_game_invite_event_trigger AFTER INSERT OR UPDATE OF status ON public.atina_game_invites FOR EACH ROW EXECUTE FUNCTION public.atina_notification_game_invite_event();

REVOKE ALL ON FUNCTION public.atina_notification_list(text) FROM public;
REVOKE ALL ON FUNCTION public.atina_notification_mark_read(text,uuid) FROM public;
REVOKE ALL ON FUNCTION public.atina_notification_clear(text) FROM public;
REVOKE ALL ON FUNCTION public.atina_notification_friend_event() FROM public;
REVOKE ALL ON FUNCTION public.atina_notification_game_invite_event() FROM public;
GRANT EXECUTE ON FUNCTION public.atina_notification_list(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atina_notification_mark_read(text,uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.atina_notification_clear(text) TO anon, authenticated;