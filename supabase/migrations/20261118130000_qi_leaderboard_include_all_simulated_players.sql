create or replace function public.atina_qi_leaderboard(p_limit integer default 15)
returns table(
  nickname text,
  qi_score integer,
  challenges integer,
  accuracy numeric,
  difficulty_score numeric,
  speed_score numeric,
  consistency_score numeric
)
language sql
stable
security definer
set search_path to ''
as $function$
with human_performance as (
  select
    e.actor_id::text as player_key,
    coalesce(max(a.nickname), max(p.nickname), max(e.nickname), 'Jogador') as player_name,
    count(*)::integer as attempts,
    avg(case when e.outcome = 'correct' then 1.0 else 0.0 end) as accuracy_rate,
    avg(case lower(coalesce(e.difficulty, ''))
      when 'easy' then 1.0 when 'facil' then 1.0 when 'fácil' then 1.0
      when 'medium' then 2.0 when 'medio' then 2.0 when 'médio' then 2.0
      when 'hard' then 3.0 when 'dificil' then 3.0 when 'difícil' then 3.0
      else null end) / 3.0 as difficulty_rate,
    avg(e.response_ms)::numeric as avg_response_ms,
    stddev_pop(case when e.outcome = 'correct' then 1.0 else 0.0 end) as outcome_deviation
  from private.atina_performance_events e
  join private.atina_player_accounts a on a.player_id = e.actor_id
  left join private.atina_players p on p.id = e.actor_id
  where e.outcome in ('correct', 'wrong', 'timeout', 'pass')
  group by e.actor_id
  having count(*) >= 1
),
bot_performance as (
  select
    'profile:' || b.id::text as player_key,
    b.nickname as player_name,
    count(*)::integer as attempts,
    avg(case when e.is_correct then 1.0 else 0.0 end) as accuracy_rate,
    coalesce(
      avg(case when e.is_correct then greatest(0, least(20, coalesce(e.points, 0))) / 20.0 end),
      0.0
    ) as difficulty_rate,
    ((b.response_min_seconds + b.response_max_seconds) / 2.0 * 1000.0)::numeric as avg_response_ms,
    stddev_pop(case when e.is_correct then 1.0 else 0.0 end) as outcome_deviation
  from private.atina_v2_bot_competition_events e
  join private.atina_v2_bot_profiles b on b.id = e.bot_profile_id
  where e.source in ('simulation', 'room')
  group by b.id, b.nickname, b.response_min_seconds, b.response_max_seconds
  having count(*) >= 1
),
per_player as (
  select * from human_performance
  union all
  select * from bot_performance
),
ranked as (
  select pp.*,
    case when pp.avg_response_ms is null then 0::numeric
      else 1.0 - percent_rank() over (order by pp.avg_response_ms asc nulls last)
    end as speed_rate
  from per_player pp
),
components as (
  select r.*,
    greatest(0.0, least(1.0, coalesce(r.accuracy_rate, 0))) as accuracy_part,
    greatest(0.0, least(1.0, coalesce(r.difficulty_rate, 0))) as difficulty_part,
    greatest(0.0, least(1.0, coalesce(r.speed_rate, 0))) as speed_part,
    greatest(0.0, least(1.0, 1.0 - 2.0 * coalesce(r.outcome_deviation, 0))) as consistency_part
  from ranked r
)
select
  c.player_name,
  round(200.0 * (
    0.40 * c.accuracy_part +
    0.25 * c.difficulty_part +
    0.15 * c.speed_part +
    0.20 * c.consistency_part
  ))::integer,
  c.attempts,
  round((c.accuracy_part * 100)::numeric, 1),
  round((c.difficulty_part * 100)::numeric, 1),
  round((c.speed_part * 100)::numeric, 1),
  round((c.consistency_part * 100)::numeric, 1)
from components c
order by 2 desc, 3 desc, 1 asc
limit least(greatest(coalesce(p_limit, 15), 1), 100);
$function$;
