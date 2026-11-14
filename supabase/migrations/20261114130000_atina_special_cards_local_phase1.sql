create or replace function public.atina_v2_local_next_challenge(p_session_id uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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
  if mod(v_next_position-1,3)=2 then
    v_roll:=floor(random()*3)::integer;
    v_card:=case v_roll
      when 0 then jsonb_build_object(
        'id','double_points','name','PONTOS A DOBRAR','icon','💎',
        'description','Duplica os pontos deste desafio se acertares.',
        'multiplier',2,'bonus',0)
      when 1 then jsonb_build_object(
        'id','speed_bonus','name','BÓNUS DE VELOCIDADE','icon','⚡',
        'description','Recebes mais 10 pontos se acertares.',
        'multiplier',1,'bonus',10)
      else jsonb_build_object(
        'id','correct_prize','name','PRÉMIO DE ACERTO','icon','🏆',
        'description','Recebes 15 pontos extra se acertares.',
        'multiplier',1,'bonus',15)
    end;
  end if;

  update private.atina_v2_local_sessions
     set position=v_next_position,current_player=v_session.current_player,
         revealed_clues=1,round_locked=false,
         deadline_at=case when timed_mode_seconds=0 then null
           else v_now+make_interval(secs=>timed_mode_seconds) end,
         special_card=v_card,last_result='{}'::jsonb,updated_at=v_now
   where id=v_session.id returning * into v_session;

  select o.player_id into v_player_id
    from private.atina_xp_session_owners o where o.session_id=v_session.id;
  if v_player_id is not null then
    insert into private.atina_challenge_exposures(scope_type,scope_key,challenge_id)
    values('player',v_player_id::text,v_session.challenge_queue[v_next_position])
    on conflict(scope_type,scope_key,challenge_id) do nothing;
  end if;

  return private.atina_v2_local_public_state(v_session);
end;
$function$;
