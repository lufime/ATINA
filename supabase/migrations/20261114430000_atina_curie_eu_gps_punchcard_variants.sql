-- Add precise English and full-name variants found during answer-tolerance audit.
with additions(challenge_id, alias) as (
  values
    (124, 'Marie Skłodowska-Curie'),
    (124, 'Marie Sklodowska Curie'),
    (550, 'European Union'),
    (905, 'Global Positioning System'),
    (1189, 'Punch card'),
    (1189, 'Punched card')
)
update private.atina_challenges c
set accepted_answers = coalesce(c.accepted_answers, '[]'::jsonb) || jsonb_build_array(a.alias)
from additions a
where c.challenge_id = a.challenge_id
  and c.active = true
  and not exists (
    select 1
    from jsonb_array_elements_text(coalesce(c.accepted_answers, '[]'::jsonb)) existing(value)
    where lower(btrim(existing.value)) = lower(btrim(a.alias))
  );
