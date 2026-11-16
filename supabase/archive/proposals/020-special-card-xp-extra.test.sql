begin;
select plan(3);
select ok(position('xp_extra' in pg_get_functiondef('public.atina_v2_local_next_challenge(uuid,text)'::regprocedure)) > 0,
  'A seleção local de cartas inclui XP Extra');
select ok(position('v_special_bonus' in pg_get_functiondef('public.atina_progress_claim_local(text,uuid,text,integer)'::regprocedure)) > 0,
  'A progressão da conta calcula o bónus especial de XP');
select ok(position('special_card_bonus' in pg_get_functiondef('public.atina_progress_claim_local(text,uuid,text,integer)'::regprocedure)) > 0,
  'A resposta da progressão reporta o bónus especial de XP');
select * from finish();
rollback;
