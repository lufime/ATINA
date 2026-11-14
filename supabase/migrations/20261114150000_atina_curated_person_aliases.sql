-- Add well-established biographical names and nicknames to exact person challenges.
do $$
declare
  v_item record;
begin
  for v_item in
    select * from (values
      (341, 'Edson Arantes do Nascimento'),
      (341, 'O Rei do Futebol'),
      (342, 'Cassius Clay'),
      (344, 'Air Jordan')
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
  if exists (select 1 from private.atina_challenges where challenge_id = 341 and active)
     and not private.atina_v2_challenge_answer_matches(341, 'Edson Arantes do Nascimento') then
    raise exception 'Pelé birth name should be accepted.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 341 and active)
     and not private.atina_v2_challenge_answer_matches(341, 'O Rei do Futebol') then
    raise exception 'Pelé nickname should be accepted.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 342 and active)
     and not private.atina_v2_challenge_answer_matches(342, 'Cassius Clay') then
    raise exception 'Muhammad Ali birth name should be accepted.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 344 and active)
     and not private.atina_v2_challenge_answer_matches(344, 'Air Jordan') then
    raise exception 'Michael Jordan nickname should be accepted.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 342 and active)
     and private.atina_v2_challenge_answer_matches(342, 'Air Jordan') then
    raise exception 'Nickname from another person must not match.';
  end if;
end
$tests$;
