-- Add only unambiguous, widely used title abbreviations to matching challenges.
-- Avoid broad acronym matching: aliases are attached to exact challenge IDs.
do $$
declare
  v_item record;
begin
  for v_item in
    select * from (values
      (35, 'GOT'),
      (194, 'LOTR'),
      (1021, 'LOTR')
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
  if exists (select 1 from private.atina_challenges where challenge_id = 35 and active)
     and not private.atina_v2_challenge_answer_matches(35, 'GOT') then
    raise exception 'GOT should be accepted for Game of Thrones.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 194 and active)
     and not private.atina_v2_challenge_answer_matches(194, 'LOTR') then
    raise exception 'LOTR should be accepted for The Lord of the Rings.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 1021 and active)
     and not private.atina_v2_challenge_answer_matches(1021, 'LOTR') then
    raise exception 'LOTR should be accepted for The Lord of the Rings.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 35 and active)
     and private.atina_v2_challenge_answer_matches(35, 'GOTXYZ') then
    raise exception 'Unrelated acronym must not be accepted.';
  end if;
end
$tests$;
