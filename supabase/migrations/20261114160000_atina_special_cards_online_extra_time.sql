do $migration$
declare
  v_def text;
  v_old text;
begin
  v_def := pg_get_functiondef('public.atina_v2_next_room_challenge(uuid,text)'::regprocedure);
  v_def := replace(v_def, 'floor(random()*6)::integer', 'floor(random()*7)::integer');
  v_old := $old$      else v_card:=jsonb_build_object('id','bonus_clue','name','PISTA BÓNUS','icon','💡','description','Recebes imediatamente mais uma pista.');
    end case;$old$;
  v_def := replace(v_def, v_old, $new$      when 5 then v_card:=jsonb_build_object('id','bonus_clue','name','PISTA BÓNUS','icon','💡','description','Recebes imediatamente mais uma pista.');
      else v_card:=jsonb_build_object('id','extra_time','name','TEMPO EXTRA','icon','⏱️','description','Recebes mais 15 segundos neste desafio.');
    end case;$new$);
  if position('random()*7' in v_def)=0 or position('' || quote_literal('extra_time') || '' in v_def)=0 then
    raise exception 'Não foi possível ativar a carta Tempo Extra no Multi.';
  end if;
  execute v_def;
end
$migration$;