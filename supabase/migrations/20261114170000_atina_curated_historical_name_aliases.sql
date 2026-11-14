-- Curated biographical name variants supported by each challenge's clues.
with aliases(challenge_id, alias) as (
  values
    (314, 'Jeanne d''Arc'),
    (314, 'Joan of Arc'),
    (325, 'Alberto Santos-Dumont'),
    (328, 'Afonso I de Portugal'),
    (333, 'Pablo Ruiz Picasso')
)
update private.atina_challenges c
set accepted_answers = coalesce(c.accepted_answers, '[]'::jsonb) || jsonb_build_array(a.alias)
from aliases a
where c.challenge_id = a.challenge_id
  and c.active
  and not exists (
    select 1
    from jsonb_array_elements_text(coalesce(c.accepted_answers, '[]'::jsonb)) existing(answer)
    where private.atina_v2_normalize_answer(existing.answer) = private.atina_v2_normalize_answer(a.alias)
  );
