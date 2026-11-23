-- Restore the account-scoped challenge catalog progress RPC used by the profile UI.
-- This migration is code-only; do not apply directly to the live Supabase project.

create or replace function public.atina_challenge_catalog_progress(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_player_id uuid;
  v_total integer;
  v_seen integer;
  v_categories jsonb;
  v_difficulties jsonb;
begin
  if p_session_token is null or p_session_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Sessão inválida.' using errcode='28000';
  end if;

  select a.player_id into v_player_id
    from private.atina_player_accounts a
   where a.session_token_hash=extensions.digest(convert_to(p_session_token,'UTF8'),'sha256')
     and a.session_expires_at>clock_timestamp();

  if v_player_id is null then
    raise exception 'Sessão expirada. Inicia sessão novamente.' using errcode='28000';
  end if;

  select count(*)::integer,
         count(*) filter (where exists (
           select 1 from private.atina_challenge_exposures e
            where e.scope_type='player'
              and e.scope_key=v_player_id::text
              and e.challenge_id=c.challenge_id
         ))::integer
    into v_total,v_seen
    from private.atina_challenges c
   where c.active;

  select coalesce(jsonb_agg(jsonb_build_object(
           'category',g.category,'total',g.total,'seen',g.seen
         ) order by g.category),'[]'::jsonb)
    into v_categories
    from (
      select c.category,count(*)::integer as total,
             count(*) filter (where exists (
               select 1 from private.atina_challenge_exposures e
                where e.scope_type='player'
                  and e.scope_key=v_player_id::text
                  and e.challenge_id=c.challenge_id
             ))::integer as seen
        from private.atina_challenges c
       where c.active
       group by c.category
    ) g;

  select coalesce(jsonb_agg(jsonb_build_object(
           'difficulty',g.difficulty,'total',g.total,'seen',g.seen
         ) order by g.difficulty),'[]'::jsonb)
    into v_difficulties
    from (
      select c.difficulty,count(*)::integer as total,
             count(*) filter (where exists (
               select 1 from private.atina_challenge_exposures e
                where e.scope_type='player'
                  and e.scope_key=v_player_id::text
                  and e.challenge_id=c.challenge_id
             ))::integer as seen
        from private.atina_challenges c
       where c.active
       group by c.difficulty
    ) g;

  return jsonb_build_object(
    'total',coalesce(v_total,0),
    'seen',coalesce(v_seen,0),
    'remaining',greatest(coalesce(v_total,0)-coalesce(v_seen,0),0),
    'categories',coalesce(v_categories,'[]'::jsonb),
    'difficulties',coalesce(v_difficulties,'[]'::jsonb)
  );
end;
$$;

revoke all on function public.atina_challenge_catalog_progress(text) from public;
grant execute on function public.atina_challenge_catalog_progress(text) to anon,authenticated;
