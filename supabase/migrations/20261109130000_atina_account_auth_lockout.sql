-- Per-account throttling for password login and recovery.
-- Failed attempts are returned as ordinary JSON so counters commit instead of
-- being rolled back by an exception. The existing per-IP PostgREST limiter
-- remains an independent outer layer.

create table if not exists private.atina_account_auth_failures (
  account_id uuid primary key references private.atina_player_accounts(id) on delete cascade,
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  window_started_at timestamptz not null default clock_timestamp(),
  locked_until timestamptz,
  updated_at timestamptz not null default clock_timestamp()
);
alter table private.atina_account_auth_failures enable row level security;
revoke all on private.atina_account_auth_failures from public, anon, authenticated;

create or replace function public.atina_account_login(p_nickname text,p_password text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_account private.atina_player_accounts;
  v_failure private.atina_account_auth_failures;
  v_session_token text;
  v_profile jsonb;
  v_now timestamptz := clock_timestamp();
begin
  if p_password is null or octet_length(convert_to(p_password,'UTF8')) > 72 then
    return jsonb_build_object('ok',false,'message','Pseudónimo ou palavra-passe incorretos.');
  end if;

  select * into v_account from private.atina_player_accounts
   where nickname_normalized=lower(btrim(coalesce(p_nickname,''))) for update;

  if not found then
    return jsonb_build_object('ok',false,'message','Pseudónimo ou palavra-passe incorretos.');
  end if;

  select * into v_failure from private.atina_account_auth_failures
   where account_id=v_account.id for update;
  if found and v_failure.locked_until is not null and v_failure.locked_until>v_now then
    return jsonb_build_object('ok',false,'message','Não foi possível iniciar sessão. Aguarda 15 minutos e tenta novamente.');
  end if;

  if v_account.password_hash <> extensions.crypt(p_password,v_account.password_hash) then
    insert into private.atina_account_auth_failures(account_id,failed_attempts,window_started_at,locked_until,updated_at)
    values(v_account.id,1,v_now,null,v_now)
    on conflict(account_id) do update set
      failed_attempts=case when private.atina_account_auth_failures.window_started_at<=v_now-interval '15 minutes'
        then 1 else private.atina_account_auth_failures.failed_attempts+1 end,
      window_started_at=case when private.atina_account_auth_failures.window_started_at<=v_now-interval '15 minutes'
        then v_now else private.atina_account_auth_failures.window_started_at end,
      locked_until=case
        when (case when private.atina_account_auth_failures.window_started_at<=v_now-interval '15 minutes'
          then 1 else private.atina_account_auth_failures.failed_attempts+1 end)>=5
        then v_now+interval '15 minutes' else null end,
      updated_at=v_now;
    return jsonb_build_object('ok',false,'message','Pseudónimo ou palavra-passe incorretos.');
  end if;

  delete from private.atina_account_auth_failures where account_id=v_account.id;
  v_session_token := encode(extensions.gen_random_bytes(32),'hex');
  update private.atina_player_accounts set session_token_hash=extensions.digest(convert_to(v_session_token,'UTF8'),'sha256'),
    session_expires_at=v_now+interval '30 days',updated_at=v_now where id=v_account.id;
  select jsonb_build_object('player_id',p.id,'nickname',p.nickname,'xp',p.total_xp,
    'level',floor(p.total_xp/250.0)::integer+1,'total_challenges',p.total_challenges,
    'daily_count',case when p.daily_date=current_date then p.daily_count else 0 end)
    into v_profile from private.atina_players p where p.id=v_account.player_id;
  return jsonb_build_object('ok',true,'session_token',v_session_token,'profile',v_profile);
end;
$function$;

create or replace function public.atina_account_recover(p_nickname text,p_recovery_key text,p_new_password text)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare
  v_account private.atina_player_accounts;
  v_failure private.atina_account_auth_failures;
  v_session_token text;
  v_new_recovery_key text;
  v_now timestamptz := clock_timestamp();
begin
  if p_new_password is null or char_length(p_new_password)<10
     or octet_length(convert_to(p_new_password,'UTF8'))>72 then
    return jsonb_build_object('ok',false,'message','A nova palavra-passe deve ter pelo menos 10 caracteres e no máximo 72 bytes UTF-8.');
  end if;

  select * into v_account from private.atina_player_accounts
   where nickname_normalized=lower(btrim(coalesce(p_nickname,''))) for update;
  if not found then
    return jsonb_build_object('ok',false,'message','Pseudónimo ou chave de recuperação inválidos.');
  end if;

  select * into v_failure from private.atina_account_auth_failures
   where account_id=v_account.id for update;
  if found and v_failure.locked_until is not null and v_failure.locked_until>v_now then
    return jsonb_build_object('ok',false,'message','Não foi possível recuperar a conta. Aguarda 15 minutos e tenta novamente.');
  end if;

  if p_recovery_key is null or v_account.recovery_key_hash <> extensions.digest(convert_to(p_recovery_key,'UTF8'),'sha256') then
    insert into private.atina_account_auth_failures(account_id,failed_attempts,window_started_at,locked_until,updated_at)
    values(v_account.id,1,v_now,null,v_now)
    on conflict(account_id) do update set
      failed_attempts=case when private.atina_account_auth_failures.window_started_at<=v_now-interval '15 minutes'
        then 1 else private.atina_account_auth_failures.failed_attempts+1 end,
      window_started_at=case when private.atina_account_auth_failures.window_started_at<=v_now-interval '15 minutes'
        then v_now else private.atina_account_auth_failures.window_started_at end,
      locked_until=case
        when (case when private.atina_account_auth_failures.window_started_at<=v_now-interval '15 minutes'
          then 1 else private.atina_account_auth_failures.failed_attempts+1 end)>=5
        then v_now+interval '15 minutes' else null end,
      updated_at=v_now;
    return jsonb_build_object('ok',false,'message','Pseudónimo ou chave de recuperação inválidos.');
  end if;

  delete from private.atina_account_auth_failures where account_id=v_account.id;
  v_session_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_new_recovery_key:=encode(extensions.gen_random_bytes(24),'hex');
  update private.atina_player_accounts set password_hash=extensions.crypt(p_new_password,extensions.gen_salt('bf',12)),
    recovery_key_hash=extensions.digest(convert_to(v_new_recovery_key,'UTF8'),'sha256'),
    session_token_hash=extensions.digest(convert_to(v_session_token,'UTF8'),'sha256'),
    session_expires_at=v_now+interval '30 days',updated_at=v_now where id=v_account.id;
  return jsonb_build_object('ok',true,'session_token',v_session_token,'recovery_key',v_new_recovery_key,'recovered',true);
end;
$function$;

revoke all on function public.atina_account_login(text,text) from public;
revoke all on function public.atina_account_recover(text,text,text) from public;
grant execute on function public.atina_account_login(text,text) to anon,authenticated;
grant execute on function public.atina_account_recover(text,text,text) to anon,authenticated;
