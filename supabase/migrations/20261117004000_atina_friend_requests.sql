-- ATINA friendship requests for authenticated player accounts.
-- Private records; every operation is mediated by SECURITY DEFINER RPCs that validate account sessions.

create table if not exists private.atina_player_friendships (
  id uuid primary key default extensions.gen_random_uuid(),
  requester_player_id uuid not null references private.atina_players(id) on delete cascade,
  addressee_player_id uuid not null references private.atina_players(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default clock_timestamp(),
  responded_at timestamptz,
  constraint atina_player_friendships_no_self check (requester_player_id <> addressee_player_id)
);
create unique index if not exists atina_player_friendships_pair_uidx
  on private.atina_player_friendships
  (least(requester_player_id,addressee_player_id),greatest(requester_player_id,addressee_player_id));
create index if not exists atina_player_friendships_addressee_pending_idx
  on private.atina_player_friendships(addressee_player_id,created_at desc)
  where status='pending';
create index if not exists atina_player_friendships_requester_pending_idx
  on private.atina_player_friendships(requester_player_id,created_at desc)
  where status='pending';

alter table private.atina_player_friendships enable row level security;
revoke all on table private.atina_player_friendships from public,anon,authenticated;

create or replace function public.atina_friendship_list(p_session_token text)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_player_id uuid; v_friends jsonb; v_incoming jsonb; v_outgoing jsonb;
begin
  if p_session_token is null or p_session_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Sessão inválida.' using errcode='28000';
  end if;
  select a.player_id into v_player_id from private.atina_player_accounts a
   where a.session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
     and a.session_expires_at>clock_timestamp();
  if v_player_id is null then raise exception 'Sessão expirada. Inicia sessão novamente.' using errcode='28000'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('nickname',p.nickname,'friend_since',f.responded_at) order by p.nickname),'[]'::jsonb)
    into v_friends
    from private.atina_player_friendships f
    join private.atina_players p on p.id=case when f.requester_player_id=v_player_id then f.addressee_player_id else f.requester_player_id end
   where f.status='accepted' and (f.requester_player_id=v_player_id or f.addressee_player_id=v_player_id);

  select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'nickname',p.nickname,'requested_at',f.created_at) order by f.created_at desc),'[]'::jsonb)
    into v_incoming
    from private.atina_player_friendships f
    join private.atina_players p on p.id=f.requester_player_id
   where f.addressee_player_id=v_player_id and f.status='pending';

  select coalesce(jsonb_agg(jsonb_build_object('nickname',p.nickname,'requested_at',f.created_at) order by f.created_at desc),'[]'::jsonb)
    into v_outgoing
    from private.atina_player_friendships f
    join private.atina_players p on p.id=f.addressee_player_id
   where f.requester_player_id=v_player_id and f.status='pending';

  return jsonb_build_object('friends',v_friends,'incoming',v_incoming,'outgoing',v_outgoing);
end;
$function$;

create or replace function public.atina_friendship_request(p_session_token text,p_nickname text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_player_id uuid; v_target_id uuid; v_target_nickname text; v_existing private.atina_player_friendships%rowtype;
begin
  if p_session_token is null or p_session_token !~ '^[0-9a-f]{64}$' then raise exception 'Sessão inválida.' using errcode='28000'; end if;
  select a.player_id into v_player_id from private.atina_player_accounts a
   where a.session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
     and a.session_expires_at>clock_timestamp();
  if v_player_id is null then raise exception 'Sessão expirada. Inicia sessão novamente.' using errcode='28000'; end if;
  if p_nickname is null or char_length(btrim(p_nickname)) not between 1 and 20 then
    raise exception 'Introduz um pseudónimo válido.' using errcode='22023';
  end if;
  select a.player_id,p.nickname into v_target_id,v_target_nickname
    from private.atina_player_accounts a join private.atina_players p on p.id=a.player_id
   where a.nickname_normalized=lower(btrim(p_nickname));
  if v_target_id is null then raise exception 'Não foi encontrada uma conta ATINA com esse pseudónimo.' using errcode='P0002'; end if;
  if v_target_id=v_player_id then raise exception 'Não podes enviar um pedido de amizade a ti próprio.' using errcode='22023'; end if;

  select * into v_existing from private.atina_player_friendships f
   where (f.requester_player_id=v_player_id and f.addressee_player_id=v_target_id)
      or (f.requester_player_id=v_target_id and f.addressee_player_id=v_player_id) for update;
  if found then
    if v_existing.status='accepted' then return jsonb_build_object('status','accepted','nickname',v_target_nickname);
    elsif v_existing.status='pending' and v_existing.requester_player_id=v_target_id then
      update private.atina_player_friendships set status='accepted',responded_at=clock_timestamp() where id=v_existing.id;
      return jsonb_build_object('status','accepted','nickname',v_target_nickname);
    elsif v_existing.status='pending' then
      raise exception 'Já enviaste um pedido a este jogador. Aguarda a resposta.' using errcode='23505';
    else
      update private.atina_player_friendships set requester_player_id=v_player_id,addressee_player_id=v_target_id,
        status='pending',created_at=clock_timestamp(),responded_at=null where id=v_existing.id;
      return jsonb_build_object('status','pending','nickname',v_target_nickname);
    end if;
  end if;
  insert into private.atina_player_friendships(requester_player_id,addressee_player_id) values(v_player_id,v_target_id);
  return jsonb_build_object('status','pending','nickname',v_target_nickname);
end;
$function$;

create or replace function public.atina_friendship_respond(p_session_token text,p_request_id uuid,p_accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_player_id uuid; v_friendship private.atina_player_friendships%rowtype;
begin
  if p_session_token is null or p_session_token !~ '^[0-9a-f]{64}$' then raise exception 'Sessão inválida.' using errcode='28000'; end if;
  select a.player_id into v_player_id from private.atina_player_accounts a
   where a.session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
     and a.session_expires_at>clock_timestamp();
  if v_player_id is null then raise exception 'Sessão expirada. Inicia sessão novamente.' using errcode='28000'; end if;
  select * into v_friendship from private.atina_player_friendships f
   where f.id=p_request_id and f.addressee_player_id=v_player_id and f.status='pending' for update;
  if not found then raise exception 'Este pedido já não está disponível.' using errcode='P0002'; end if;
  update private.atina_player_friendships set status=case when coalesce(p_accept,false) then 'accepted' else 'declined' end,
    responded_at=clock_timestamp() where id=v_friendship.id;
  return jsonb_build_object('status',case when coalesce(p_accept,false) then 'accepted' else 'declined' end);
end;
$function$;

revoke all on function public.atina_friendship_list(text) from public;
revoke all on function public.atina_friendship_request(text,text) from public;
revoke all on function public.atina_friendship_respond(text,uuid,boolean) from public;
grant execute on function public.atina_friendship_list(text) to anon,authenticated;
grant execute on function public.atina_friendship_request(text,text) to anon,authenticated;
grant execute on function public.atina_friendship_respond(text,uuid,boolean) to anon,authenticated;
