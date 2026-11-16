-- Keep names already copied into active rooms in sync with their public player-style nicknames.
update public.atina_v2_room_players p
   set nickname=b.nickname
  from private.atina_v2_bot_matches m
  join private.atina_v2_bot_profiles b on b.id=m.bot_profile_id
  join public.atina_v2_rooms r on r.id=m.room_id
 where p.id=m.bot_player_id
   and p.room_id=m.room_id
   and r.status in ('waiting','playing');
