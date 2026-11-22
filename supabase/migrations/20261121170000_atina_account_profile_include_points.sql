-- Include points in the authenticated account profile RPC used by the results view.
-- Code migration only; do not apply directly to the production Supabase project.
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
  select jsonb_build_object(
    'player_id',p.id,
    'nickname',p.nickname,
    'points',p.total_points,
    'xp',p.total_xp,
    'level',floor(p.total_xp/250.0)::integer+1,
    'total_challenges',p.total_challenges,
    'daily_count',case when p.daily_date=current_date then p.daily_count else 0 end
  )
  into v_profile from private.atina_players p where p.id=v_account.player_id;
  return v_profile;
end;
$$;
