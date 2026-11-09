-- Award the actual points earned in the V2 round to the account ranking total.
-- The unique event key makes the award idempotent even when the client retries.
alter table private.atina_xp_events
  drop constraint if exists atina_xp_events_xp_check;
alter table private.atina_xp_events
  add constraint atina_xp_events_xp_check check (xp > 0);

create or replace function public.atina_progress_claim_local(
  p_device_token text,
  p_session_id uuid,
  p_session_token text,
  p_position integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_player private.atina_players;
  v_session private.atina_v2_local_sessions;
  v_owner private.atina_xp_session_owners;
  v_inserted bigint;
  v_today date := current_date;
  v_daily_count integer;
  v_award integer;
begin
  if p_device_token is null or p_device_token !~ '^[0-9a-f]{64}$'
     or p_session_id is null or p_session_token is null
     or p_session_token !~ '^[0-9a-f]{64}$'
     or p_position is null or p_position < 1 then
    raise exception 'Pedido de progressão inválido.' using errcode = '22023';
  end if;

  select * into v_player from private.atina_players
   where device_token_hash = extensions.digest(convert_to(p_device_token, 'UTF8'), 'sha256')
      or id = (
        select a.player_id from private.atina_player_accounts a
         where a.session_token_hash = extensions.digest(convert_to(p_device_token, 'UTF8'), 'sha256')
           and a.session_expires_at > clock_timestamp() limit 1
      ) for update;
  if not found then raise exception 'Inicia sessão para guardar os pontos.' using errcode = '28000'; end if;

  select * into v_session from private.atina_v2_local_sessions
   where id = p_session_id
     and token_hash = extensions.digest(convert_to(p_session_token, 'UTF8'), 'sha256')
   for update;
  if not found or v_session.position <> p_position or not v_session.round_locked
     or v_session.last_result ->> 'outcome' is distinct from 'correct'
     or v_session.expires_at <= clock_timestamp() then
    raise exception 'O servidor ainda não confirmou este desafio como concluído.' using errcode = '55000';
  end if;

  select * into v_owner from private.atina_xp_session_owners
   where session_id = p_session_id for update;
  if not found or v_owner.player_id <> v_player.id then
    raise exception 'Esta sessão não está associada a esta conta.' using errcode = '42501';
  end if;

  v_award := coalesce((v_session.last_result ->> 'points')::integer, 0);
  if v_award <= 0 then raise exception 'Não foi possível confirmar os pontos deste desafio.' using errcode = '55000'; end if;

  insert into private.atina_xp_events (player_id, session_id, challenge_position, xp)
  values (v_player.id, p_session_id, p_position, v_award)
  on conflict (player_id, session_id, challenge_position) do nothing
  returning id into v_inserted;

  if v_inserted is null then
    return jsonb_build_object('awarded', false, 'reason', 'already_claimed',
      'xp', v_player.total_xp, 'level', floor(v_player.total_xp / 250.0)::integer + 1,
      'total_challenges', v_player.total_challenges,
      'daily_count', case when v_player.daily_date = v_today then v_player.daily_count else 0 end);
  end if;

  v_daily_count := case when v_player.daily_date = v_today then v_player.daily_count + 1 else 1 end;
  update private.atina_players set total_xp = total_xp + v_award,
    total_challenges = total_challenges + 1, daily_date = v_today,
    daily_count = least(v_daily_count, 3), updated_at = clock_timestamp()
   where id = v_player.id returning * into v_player;

  return jsonb_build_object('awarded', true, 'challenge_xp', v_award, 'daily_bonus', 0,
    'xp', v_player.total_xp, 'level', floor(v_player.total_xp / 250.0)::integer + 1,
    'total_challenges', v_player.total_challenges, 'daily_count', v_player.daily_count);
end;
$function$;
