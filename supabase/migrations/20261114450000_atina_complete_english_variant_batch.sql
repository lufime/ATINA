-- Add missing English equivalents found in the modulo-73 answer audit.
with additions(challenge_id, alias) as (
  values
    (61, 'Two euros'),
    (207, 'Bottle'),
    (499, 'Extraordinary feat'),
    (937, 'Digital photography')
),
grouped as (
  select c.challenge_id,
         jsonb_agg(a.alias order by a.alias) filter (
           where not exists (
             select 1
             from jsonb_array_elements_text(coalesce(c.accepted_answers, '[]'::jsonb)) e(value)
             where lower(btrim(e.value)) = lower(btrim(a.alias))
           )
         ) as aliases
  from private.atina_challenges c
  join additions a on a.challenge_id = c.challenge_id
  where c.active = true
  group by c.challenge_id
)
update private.atina_challenges c
set accepted_answers = coalesce(c.accepted_answers, '[]'::jsonb) || g.aliases
from grouped g
where c.challenge_id = g.challenge_id
  and g.aliases is not null
  and jsonb_array_length(g.aliases) > 0;
