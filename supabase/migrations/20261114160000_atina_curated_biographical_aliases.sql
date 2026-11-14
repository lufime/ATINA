-- Add verified birth names, international names and established nicknames to exact person challenges.
do $$
declare
  v_item record;
begin
  for v_item in
    select * from (values
      (321, 'Rosa Louise McCauley Parks'),
      (322, 'Martin Luther King'),
      (322, 'MLK'),
      (324, 'Lady Lindy'),
      (327, 'Ferdinand Magellan'),
      (329, 'Luís Vaz de Camões'),
      (331, 'José de Sousa Saramago'),
      (334, 'Vincent Willem van Gogh'),
      (338, 'Fryderyk Chopin'),
      (339, 'António Joaquim Rodrigues Ribeiro'),
      (340, 'Amália da Piedade Rebordão Rodrigues'),
      (343, 'Serena'),
      (345, 'Lightning Bolt'),
      (349, 'Katherine Coleman Goble Johnson')
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
  if exists (select 1 from private.atina_challenges where challenge_id=321 and active)
     and not private.atina_v2_challenge_answer_matches(321, 'Rosa Louise McCauley Parks') then raise exception 'Rosa Parks full name should match'; end if;
  if exists (select 1 from private.atina_challenges where challenge_id=322 and active)
     and not private.atina_v2_challenge_answer_matches(322, 'MLK') then raise exception 'MLK should match Martin Luther King Jr.'; end if;
  if exists (select 1 from private.atina_challenges where challenge_id=324 and active)
     and not private.atina_v2_challenge_answer_matches(324, 'Lady Lindy') then raise exception 'Lady Lindy should match Amelia Earhart'; end if;
  if exists (select 1 from private.atina_challenges where challenge_id=327 and active)
     and not private.atina_v2_challenge_answer_matches(327, 'Ferdinand Magellan') then raise exception 'Ferdinand Magellan should match Fernão de Magalhães'; end if;
  if exists (select 1 from private.atina_challenges where challenge_id=331 and active)
     and not private.atina_v2_challenge_answer_matches(331, 'José de Sousa Saramago') then raise exception 'Saramago full name should match'; end if;
  if exists (select 1 from private.atina_challenges where challenge_id=338 and active)
     and not private.atina_v2_challenge_answer_matches(338, 'Fryderyk Chopin') then raise exception 'Polish name should match Chopin'; end if;
  if exists (select 1 from private.atina_challenges where challenge_id=343 and active)
     and not private.atina_v2_challenge_answer_matches(343, 'Serena') then raise exception 'Serena should match Serena Williams'; end if;
  if exists (select 1 from private.atina_challenges where challenge_id=345 and active)
     and not private.atina_v2_challenge_answer_matches(345, 'Lightning Bolt') then raise exception 'Lightning Bolt should match Usain Bolt'; end if;
  if exists (select 1 from private.atina_challenges where challenge_id=349 and active)
     and not private.atina_v2_challenge_answer_matches(349, 'Katherine Coleman Goble Johnson') then raise exception 'Katherine Johnson full name should match'; end if;
  if exists (select 1 from private.atina_challenges where challenge_id=321 and active)
     and private.atina_v2_challenge_answer_matches(321, 'Lady Lindy') then raise exception 'Nickname from another person must not match'; end if;
end
$tests$;
