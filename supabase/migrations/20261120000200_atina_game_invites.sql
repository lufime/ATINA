-- ATINA game invitations. Friendship and game invitations remain separate.
create table if not exists private.atina_game_invites(
 id uuid primary key default gen_random_uuid(),
 sender_player_id uuid not null references private.atina_players(id) on delete cascade,
 recipient_player_id uuid not null references private.atina_players(id) on delete cascade,
 room_id uuid not null references public.atina_rooms(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','accepted','declined','cancelled')),
 created_at timestamptz not null default clock_timestamp(),
 updated_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default clock_timestamp()+interval '48 hours',
 check(sender_player_id<>recipient_player_id)
);
create unique index if not exists atina_game_invite_pending_unique
 on private.atina_game_invites(sender_player_id,recipient_player_id,room_id) where status='pending';
alter table private.atina_game_invites enable row level security;
revoke all on private.atina_game_invites from public,anon,authenticated;

create or replace function public.atina_social_send_game_invite(p_session_token text,p_target_nickname text,p_room_code text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_sender uuid;v_recipient uuid;v_room_id uuid;
begin
 select player_id into v_sender from private.atina_player_accounts
 where session_token_hash=extensions.digest(convert_to(coalesce(p_session_token,''),'UTF8'),'sha256') and session_expires_at>clock_timestamp();
 if v_sender is null then raise exception 'Sessão expirada. Inicia sessão novamente.';end if;
 select player_id into v_recipient from private.atina_player_accounts where nickname_normalized=lower(btrim(coalesce(p_target_nickname,'')));
 if v_recipient is null then raise exception 'Jogador não encontrado.';end if;
 if v_sender=v_recipient then raise exception 'Não podes convidar-te a ti próprio.';end if;
 if not exists(select 1 from private.atina_friendships where player_a=least(v_sender,v_recipient) and player_b=greatest(v_sender,v_recipient)) then raise exception 'Só podes convidar amigos para jogar.';end if;
 select id into v_room_id from public.atina_rooms where code=upper(btrim(coalesce(p_room_code,''))) and status='waiting' and (select count(*) from public.atina_room_players p where p.room_id=atina_rooms.id)<max_players;
 if v_room_id is null then raise exception 'Sala inexistente ou partida já iniciada.';end if;
 insert into private.atina_game_invites(sender_player_id,recipient_player_id,room_id)
 values(v_sender,v_recipient,v_room_id) on conflict(sender_player_id,recipient_player_id,room_id) where status='pending' do nothing;
 return jsonb_build_object('status','sent','message','Convite para jogar enviado.');
end $$;

create or replace function public.atina_social_game_invites_list(p_session_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid;
begin
 select player_id into v_me from private.atina_player_accounts
 where session_token_hash=extensions.digest(convert_to(coalesce(p_session_token,''),'UTF8'),'sha256') and session_expires_at>clock_timestamp();
 if v_me is null then raise exception 'Sessão expirada. Inicia sessão novamente.';end if;
 return jsonb_build_object(
 'incoming',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'nickname',a.nickname,'room_code',r.code,'created_at',i.created_at) order by i.created_at desc)
 from private.atina_game_invites i join private.atina_player_accounts a on a.player_id=i.sender_player_id join public.atina_rooms r on r.id=i.room_id
 where i.recipient_player_id=v_me and i.status='pending' and i.expires_at>clock_timestamp() and r.status='waiting'),'[]'::jsonb),
 'outgoing',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'nickname',a.nickname,'room_code',r.code,'created_at',i.created_at) order by i.created_at desc)
 from private.atina_game_invites i join private.atina_player_accounts a on a.player_id=i.recipient_player_id join public.atina_rooms r on r.id=i.room_id
 where i.sender_player_id=v_me and i.status='pending' and i.expires_at>clock_timestamp() and r.status='waiting'),'[]'::jsonb));
end $$;

create or replace function public.atina_social_game_invite_response(p_session_token text,p_invite_id uuid,p_accept boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid;v_inv private.atina_game_invites%rowtype;v_code text;
begin
 select player_id into v_me from private.atina_player_accounts
 where session_token_hash=extensions.digest(convert_to(coalesce(p_session_token,''),'UTF8'),'sha256') and session_expires_at>clock_timestamp();
 if v_me is null then raise exception 'Sessão expirada. Inicia sessão novamente.';end if;
 select * into v_inv from private.atina_game_invites where id=p_invite_id and recipient_player_id=v_me and status='pending' and expires_at>clock_timestamp() for update;
 if not found then raise exception 'Convite expirado ou indisponível.';end if;
 if not exists(select 1 from public.atina_rooms r where r.id=v_inv.room_id and r.status='waiting' and (select count(*) from public.atina_room_players p where p.room_id=r.id)<r.max_players) then raise exception 'A sala já não está disponível ou está cheia.';end if;
 if p_accept then
  update private.atina_game_invites set status='accepted',updated_at=clock_timestamp() where id=p_invite_id;
  select code into v_code from public.atina_rooms where id=v_inv.room_id;
  return jsonb_build_object('status','accepted','room_code',v_code,'message','Convite aceite! A entrar na sala.');
 end if;
 update private.atina_game_invites set status='declined',updated_at=clock_timestamp() where id=p_invite_id;
 return jsonb_build_object('status','declined','message','Convite recusado.');
end $$;

create or replace function public.atina_social_cancel_game_invite(p_session_token text,p_invite_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_me uuid;
begin
 select player_id into v_me from private.atina_player_accounts
 where session_token_hash=extensions.digest(convert_to(coalesce(p_session_token,''),'UTF8'),'sha256') and session_expires_at>clock_timestamp();
 if v_me is null then raise exception 'Sessão expirada. Inicia sessão novamente.';end if;
 update private.atina_game_invites set status='cancelled',updated_at=clock_timestamp() where id=p_invite_id and sender_player_id=v_me and status='pending';
 if not found then raise exception 'Convite já não está pendente.';end if;
 return jsonb_build_object('status','cancelled');
end $$;

revoke all on function public.atina_social_send_game_invite(text,text,text) from public;
revoke all on function public.atina_social_game_invites_list(text) from public;
revoke all on function public.atina_social_game_invite_response(text,uuid,boolean) from public;
revoke all on function public.atina_social_cancel_game_invite(text,uuid) from public;
grant execute on function public.atina_social_send_game_invite(text,text,text) to anon,authenticated;
grant execute on function public.atina_social_game_invites_list(text) to anon,authenticated;
grant execute on function public.atina_social_game_invite_response(text,uuid,boolean) to anon,authenticated;
grant execute on function public.atina_social_cancel_game_invite(text,uuid) to anon,authenticated;
