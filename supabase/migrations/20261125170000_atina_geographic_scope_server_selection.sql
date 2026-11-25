-- Enforce geographic scope in the authoritative server-side Solo/Mix selector.
-- Code-only proposal. Do not apply to production without separate deployment approval.
-- The legacy overload remains available; this overload requires p_geographic_scope.

CREATE OR REPLACE FUNCTION public.atina_v2_start_local_game(p_game_mode text, p_difficulty text, p_challenge_count integer, p_geographic_scope text, p_category text DEFAULT NULL::text, p_timed_mode_seconds integer DEFAULT 60, p_device_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_token text;
  v_queue integer[];
  v_session private.atina_v2_local_sessions;
  v_player_id uuid;
begin
  if p_game_mode is null or p_game_mode not in ('solo','duel','mix','party') then
    raise exception 'Modo inválido.' using errcode='22023';
  end if;
  if p_difficulty is null or p_difficulty not in ('easy','medium','hard','mixed') then
    raise exception 'Dificuldade inválida.' using errcode='22023';
  end if;
  if p_challenge_count is null or p_challenge_count not between 1 and 1000 then
    raise exception 'Quantidade de desafios inválida.' using errcode='22023';
  end if;
  if p_timed_mode_seconds is null or p_timed_mode_seconds not between 0 and 3600 then
    raise exception 'Duração inválida.' using errcode='22023';
  end if;
  if p_category is not null and length(trim(p_category))=0 then
    raise exception 'Categoria inválida.' using errcode='22023';
  end if;

  if p_geographic_scope is null or p_geographic_scope not in ('Todos','Portugal','Internacional','Universal') then
    raise exception 'Âmbito geográfico inválido.' using errcode='22023';
  end if;

  if p_device_token is not null then
    if p_game_mode not in ('solo','mix') then
      raise exception 'A progressão individual só está disponível em Solo e Mix.' using errcode='22023';
    end if;
    if p_device_token !~ '^[0-9a-f]{64}$' then
      raise exception 'Identificador de sessão inválido.' using errcode='28000';
    end if;
    select coalesce(
      (select a.player_id from private.atina_player_accounts a
        where a.session_token_hash=extensions.digest(convert_to(p_device_token,'UTF8'),'sha256')
          and a.session_expires_at>clock_timestamp()),
      (select p.id from private.atina_players p
        where p.device_token_hash=extensions.digest(convert_to(p_device_token,'UTF8'),'sha256'))
    ) into v_player_id;
    if v_player_id is null then
      raise exception 'Sessão expirada. Inicia sessão novamente.' using errcode='28000';
    end if;
  end if;

  if p_game_mode='mix' or p_difficulty='mixed' then
    with eligible as (
      select c.challenge_id,c.category,
             row_number() over (partition by c.category order by random()) as category_rank,
             random() as tie_order
        from private.atina_challenges c
       where c.active
         and (p_geographic_scope='Todos' or c.geographic_scope=p_geographic_scope)
         and (p_category is null or c.category=p_category)
         and (p_difficulty='mixed' or c.difficulty=p_difficulty)
         and not exists (
           select 1 from private.atina_challenge_exposures e
            where e.scope_type='player' and e.scope_key=v_player_id::text
              and e.challenge_id=c.challenge_id
         )
    )
    select array_agg(challenge_id order by category_rank,tie_order)
      into v_queue
      from (select challenge_id,category_rank,tie_order from eligible
             order by category_rank,tie_order limit p_challenge_count) chosen;
 else
    select array_agg(c.challenge_id order by random()) into v_queue
      from private.atina_challenges c
     where c.active
         and (p_geographic_scope='Todos' or c.geographic_scope=p_geographic_scope) and c.difficulty=p_difficulty
       and (p_category is null or c.category=p_category)
       and not exists (
         select 1 from private.atina_challenge_exposures e
          where e.scope_type='player' and e.scope_key=v_player_id::text
            and e.challenge_id=c.challenge_id
       );
  end if;

  -- If personal history exhausted the unseen pool, recycle eligible active challenges.
  -- Fill the requested count with previously seen active challenges if unseen pool is short.
  if coalesce(cardinality(v_queue),0)<p_challenge_count then
    if p_game_mode='mix' or p_difficulty='mixed' then
      v_queue:=coalesce(v_queue,ARRAY[]::integer[])||coalesce((
        select array_agg(c.challenge_id order by random())
          from (select c.challenge_id from private.atina_challenges c
                 where c.active
         and (p_geographic_scope='Todos' or c.geographic_scope=p_geographic_scope) and (p_category is null or c.category=p_category)
                   and not (c.challenge_id=any(coalesce(v_queue,ARRAY[]::integer[])))
                 order by random() limit p_challenge_count-cardinality(coalesce(v_queue,ARRAY[]::integer[]))) c
      ),ARRAY[]::integer[]);
    else
      v_queue:=coalesce(v_queue,ARRAY[]::integer[])||coalesce((
        select array_agg(c.challenge_id order by random())
          from (select c.challenge_id from private.atina_challenges c
                 where c.active
         and (p_geographic_scope='Todos' or c.geographic_scope=p_geographic_scope) and c.difficulty=p_difficulty
                   and (p_category is null or c.category=p_category)
                   and not (c.challenge_id=any(coalesce(v_queue,ARRAY[]::integer[])))
                 order by random() limit p_challenge_count-cardinality(coalesce(v_queue,ARRAY[]::integer[]))) c
      ),ARRAY[]::integer[]);
    end if;
  end if;
  if coalesce(cardinality(v_queue),0)=0 then
    if p_game_mode='mix' or p_difficulty='mixed' then
      select array_agg(c.challenge_id order by random()) into v_queue
        from private.atina_challenges c
       where c.active
         and (p_geographic_scope='Todos' or c.geographic_scope=p_geographic_scope) and (p_category is null or c.category=p_category);
    else
      select array_agg(c.challenge_id order by random()) into v_queue
        from private.atina_challenges c
       where c.active
         and (p_geographic_scope='Todos' or c.geographic_scope=p_geographic_scope) and c.difficulty=p_difficulty
         and (p_category is null or c.category=p_category);
    end if;
  end if;
  -- Fill the requested count with previously seen active challenges if unseen pool is short.
  if coalesce(cardinality(v_queue),0)<p_challenge_count then
    if p_game_mode='mix' or p_difficulty='mixed' then
      v_queue:=coalesce(v_queue,ARRAY[]::integer[])||coalesce((
        select array_agg(c.challenge_id order by random())
          from (select c.challenge_id from private.atina_challenges c
                 where c.active
         and (p_geographic_scope='Todos' or c.geographic_scope=p_geographic_scope) and (p_category is null or c.category=p_category)
                   and not (c.challenge_id=any(coalesce(v_queue,ARRAY[]::integer[])))
                 order by random() limit p_challenge_count-cardinality(coalesce(v_queue,ARRAY[]::integer[]))) c
      ),ARRAY[]::integer[]);
    else
      v_queue:=coalesce(v_queue,ARRAY[]::integer[])||coalesce((
        select array_agg(c.challenge_id order by random())
          from (select c.challenge_id from private.atina_challenges c
                 where c.active
         and (p_geographic_scope='Todos' or c.geographic_scope=p_geographic_scope) and c.difficulty=p_difficulty
                   and (p_category is null or c.category=p_category)
                   and not (c.challenge_id=any(coalesce(v_queue,ARRAY[]::integer[])))
                 order by random() limit p_challenge_count-cardinality(coalesce(v_queue,ARRAY[]::integer[]))) c
      ),ARRAY[]::integer[]);
    end if;
  end if;
  if coalesce(cardinality(v_queue),0)=0 then
    raise exception 'Já viste todos os desafios disponíveis para estes critérios. Experimenta outra categoria ou dificuldade.';
  end if;
  v_queue:=v_queue[1:least(p_challenge_count,cardinality(v_queue))];
  if p_game_mode='party' then
    v_queue:=v_queue[1:least(10,cardinality(v_queue))];
  end if;

  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into private.atina_v2_local_sessions (
    token_hash,game_mode,difficulty,category,timed_mode_seconds,
    challenge_queue,position,revealed_clues,current_player,scores,streaks,
    round_context,deadline_at,expires_at,special_card
  ) values (
    extensions.digest(convert_to(v_token,'UTF8'),'sha256'),
    p_game_mode,p_difficulty,p_category,p_timed_mode_seconds,
    v_queue,1,0,1,array[0,0],array[0,0],'{}'::jsonb,
    null,
    clock_timestamp()+interval '8 hours',null
  ) returning * into v_session;

  if v_player_id is not null then
    insert into private.atina_xp_session_owners(session_id,player_id)
    values(v_session.id,v_player_id);

    insert into private.atina_challenge_exposures(scope_type,scope_key,challenge_id)
    values('player',v_player_id::text,v_queue[1])
    on conflict(scope_type,scope_key,challenge_id) do nothing;
  end if;

  select * into v_session from private.atina_v2_local_sessions where id=v_session.id;
  return jsonb_build_object('token',v_token,'state',private.atina_v2_local_public_state(v_session));
end;
$function$
;

revoke all on function public.atina_v2_start_local_game(text,text,integer,text,text,integer,text) from public;
grant execute on function public.atina_v2_start_local_game(text,text,integer,text,text,integer,text) to anon, authenticated;

-- Improve Prague clues. The catalog is populated in production, but clean migration
-- replay environments may not contain challenge seed data; therefore these updates
-- intentionally do not assert a row count.
update private.atina_challenges
   set clues = jsonb_build_array(
     'A minha história foi marcada pela posição estratégica na Europa Central.',
     'O rio Vltava atravessa a cidade e passa sob uma ponte medieval decorada com esculturas.',
     'O Castelo de Praga ergue-se sobre a margem ocidental do rio.',
     'Durante o reinado de Carlos IV, tornei-me um importante centro político e cultural.',
     'A Ponte Carlos, o Castelo e o rio Vltava são marcos desta capital europeia.'
   )
 where challenge_id=199 and answer='Praga' and geographic_scope='Internacional';

update private.atina_challenges
   set clues = jsonb_build_array(
     'A Praça da Cidade Velha é conhecida por um relógio astronómico medieval.',
     'A Ponte Carlos liga as margens do rio Moldava e é ladeada por esculturas.',
     'O centro histórico reúne edifícios góticos, barrocos e renascentistas.',
     'O Castelo de Praga forma um vasto conjunto monumental sobre a cidade.',
     'A cidade foi capital do Reino da Boémia e teve um papel importante no Sacro Império Romano-Germânico.'
   )
 where challenge_id=1084 and answer='Praga' and geographic_scope='Internacional';
