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

-- Challenge catalog rows are deployed separately from schema migrations.
-- A clean schema replay may intentionally omit that private catalog; in that
-- case this additive alias update is a no-op and production rows are preserved.
