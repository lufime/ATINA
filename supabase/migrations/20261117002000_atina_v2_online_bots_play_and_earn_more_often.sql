create or replace function private.atina_v2_simulate_bot_games()
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_bot record;
  v_challenge record;
  v_game_id uuid;
  v_used integer[];
  v_challenge_count integer;
  v_clues integer;
  v_correct boolean;
  v_points integer;
  v_inserted integer;
  v_games integer := 0;
  i integer;
begin
  insert into private.atina_v2_bot_competition_stats (bot_profile_id, next_game_at)
  select b.id, clock_timestamp() + make_interval(mins => 1 + floor(random()*3)::integer)
  from private.atina_v2_bot_profiles b
  on conflict (bot_profile_id) do nothing;

  update private.atina_v2_bot_competition_stats s
     set next_game_at = clock_timestamp() + make_interval(mins => 1 + floor(random()*3)::integer),
         updated_at = clock_timestamp()
    from private.atina_v2_bot_profiles b
    join private.atina_v2_bot_presence_windows w on w.bot_profile_id=b.id
   where s.bot_profile_id=b.id
     and b.active
     and private.atina_v2_bot_is_available(b)
     and w.online_since >= clock_timestamp() - interval '2 minutes'
     and (s.last_game_at is null or s.last_game_at < w.online_since)
     and s.next_game_at > clock_timestamp() + interval '3 minutes';

  for v_bot in
    select b.id, b.knowledge_level, b.mistake_rate, s.next_game_at
      from private.atina_v2_bot_profiles b
      join private.atina_v2_bot_competition_stats s on s.bot_profile_id=b.id
     where b.active
       and s.next_game_at <= clock_timestamp()
       and private.atina_v2_bot_is_available(b)
       and not exists (
         select 1 from private.atina_v2_bot_matches m
         join public.atina_v2_rooms r on r.id=m.room_id
         where m.bot_profile_id=b.id and r.status in ('waiting','playing')
       )
     order by s.next_game_at
     limit 8
     for update of s skip locked
  loop
    v_game_id := extensions.gen_random_uuid();
    v_used := array[]::integer[];
    v_challenge_count := 3 + floor(random()*3)::integer;

    for i in 1..v_challenge_count loop
      select c.challenge_id, c.category, c.difficulty, c.image_url
        into v_challenge
        from private.atina_challenges c
       where c.active and not (c.challenge_id = any(v_used))
       order by random()
       limit 1;

      if not found then exit; end if;
      v_used := array_append(v_used, v_challenge.challenge_id);
      v_clues := case when v_bot.knowledge_level >= 0.78 then 1
                      when v_bot.knowledge_level >= 0.55 then 2 else 3 end;
      v_correct := random() < greatest(0.03, least(0.98,
        v_bot.knowledge_level * (1 - v_bot.mistake_rate)));
      v_points := case when not v_correct then 0 when v_clues=1 then 20
                       when v_clues=2 then 16 else 12 end;

      insert into private.atina_v2_bot_competition_events
        (bot_profile_id, source, source_id, challenge_position, points, xp, is_correct)
      values (v_bot.id, 'simulation', v_game_id, i, v_points, 10, v_correct)
      on conflict (bot_profile_id, source, source_id, challenge_position) do nothing;

      get diagnostics v_inserted = row_count;
      if v_inserted=1 then
        update private.atina_v2_bot_competition_stats
           set points=points+v_points, xp=xp+10,
               total_challenges=total_challenges+1, updated_at=clock_timestamp()
         where bot_profile_id=v_bot.id;
      end if;
    end loop;

    update private.atina_v2_bot_competition_stats
       set simulated_games=simulated_games+1,
           last_game_at=clock_timestamp(),
           next_game_at=clock_timestamp()+make_interval(mins=>8+floor(random()*18)::integer),
           updated_at=clock_timestamp()
     where bot_profile_id=v_bot.id;
    v_games := v_games+1;
  end loop;
  return v_games;
end;
$function$;

update private.atina_v2_bot_competition_stats s
   set next_game_at = clock_timestamp() + make_interval(mins => 1 + floor(random()*3)::integer),
       updated_at = clock_timestamp()
  from private.atina_v2_bot_profiles b
 where s.bot_profile_id=b.id
   and b.active
   and private.atina_v2_bot_is_available(b)
   and (s.last_game_at is null or s.last_game_at < (
     select w.online_since from private.atina_v2_bot_presence_windows w where w.bot_profile_id=b.id
   ));
