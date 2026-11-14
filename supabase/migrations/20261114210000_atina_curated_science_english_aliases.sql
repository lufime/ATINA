-- Common English scientific equivalents supported by the challenge clues.
with aliases(challenge_id, alias) as (
  values
    (24, 'Oxygen'),
    (53, 'Gravity'),
    (138, 'Photosynthesis'),
    (139, 'Mercury'),
    (173, 'Atmosphere'),
    (502, 'Saturn'),
    (503, 'Mars'),
    (504, 'Milky Way'),
    (505, 'Sun'),
    (507, 'Magma'),
    (508, 'Butterfly'),
    (509, 'Dolphin'),
    (510, 'Bee'),
    (511, 'Forest'),
    (512, 'Temperature'),
    (513, 'Electricity'),
    (514, 'Magnetic field'),
    (517, 'Lung'),
    (519, 'Blood'),
    (520, 'Gene'),
    (521, 'Germination'),
    (522, 'Pollination'),
    (524, 'Snake'),
    (525, 'Dinosaurs'),
    (526, 'Coral'),
    (527, 'Tide'),
    (528, 'Wind'),
    (529, 'Cloud'),
    (530, 'Precipitation'),
    (531, 'Weathering'),
    (532, 'Ice'),
    (533, 'Bacteria'),
    (534, 'Virus'),
    (535, 'Dispersion of light'),
    (536, 'Sound'),
    (537, 'Heat'),
    (538, 'Atom'),
    (539, 'Periodic table')
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
