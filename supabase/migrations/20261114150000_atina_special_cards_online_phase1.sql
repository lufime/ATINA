alter table private.atina_v2_room_game_state
  add column if not exists special_card jsonb;

do $migration$
declare
  v_def text;
begin
  -- Seleção automática de carta nas posições 3, 6, 9... da partida online.
  v_def := pg_get_functiondef('public.atina_v2_next_room_challenge(uuid,text)'::regprocedure);
  v_def := replace(v_def, '  v_results jsonb;', '  v_results jsonb;'||chr(10)||'  v_card jsonb;');
  v_def := replace(v_def, '  v_now:=clock_timestamp();', '  v_now:=clock_timestamp();'||chr(10)||
    '  v_card:=null;'||chr(10)||
    '  if mod(v_game.position,3)=0 then'||chr(10)||
    '    case floor(random()*6)::integer'||chr(10)||
    '      when 0 then v_card:=jsonb_build_object(''id'',''double_points'',''name'',''PONTOS A DOBRAR'',''icon'',''💎'',''description'',''Duplica os pontos deste desafio se acertares.'',''multiplier'',2,''bonus'',0);'||chr(10)||
    '      when 1 then v_card:=jsonb_build_object(''id'',''speed_bonus'',''name'',''BÓNUS DE VELOCIDADE'',''icon'',''⚡'',''description'',''Recebes mais 10 pontos se acertares.'',''multiplier'',1,''bonus'',10);'||chr(10)||
    '      when 2 then v_card:=jsonb_build_object(''id'',''correct_prize'',''name'',''PRÉMIO DE ACERTO'',''icon'',''🏆'',''description'',''Recebes 15 pontos extra se acertares.'',''multiplier'',1,''bonus'',15);'||chr(10)||
    '      when 3 then v_card:=jsonb_build_object(''id'',''shield'',''name'',''ESCUDO'',''icon'',''🛡️'',''description'',''Anula a penalização se errares.'');'||chr(10)||
    '      when 4 then v_card:=jsonb_build_object(''id'',''reduced_penalty'',''name'',''PENALIZAÇÃO REDUZIDA'',''icon'',''➖'',''description'',''A penalização por erro passa de 10 para 5 pontos.'');'||chr(10)||
    '      else v_card:=jsonb_build_object(''id'',''bonus_clue'',''name'',''PISTA BÓNUS'',''icon'',''💡'',''description'',''Recebes imediatamente mais uma pista.'');'||chr(10)||
    '    end case;'||chr(10)||
    '  end if;');
  v_def := replace(v_def,
    'set position=position+1,revealed_clues=1,round_locked=false,',
    'set position=position+1,revealed_clues=case when v_card->>''id''=''bonus_clue'' then 2 else 1 end,round_locked=false,special_card=v_card,');
  v_def := replace(v_def,
    'else v_now+make_interval(secs=>timed_mode_seconds) end,',
    'else v_now+make_interval(secs=>timed_mode_seconds + case when v_card->>''id''=''extra_time'' then 15 else 0 end) end,');
  if position('v_card:=null' in v_def)=0 or position('special_card=v_card' in v_def)=0 then
    raise exception 'Não foi possível integrar as cartas na progressão online.';
  end if;
  execute v_def;

  -- Expor apenas os dados públicos da carta no estado da sala.
  v_def := pg_get_functiondef('private.atina_v2_room_public_state(uuid)'::regprocedure);
  v_def := replace(v_def,
    '''revealed'',v_game.revealed_clues,''timedMode'',v_game.timed_mode_seconds,',
    '''revealed'',v_game.revealed_clues,''special_card'',v_game.special_card,''timedMode'',v_game.timed_mode_seconds,');
  if position('special_card' in v_def)=0 then
    raise exception 'Não foi possível expor a carta no estado público.';
  end if;
  execute v_def;

  -- Aplicar multiplicadores, prémios e proteções na validação central da resposta.
  v_def := pg_get_functiondef('public.atina_v2_submit_room_answer(uuid,text,text)'::regprocedure);
  v_def := replace(v_def,
    'v_prior_correct boolean; v_state jsonb;',
    'v_prior_correct boolean; v_state jsonb; v_multiplier integer:=1; v_bonus integer:=0; v_penalty integer:=10;');
  v_def := replace(v_def,
    'v_correct:=private.atina_v2_challenge_answer_matches(v_game.challenge_queue[v_game.position],btrim(p_answer));',
    'v_correct:=private.atina_v2_challenge_answer_matches(v_game.challenge_queue[v_game.position],btrim(p_answer));'||chr(10)||
    '  v_multiplier:=coalesce((v_game.special_card->>''multiplier'')::integer,1);'||chr(10)||
    '  v_bonus:=coalesce((v_game.special_card->>''bonus'')::integer,0);'||chr(10)||
    '  v_penalty:=case v_game.special_card->>''id'' when ''shield'' then 0 when ''reduced_penalty'' then 5 else 10 end;');
  v_def := replace(v_def,
    'v_points:=v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END;',
    'v_points:=(v_base+CASE WHEN v_game.timed_mode_seconds>0 THEN v_speed ELSE 0 END)*v_multiplier+v_bonus;');
  v_def := replace(v_def, 'score=greatest(0,score-10)', 'score=greatest(0,score-v_penalty)');
  v_def := replace(v_def, 'CASE WHEN v_correct THEN 0 ELSE 10 END', 'CASE WHEN v_correct THEN 0 ELSE v_penalty END');
  if position('v_multiplier' in v_def)=0 or position('v_penalty' in v_def)=0 then
    raise exception 'Não foi possível integrar os efeitos das cartas na pontuação online.';
  end if;
  execute v_def;
end
$migration$;