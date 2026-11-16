do $migration$
declare
  v_def text;
begin
  v_def := pg_get_functiondef('public.atina_progress_claim_local(text,uuid,text,integer)'::regprocedure);
  if position('special_card_bonus' in v_def) > 0 then
    return;
  end if;

  v_def := replace(v_def,
    '  v_milestone_bonus integer := 0;',
    '  v_milestone_bonus integer := 0;'||chr(10)||'  v_special_bonus integer := 0;');
  v_def := replace(v_def,
    '  update private.atina_players',
    '  v_special_bonus:=case when v_outcome=''correct'' and v_session.special_card->>''id''=''xp_extra'' then 10 else 0 end;'||chr(10)||
    '  update private.atina_players');
  v_def := replace(v_def,
    'v_milestone_bonus,',
    'v_milestone_bonus+v_special_bonus,');
  v_def := replace(v_def,
    '''bonus_total'',',
    '''special_card_bonus'',v_special_bonus,''bonus_total'',');
  if position('v_special_bonus' in v_def)=0
     or position('special_card_bonus' in v_def)=0
     or position('v_session.special_card' in v_def)=0 then
    raise exception 'Não foi possível integrar o bónus XP Extra na progressão da conta.';
  end if;
  execute v_def;
end
$migration$;
