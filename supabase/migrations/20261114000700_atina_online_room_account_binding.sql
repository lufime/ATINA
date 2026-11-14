-- Bind each online-room participant to a verified ATINA account on their own device.
ALTER TABLE public.atina_v2_room_players ADD COLUMN IF NOT EXISTS account_player_id uuid REFERENCES private.atina_players(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS atina_v2_room_players_account_unique ON public.atina_v2_room_players(room_id,account_player_id) WHERE account_player_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.atina_v2_create_room(p_nickname text, p_max_players integer, p_session_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_room public.atina_v2_rooms%rowtype; v_player public.atina_v2_room_players%rowtype;
 v_account_player_id uuid; v_token text; v_code text; v_attempt integer:=0;
begin
 if p_session_token is null or p_session_token !~ '^[0-9a-f]{64}$' then raise exception 'Inicia sessão na tua conta ATINA.' using errcode='28000'; end if;
 select a.player_id into v_account_player_id from private.atina_player_accounts a where a.session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256') and a.session_expires_at>clock_timestamp() and a.nickname_normalized=lower(btrim(p_nickname));
 if v_account_player_id is null then raise exception 'A conta ATINA e o pseudónimo da sala não correspondem.' using errcode='28000'; end if;
 if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 32 then raise exception 'Pseudónimo inválido.'; end if;
 if p_max_players is null or p_max_players not between 2 and 20 then raise exception 'Número de jogadores inválido.'; end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 loop
  v_code:=upper(substr(encode(extensions.gen_random_bytes(8),'hex'),1,6));
  begin
   insert into public.atina_v2_rooms(code,max_players) values(v_code,p_max_players) returning * into v_room;
   exit;
  exception when unique_violation then
   v_attempt:=v_attempt+1;
   if v_attempt>=8 then raise exception 'Não foi possível gerar um código de sala. Tenta novamente.'; end if;
  end;
 end loop;
 insert into public.atina_v2_room_players(room_id,token_hash,nickname,is_host,ready,account_player_id)
 values(v_room.id,extensions.digest(v_token,'sha256'),btrim(p_nickname),true,true,v_account_player_id)
 returning * into v_player;
 return jsonb_build_object('room_id',v_room.id,'token',v_token,'code',v_room.code,'player_id',v_player.id);
end;
$function$;

CREATE OR REPLACE FUNCTION public.atina_v2_join_room(p_nickname text, p_code text, p_session_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_room public.atina_v2_rooms%rowtype; v_player public.atina_v2_room_players%rowtype;
 v_account_player_id uuid; v_token text;
begin
 if p_session_token is null or p_session_token !~ '^[0-9a-f]{64}$' then raise exception 'Inicia sessão na tua conta ATINA.' using errcode='28000'; end if;
 select a.player_id into v_account_player_id from private.atina_player_accounts a where a.session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256') and a.session_expires_at>clock_timestamp() and a.nickname_normalized=lower(btrim(p_nickname));
 if v_account_player_id is null then raise exception 'A conta ATINA e o pseudónimo da sala não correspondem.' using errcode='28000'; end if;
 if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 32 then raise exception 'Pseudónimo inválido.'; end if;
 if p_code is null or p_code !~ '^[A-Za-z0-9]{6}$' then raise exception 'Código de sala inválido.'; end if;
 select * into v_room from public.atina_v2_rooms where code=upper(p_code) for update;
 if not found or v_room.status<>'waiting' then raise exception 'Sala não encontrada ou já iniciada.'; end if;
 if (select count(*) from public.atina_v2_room_players where room_id=v_room.id)>=v_room.max_players then raise exception 'A sala está cheia.'; end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.atina_v2_room_players(room_id,token_hash,nickname,is_host,ready,account_player_id)
 values(v_room.id,extensions.digest(v_token,'sha256'),btrim(p_nickname),false,false,v_account_player_id)
 returning * into v_player;
 return jsonb_build_object('room_id',v_room.id,'token',v_token,'code',v_room.code,'player_id',v_player.id);
end;
$function$;

REVOKE ALL ON FUNCTION public.atina_v2_create_room(text,integer,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.atina_v2_join_room(text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.atina_v2_create_room(text,integer,text) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.atina_v2_join_room(text,text,text) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.atina_v2_create_room(text,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.atina_v2_join_room(text,text) FROM PUBLIC,anon,authenticated;
