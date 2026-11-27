-- Curated, challenge-specific aliases for Portuguese football clubs.
-- Ambiguous city/common-word fragments are intentionally excluded.
-- In particular, "Vitória" and "Guimarães" alone must NOT identify Vitória SC.
with aliases(challenge_id, alias) as (
  values
    (1411, 'FC Porto'), (1411, 'F.C. Porto'), (1411, 'FCP'), (1411, 'Porto FC'),
    (1412, 'Benfica'), (1412, 'SL Benfica'), (1412, 'S.L. Benfica'), (1412, 'Sport Lisboa Benfica'),
    (1413, 'Sporting CP'), (1413, 'SCP'), (1413, 'Sporting Portugal'),
    (1414, 'SC Braga'), (1414, 'S.C. Braga'), (1414, 'Sporting de Braga'),
    (1415, 'Vitória de Guimarães'), (1415, 'Vitoria de Guimaraes'), (1415, 'Vitória SC'), (1415, 'Vitoria SC'), (1415, 'VSC'),
    (1416, 'Boavista FC'), (1416, 'BFC'),
    (1417, 'CF Os Belenenses'), (1417, 'Os Belenenses'), (1417, 'Clube de Futebol Os Belenenses'),
    (1418, 'Académica'), (1418, 'Academica de Coimbra'), (1418, 'Associação Académica de Coimbra'), (1418, 'AAC')
)
update private.atina_challenges challenge
set accepted_answers = coalesce(challenge.accepted_answers, '[]'::jsonb) || jsonb_build_array(aliases.alias)
from aliases
where challenge.challenge_id = aliases.challenge_id
  and challenge.active
  and private.atina_v2_normalize_answer(challenge.answer) =
      private.atina_v2_normalize_answer(case aliases.challenge_id
        when 1411 then 'Futebol Clube do Porto'
        when 1412 then 'Sport Lisboa e Benfica'
        when 1413 then 'Sporting Clube de Portugal'
        when 1414 then 'Sporting Clube de Braga'
        when 1415 then 'Vitória Sport Clube'
        when 1416 then 'Boavista Futebol Clube'
        when 1417 then 'Belenenses'
        when 1418 then 'Académica de Coimbra'
      end)
  and not exists (
    select 1
    from jsonb_array_elements_text(
      case when jsonb_typeof(challenge.accepted_answers) = 'array'
        then challenge.accepted_answers else '[]'::jsonb end
    ) existing(value)
    where private.atina_v2_normalize_answer(existing.value) = private.atina_v2_normalize_answer(aliases.alias)
  );

do $tests$
begin
  if exists (select 1 from private.atina_challenges where challenge_id = 1415 and active) then
    if not private.atina_v2_challenge_answer_matches(1415, 'Vitória de Guimarães')
       or not private.atina_v2_challenge_answer_matches(1415, 'Vitoria SC')
       or not private.atina_v2_challenge_answer_matches(1415, 'VSC') then
      raise exception 'Vitória SC: full names and abbreviation must be accepted.';
    end if;
    if private.atina_v2_challenge_answer_matches(1415, 'Vitória')
       or private.atina_v2_challenge_answer_matches(1415, 'Guimarães') then
      raise exception 'Vitória SC: ambiguous single words must remain incorrect.';
    end if;
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 1411 and active)
     and not private.atina_v2_challenge_answer_matches(1411, 'FCP') then
    raise exception 'FC Porto: FCP must be accepted.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 1412 and active)
     and not private.atina_v2_challenge_answer_matches(1412, 'SL Benfica') then
    raise exception 'Benfica: SL Benfica must be accepted.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 1413 and active)
     and not private.atina_v2_challenge_answer_matches(1413, 'Sporting CP') then
    raise exception 'Sporting: Sporting CP must be accepted.';
  end if;
  if exists (select 1 from private.atina_challenges where challenge_id = 1414 and active)
     and not private.atina_v2_challenge_answer_matches(1414, 'SC Braga') then
    raise exception 'Braga: SC Braga must be accepted.';
  end if;
end
$tests$;
