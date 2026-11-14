with aliases(challenge_id, variants) as (values
(8,array['quarenta e oito']),(28,array['trinta e dois']),(56,array['sessenta e três']),
(64,array['quarenta e cinco']),(147,array['cinco']),(148,array['quarenta e dois']),
(149,array['três']),(176,array['vinte e três']),(191,array['quatro']),
(206,array['dois']),(220,array['trinta e seis']),(235,array['oito']),
(275,array['quarenta e nove']),(276,array['sessenta e quatro']),(277,array['oitenta e um']),
(278,array['cem']),(279,array['cento e vinte e um']),(280,array['cento e quarenta e quatro']),
(281,array['cento e sessenta e nove']),(282,array['cento e noventa e seis']),
(283,array['duzentos e vinte e cinco']),(284,array['duzentos e cinquenta e seis']),
(285,array['duzentos e oitenta e nove']),(286,array['trezentos e vinte e quatro']),
(287,array['quatrocentos']),(288,array['seiscentos e vinte e cinco']),
(289,array['setecentos e vinte e nove']),(290,array['mil']),(291,array['vinte e cinco']),
(292,array['vinte e um']),(293,array['cento e vinte']),(294,array['cinco mil e quarenta']),
(295,array['trinta']),(296,array['cento e um']),(297,array['novecentos e noventa e nove']),
(298,array['mil e vinte e quatro']),(299,array['180°','180 degrees']),
(300,array['360°','360 degrees']),(301,array['12']),(302,array['9']),
(303,array['Octagon']),(304,array['Pentagon']),(305,array['Hexagon']),
(306,array['3 pessoas']),(307,array['0,20 euros','20 cents']),(309,array['0','Nulo'])
)
update private.atina_challenges c
set accepted_answers = coalesce(c.accepted_answers,'[]'::jsonb) ||
coalesce((select jsonb_agg(to_jsonb(v)) from aliases al cross join lateral unnest(al.variants) v
where al.challenge_id=c.challenge_id and private.atina_v2_normalize_answer(v) <> private.atina_v2_normalize_answer(c.answer)
and not exists(select 1 from jsonb_array_elements_text(coalesce(c.accepted_answers,'[]'::jsonb)) old(a) where private.atina_v2_normalize_answer(old.a)=private.atina_v2_normalize_answer(v))),'[]'::jsonb)
from aliases al where c.challenge_id=al.challenge_id and c.active is true