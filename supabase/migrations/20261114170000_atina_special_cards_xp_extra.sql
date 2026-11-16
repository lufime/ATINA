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

  -- The live account progression API is atina_progress_claim_local.
  -- Grant the XP card only after a correct answer, alongside normal daily bonuses.
  v_def := pg_get_functiondef('public.atina_progress_claim_local(text,uuid,text,integer)'::regprocedure);
  v_def := replace(v_def,
    '  v_milestone_bonus integer := 0;',
    '  v_milestone_bonus integer := 0;'||chr(10)||'  v_special_bonus integer := 0;');
  v_def := replace(v_def,
    '  update private.atina_players'||chr(10)||
    '     set total_xp=total_xp+v_xp+v_daily_bonus+v_mission_bonus+v_streak_bonus+'||
    '                  v_category_bonus+v_hard_bonus+v_milestone_bonus,',
    '  v_special_bonus:=case when v_outcome=''correct'' and v_session.special_card->>''id''=''xp_extra'' then 10 else 0 end;'||chr(10)||
    '  update private.atina_players'||chr(10)||
    '     set total_xp=total_xp+v_xp+v_daily_bonus+v_mission_bonus+v_streak_bonus+'||
    'v_category_bonus+v_hard_bonus+v_milestone_bonus+v_special_bonus,');
  v_def := replace(v_def,
    '''bonus_total'',v_daily_bonus+v_mission_bonus+v_streak_bonus+v_category_bonus+v_hard_bonus+v_milestone_bonus,',
    '''bonus_total'',v_daily_bonus+v_mission_bonus+v_streak_bonus+v_category_bonus+v_hard_bonus+v_milestone_bonus+v_special_bonus,'||chr(10)||
    '    ''special_card_bonus'',v_special_bonus,');
  if position('v_special_bonus' in v_def)=0
     or position('special_card_bonus' in v_def)=0
     or position('v_session.special_card' in v_def)=0 then
    raise exception 'Não foi possível integrar o bónus de XP na progressão da conta.';
  end if;
  execute v_def;
end
$migration$;