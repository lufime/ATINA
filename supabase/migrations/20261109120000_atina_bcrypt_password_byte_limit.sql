-- pgcrypto bcrypt only incorporates the first 72 bytes of a password.
-- Reject longer UTF-8 passwords consistently instead of silently truncating them.
create or replace function public.atina_account_register(p_nickname text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_device_token text;
  v_session_token text;
  v_recovery_key text;
  v_profile jsonb;
  v_player_id uuid;
  v_nickname text := btrim(coalesce(p_nickname,''));
begin
  if char_length(v_nickname) not between 1 and 20
     or v_nickname !~ '^[[:alnum:]À-ÿ _.-]{1,20}$'
     or lower(v_nickname) = 'admin' then
    raise exception 'Pseudónimo inválido ou reservado (1 a 20 caracteres).' using errcode='22023';
  end if;
  if p_password is null or char_length(p_password) < 10
     or octet_length(convert_to(p_password,'UTF8')) > 72 then
    raise exception 'A palavra-passe deve ter pelo menos 10 caracteres e no máximo 72 bytes UTF-8.' using errcode='22023';
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
$function$;

create or replace function public.atina_account_login(p_nickname text,p_password text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account private.atina_player_accounts;
  v_session_token text;
  v_profile jsonb;
begin
  if p_password is null or octet_length(convert_to(p_password,'UTF8')) > 72 then
    raise exception 'Palavra-passe inválida. Se a palavra-passe antiga exceder 72 bytes, recupera a conta com a chave de recuperação.' using errcode='22023';
  end if;

  select * into v_account
    from private.atina_player_accounts
   where nickname_normalized=lower(btrim(coalesce(p_nickname,'')))
   for update;

  if not found or v_account.password_hash <> extensions.crypt(p_password,v_account.password_hash) then
    raise exception 'Pseudónimo ou palavra-passe incorretos.' using errcode='28000';
  end if;

  v_session_token := encode(extensions.gen_random_bytes(32),'hex');
  update private.atina_player_accounts
     set session_token_hash=extensions.digest(convert_to(v_session_token,'UTF8'),'sha256'),
         session_expires_at=clock_timestamp()+interval '30 days',
         updated_at=clock_timestamp()
   where id=v_account.id;

  select jsonb_build_object('player_id',p.id,'nickname',p.nickname,'xp',p.total_xp,
    'level',floor(p.total_xp/250.0)::integer+1,'total_challenges',p.total_challenges,
    'daily_count',case when p.daily_date=current_date then p.daily_count else 0 end)
    into v_profile
    from private.atina_players p
   where p.id=v_account.player_id;

  return jsonb_build_object('session_token',v_session_token,'profile',v_profile);
end;
$function$;

create or replace function public.atina_account_recover(p_nickname text,p_recovery_key text,p_new_password text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account private.atina_player_accounts;
  v_session_token text;
  v_new_recovery_key text;
begin
  if p_new_password is null or char_length(p_new_password)<10
     or octet_length(convert_to(p_new_password,'UTF8'))>72 then
    raise exception 'A nova palavra-passe deve ter pelo menos 10 caracteres e no máximo 72 bytes UTF-8.' using errcode='22023';
  end if;

  select * into v_account
    from private.atina_player_accounts
   where nickname_normalized=lower(btrim(coalesce(p_nickname,'')))
   for update;

  if not found or p_recovery_key is null
     or v_account.recovery_key_hash <> extensions.digest(convert_to(p_recovery_key,'UTF8'),'sha256') then
    raise exception 'Pseudónimo ou chave de recuperação inválidos.' using errcode='28000';
  end if;

  v_session_token := encode(extensions.gen_random_bytes(32),'hex');
  v_new_recovery_key := encode(extensions.gen_random_bytes(24),'hex');

  update private.atina_player_accounts
     set password_hash=extensions.crypt(p_new_password,extensions.gen_salt('bf',12)),
         recovery_key_hash=extensions.digest(convert_to(v_new_recovery_key,'UTF8'),'sha256'),
         session_token_hash=extensions.digest(convert_to(v_session_token,'UTF8'),'sha256'),
         session_expires_at=clock_timestamp()+interval '30 days',
         updated_at=clock_timestamp()
   where id=v_account.id;

  return jsonb_build_object('session_token',v_session_token,'recovery_key',v_new_recovery_key,'recovered',true);
end;
$function$;

revoke all on function public.atina_account_register(text,text) from public;
revoke all on function public.atina_account_login(text,text) from public;
revoke all on function public.atina_account_recover(text,text,text) from public;
grant execute on function public.atina_account_register(text,text) to anon,authenticated;
grant execute on function public.atina_account_login(text,text) to anon,authenticated;
grant execute on function public.atina_account_recover(text,text,text) to anon,authenticated;
