-- Multiplayer server-authoritative challenge count.
-- Adds count validation and limits the no-repeat queue to the requested number.
-- This migration is committed only to an isolated branch; it has NOT been executed.
DROP FUNCTION IF EXISTS public.atina_v2_start_room_challenges(uuid,text,text,integer,text);
create or replace function public.atina_v2_start_room_challenges(
  p_room_id uuid,
  p_token text,
  p_difficulty text default 'medium',
  p_duration_seconds integer default 60,
  p_category text default null,
  p_challenge_count integer default 10
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_host public.atina_v2_room_players%rowtype;
  v_room public.atina_v2_rooms%rowtype;
  v_queue integer[];
  v_now timestamptz;
  v_deadline timestamptz;
  v_challenge private.atina_challenges%rowtype;
  v_state jsonb;
begin
  if p_challenge_count is null or p_challenge_count not between 1 and 1000 then
    raise exception 'Quantidade de desafios inválida.';
  end if;
  if p_difficulty is null or p_difficulty not in ('easy','medium','hard') then
    raise exception 'Dificuldade inválida.';
  end if;
  if p_duration_seconds is null or p_duration_seconds not between 0 and 3600 then
    raise exception 'Duração inválida.';
  end if;
  if p_category is not null and char_length(btrim(p_category)) not between 1 and 80 then
    raise exception 'Categoria inválida.';
  end if;

  select * into v_host from public.atina_v2_room_players
   where room_id=p_room_id
     and token_hash=extensions.digest(coalesce(p_token,''),'sha256')
   for update;
  if not found or not v_host.is_host then
    raise exception 'Só o anfitrião pode iniciar os desafios.';
  end if;

  select * into v_room from public.atina_v2_rooms where id=p_room_id for update;
  if not found or v_room.status<>'playing' or v_room.game_state->>'mode'<>'pending' then
    raise exception 'A sala não está preparada para iniciar os desafios.';
  end if;

  select array_agg(q.challenge_id order by q.random_order)
    into v_queue
    from (
      select c.challenge_id, random() as random_order
        from private.atina_challenges c
       where c.active and c.difficulty=p_difficulty
         and (p_category is null or c.category=p_category)
         and not exists (
           select 1
             from private.atina_room_challenge_scopes(p_room_id) s
             join private.atina_challenge_exposures e
               on e.scope_type=s.scope_type and e.scope_key=s.scope_key
            where e.challenge_id=c.challenge_id
         )
       order by random()
       limit p_challenge_count
    ) q;

  if coalesce(cardinality(v_queue),0)=0 then
    raise exception 'Esta equipa já viu todos os desafios disponíveis para estes critérios. Experimenta outra categoria ou dificuldade.';
  end if;

  v_now:=clock_timestamp();
  v_deadline:=case when p_duration_seconds=0 then null
    else v_now+make_interval(secs=>p_duration_seconds) end;

  insert into private.atina_v2_room_game_state(
    room_id,challenge_queue,position,difficulty,category,timed_mode_seconds,
    revealed_clues,deadline_at,round_locked,status,created_at,updated_at
  ) values (
    p_room_id,v_queue,1,p_difficulty,p_category,p_duration_seconds,
    1,v_deadline,false,'active',v_now,v_now
  );

  perform private.atina_record_room_challenge_exposure(p_room_id,v_queue[1]);

  select * into v_challenge from private.atina_challenges
   where challenge_id=v_queue[1] and active;

  v_state:=jsonb_build_object(
    'mode','challenges','protocol_version',1,
    'challenge_id',v_challenge.challenge_id,'category',v_challenge.category,
    'emoji',v_challenge.emoji,'clues',jsonb_build_array(v_challenge.clues->0),
    'image_url',v_challenge.image_url,'pos',0,'queue_length',cardinality(v_queue),
    'revealed',1,'timedMode',p_duration_seconds,
    'deadline',case when v_deadline is null then 0 else extract(epoch from v_deadline)*1000 end,
    'locked',false,'revision',v_room.state_version+1
  );

  update public.atina_v2_rooms
     set game_state=v_state,state_version=state_version+1,updated_at=v_now
   where id=p_room_id;

  return jsonb_build_object('status','started','queue_length',cardinality(v_queue),'state',v_state);
end;
$function$;
revoke all on function public.atina_v2_start_room_challenges(uuid,text,text,integer,text,integer) from public;
grant execute on function public.atina_v2_start_room_challenges(uuid,text,text,integer,text,integer) to anon,authenticated;
