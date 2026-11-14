-- International/alternate published titles supported by the literary challenge clues.
with aliases(challenge_id, alias) as (
  values
    (1002, 'The Lusiads'),
    (1004, 'Blindness'),
    (1006, 'The Relic'),
    (1007, 'The Iliad'),
    (1012, 'The Little Prince'),
    (1024, 'The Adventures of Tom Sawyer'),
    (1040, 'The City and the Mountains'),
    (1042, 'The Year of the Death of Ricardo Reis'),
    (1044, 'The Book of Disquiet')
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
