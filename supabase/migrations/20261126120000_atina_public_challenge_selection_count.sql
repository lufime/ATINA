-- Return authoritative active challenge availability for the Solo/Mix pre-game selector.
-- The privileged table read stays behind a SECURITY DEFINER helper in the private schema.
-- The public API wrapper is SECURITY INVOKER and returns only an integer count.
-- Code-only migration: do not apply to production without explicit approval.

create or replace function private.atina_count_active_challenges_for_selection(
  p_geographic_scope text,
  p_category text,
  p_difficulty text
)
returns integer
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_count integer;
begin
  if p_geographic_scope is null or p_geographic_scope not in ('Todos','Portugal','Internacional','Universal') then
    raise exception 'Âmbito geográfico inválido.' using errcode='22023';
  end if;
  if p_difficulty is null or p_difficulty not in ('easy','medium','hard','mixed') then
    raise exception 'Dificuldade inválida.' using errcode='22023';
  end if;
  if p_category is not null and length(trim(p_category))=0 then
    raise exception 'Categoria inválida.' using errcode='22023';
  end if;

  select count(*)::integer into v_count
    from private.atina_challenges c
   where c.active
     and (p_geographic_scope='Todos' or c.geographic_scope=p_geographic_scope)
     and (p_category is null or c.category=p_category)
     and (p_difficulty='mixed' or c.difficulty=p_difficulty);

  return coalesce(v_count,0);
end;
$function$;

revoke all on function private.atina_count_active_challenges_for_selection(text,text,text) from public;
grant usage on schema private to anon, authenticated;
grant execute on function private.atina_count_active_challenges_for_selection(text,text,text) to anon, authenticated;

create or replace function public.atina_public_challenge_selection_count(
  p_geographic_scope text default 'Todos',
  p_category text default null,
  p_difficulty text default 'mixed'
)
returns integer
language sql
stable
security invoker
set search_path to ''
as $function$
  select private.atina_count_active_challenges_for_selection(
    p_geographic_scope,
    p_category,
    p_difficulty
  );
$function$;

revoke all on function public.atina_public_challenge_selection_count(text,text,text) from public;
grant execute on function public.atina_public_challenge_selection_count(text,text,text) to anon, authenticated;
