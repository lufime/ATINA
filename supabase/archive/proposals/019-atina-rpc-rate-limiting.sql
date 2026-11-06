-- ATINA per-IP rate limiting for all PostgREST RPCs named atina_*.
-- PostgREST invokes this hook before every Data API request; this function
-- deliberately ignores non-ATINA routes and non-ATINA RPCs.

CREATE TABLE IF NOT EXISTS private.atina_rpc_rate_limits (
  ip_hash bytea NOT NULL CHECK (octet_length(ip_hash)=32),
  rpc_name text NOT NULL CHECK (rpc_name ~ '^atina_[a-z0-9_]+$'),
  window_started_at timestamptz NOT NULL,
  request_count integer NOT NULL CHECK (request_count > 0),
  PRIMARY KEY (ip_hash,rpc_name)
);

ALTER TABLE private.atina_rpc_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.atina_rpc_rate_limits FROM public,anon,authenticated;
CREATE INDEX IF NOT EXISTS atina_rpc_rate_limits_window_idx
  ON private.atina_rpc_rate_limits(window_started_at);

CREATE OR REPLACE FUNCTION public.atina_pre_request_rate_limit()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $function$
DECLARE
  v_method text := upper(coalesce(current_setting('request.method',true),''));
  v_path text := coalesce(current_setting('request.path',true),'');
  v_headers jsonb;
  v_forwarded text;
  v_ip inet;
  v_ip_hash bytea;
  v_rpc text;
  v_limit integer;
  v_window timestamptz;
  v_count integer;
BEGIN
  -- The hook is global to PostgREST. Restrict its effect to ATINA RPCs.
  IF v_method NOT IN ('POST','PUT','PATCH','DELETE') THEN
    RETURN;
  END IF;
  IF v_path !~ '^/?rpc/(atina_[a-z0-9_]+)$' THEN
    RETURN;
  END IF;
  v_rpc := substring(v_path FROM '^/?rpc/(atina_[a-z0-9_]+)$');

  BEGIN
    v_headers := coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb;
    v_forwarded := btrim(split_part(coalesce(v_headers->>'x-forwarded-for',''),',',1));
    IF v_forwarded='' THEN
      RAISE invalid_text_representation;
    END IF;
    v_ip := v_forwarded::inet;
  EXCEPTION WHEN OTHERS THEN
    RAISE SQLSTATE 'PGRST'
      USING message=json_build_object(
        'code','ATINA_RATE_LIMIT_UNAVAILABLE',
        'message','Não foi possível validar a origem do pedido. Tenta novamente.'
      )::text,
      detail=json_build_object('status',503)::text;
  END;

  -- Hash the address: no raw IP addresses are retained in the rate-limit table.
  v_ip_hash := extensions.digest(convert_to(host(v_ip),'UTF8'),'sha256');

  -- Lobby creation/join and secret retrieval are especially sensitive.
  -- Room-state polling follows the existing 3-second client cadence.
  v_limit := CASE
    WHEN v_rpc IN ('atina_create_room','atina_join_room','atina_get_mime_secret') THEN 10
    WHEN v_rpc IN ('atina_room_state','atina_local_game_state') THEN 120
    ELSE 30
  END;
  v_window := date_trunc('minute',clock_timestamp());

  INSERT INTO private.atina_rpc_rate_limits(ip_hash,rpc_name,window_started_at,request_count)
  VALUES(v_ip_hash,v_rpc,v_window,1)
  ON CONFLICT(ip_hash,rpc_name) DO UPDATE
    SET window_started_at=EXCLUDED.window_started_at,
        request_count=CASE
          WHEN private.atina_rpc_rate_limits.window_started_at=EXCLUDED.window_started_at
            THEN private.atina_rpc_rate_limits.request_count+1
          ELSE 1
        END
  RETURNING request_count INTO v_count;

  IF v_count>v_limit THEN
    RAISE SQLSTATE 'PGRST'
      USING message=json_build_object(
        'code','ATINA_RATE_LIMIT',
        'message','Demasiados pedidos. Aguarda um minuto e tenta novamente.'
      )::text,
      detail=json_build_object(
        'status',429,
        'headers',json_build_object('Retry-After','60')
      )::text;
  END IF;

  -- Opportunistic bounded cleanup; the table keeps only one row per IP/RPC.
  IF random()<0.01 THEN
    DELETE FROM private.atina_rpc_rate_limits
    WHERE window_started_at<clock_timestamp()-interval '1 day';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.atina_pre_request_rate_limit() FROM public;
GRANT EXECUTE ON FUNCTION public.atina_pre_request_rate_limit() TO anon,authenticated;

-- Activate the hook only for this development project's PostgREST requests.
ALTER ROLE authenticator
  SET pgrst.db_pre_request='public.atina_pre_request_rate_limit';
NOTIFY pgrst,'reload config';
