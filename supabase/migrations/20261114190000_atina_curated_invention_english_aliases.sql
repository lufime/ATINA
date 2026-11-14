-- Widely used English equivalents for invention/technology challenges.
with aliases(challenge_id, alias) as (
  values
    (1153, 'Sewing machine'),
    (1156, 'Telescope'),
    (1157, 'Microscope'),
    (1158, 'Compass'),
    (1160, 'Photography'),
    (1166, 'Parachute'),
    (1167, 'Refrigerator'),
    (1168, 'Phonograph'),
    (1169, 'Airplane'),
    (1170, 'Vacuum cleaner'),
    (1172, 'Fire extinguisher'),
    (1173, 'Washing machine'),
    (1174, 'Lightning rod'),
    (1175, 'Bicycle'),
    (1176, 'Incandescent light bulb'),
    (1177, 'Electric battery'),
    (1179, 'Telephone'),
    (1181, 'Television'),
    (1184, 'Electric motor'),
    (1185, 'Wind turbine'),
    (1187, 'Submarine'),
    (1190, 'Anesthesia'),
    (1192, 'Stainless steel'),
    (1194, 'Microwave oven'),
    (1196, 'X-rays'),
    (1199, 'Calculator'),
    (1200, 'Barometer'),
    (1201, 'Astrolabe')
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
