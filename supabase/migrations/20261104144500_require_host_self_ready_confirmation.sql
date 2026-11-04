-- O anfitrião também tem de confirmar explicitamente a sua entrada no jogo.
CREATE OR REPLACE FUNCTION public.atina_v2_create_room(p_nickname text, p_max_players integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_room public.atina_v2_rooms%rowtype;
  v_player public.atina_v2_room_players%rowtype;
  v_token text;
  v_code text;
  v_random bytea;
  v_byte integer;
  v_alphabet text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  v_i integer;
  v_attempt integer:=0;
BEGIN
  IF p_nickname IS NULL OR char_length(btrim(p_nickname)) NOT BETWEEN 1 AND 32 THEN
    RAISE EXCEPTION 'Pseudónimo inválido.';
  END IF;
  IF p_max_players IS NULL OR p_max_players NOT BETWEEN 2 AND 20 THEN
    RAISE EXCEPTION 'Número de jogadores inválido.';
  END IF;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  LOOP
    v_code := '';
    FOR v_i IN 1..10 LOOP
      LOOP
        v_random := extensions.gen_random_bytes(1);
        v_byte := get_byte(v_random,0);
        EXIT WHEN v_byte < 252;
      END LOOP;
      v_code := v_code || substr(v_alphabet,(v_byte % 36)+1,1);
    END LOOP;

    BEGIN
      INSERT INTO public.atina_v2_rooms(code,max_players)
      VALUES(v_code,p_max_players)
      RETURNING * INTO v_room;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      v_attempt:=v_attempt+1;
      IF v_attempt>=8 THEN
        RAISE EXCEPTION 'Não foi possível gerar um código de sala. Tenta novamente.';
      END IF;
    END;
  END LOOP;

  INSERT INTO public.atina_v2_room_players(room_id,token_hash,nickname,is_host,ready)
  VALUES(v_room.id,extensions.digest(v_token,'sha256'),btrim(p_nickname),true,false)
  RETURNING * INTO v_player;

  RETURN jsonb_build_object(
    'room_id',v_room.id,'token',v_token,'code',v_room.code,'player_id',v_player.id
  );
END;
$function$;
