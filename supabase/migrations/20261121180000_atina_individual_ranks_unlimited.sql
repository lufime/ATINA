-- Individual rank lookup without the public Top 100 cap.
-- Proposal only: this migration is not applied to any database by this PR.
create or replace function public.atina_profile_individual_ranks(p_session_token text)
returns table(
  points integer,
  points_rank bigint,
  xp integer,
  xp_rank bigint,
  qi_score integer,
  qi_rank bigint,
  qi_challenges integer
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_player_id uuid;
begin
  if p_session_token is null or p_session_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Sessão inválida.' using errcode='28000';
  end if;

  select a.player_id into v_player_id
    from private.atina_player_accounts a
   where a.session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
     and a.session_expires_at>clock_timestamp();

  if v_player_id is null then
    raise exception 'Sessão expirada. Inicia sessão novamente.' using errcode='28000';
  end if;

  return query
  with point_ranked as (
    select p.id, p.total_points::integer as value,
      row_number() over(order by p.total_points desc,p.total_challenges desc,p.created_at asc) as position
    from private.atina_players p
  ),
  xp_ranked as (
    select p.id, p.total_xp::integer as value,
      row_number() over(order by p.total_xp desc,p.total_challenges desc,p.created_at asc) as position
    from private.atina_players p
  ),
  human_performance as (
    select e.actor_id as player_id,
      coalesce(max(a.nickname),max(p.nickname),max(e.nickname),'Jogador') as player_name,
      count(*)::integer as attempts,
      avg(case when e.outcome='correct' then 1.0 else 0.0 end) as accuracy_rate,
      avg(case lower(coalesce(e.difficulty,'')) when 'easy' then 1.0 when 'facil' then 1.0 when 'fácil' then 1.0
        when 'medium' then 2.0 when 'medio' then 2.0 when 'médio' then 2.0
        when 'hard' then 3.0 when 'dificil' then 3.0 when 'difícil' then 3.0 else null end)/3.0 as difficulty_rate,
      avg(e.response_ms)::numeric as avg_response_ms,
      stddev_pop(case when e.outcome='correct' then 1.0 else 0.0 end) as outcome_deviation
    from private.atina_performance_events e
    join private.atina_player_accounts a on a.player_id=e.actor_id
    left join private.atina_players p on p.id=e.actor_id
    where e.outcome in ('correct','wrong','timeout','pass')
    group by e.actor_id
    having count(*) filter(where e.outcome in ('correct','wrong')) > 10
  ),
  qi_speed as (
    select h.*,
      case when h.avg_response_ms is null then 0::numeric
        else 1.0-percent_rank() over(order by h.avg_response_ms asc nulls last) end as speed_rate
    from human_performance h
  ),
  qi_components as (
    select s.*,
      greatest(0.0,least(1.0,coalesce(s.accuracy_rate,0))) as accuracy_part,
      greatest(0.0,least(1.0,coalesce(s.difficulty_rate,0))) as difficulty_part,
      greatest(0.0,least(1.0,coalesce(s.speed_rate,0))) as speed_part,
      greatest(0.0,least(1.0,1.0-2.0*coalesce(s.outcome_deviation,0))) as consistency_part
    from qi_speed s
  ),
  qi_ranked as (
    select c.player_id,c.attempts,
      round(200.0*(0.40*c.accuracy_part+0.25*c.difficulty_part+0.15*c.speed_part+0.20*c.consistency_part))::integer as score,
      row_number() over(order by round(200.0*(0.40*c.accuracy_part+0.25*c.difficulty_part+0.15*c.speed_part+0.20*c.consistency_part)) desc,c.attempts desc,c.player_name asc) as position
    from qi_components c
  )
  select coalesce(pr.value,0)::integer,pr.position,
         coalesce(xr.value,0)::integer,xr.position,
         coalesce(qr.score,0)::integer,qr.position,coalesce(qr.attempts,0)::integer
    from private.atina_players p
    left join point_ranked pr on pr.id=p.id
    left join xp_ranked xr on xr.id=p.id
    left join qi_ranked qr on qr.player_id=p.id
   where p.id=v_player_id;
end;
$function$;

grant execute on function public.atina_profile_individual_ranks(text) to anon, service_role;
revoke execute on function public.atina_profile_individual_ranks(text) from authenticated;
