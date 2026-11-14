-- Remove the case-insensitive duplicate "Ponte Velha de Mostar" entry.
update private.atina_challenges c
set accepted_answers = (
  select jsonb_agg(x.value order by x.ordinality)
  from (
    select e.value, e.ordinality,
           row_number() over (partition by lower(btrim(e.value)) order by e.ordinality) as duplicate_rank
    from jsonb_array_elements_text(coalesce(c.accepted_answers, '[]'::jsonb)) with ordinality e(value, ordinality)
  ) x
  where x.duplicate_rank = 1
)
where c.challenge_id = 190
  and c.active = true;
