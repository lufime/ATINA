-- Curated challenge-specific synonyms and popular-language aliases.
-- Pending entries never affect answer validation; only an administrator can approve them.
create table if not exists private.atina_challenge_answer_aliases (
  id bigint generated always as identity primary key,
  challenge_id integer not null references private.atina_challenges(challenge_id) on delete cascade,
  alias text not null check (char_length(btrim(alias)) between 2 and 120),
  normalized_alias text not null,
  alias_type text not null check (alias_type in ('synonym','popular','regionalism','variant','abbreviation')),
  locale text not null default 'pt-PT' check (locale in ('pt-PT','pt-BR','pt','en','other')),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  review_notes text,
  created_by uuid,
  created_at timestamptz not null default now(),
  reviewed_by uuid,
  reviewed_at timestamptz,
  added_to_accepted_answers boolean not null default false,
  unique (challenge_id, normalized_alias)
);

create index if not exists atina_challenge_answer_aliases_status_idx
  on private.atina_challenge_answer_aliases(status, challenge_id);

alter table private.atina_challenge_answer_aliases enable row level security;
revoke all on private.atina_challenge_answer_aliases from public, anon, authenticated;

create or replace function public.atina_admin_list_challenge_answer_aliases(
  p_challenge_id integer default null,
  p_status text default null
)
returns table (
  alias_id bigint,
  challenge_id integer,
  canonical_answer text,
  alias text,
  alias_type text,
  locale text,
  status text,
  review_notes text,
  created_at timestamptz,
  reviewed_at timestamptz,
  added_to_accepted_answers boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.atina_error_report_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Acesso reservado à administração.' using errcode = '42501';
  end if;

  if p_status is not null and p_status not in ('pending','approved','rejected') then
    raise exception 'Estado inválido.';
  end if;

  return query
  select a.id, a.challenge_id, c.answer, a.alias, a.alias_type, a.locale,
         a.status, a.review_notes, a.created_at, a.reviewed_at,
         a.added_to_accepted_answers
  from private.atina_challenge_answer_aliases a
  join private.atina_challenges c on c.challenge_id = a.challenge_id
  where (p_challenge_id is null or a.challenge_id = p_challenge_id)
    and (p_status is null or a.status = p_status)
  order by case a.status when 'pending' then 0 when 'approved' then 1 else 2 end,
           a.challenge_id, a.id;
end;
$$;

create or replace function public.atina_admin_add_challenge_answer_alias(
  p_challenge_id integer,
  p_alias text,
  p_alias_type text default 'synonym',
  p_locale text default 'pt-PT',
  p_notes text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alias text := btrim(coalesce(p_alias,''));
  v_normalized text;
  v_id bigint;
begin
  if auth.uid() is null or not exists (
    select 1 from public.atina_error_report_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Acesso reservado à administração.' using errcode = '42501';
  end if;

  if char_length(v_alias) < 2 or char_length(v_alias) > 120 then
    raise exception 'A variante deve ter entre 2 e 120 caracteres.';
  end if;
  if p_alias_type not in ('synonym','popular','regionalism','variant','abbreviation') then
    raise exception 'Tipo de variante inválido.';
  end if;
  if p_locale not in ('pt-PT','pt-BR','pt','en','other') then
    raise exception 'Variante linguística inválida.';
  end if;
  if not exists (select 1 from private.atina_challenges c where c.challenge_id = p_challenge_id) then
    raise exception 'Desafio não encontrado.';
  end if;

  v_normalized := private.atina_v2_normalize_answer(v_alias);
  if v_normalized = '' then raise exception 'Variante vazia após normalização.'; end if;

  insert into private.atina_challenge_answer_aliases
    (challenge_id, alias, normalized_alias, alias_type, locale, status, review_notes, created_by, reviewed_by, reviewed_at, added_to_accepted_answers)
  values
    (p_challenge_id, v_alias, v_normalized, p_alias_type, p_locale, 'pending', nullif(btrim(p_notes),''), auth.uid(), null, null, false)
  on conflict (challenge_id, normalized_alias) do update
    set alias = excluded.alias,
        alias_type = excluded.alias_type,
        locale = excluded.locale,
        status = 'pending',
        review_notes = excluded.review_notes,
        created_by = auth.uid(),
        created_at = now(),
        reviewed_by = null,
        reviewed_at = null,
        added_to_accepted_answers = false
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.atina_admin_review_challenge_answer_alias(
  p_alias_id bigint,
  p_status text,
  p_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alias private.atina_challenge_answer_aliases%rowtype;
  v_collision boolean;
  v_added boolean := false;
begin
  if auth.uid() is null or not exists (
    select 1 from public.atina_error_report_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Acesso reservado à administração.' using errcode = '42501';
  end if;

  if p_status not in ('approved','rejected') then
    raise exception 'A decisão tem de ser aprovar ou rejeitar.';
  end if;

  select * into v_alias
  from private.atina_challenge_answer_aliases
  where id = p_alias_id
  for update;

  if not found then raise exception 'Variante não encontrada.'; end if;

  if p_status = 'approved' then
    select exists (
      select 1
      from private.atina_challenges c
      where c.active
        and c.challenge_id <> v_alias.challenge_id
        and (
          private.atina_v2_normalize_answer(c.answer) = v_alias.normalized_alias
          or exists (
            select 1 from jsonb_array_elements_text(coalesce(c.accepted_answers,'[]'::jsonb)) x(value)
            where private.atina_v2_normalize_answer(x.value) = v_alias.normalized_alias
          )
        )
    ) into v_collision;

    if v_collision then
      raise exception 'A variante coincide com uma resposta de outro desafio ativo. Não pode ser aprovada.';
    end if;

    update private.atina_challenges c
    set accepted_answers = case
      when exists (
        select 1 from jsonb_array_elements_text(coalesce(c.accepted_answers,'[]'::jsonb)) x(value)
        where private.atina_v2_normalize_answer(x.value) = v_alias.normalized_alias
      ) then coalesce(c.accepted_answers,'[]'::jsonb)
      else coalesce(c.accepted_answers,'[]'::jsonb) || jsonb_build_array(v_alias.alias)
    end
    where c.challenge_id = v_alias.challenge_id
      and not exists (
        select 1 from jsonb_array_elements_text(coalesce(c.accepted_answers,'[]'::jsonb)) x(value)
        where private.atina_v2_normalize_answer(x.value) = v_alias.normalized_alias
      );

    v_added := found;

    if not private.atina_v2_challenge_answer_matches(v_alias.challenge_id, v_alias.alias) then
      raise exception 'A variante não passou as proteções atuais de validação. Mantida como pendente.';
    end if;

    update private.atina_challenge_answer_aliases
    set status = 'approved',
        review_notes = nullif(btrim(p_notes),''),
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        added_to_accepted_answers = v_alias.added_to_accepted_answers or v_added
    where id = p_alias_id;
  else
    if v_alias.status = 'approved' and v_alias.added_to_accepted_answers then
      update private.atina_challenges c
      set accepted_answers = coalesce((
        select jsonb_agg(to_jsonb(x.value) order by x.ordinality)
        from jsonb_array_elements_text(coalesce(c.accepted_answers,'[]'::jsonb))
             with ordinality x(value, ordinality)
        where private.atina_v2_normalize_answer(x.value) <> v_alias.normalized_alias
      ), '[]'::jsonb)
      where c.challenge_id = v_alias.challenge_id;
    end if;

    update private.atina_challenge_answer_aliases
    set status = 'rejected',
        review_notes = nullif(btrim(p_notes),''),
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        added_to_accepted_answers = false
    where id = p_alias_id;
  end if;

  return true;
end;
$$;

revoke all on function public.atina_admin_list_challenge_answer_aliases(integer,text) from public, anon;
revoke all on function public.atina_admin_add_challenge_answer_alias(integer,text,text,text,text) from public, anon;
revoke all on function public.atina_admin_review_challenge_answer_alias(bigint,text,text) from public, anon;
grant execute on function public.atina_admin_list_challenge_answer_aliases(integer,text) to authenticated;
grant execute on function public.atina_admin_add_challenge_answer_alias(integer,text,text,text,text) to authenticated;
grant execute on function public.atina_admin_review_challenge_answer_alias(bigint,text,text) to authenticated;

comment on table private.atina_challenge_answer_aliases is
  'Challenge-specific synonym, popular-language and regional answer variants. Pending variants never affect gameplay; approved variants are added to accepted_answers after collision and matcher checks.';
