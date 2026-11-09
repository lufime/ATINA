-- Recovery keys are single-use: rotate the key atomically after a successful reset.
create or replace function public.atina_account_recover(
  p_nickname text,
  p_recovery_key text,
  p_new_password text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_account private.atina_player_accounts;
  v_session_token text;
  v_new_recovery_key text;
begin
  if p_new_password is null or char_length(p_new_password) < 10 or char_length(p_new_password) > 128 then
    raise exception 'A nova palavra-passe deve ter entre 10 e 128 caracteres.' using errcode = '22023';
  end if;

  select * into v_account
    from private.atina_player_accounts
   where nickname_normalized = lower(btrim(coalesce(p_nickname, '')))
   for update;

  if not found or p_recovery_key is null
     or v_account.recovery_key_hash <> extensions.digest(convert_to(p_recovery_key, 'UTF8'), 'sha256') then
    raise exception 'Pseudónimo ou chave de recuperação inválidos.' using errcode = '28000';
  end if;

  v_session_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_new_recovery_key := encode(extensions.gen_random_bytes(24), 'hex');

  update private.atina_player_accounts
     set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 12)),
         recovery_key_hash = extensions.digest(convert_to(v_new_recovery_key, 'UTF8'), 'sha256'),
         session_token_hash = extensions.digest(convert_to(v_session_token, 'UTF8'), 'sha256'),
         session_expires_at = clock_timestamp() + interval '30 days',
         updated_at = clock_timestamp()
   where id = v_account.id;

  return jsonb_build_object(
    'session_token', v_session_token,
    'recovery_key', v_new_recovery_key,
    'recovered', true
  );
end;
$function$;

revoke all on function public.atina_account_recover(text, text, text) from public;
grant execute on function public.atina_account_recover(text, text, text) to anon, authenticated;
