with aliases(challenge_id, variants) as (values
(59,array['Harry Potter']), (179,array['Friends']), (653,array['Casablanca']), (661,array['Titanic']),
(664,array['Parasite']), (670,array['Toy Story']), (671,array['Finding Dory']), (672,array['Shrek']),
(673,array['Coco']), (676,array['Ratatouille']), (679,array['Blade Runner']), (684,array['Downton Abbey']),
(685,array['Breaking Bad']), (686,array['The Crown']), (687,array['The Office']), (688,array['Black Mirror']),
(690,array['Stranger Things']),
(540,array['Lighthouse']), (542,array['Painting']), (543,array['Sculpture']), (554,array['Chemistry']),
(555,array['Physics']), (556,array['Biology']), (557,array['Geometry']), (558,array['Statistics']),
(559,array['Medal']), (561,array['Violin']), (562,array['Piano']), (567,array['Newspaper']),
(571,array['Traditional Tejo boat']), (573,array['Jazz']), (574,array['Flamenco']), (575,array['Cubism']),
(576,array['Romanticism']),
(853,array['Portuguese kale soup']), (854,array['Portuguese custard tart','Pastel de Belém']),
(856,array['Sushi']), (858,array['Ratatouille']), (868,array['Rice cake']), (872,array['Japanese noodle soup']),
(880,array['Avocado dip']), (881,array['Sour roast']), (882,array['Meringue dessert']),
(200,array['Sextant']), (391,array['Magnifying glass']), (392,array['Spoon']), (396,array['Fog','Mist']),
(398,array['Plant root']), (400,array['Candle']), (403,array['Drum']), (408,array['Bone']),
(412,array['Doorbell']), (413,array['Brick']), (414,array['Toothbrush']), (415,array['Knife']),
(416,array['Computer keyboard']), (418,array['Book']), (421,array['Gold']), (422,array['Tidal wave']),
(907,array['Bluetooth']), (935,array['Sound navigation and ranging']),
(1053,array['Petra']), (1054,array['Machu Picchu']), (1060,array['Angkor temple']),
(1063,array['Taj Mahal']), (1082,array['Bora Bora']), (1087,array['Rio']),
(1096,array['Cotton castle']), (1099,array['Komodo National Park']),
(955,array['Pluto']), (967,array['Gorgon']), (992,array['Titan']), (994,array['Pandora']),
(1000,array['Loki'])
)
update private.atina_challenges c
set accepted_answers = coalesce(c.accepted_answers,'[]'::jsonb) ||
coalesce((select jsonb_agg(to_jsonb(v)) from aliases al cross join lateral unnest(al.variants) v
where al.challenge_id=c.challenge_id and private.atina_v2_normalize_answer(v) <> private.atina_v2_normalize_answer(c.answer)
and not exists(select 1 from jsonb_array_elements_text(coalesce(c.accepted_answers,'[]'::jsonb)) old(a) where private.atina_v2_normalize_answer(old.a)=private.atina_v2_normalize_answer(v))),'[]'::jsonb)
from aliases al where c.challenge_id=al.challenge_id and c.active is true
and exists(select 1 from unnest(al.variants) v where private.atina_v2_normalize_answer(v) <> private.atina_v2_normalize_answer(c.answer))