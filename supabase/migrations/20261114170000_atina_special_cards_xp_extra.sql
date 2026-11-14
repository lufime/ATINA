do $migration$
declare
  v_def text;
  v_old text;
begin
  v_def := pg_get_functiondef('public.atina_v2_local_next_challenge(uuid,text)'::regprocedure);
  v_def := replace(v_def, 'floor(random()*8)::integer', 'floor(random()*9)::integer');
  v_old := $old$      else jsonb_build_object('id','extra_time','name','TEMPO EXTRA','icon','⏱️','description','Recebes mais 15 segundos neste desafio.')
    end;$old$;
  v_def := replace(v_def, v_old, $new$      when 7 then jsonb_build_object('id','extra_time','name','TEMPO EXTRA','icon','⏱️','description','Recebes mais 15 segundos neste desafio.')
      else jsonb_build_object('id','xp_extra','name','XP EXTRA','icon','✨','description','Recebes mais 10 XP adicionais se acertares.')
    end;$new$);
  if position('random()*9' in v_def)=0 or position('xp_extra' in v_def)=0 then
    raise exception 'Não foi possível acrescentar XP Extra ao conjunto local de cartas.';
  end if;
  execute v_def;

  v_def := pg_get_functiondef('public.atina_v2_record_local_progress(uuid,text)'::regprocedure);
  v_def := replace(v_def,
    '  if v_player.daily_count >= 3 and v_player.rewarded_date is distinct from v_today then'||chr(10)||
    '    v_points := 60;'||chr(10)||
    '    v_player.rewarded_date := v_today;'||chr(10)||
    '  end if;',
    '  if v_player.daily_count >= 3 and v_player.rewarded_date is distinct from v_today then'||chr(10)||
    '    v_points := 60;'||chr(10)||
    '    v_player.rewarded_date := v_today;'||chr(10)||
    '  end if;'||chr(10)||
    '  if v_session.special_card->>''id'' = ''xp_extra'' then'||chr(10)||
    '    v_points := v_points + 10;'||chr(10)||
    '  end if;');
  if position('v_points := v_points + 10' in v_def)=0 then
    raise exception 'Não foi possível integrar o bónus de XP.';
  end if;
  execute v_def;
end
$migration$;