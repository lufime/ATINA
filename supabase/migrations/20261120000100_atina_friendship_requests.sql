-- ATINA social friendship requests. Player-account sessions are the only authorization.
create table if not exists private.atina_friend_requests(
 id uuid primary key default gen_random_uuid(),
 sender_player_id uuid not null references private.atina_players(id) on delete cascade,
 recipient_player_id uuid not null references private.atina_players(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','accepted','declined','cancelled')),
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default clock_timestamp()+interval '30 days',
 check(sender_player_id<>recipient_player_id)
);
create unique index if not exists atina_friend_request_pending_pair
 on private.atina_friend_requests(sender_player_id,recipient_player_id) where status='pending';
create table if not exists private.atina_friendships(
 player_a uuid not null references private.atina_players(id) on delete cascade,
 player_b uuid not null references private.atina_players(id) on delete cascade,
 created_at timestamptz not null default clock_timestamp(),
 primary key(player_a,player_b),
 check(player_a<player_b)
);
alter table private.atina_friend_requests enable row level security;
alter table private.atina_friendships enable row level security;
revoke all on private.atina_friend_requests,private.atina_friendships from public,anon,authenticated;

create or replace function public.atina_social_send_friend_request(p_session_token text,p_target_nickname text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_sender uuid; v_recipient uuid;
begin
 select player_id into v_sender from private.atina_player_accounts
 where session_token_hash=extensions.digest(convert_to(coalesce(p_session_token,''),'UTF8'),'sha256')
 and session_expires_at>clock_timestamp();
 if v_sender is null then raise exception 'Sessão expirada. Inicia sessão novamente.'; end if;
 select player_id into v_recipient from private.atina_player_accounts
 where nickname_normalized=lower(btrim(coalesce(p_target_nickname,'')));
 if v_recipient is null then raise exception 'Jogador não encontrado.'; end if;
 if v_sender=v_recipient then raise exception 'Não podes adicionar-te a ti próprio.'; end if;
 if exists(select 1 from private.atina_friendships where player_a=least(v_sender,v_recipient) and player_b=greatest(v_sender,v_recipient)) then
  return jsonb_build_object('status','friends','message','Já são amigos.');
 end if;
 if exists(select 1 from private.atina_friend_requests where sender_player_id=v_recipient and recipient_player_id=v_sender and status='pending') then
  return jsonb_build_object('status','incoming_exists','message','Este jogador já te enviou um pedido. Consulta os pedidos recebidos.');
 end if;
 insert into private.atina_friend_requests(sender_player_id,recipient_player_id)
 values(v_sender,v_recipient) on conflict(sender_player_id,recipient_player_id) where status='pending' do nothing;
 return jsonb_build_object('status','sent','message','Pedido de amizade enviado!');
end $$;

create or replace function public.atina_social_list(p_session_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid;
begin
 select player_id into v_me from private.atina_player_accounts
 where session_token_hash=extensions.digest(convert_to(coalesce(p_session_token,''),'UTF8'),'sha256')
 and session_expires_at>clock_timestamp();
 if v_me is null then raise exception 'Sessão expirada. Inicia sessão novamente.'; end if;
 return jsonb_build_object(
  'friends',coalesce((select jsonb_agg(jsonb_build_object('player_id',p.player_id,'nickname',p.nickname) order by p.nickname)
   from private.atina_friendships f join private.atina_player_accounts p on p.player_id=case when f.player_a=v_me then f.player_b else f.player_a end
   where f.player_a=v_me or f.player_b=v_me),'[]'::jsonb),
  'incoming',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'nickname',p.nickname,'created_at',r.created_at) order by r.created_at desc)
   from private.atina_friend_requests r join private.atina_player_accounts p on p.player_id=r.sender_player_id
   where r.recipient_player_id=v_me and r.status='pending' and r.expires_at>clock_timestamp()),'[]'::jsonb),
  'outgoing',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'nickname',p.nickname,'created_at',r.created_at) order by r.created_at desc)
   from private.atina_friend_requests r join private.atina_player_accounts p on p.player_id=r.recipient_player_id
   where r.sender_player_id=v_me and r.status='pending' and r.expires_at>clock_timestamp()),'[]'::jsonb)
 );
end $$;

create or replace function public.atina_social_friend_response(p_session_token text,p_request_id uuid,p_accept boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid; v_req private.atina_friend_requests%rowtype;
begin
 select player_id into v_me from private.atina_player_accounts
 where session_token_hash=extensions.digest(convert_to(coalesce(p_session_token,''),'UTF8'),'sha256') and session_expires_at>clock_timestamp();
 if v_me is null then raise exception 'Sessão expirada. Inicia sessão novamente.'; end if;
 select * into v_req from private.atina_friend_requests where id=p_request_id and recipient_player_id=v_me and status='pending' for update;
 if not found then raise exception 'Pedido já respondido ou indisponível.'; end if;
 if p_accept then
  insert into private.atina_friendships(player_a,player_b) values(least(v_req.sender_player_id,v_req.recipient_player_id),greatest(v_req.sender_player_id,v_req.recipient_player_id)) on conflict do nothing;
  update private.atina_friend_requests set status='accepted',updated_at=clock_timestamp() where id=p_request_id;
  update private.atina_friend_requests set status='cancelled',updated_at=clock_timestamp()
   where status='pending' and ((sender_player_id=v_req.sender_player_id and recipient_player_id=v_req.recipient_player_id) or (sender_player_id=v_req.recipient_player_id and recipient_player_id=v_req.sender_player_id));
  return jsonb_build_object('status','accepted','message','Pedido de amizade aceite!');
 end if;
 update private.atina_friend_requests set status='declined',updated_at=clock_timestamp() where id=p_request_id;
 return jsonb_build_object('status','declined','message','Pedido de amizade recusado.');
end $$;

create or replace function public.atina_social_cancel_friend_request(p_session_token text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid;
begin
 select player_id into v_me from private.atina_player_accounts
 where session_token_hash=extensions.digest(convert_to(coalesce(p_session_token,''),'UTF8'),'sha256') and session_expires_at>clock_timestamp();
 if v_me is null then raise exception 'Sessão expirada. Inicia sessão novamente.'; end if;
 update private.atina_friend_requests set status='cancelled',updated_at=clock_timestamp()
 where id=p_request_id and sender_player_id=v_me and status='pending';
 if not found then raise exception 'Pedido já não está pendente.'; end if;
 return jsonb_build_object('status','cancelled');
end $$;

revoke all on function public.atina_social_send_friend_request(text,text) from public;
revoke all on function public.atina_social_list(text) from public;
revoke all on function public.atina_social_friend_response(text,uuid,boolean) from public;
revoke all on function public.atina_social_cancel_friend_request(text,uuid) from public;
grant execute on function public.atina_social_send_friend_request(text,text) to anon,authenticated;
grant execute on function public.atina_social_list(text) to anon,authenticated;
grant execute on function public.atina_social_friend_response(text,uuid,boolean) to anon,authenticated;
grant execute on function public.atina_social_cancel_friend_request(text,uuid) to anon,authenticated;
