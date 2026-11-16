-- Reserve 10% of simulated player profiles for varied international names.
update private.atina_v2_bot_profiles set nickname='atina_tmp_'||id::text where id between 91 and 100;
update private.atina_v2_bot_profiles as p
set nickname=v.nickname
from (values
(91,'Emma Müller'),
(92,'Lucas García'),
(93,'Sofia Rossi'),
(94,'Alex Johnson'),
(95,'Camille Dubois'),
(96,'Ivan Petrov'),
(97,'Aiko Tanaka'),
(98,'Omar Hassan'),
(99,'Mia Novak'),
(100,'Diego Fernández')
) as v(id,nickname)
where p.id=v.id;
update public.atina_v2_room_players p
set nickname=b.nickname
from private.atina_v2_bot_matches m
join private.atina_v2_bot_profiles b on b.id=m.bot_profile_id
join public.atina_v2_rooms r on r.id=m.room_id
where p.id=m.bot_player_id and p.room_id=m.room_id and r.status in ('waiting','playing');