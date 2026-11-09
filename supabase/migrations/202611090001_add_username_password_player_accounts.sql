-- ATINA username/password player accounts (no email or phone).
-- Applied to the atina-development project; do not run against production without review.

create table if not exists private.atina_player_accounts (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null unique references private.atina_players(id) on delete cascade,
  nickname text not null,
  nickname_normalized text generated always as (lower(btrim(nickname))) stored,
  password_hash text not null,
  recovery_key_hash text not null,
  session_token_hash bytea,
  session_expires_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint atina_player_accounts_nickname_unique unique (nickname_normalized),
  constraint atina_player_accounts_nickname_length check (char_length(btrim(nickname)) between 1 and 20)
);
alter table private.atina_player_accounts enable row level security;

create or replace function public.atina_account_register(p_nickname text, p_password text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_device_token text;
  v_session_token text;
  v_recovery_key text;
  v_profile jsonb;
  v_player_id uuid;
  v_nickname text := btrim(coalesce(p_nickname,''));
begin
  if char_length(v_nickname) not between 1 and 20 or v_nickname !~ '^[[:alnum:]À-ÿ _.-]{1,20}$'
     or lower(v_nickname) = 'admin' then
    raise exception 'Pseudónimo inválido ou reservado (1 a 20 caracteres).' using errcode='22023';
  end if;
  if p_password is null or char_length(p_password) < 10 or char_length(p_password) > 128 then
    raise exception 'A palavra-passe deve ter entre 10 e 128 caracteres.' using errcode='22023';
  end if;
  if exists(select 1 from private.atina_player_accounts where nickname_normalized=lower(v_nickname)) then
    raise exception 'Este pseudónimo já está registado.' using errcode='23505';
  end if;
  v_device_token := encode(extensions.gen_random_bytes(32),'hex');
  v_profile := public.atina_progress_register(v_nickname,v_device_token);
  v_player_id := (v_profile->>'player_id')::uuid;
  v_session_token := encode(extensions.gen_random_bytes(32),'hex');
  v_recovery_key := encode(extensions.gen_random_bytes(24),'hex');
  insert into private.atina_player_accounts(player_id,nickname,password_hash,recovery_key_hash,session_token_hash,session_expires_at)
  values(v_player_id,v_nickname,extensions.crypt(p_password,extensions.gen_salt('bf',12)),
    extensions.digest(convert_to(v_recovery_key,'UTF8'),'sha256'),
    extensions.digest(convert_to(v_session_token,'UTF8'),'sha256'),
    clock_timestamp()+interval '30 days');
  return jsonb_build_object('session_token',v_session_token,'recovery_key',v_recovery_key,'profile',v_profile);
exception when unique_violation then
  raise exception 'Este pseudónimo já está registado.' using errcode='23505';
end;
$$;

create or replace function public.atina_account_login(p_nickname text,p_password text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_account private.atina_player_accounts; v_session_token text; v_profile jsonb;
begin
  select * into v_account from private.atina_player_accounts
   where nickname_normalized=lower(btrim(coalesce(p_nickname,''))) for update;
  if not found or p_password is null
     or v_account.password_hash <> extensions.crypt(p_password,v_account.password_hash) then
    raise exception 'Pseudónimo ou palavra-passe incorretos.' using errcode='28000';
  end if;
  v_session_token := encode(extensions.gen_random_bytes(32),'hex');
  update private.atina_player_accounts set session_token_hash=extensions.digest(convert_to(v_session_token,'UTF8'),'sha256'),
    session_expires_at=clock_timestamp()+interval '30 days',updated_at=clock_timestamp() where id=v_account.id;
  select jsonb_build_object('player_id',p.id,'nickname',p.nickname,'xp',p.total_xp,
    'level',floor(p.total_xp/250.0)::integer+1,'total_challenges',p.total_challenges,
    'daily_count',case when p.daily_date=current_date then p.daily_count else 0 end)
    into v_profile from private.atina_players p where p.id=v_account.player_id;
  return jsonb_build_object('session_token',v_session_token,'profile',v_profile);
end;
$$;

create or replace function public.atina_account_recover(p_nickname text,p_recovery_key text,p_new_password text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_account private.atina_player_accounts; v_session_token text;
begin
  if p_new_password is null or char_length(p_new_password)<10 or char_length(p_new_password)>128 then
    raise exception 'A nova palavra-passe deve ter entre 10 e 128 caracteres.' using errcode='22023';
  end if;
  select * into v_account from private.atina_player_accounts
   where nickname_normalized=lower(btrim(coalesce(p_nickname,''))) for update;
  if not found or p_recovery_key is null or
     v_account.recovery_key_hash <> extensions.digest(convert_to(p_recovery_key,'UTF8'),'sha256') then
    raise exception 'Pseudónimo ou chave de recuperação inválidos.' using errcode='28000';
  end if;
  v_session_token:=encode(extensions.gen_random_bytes(32),'hex');
  update private.atina_player_accounts set password_hash=extensions.crypt(p_new_password,extensions.gen_salt('bf',12)),
    session_token_hash=extensions.digest(convert_to(v_session_token,'UTF8'),'sha256'),
    session_expires_at=clock_timestamp()+interval '30 days',updated_at=clock_timestamp() where id=v_account.id;
  return jsonb_build_object('session_token',v_session_token,'recovered',true);
end;
$$;

create or replace function public.atina_account_profile(p_session_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_account private.atina_player_accounts; v_profile jsonb;
begin
  if p_session_token is null or p_session_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Sessão inválida.' using errcode='28000';
  end if;
  select * into v_account from private.atina_player_accounts
   where session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
     and session_expires_at>clock_timestamp();
  if not found then raise exception 'Sessão expirada. Inicia sessão novamente.' using errcode='28000'; end if;
  select jsonb_build_object('player_id',p.id,'nickname',p.nickname,'xp',p.total_xp,
    'level',floor(p.total_xp/250.0)::integer+1,'total_challenges',p.total_challenges,
    'daily_count',case when p.daily_date=current_date then p.daily_count else 0 end)
    into v_profile from private.atina_players p where p.id=v_account.player_id;
  return v_profile;
end;
$$;

revoke all on function public.atina_account_register(text,text) from public;
revoke all on function public.atina_account_login(text,text) from public;
revoke all on function public.atina_account_recover(text,text,text) from public;
revoke all on function public.atina_account_profile(text) from public;
grant execute on function public.atina_account_register(text,text) to anon, authenticated;
grant execute on function public.atina_account_login(text,text) to anon, authenticated;
grant execute on function public.atina_account_recover(text,text,text) to anon, authenticated;
grant execute on function public.atina_account_profile(text) to anon, authenticated;

-- Allow authenticated account sessions to resolve the existing XP player.
do $$
declare v_def text; v_old text; v_new text;
begin
  select pg_get_functiondef('public.atina_v2_start_local_game(text,text,text,integer,text)'::regprocedure) into v_def;
  v_old := $old$
    select id into v_player_id
      from private.atina_players
     where device_token_hash=extensions.digest(convert_to(p_device_token,'UTF8'),'sha256');
$old$;
  v_new := $new$
    select coalesce(
      (select a.player_id from private.atina_player_accounts a
        where a.session_token_hash=extensions.digest(convert_to(p_device_token,'UTF8'),'sha256')
          and a.session_expires_at>clock_timestamp()),
      (select p.id from private.atina_players p
        where p.device_token_hash=extensions.digest(convert_to(p_device_token,'UTF8'),'sha256'))
    ) into v_player_id;
$new$;
  if position(v_old in v_def)=0 then raise exception 'Could not safely patch atina_v2_start_local_game'; end if;
  execute replace(v_def,v_old,v_new);

  select pg_get_functiondef('public.atina_progress_claim_local(text,uuid,text,integer)'::regprocedure) into v_def;
  v_old := $old$
   where device_token_hash =
     extensions.digest(convert_to(p_device_token, 'UTF8'), 'sha256')
   for update;
$old$;
  v_new := $new$
   where device_token_hash =
     extensions.digest(convert_to(p_device_token, 'UTF8'), 'sha256')
      or id = (
        select a.player_id from private.atina_player_accounts a
         where a.session_token_hash=extensions.digest(convert_to(p_device_token,'UTF8'),'sha256')
           and a.session_expires_at>clock_timestamp()
      )
   for update;
$new$;
  if position(v_old in v_def)=0 then raise exception 'Could not safely patch atina_progress_claim_local'; end if;
  execute replace(v_def,v_old,v_new);
end $$;
