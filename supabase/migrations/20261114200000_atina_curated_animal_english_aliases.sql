-- Common English names supported by the animal challenge clues.
with aliases(challenge_id, alias) as (
  values
    (810, 'Whale shark'),
    (811, 'Wandering albatross'),
    (812, 'Iberian lynx'),
    (813, 'Fire salamander'),
    (814, 'Indian peafowl'),
    (815, 'Dugong'),
    (816, 'Midwife toad'),
    (817, 'Hyacinth macaw'),
    (818, 'Coelacanth'),
    (819, 'Mediterranean monk seal'),
    (820, 'Scimitar-horned oryx'),
    (821, 'Red panda'),
    (822, 'Black rhinoceros'),
    (823, 'Aye-aye'),
    (825, 'Ostrich'),
    (827, 'Capybara'),
    (828, 'Red kangaroo'),
    (829, 'Wombat'),
    (830, 'Echidna'),
    (831, 'Bactrian camel'),
    (832, 'Dromedary'),
    (833, 'Rhinoceros hornbill'),
    (834, 'Sawfish'),
    (836, 'Starfish'),
    (837, 'Sea urchin'),
    (838, 'Portuguese man o'' war'),
    (839, 'Water bear'),
    (840, 'Praying mantis'),
    (841, 'Stick insect'),
    (842, 'Dragonfly'),
    (843, 'Rhinoceros beetle'),
    (844, 'Leafcutter ant'),
    (845, 'Mimic octopus'),
    (846, 'Vampire squid'),
    (847, 'Stonefish'),
    (848, 'Clark''s anemonefish'),
    (849, 'Walrus'),
    (850, 'Musk ox'),
    (851, 'Saiga')
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
