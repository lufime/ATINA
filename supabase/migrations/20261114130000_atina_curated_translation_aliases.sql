-- Add exact, challenge-scoped translations and alternate release titles.
do $$
declare
  v_item record;
begin
  for v_item in
    select * from (values
      (689, 'Os Simpsons'),
      (1023, 'Harry Potter and the Sorcerer''s Stone')
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
  if exists (select 1 from private.atina_challenges where challenge_id = 689 and active)
     and not private.atina_v2_challenge_answer_matches(689, 'Os Simpsons') then
    raise exception 'Portuguese title should be accepted for The Simpsons.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 1023 and active)
     and not private.atina_v2_challenge_answer_matches(1023, 'Harry Potter and the Sorcerer''s Stone') then
    raise exception 'US release title should be accepted for Harry Potter and the Philosopher''s Stone.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 689 and active)
     and private.atina_v2_challenge_answer_matches(689, 'Breaking Bad') then
    raise exception 'Unrelated series title must not be accepted.';
  end if;
end
$tests$;
