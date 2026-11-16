do $migration$
declare
  v_def text;
  v_old text := $old$
     and not exists (
       select 1
         from (
           select h.challenge_id
             from private.atina_difficulty_history h
            where h.player_id=new.player_id
            order by h.created_at desc,h.id desc
            limit 20
         ) recent
        where recent.challenge_id=c.challenge_id
     )
$old$;
  v_new text := $new$
     and not exists (
       select 1
         from private.atina_challenge_exposures exposure
        where exposure.scope_type='player'
          and exposure.scope_key=new.player_id::text
          and exposure.challenge_id=c.challenge_id
     )
$new$;
begin
  v_def := pg_get_functiondef('private.atina_apply_adaptive_difficulty()'::regprocedure);
  v_def := replace(v_def,v_old,v_new);
  if position('exposure.scope_key=new.player_id::text' in v_def)=0 then
    raise exception 'Não foi possível alinhar a dificuldade adaptativa com o histórico de desafios expostos.';
  end if;
  execute v_def;
end
$migration$;
