-- Add carefully curated shorter answer variants to individual challenges.
-- Keep aliases challenge-specific to avoid broad false positives.
with aliases(challenge_id, alias) as (
  values
    (668, 'Vida Bela'),
    (675, 'Up'),
    (658, 'E.T.'),
    (663, 'Amélie'),
    (678, 'A Irmandade do Anel'),
    (680, 'Alien'),
    (1028, 'Dorian Gray')
)
update private.atina_challenges as challenge
set accepted_answers = challenge.accepted_answers || jsonb_build_array(aliases.alias)
from aliases
where challenge.challenge_id = aliases.challenge_id
  and not exists (
    select 1
    from jsonb_array_elements_text(challenge.accepted_answers) as existing(value)
    where existing.value = aliases.alias
  );

-- Fail visibly if the expected challenge rows are missing.
do $$
begin
  if (
    select count(*)
    from private.atina_challenges
    where challenge_id in (668, 675, 658, 663, 678, 680, 1028)
  ) <> 7 then
    raise exception 'Expected all 7 ATINA challenge rows before applying answer aliases';
  end if;
end;
$$;
