-- Strengthen ATINA nickname moderation at the database boundary.
-- This migration is intended for review through a pull request; do not apply
-- directly to the live atina-development project.

create or replace function private.atina_nickname_is_acceptable(p_nickname text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_normalized text;
  v_compact text;
  v_token text;
  v_blocked text[] := array[
    'caralho','merda','bosta','porra','foda','foder','fodase','fodas','puta','puto',
    'fdp','arrombado','cabrao','viado','bicha','otario','babaca','idiota','imbecil',
    'estupido','nigger','faggot','retard','whore','bitch','asshole','fuck','shit',
    'dick','cunt','slut','bastard','bastardo','bastarda','cona','cu','corno',
    'boiola','paneleiro','paneleira','buceta','vagabundo','vagabunda','desgraca',
    'pqp','vsf','vtc','crl','krl','fck','fuk','motherfucker','motherfucking',
    'filhodaputa','filhodocaralho','putaquepariu','vaitomarnocu','vaise foder'
  ];
begin
  if p_nickname is null then
    return false;
  end if;

  -- Normalize common Portuguese accents and simple leetspeak substitutions.
  v_normalized := lower(translate(
    p_nickname,
    'áàâãäéèêëíìîïóòôõöúùûüçñ',
    'aaaaaeeeeiiiiooooouuuucn'
  ));
  v_normalized := translate(v_normalized, '013457@$86', 'oieastasbg');
  -- Treat punctuation, symbols and repeated separators as word boundaries.
  v_normalized := regexp_replace(v_normalized, '[^a-z0-9]+', ' ', 'g');
  v_normalized := btrim(v_normalized);
  v_compact := regexp_replace(v_normalized, '[[:space:]]+', '', 'g');

  foreach v_token in array regexp_split_to_array(v_normalized, '[[:space:]]+')
  loop
    if v_token = any(v_blocked) then
      return false;
    end if;
  end loop;

  -- Catch a single offensive word split by punctuation (e.g. p.u.t.a).
  if v_compact = any(v_blocked) then
    return false;
  end if;

  -- Catch common offensive phrases even when separators differ.
  if v_normalized ~ '(^| )(filho da puta|filho do caralho|puta que pariu|vai tomar no cu|vai se foder|vai à merda|vai para o caralho)( |$)'
     or v_compact = any(array[
       'filhodaputa','filhodocaralho','putaquepariu','vaitomarnocu',
       'vaisefoder','vaimerda','vaiparaocaralho'
     ]) then
    return false;
  end if;

  return true;
end;
$function$;

-- Enforce the same rule even if a future code path writes directly to either
-- nickname table instead of going through the registration RPCs.
create or replace function private.atina_enforce_nickname_policy()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if not private.atina_nickname_is_acceptable(new.nickname) then
    raise exception 'Pseudónimo inválido ou com linguagem ofensiva. Escolhe outro nome.'
      using errcode = '22023';
  end if;
  return new;
end;
$function$;

drop trigger if exists atina_player_accounts_nickname_policy on private.atina_player_accounts;
create trigger atina_player_accounts_nickname_policy
before insert or update of nickname on private.atina_player_accounts
for each row execute function private.atina_enforce_nickname_policy();

drop trigger if exists atina_players_nickname_policy on private.atina_players;
create trigger atina_players_nickname_policy
before insert or update of nickname on private.atina_players
for each row execute function private.atina_enforce_nickname_policy();

-- Existing accounts with newly prohibited names cannot start another session.
-- Preserve the existing lockout counters and password verification behaviour.
create or replace function public.atina_account_login(p_nickname text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account private.atina_player_accounts;
  v_failure private.atina_account_auth_failures;
  v_session_token text;
  v_profile jsonb;
  v_now timestamptz := clock_timestamp();
begin
  if p_password is null or octet_length(convert_to(p_password,'UTF8')) > 72
     or not private.atina_nickname_is_acceptable(btrim(coalesce(p_nickname,''))) then
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
    'points',p.total_points,
    'level',private.atina_level_for_xp(p.total_xp),'total_challenges',p.total_challenges,
    'daily_count',case when p.daily_date=current_date then p.daily_count else 0 end)
    into v_profile from private.atina_players p where p.id=v_account.player_id;

  return jsonb_build_object('ok',true,'session_token',v_session_token,'profile',v_profile);
end;
$function$;

revoke all on function public.atina_account_login(text,text) from public;
grant execute on function public.atina_account_login(text,text) to anon, authenticated;

-- Regression checks: reject common profanity, accent/leet substitutions,
-- punctuation splitting and phrases, while keeping ordinary nicknames valid.
do $tests$
begin
  if private.atina_nickname_is_acceptable('Caralho')
     or private.atina_nickname_is_acceptable('c@r@lh0')
     or private.atina_nickname_is_acceptable('p.u.t.a')
     or private.atina_nickname_is_acceptable('P0rr4')
     or private.atina_nickname_is_acceptable('Puta Que Pariu')
     or private.atina_nickname_is_acceptable('Vai tomar no cu') then
    raise exception 'Nickname profanity regression test failed: an offensive test value was accepted.';
  end if;

  if not private.atina_nickname_is_acceptable('Pikachu')
     or not private.atina_nickname_is_acceptable('Ana Sousa')
     or not private.atina_nickname_is_acceptable('João Silva') then
    raise exception 'Nickname profanity regression test failed: a normal nickname was rejected.';
  end if;
end;
$tests$;
