create table private.atina_v2_bot_competition_stats (
  bot_profile_id integer primary key references private.atina_v2_bot_profiles(id) on delete cascade,
  points integer not null default 0 check (points >= 0),
  xp integer not null default 0 check (xp >= 0),
  total_challenges integer not null default 0 check (total_challenges >= 0),
  simulated_games integer not null default 0 check (simulated_games >= 0),
  last_game_at timestamptz,
  next_game_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);

create table private.atina_v2_bot_competition_events (
  id bigint generated always as identity primary key,
  bot_profile_id integer not null references private.atina_v2_bot_profiles(id) on delete cascade,
  source text not null check (source in ('simulation','room')),
  source_id uuid not null,
  challenge_position integer not null check (challenge_position > 0),
  points integer not null default 0 check (points >= 0),
  xp integer not null default 10 check (xp >= 0),
  is_correct boolean not null default false,
  created_at timestamptz not null default clock_timestamp(),
  unique (bot_profile_id, source, source_id, challenge_position)
);

create index atina_v2_bot_competition_events_created_idx
  on private.atina_v2_bot_competition_events (created_at desc);

insert into private.atina_v2_bot_competition_stats (bot_profile_id, next_game_at)
select b.id, clock_timestamp() + make_interval(mins => 30 + floor(random()*180)::integer)
from private.atina_v2_bot_profiles b
on conflict (bot_profile_id) do nothing;

create or replace function private.atina_v2_simulate_bot_games()
returns integer
language plpgsql
security definer
set search_path = ''
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
  select b.id, clock_timestamp() + make_interval(mins => 30 + floor(random()*180)::integer)
  from private.atina_v2_bot_profiles b
  on conflict (bot_profile_id) do nothing;

  for v_bot in
    select b.id, b.knowledge_level, b.mistake_rate, b.online_probability
      from private.atina_v2_bot_profiles b
      join private.atina_v2_bot_competition_stats s on s.bot_profile_id=b.id
     where b.active and s.next_game_at <= clock_timestamp()
     order by s.next_game_at
     limit 8
     for update of s skip locked
  loop
    if not private.atina_v2_bot_is_available(
      (select b from private.atina_v2_bot_profiles b where b.id=v_bot.id)
    ) or random() > v_bot.online_probability then
      update private.atina_v2_bot_competition_stats
         set next_game_at=clock_timestamp()+make_interval(mins=>15+floor(random()*31)::integer),
             updated_at=clock_timestamp()
       where bot_profile_id=v_bot.id;
      continue;
    end if;

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

      if not found then
        exit;
      end if;

      v_used := array_append(v_used, v_challenge.challenge_id);
      v_clues := case
        when v_bot.knowledge_level >= 0.78 then 1
        when v_bot.knowledge_level >= 0.55 then 2
        else 3
      end;
      v_correct := random() < greatest(0.03, least(0.98,
        v_bot.knowledge_level * (1 - v_bot.mistake_rate)));
      v_points := case
        when not v_correct then 0
        when v_clues=1 then 20
        when v_clues=2 then 16
        else 12
      end;

      insert into private.atina_v2_bot_competition_events
        (bot_profile_id, source, source_id, challenge_position, points, xp, is_correct)
      values
        (v_bot.id, 'simulation', v_game_id, i, v_points, 10, v_correct)
      on conflict (bot_profile_id, source, source_id, challenge_position) do nothing;

      get diagnostics v_inserted = row_count;
      if v_inserted=1 then
        update private.atina_v2_bot_competition_stats
           set points=points+v_points,
               xp=xp+10,
               total_challenges=total_challenges+1,
               updated_at=clock_timestamp()
         where bot_profile_id=v_bot.id;
      end if;
    end loop;

    update private.atina_v2_bot_competition_stats
       set simulated_games=simulated_games+1,
           last_game_at=clock_timestamp(),
           next_game_at=clock_timestamp()+make_interval(mins=>90+floor(random()*151)::integer),
           updated_at=clock_timestamp()
     where bot_profile_id=v_bot.id;

    v_games := v_games+1;
  end loop;

  return v_games;
end;
$function$;

revoke all on function private.atina_v2_simulate_bot_games() from public, anon, authenticated;

create or replace function public.atina_progress_leaderboard(p_limit integer default 50)
returns table(nickname text, xp integer, level integer, challenges integer)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  -- Older production projects may contain this legacy table, while clean
  -- migration replays do not. Keep the compatibility path optional.
  if to_regclass('private.atina_v2_players') is not null then
    return query
      with all_players as (
        select p.nickname, p.total_xp as xp,
               private.atina_level_for_xp(p.total_xp) as level,
               p.total_challenges as challenges, p.created_at
          from private.atina_players p
        union all
        select p.nickname, p.xp,
               private.atina_level_for_xp(p.xp) as level,
               p.total_challenges as challenges, p.created_at
          from private.atina_v2_players p
        union all
        select b.nickname, s.xp,
               private.atina_level_for_xp(s.xp) as level,
               s.total_challenges as challenges, s.created_at
          from private.atina_v2_bot_competition_stats s
          join private.atina_v2_bot_profiles b on b.id=s.bot_profile_id
         where s.xp>0
      )
      select all_players.nickname, all_players.xp, all_players.level, all_players.challenges
        from all_players
       order by all_players.xp desc, all_players.challenges desc, all_players.created_at asc
       limit least(greatest(coalesce(p_limit,50),1),100);
  else
    return query
      with all_players as (
        select p.nickname, p.total_xp as xp,
               private.atina_level_for_xp(p.total_xp) as level,
               p.total_challenges as challenges, p.created_at
          from private.atina_players p
        union all
        select b.nickname, s.xp,
               private.atina_level_for_xp(s.xp) as level,
               s.total_challenges as challenges, s.created_at
          from private.atina_v2_bot_competition_stats s
          join private.atina_v2_bot_profiles b on b.id=s.bot_profile_id
         where s.xp>0
      )
      select all_players.nickname, all_players.xp, all_players.level, all_players.challenges
        from all_players
       order by all_players.xp desc, all_players.challenges desc, all_players.created_at asc
       limit least(greatest(coalesce(p_limit,50),1),100);
  end if;
end;
$function$;

create or replace function public.atina_points_leaderboard(p_limit integer default 50)
returns table(nickname text, points integer, challenges integer)
language sql
stable
security definer
set search_path = ''
as $function$
  with all_players as (
    select p.nickname, p.total_points as points,
           p.total_challenges as challenges, p.created_at
      from private.atina_players p
     where p.total_points>0
    union all
    select b.nickname, s.points,
           s.total_challenges as challenges, s.created_at
      from private.atina_v2_bot_competition_stats s
      join private.atina_v2_bot_profiles b on b.id=s.bot_profile_id
     where s.points>0
  )
  select all_players.nickname, all_players.points, all_players.challenges
    from all_players
   order by all_players.points desc, all_players.challenges desc, all_players.created_at asc
   limit least(greatest(coalesce(p_limit,50),1),100);
$function$;

-- Some disposable/local Supabase environments do not preload pg_cron.
-- Keep migration replay portable; production environments with pg_cron still
-- receive the scheduled bot simulation.
do $schedule$
begin
  if to_regnamespace('cron') is not null then
    execute $sql$
      select cron.schedule(
        'atina-v2-bot-simulated-games',
        '* * * * *',
        'select private.atina_v2_simulate_bot_games();'
      )
    $sql$;
  end if;
end;
$schedule$;
