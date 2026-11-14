-- Add clear English/common-name variants found in the challenge audit.
update private.atina_challenges c
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(c.accepted_answers, '[]'::jsonb) || to_jsonb(additions.values)::jsonb)
  ) s
)
from (values
  (592, array['Gravity']::text[]),
  (836, array['Sea star']::text[]),
  (1080, array['Galapagos Islands']::text[])
) as additions(challenge_id, values)
where c.challenge_id = additions.challenge_id
  and c.active;
