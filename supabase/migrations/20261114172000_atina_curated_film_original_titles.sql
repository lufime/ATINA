-- Original/international film titles supported by the challenge descriptions.
with aliases(challenge_id, alias) as (
  values
    (654, 'Citizen Kane'),
    (655, 'Modern Times'),
    (656, 'Psycho'),
    (657, 'Jaws'),
    (658, 'E.T. the Extra-Terrestrial'),
    (662, 'Gladiator'),
    (665, 'The Pianist'),
    (666, 'Schindler''s List'),
    (667, 'The Silence of the Lambs'),
    (668, 'Life Is Beautiful'),
    (669, 'The BFG'),
    (677, 'The Nightmare Before Christmas'),
    (678, 'The Fellowship of the Ring'),
    (681, 'The Big Lebowski'),
    (682, 'Fight Club'),
    (683, 'The King''s Speech')
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
