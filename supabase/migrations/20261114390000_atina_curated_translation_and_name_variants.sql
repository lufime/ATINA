-- Add unambiguous translations and established full-name variants.
update private.atina_challenges c
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(c.accepted_answers, '[]'::jsonb) || to_jsonb(additions.values)::jsonb)
  ) s
)
from (values
  (190, array['Old Bridge','Ponte Velha de Mostar']::text[]),
  (349, array['Katherine Coleman Johnson']::text[]),
  (1091, array['Plitvice Lakes']::text[]),
  (1197, array['Vaccine']::text[])
) as additions(challenge_id, values)
where c.challenge_id = additions.challenge_id
  and c.active;
