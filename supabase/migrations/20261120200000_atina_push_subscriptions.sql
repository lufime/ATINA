-- Push subscriptions: authenticated via ATINA session token (not browser auth)
CREATE TABLE IF NOT EXISTS public.atina_push_subscriptions (id uuid primary key default extensions.gen_random_uuid(),player_id uuid not null,endpoint text not null unique,subscription jsonb not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
CREATE INDEX IF NOT EXISTS atina_push_subscriptions_player_idx ON public.atina_push_subscriptions(player_id);
ALTER TABLE public.atina_push_subscriptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.atina_push_subscriptions FROM public, anon, authenticated;
CREATE OR REPLACE FUNCTION public.atina_push_subscription_save(p_session_token text,p_subscription jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_player uuid; v_endpoint text; BEGIN v_player:=private.atina_social_player_from_session(p_session_token); v_endpoint:=p_subscription->>'endpoint'; IF v_endpoint IS NULL OR length(v_endpoint)>2048 OR p_subscription->'keys'->>'p256dh' IS NULL OR p_subscription->'keys'->>'auth' IS NULL THEN RAISE EXCEPTION 'Subscrição Push inválida.'; END IF; INSERT INTO public.atina_push_subscriptions(player_id,endpoint,subscription,updated_at) VALUES(v_player,v_endpoint,p_subscription,now()) ON CONFLICT(endpoint) DO UPDATE SET player_id=excluded.player_id,subscription=excluded.subscription,updated_at=now(); RETURN jsonb_build_object('ok',true); END; $function$;
CREATE OR REPLACE FUNCTION public.atina_push_subscription_remove(p_session_token text,p_endpoint text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $function$
DECLARE v_player uuid; v_count int; BEGIN v_player:=private.atina_social_player_from_session(p_session_token); DELETE FROM public.atina_push_subscriptions WHERE player_id=v_player AND endpoint=p_endpoint; GET DIAGNOSTICS v_count=ROW_COUNT; RETURN jsonb_build_object('ok',true,'removed',v_count); END; $function$;
REVOKE ALL ON FUNCTION public.atina_push_subscription_save(text,jsonb) FROM public;
REVOKE ALL ON FUNCTION public.atina_push_subscription_remove(text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.atina_push_subscription_save(text,jsonb) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_push_subscription_remove(text,text) TO anon,authenticated;