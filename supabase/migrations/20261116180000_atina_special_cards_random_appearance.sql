-- Regista no repositório a alteração já aplicada no projeto Supabase.
-- As cartas são sorteadas independentemente em cada avanço, com 20% de probabilidade.

CREATE OR REPLACE FUNCTION public.atina_v2_local_next_challenge(p_session_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_session private.atina_v2_local_sessions;
  v_next_position integer;
  v_card jsonb;
  v_now timestamptz;
  v_player_id uuid;
  v_roll integer;
begin
  select * into v_session
    from private.atina_v2_local_sessions
   where id=p_session_id
     and token_hash=extensions.digest(convert_to(p_token,'UTF8'),'sha256')
   for update;
  if not found then raise exception 'Sessão inválida ou expirada.' using errcode='28000'; end if;
  v_now:=clock_timestamp();
  if v_session.expires_at<=v_now then raise exception 'Sessão inválida ou expirada.' using errcode='28000'; end if;
  if v_session.status<>'active' or not v_session.round_locked then
    raise exception 'Fecha a ronda antes de avançar.' using errcode='55000';
  end if;
  v_next_position:=v_session.position+1;
  if v_next_position>cardinality(v_session.challenge_queue) then
    update private.atina_v2_local_sessions
       set status='completed',round_locked=true,deadline_at=null,updated_at=v_now
     where id=v_session.id returning * into v_session;
    return private.atina_v2_local_public_state(v_session);
  end if;
  if v_session.game_mode in ('duel','party') then
    v_session.current_player:=3-v_session.current_player;
  else
    v_session.current_player:=1;
  end if;
  v_card:=null;
  -- Sorteio independente por desafio: 20% de probabilidade de aparecer uma carta.
  if random() < 0.20 then
    v_roll:=floor(random()*9)::integer;
    v_card:=case v_roll
      when 0 then jsonb_build_object('id','double_points','name','PONTOS A DOBRAR','icon','💎','description','Multiplica por 3 os pontos deste desafio se acertares.','multiplier',3,'bonus',0)
      when 1 then jsonb_build_object('id','speed_bonus','name','BÓNUS DE VELOCIDADE','icon','⚡','description','Recebes mais 25 pontos se acertares.','multiplier',1,'bonus',25)
      when 2 then jsonb_build_object('id','correct_prize','name','PRÉMIO DE ACERTO','icon','🏆','description','Recebes 40 pontos extra se acertares.','multiplier',1,'bonus',40)
      when 3 then jsonb_build_object('id','shield','name','ESCUDO','icon','🛡️','description','Anula a penalização se errares ou o tempo terminar.')
      when 4 then jsonb_build_object('id','reduced_penalty','name','PENALIZAÇÃO REDUZIDA','icon','➖','description','A penalização por erro ou tempo esgotado passa de 10 para 5 pontos.')
      when 5 then jsonb_build_object('id','protected_streak','name','SEQUÊNCIA PROTEGIDA','icon','🔥','description','Mantém a tua sequência mesmo que falhes.')
      when 6 then jsonb_build_object('id','bonus_clue','name','PISTA BÓNUS','icon','💡','description','Recebes imediatamente mais uma pista.')
      when 7 then jsonb_build_object('id','extra_time','name','TEMPO EXTRA','icon','⏱️','description','Recebes mais 30 segundos neste desafio.')
      else jsonb_build_object('id','xp_extra','name','XP EXTRA','icon','✨','description','Recebes mais 25 XP adicionais se acertares.')
    end;
  end if;
  update private.atina_v2_local_sessions
     set position=v_next_position,current_player=v_session.current_player,
         revealed_clues=0,round_locked=false,
         deadline_at=null,
         special_card=v_card,last_result='{}'::jsonb,updated_at=v_now
   where id=v_session.id returning * into v_session;
  select o.player_id into v_player_id from private.atina_xp_session_owners o where o.session_id=v_session.id;
  if v_player_id is not null then
    insert into private.atina_challenge_exposures(scope_type,scope_key,challenge_id)
    values('player',v_player_id::text,v_session.challenge_queue[v_next_position])
    on conflict(scope_type,scope_key,challenge_id) do nothing;
  end if;
  return private.atina_v2_local_public_state(v_session);
end;
$function$;

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
  -- Sorteio independente por desafio: 20% de probabilidade de aparecer uma carta.
  if random() < 0.20 and cardinality(v_game.team_order)>1 then
   case floor(random()*9)::integer
    when 0 then v_card:=jsonb_build_object('id','double_points','name','PONTOS A DOBRAR','icon','💎','description','Multiplica por 3 os pontos deste desafio se acertares.','multiplier',3);
    when 1 then v_card:=jsonb_build_object('id','speed_bonus','name','BÓNUS DE VELOCIDADE','icon','⚡','description','Recebes mais 25 pontos se acertares.','bonus',25);
    when 2 then v_card:=jsonb_build_object('id','correct_prize','name','PRÉMIO DE ACERTO','icon','🏆','description','Recebes 40 pontos extra se acertares.','bonus',40);
    when 3 then v_card:=jsonb_build_object('id','shield','name','ESCUDO','icon','🛡️','description','Anula a penalização se errares.');
    when 4 then v_card:=jsonb_build_object('id','reduced_penalty','name','PENALIZAÇÃO REDUZIDA','icon','➖','description','A penalização por erro passa de 10 para 5 pontos.');
    when 5 then v_card:=jsonb_build_object('id','bonus_clue','name','PISTA BÓNUS','icon','💡','description','Recebes imediatamente mais uma pista.');
    when 6 then v_card:=jsonb_build_object('id','extra_time','name','TEMPO EXTRA','icon','⏱️','description','Recebes mais 30 segundos neste desafio.');
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
    else v_now+make_interval(secs=>timed_mode_seconds+case when v_card->>'id'='extra_time' then 30 else 0 end) end,
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
$function$;
