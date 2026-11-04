CREATE OR REPLACE FUNCTION public.atina_v2_set_room_team(
  p_room_id uuid,
  p_token text,
  p_player_id uuid,
  p_team text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_host public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
BEGIN
  SELECT * INTO v_host
  FROM public.atina_v2_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;

  IF NOT FOUND OR NOT v_host.is_host THEN
    RAISE EXCEPTION 'Só o anfitrião pode atribuir equipas.';
  END IF;

  SELECT * INTO v_room
  FROM public.atina_v2_rooms
  WHERE id=p_room_id
  FOR UPDATE;

  IF NOT FOUND OR v_room.status<>'waiting' THEN
    RAISE EXCEPTION 'As equipas já não podem ser alteradas.';
  END IF;

  IF p_team IS NULL OR btrim(p_team)='' THEN
    UPDATE public.atina_v2_room_players
    SET team_label=NULL, ready=false, last_seen_at=clock_timestamp()
    WHERE room_id=p_room_id AND id=p_player_id;
  ELSE
    IF char_length(btrim(p_team))>32 THEN
      RAISE EXCEPTION 'Nome de equipa demasiado longo.';
    END IF;
    UPDATE public.atina_v2_room_players
    SET team_label=btrim(p_team), ready=false, last_seen_at=clock_timestamp()
    WHERE room_id=p_room_id AND id=p_player_id;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Jogador não encontrado nesta sala.';
  END IF;

  RETURN jsonb_build_object(
    'player_id',p_player_id,
    'team',nullif(btrim(coalesce(p_team,'')),'')
  );
END;
$function$;
