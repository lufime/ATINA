-- Add verified Portuguese/international film-title variants to exact challenges.
do $$
declare
  v_item record;
begin
  for v_item in
    select * from (values
      (659, 'Back to the Future'),
      (660, 'Parque Jurássico'),
      (674, 'Frozen: O Reino do Gelo')
    ) as aliases(challenge_id, alias)
  loop
    update private.atina_challenges c
       set accepted_answers = case
         when jsonb_typeof(c.accepted_answers) = 'array' then c.accepted_answers
         else '[]'::jsonb
       end || jsonb_build_array(v_item.alias)
     where c.challenge_id = v_item.challenge_id
       and c.active
       and not exists (
         select 1
         from jsonb_array_elements_text(
           case when jsonb_typeof(c.accepted_answers) = 'array'
                then c.accepted_answers else '[]'::jsonb end
         ) accepted(value)
         where private.atina_v2_normalize_answer(accepted.value)
             = private.atina_v2_normalize_answer(v_item.alias)
       );
  end loop;
end;
$$;

do $tests$
begin
  if exists (select 1 from private.atina_challenges where challenge_id = 659 and active)
     and not private.atina_v2_challenge_answer_matches(659, 'Back to the Future') then
    raise exception 'International title should be accepted for Regresso ao Futuro.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 660 and active)
     and not private.atina_v2_challenge_answer_matches(660, 'Parque Jurássico') then
    raise exception 'Portuguese title should be accepted for Jurassic Park.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 674 and active)
     and not private.atina_v2_challenge_answer_matches(674, 'Frozen: O Reino do Gelo') then
    raise exception 'Portuguese subtitle should be accepted for Frozen.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 660 and active)
     and private.atina_v2_challenge_answer_matches(660, 'Back to the Future') then
    raise exception 'A title belonging to another challenge must not match.';
  end if;
end
$tests$;
