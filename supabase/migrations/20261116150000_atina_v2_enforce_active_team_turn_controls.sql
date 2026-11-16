-- Only the team whose turn is active may reveal clues, pass, or advance.
-- Keep server authorization aligned with the multiplayer UI.

CREATE OR REPLACE FUNCTION public.atina_v2_reveal_room_clue(p_room_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_player public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_game private.atina_v2_room_game_state%rowtype;
  v_total integer;
  v_now timestamptz;
  v_state jsonb;
BEGIN
  SELECT * INTO v_player FROM public.atina_v2_room_players
  WHERE room_id=p_room_id
    AND token_hash=extensions.digest(coalesce(p_token,''),'sha256')
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;

  SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
  SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
  IF NOT FOUND OR v_game.status<>'active' OR v_game.round_locked THEN
    RAISE EXCEPTION 'A ronda não está ativa.';
  END IF;
  IF v_player.team_label IS NULL OR cardinality(v_game.team_order)=0
     OR v_player.team_label IS DISTINCT FROM v_game.team_order[v_game.active_team_index] THEN
    RAISE EXCEPTION 'Só a equipa que tem a vez pode revelar pistas.';
  END IF;
  v_now:=clock_timestamp();
  IF v_game.deadline_at IS NOT NULL AND v_game.deadline_at<=v_now THEN
    UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
    UPDATE public.atina_v2_rooms SET game_state=coalesce(private.atina_v2_room_public_state(p_room_id),'{}'::jsonb) || jsonb_build_object('feedback','Tempo esgotado.','locked',true),
      state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
    RETURN jsonb_build_object('status','timeout','state',private.atina_v2_room_public_state(p_room_id));
  END IF;

  SELECT jsonb_array_length(clues) INTO v_total
  FROM private.atina_challenges
  WHERE challenge_id=v_game.challenge_queue[v_game.position] AND active;
  IF v_game.revealed_clues>=v_total THEN
    RETURN jsonb_build_object('status','unchanged','state',private.atina_v2_room_public_state(p_room_id));
  END IF;

  UPDATE private.atina_v2_room_game_state
  SET revealed_clues=revealed_clues+1,updated_at=v_now
  WHERE room_id=p_room_id;
  v_state:=private.atina_v2_room_public_state(p_room_id);
  UPDATE public.atina_v2_rooms
  SET game_state=v_state,state_version=state_version+1,updated_at=v_now
  WHERE id=p_room_id;
  RETURN jsonb_build_object('status','revealed','state',v_state);
END;
$function$


CREATE OR REPLACE FUNCTION public.atina_v2_pass_room_challenge(p_room_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_player public.atina_v2_room_players%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_game private.atina_v2_room_game_state%rowtype;
 v_now timestamptz;
 v_state jsonb;
 v_status text;
BEGIN
 SELECT * INTO v_player FROM public.atina_v2_room_players
 WHERE room_id=p_room_id AND token_hash=extensions.digest(coalesce(p_token,''),'sha256') FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sessão da sala inválida.'; END IF;
 SELECT * INTO v_room FROM public.atina_v2_rooms WHERE id=p_room_id FOR UPDATE;
 SELECT * INTO v_game FROM private.atina_v2_room_game_state WHERE room_id=p_room_id FOR UPDATE;
 IF NOT FOUND OR v_game.status<>'active' THEN RAISE EXCEPTION 'A ronda não está ativa.'; END IF;
 IF (
   v_player.team_label IS NULL OR cardinality(v_game.team_order)=0
   OR v_player.team_label IS DISTINCT FROM v_game.team_order[v_game.active_team_index]
 ) THEN RAISE EXCEPTION 'Só a equipa que tem a vez pode passar este desafio.'; END IF;
 v_now:=clock_timestamp();
 v_status:=case when v_game.deadline_at is not null and v_game.deadline_at<=v_now then 'timeout' else 'passed' end;
 UPDATE private.atina_v2_room_game_state SET round_locked=true,updated_at=v_now WHERE room_id=p_room_id;
 v_state:=private.atina_v2_room_public_state(p_room_id)||jsonb_build_object('feedback',case when v_status='timeout' then 'Tempo esgotado.' else 'Desafio passado.' end,'locked',true);
 UPDATE public.atina_v2_rooms SET game_state=v_state,state_version=state_version+1,updated_at=v_now WHERE id=p_room_id;
 RETURN jsonb_build_object('status',v_status,'state',v_state);
END;
$function$


CREATE OR REPLACE FUNCTION public.atina_v2_next_room_challenge(p_room_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_player public.atina_v2_room_players%rowtype;
 v_room public.atina_v2_rooms%rowtype;
 v_game private.atina_v2_room_game_state%rowtype;
 v_now timestamptz;
 v_state jsonb;
 v_results jsonb;
 v_card jsonb;
 v_next_team integer;
begin
 select * into v_player from public.atina_v2_room_players where room_id=p_room_id
  and token_hash=extensions.digest(coalesce(p_token,''),'sha256') for update;
 if not found then raise exception 'Sessão da sala inválida.'; end if;
 select * into v_room from public.atina_v2_rooms where id=p_room_id for update;
 if not found or v_room.status<>'playing' then raise exception 'A partida não está ativa.'; end if;
 select * into v_game from private.atina_v2_room_game_state where room_id=p_room_id for update;
 if not found or v_game.status<>'active' then raise exception 'A ronda não está ativa.'; end if;
 IF (
   v_player.team_label is null or cardinality(v_game.team_order)=0
   or v_player.team_label is distinct from v_game.team_order[v_game.active_team_index]
 ) then raise exception 'Só a equipa que tem a vez pode avançar para o próximo desafio.'; end if;
 if not v_game.round_locked then raise exception 'Fecha o desafio antes de avançar.'; end if;
 v_now:=clock_timestamp();
 if v_game.position<cardinality(v_game.challenge_queue) then
  v_next_team:=v_game.active_team_index;
  if cardinality(v_game.team_order)>1 then
   v_next_team:=mod(v_game.active_team_index,cardinality(v_game.team_order))+1;
  end if;
  v_card:=null;
  if mod(v_game.position+1,3)=0 and cardinality(v_game.team_order)>1 then
   case floor(random()*9)::integer
    when 0 then v_card:=jsonb_build_object('id','double_points','name','PONTOS A DOBRAR','icon','💎','description','Duplica os pontos deste desafio se acertares.','multiplier',2);
    when 1 then v_card:=jsonb_build_object('id','speed_bonus','name','BÓNUS DE VELOCIDADE','icon','⚡','description','Recebes mais 10 pontos se acertares.','bonus',10);
    when 2 then v_card:=jsonb_build_object('id','correct_prize','name','PRÉMIO DE ACERTO','icon','🏆','description','Recebes 15 pontos extra se acertares.','bonus',15);
    when 3 then v_card:=jsonb_build_object('id','shield','name','ESCUDO','icon','🛡️','description','Anula a penalização se errares.');
    when 4 then v_card:=jsonb_build_object('id','reduced_penalty','name','PENALIZAÇÃO REDUZIDA','icon','➖','description','A penalização por erro passa de 10 para 5 pontos.');
    when 5 then v_card:=jsonb_build_object('id','bonus_clue','name','PISTA BÓNUS','icon','💡','description','Recebes imediatamente mais uma pista.');
    when 6 then v_card:=jsonb_build_object('id','extra_time','name','TEMPO EXTRA','icon','⏱️','description','Recebes mais 15 segundos neste desafio.');
    when 7 then v_card:=jsonb_build_object('id','pass_team','name','PASSAR A EQUIPA','icon','⏭️','description','A equipa que recebe esta carta perde a vez; o desafio é saltado.');
    else v_card:=jsonb_build_object('id','steal_turn','name','ROUBAR A VEZ','icon','🔄','description','A equipa seguinte assume imediatamente este desafio.');
   end case;
  end if;
  if v_card->>'id'='steal_turn' then
   v_next_team:=mod(v_next_team,cardinality(v_game.team_order))+1;
  end if;
  update private.atina_v2_room_game_state set position=position+1,active_team_index=v_next_team,
   team_turn_advanced=false,
   revealed_clues=case when v_card->>'id'='bonus_clue' then 2 else 1 end,
   round_locked=(v_card->>'id'='pass_team'),special_card=v_card,
   deadline_at=case when timed_mode_seconds=0 or v_card->>'id'='pass_team' then null
    else v_now+make_interval(secs=>timed_mode_seconds+case when v_card->>'id'='extra_time' then 15 else 0 end) end,
   updated_at=v_now where room_id=p_room_id;
  perform private.atina_record_room_challenge_exposure(p_room_id,v_game.challenge_queue[v_game.position+1]);
  v_state:=private.atina_v2_room_public_state(p_room_id);
  if v_card->>'id'='pass_team' then v_state:=v_state||jsonb_build_object('feedback','A carta PASSAR A EQUIPA saltou este desafio.','locked',true); end if;
  update public.atina_v2_rooms set game_state=v_state,state_version=state_version+1,updated_at=v_now where id=p_room_id;
  return jsonb_build_object('status','next','state',v_state);
 end if;
 update private.atina_v2_room_game_state set status='completed',round_locked=true,updated_at=v_now where room_id=p_room_id;
 insert into public.atina_v2_room_results(room_id,player_id,nickname,team_label,score,completed_at)
 select p.room_id,p.id,p.nickname,p.team_label,p.score,v_now from public.atina_v2_room_players p where p.room_id=p_room_id
 on conflict(room_id,player_id) do update set nickname=excluded.nickname,team_label=excluded.team_label,score=excluded.score,completed_at=excluded.completed_at;
 select coalesce(jsonb_agg(jsonb_build_object('player_id',r.player_id,'nickname',r.nickname,'team',r.team_label,'score',r.score) order by r.score desc,r.nickname),'[]'::jsonb)
 into v_results from public.atina_v2_room_results r where r.room_id=p_room_id;
 update public.atina_v2_rooms set status='completed',game_state=jsonb_build_object('mode','completed','protocol_version',1,
  'pos',cardinality(v_game.challenge_queue),'queue_length',cardinality(v_game.challenge_queue),'locked',true,'revision',state_version+1),
  state_version=state_version+1,updated_at=v_now where id=p_room_id;
 return jsonb_build_object('status','completed','results',v_results);
end;
$function$

