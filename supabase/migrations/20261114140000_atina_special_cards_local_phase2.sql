do $migration$
declare
  v_def text;
  v_old text;
begin
  -- Expandir a seleção automática de cartas e aplicar efeitos de apoio no servidor.
  v_def := pg_get_functiondef('public.atina_v2_local_next_challenge(uuid,text)'::regprocedure);
  v_def := replace(v_def, 'v_roll:=floor(random()*3)::integer;', 'v_roll:=floor(random()*8)::integer;');
  v_old := $old$  v_card:=case v_roll
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
    end;$old$;
  v_def := replace(v_def, v_old, $new$  v_card:=case v_roll
      when 0 then jsonb_build_object('id','double_points','name','PONTOS A DOBRAR','icon','💎','description','Duplica os pontos deste desafio se acertares.','multiplier',2,'bonus',0)
      when 1 then jsonb_build_object('id','speed_bonus','name','BÓNUS DE VELOCIDADE','icon','⚡','description','Recebes mais 10 pontos se acertares.','multiplier',1,'bonus',10)
      when 2 then jsonb_build_object('id','correct_prize','name','PRÉMIO DE ACERTO','icon','🏆','description','Recebes 15 pontos extra se acertares.','multiplier',1,'bonus',15)
      when 3 then jsonb_build_object('id','shield','name','ESCUDO','icon','🛡️','description','Anula a penalização se errares ou o tempo terminar.')
      when 4 then jsonb_build_object('id','reduced_penalty','name','PENALIZAÇÃO REDUZIDA','icon','➖','description','A penalização por erro ou tempo esgotado passa de 10 para 5 pontos.')
      when 5 then jsonb_build_object('id','protected_streak','name','SEQUÊNCIA PROTEGIDA','icon','🔥','description','Mantém a tua sequência mesmo que falhes.')
      when 6 then jsonb_build_object('id','bonus_clue','name','PISTA BÓNUS','icon','💡','description','Recebes imediatamente mais uma pista.')
      else jsonb_build_object('id','extra_time','name','TEMPO EXTRA','icon','⏱️','description','Recebes mais 15 segundos neste desafio.')
    end;$new$);
  v_def := replace(v_def, 'revealed_clues=1,round_locked=false,', 'revealed_clues=case when v_card->>''id''=''bonus_clue'' then 2 else 1 end,round_locked=false,');
  v_def := replace(v_def, 'v_now+make_interval(secs=>timed_mode_seconds) end,', 'v_now+make_interval(secs=>timed_mode_seconds + case when v_card->>''id''=''extra_time'' then 15 else 0 end) end,');
  if position('protected_streak' in v_def)=0 or position('bonus_clue' in v_def)=0 or position('extra_time' in v_def)=0 then
    raise exception 'Não foi possível atualizar a seleção das cartas.';
  end if;
  execute v_def;

  -- Erro ou timeout: escudo anula a penalização; penalização reduzida aplica -5;
  -- sequência protegida mantém a sequência atual.
  v_def := pg_get_functiondef('public.atina_v2_local_submit_answer(uuid,text,text)'::regprocedure);
  v_def := replace(v_def, 'v_round integer;', 'v_round integer;'||chr(10)||'  v_penalty integer:=10;'||chr(10)||'  v_protect_streak boolean:=false;');
  v_def := replace(v_def, 'v_round:=v_session.answered_count+1;', 'v_round:=v_session.answered_count+1;'||chr(10)||'  v_penalty:=case v_session.special_card->>''id'' when ''shield'' then 0 when ''reduced_penalty'' then 5 else 10 end;'||chr(10)||'  v_protect_streak:=coalesce(v_session.special_card->>''id''=''protected_streak'',false);');
  v_def := replace(v_def, 'v_session.scores[v_session.current_player]:=v_session.scores[v_session.current_player]-10;', 'v_session.scores[v_session.current_player]:=v_session.scores[v_session.current_player]-v_penalty;');
  v_def := replace(v_def, 'v_session.streaks[v_session.current_player]:=0;', 'if not v_protect_streak then v_session.streaks[v_session.current_player]:=0; end if;');
  v_def := replace(v_def, '''penalty'',10', '''penalty'',v_penalty');
  v_def := replace(v_def, '''timeout'',-10', '''timeout'',-v_penalty');
  v_def := replace(v_def, '''wrong'',-10', '''wrong'',-v_penalty');
  if position('v_penalty' in v_def)=0 or position('v_protect_streak' in v_def)=0 then
    raise exception 'Não foi possível atualizar as penalizações.';
  end if;
  execute v_def;

  -- Timeout ao passar também respeita escudo, penalização reduzida e sequência protegida.
  -- Esta versão-base não declara v_round/v_challenge; inserir as variáveis no DECLARE
  -- e aplicar os efeitos diretamente ao ramo de timeout.
  v_def := pg_get_functiondef('public.atina_v2_local_pass_challenge(uuid,text)'::regprocedure);
  v_def := replace(v_def,
    'v_session private.atina_v2_local_sessions;',
    'v_session private.atina_v2_local_sessions;'||chr(10)||'  v_penalty integer:=10;'||chr(10)||'  v_protect_streak boolean:=false;');
  v_def := replace(v_def,
    '  if v_session.status <> ''active'' or v_session.round_locked then',
    '  v_penalty:=case v_session.special_card->>''id'' when ''shield'' then 0 when ''reduced_penalty'' then 5 else 10 end;'||chr(10)||
    '  v_protect_streak:=v_session.special_card->>''id''=''protected_streak'';'||chr(10)||
    '  if v_session.status <> ''active'' or v_session.round_locked then');
  v_def := replace(v_def,
    'v_session.scores[v_session.current_player]-10;',
    'v_session.scores[v_session.current_player]-v_penalty;');
  v_def := replace(v_def,
    'v_session.streaks[v_session.current_player] := 0;',
    'if not v_protect_streak then v_session.streaks[v_session.current_player] := 0; end if;');
  v_def := replace(v_def,
    '''outcome'',''timeout'',''penalty'',10',
    '''outcome'',''timeout'',''penalty'',v_penalty');
  if position('v_penalty integer' in v_def)=0
     or position('v_protect_streak boolean' in v_def)=0
     or position('v_penalty:=' in v_def)=0
     or position('v_session.scores[v_session.current_player]-v_penalty' in v_def)=0 then
    raise exception 'Não foi possível atualizar o timeout ao passar.';
  end if;
  execute v_def;
end
$migration$;