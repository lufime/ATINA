-- Add precise spelling/translation variants and prevent a science-category false positive.
update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Raposa vermelha"]'::jsonb)
  ) s
)
where challenge_id = 269
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Raposa vermelha');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Battle of Thermopylae"]'::jsonb)
  ) s
)
where challenge_id = 433
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Battle of Thermopylae');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Footprint"]'::jsonb)
  ) s
)
where challenge_id = 597
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Footprint');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Besouro rinoceronte"]'::jsonb)
  ) s
)
where challenge_id = 843
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Besouro rinoceronte');

create or replace function private.atina_v2_challenge_answer_matches(p_challenge_id integer, p_answer text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select case
    when p_challenge_id = 1055
      and private.atina_v2_normalize_answer(p_answer) in ('irlanda', 'ireland')
      then false
    when p_challenge_id = 556
      and private.atina_v2_normalize_answer(p_answer) in ('geologia', 'geology')
      then false
    else exists (
      select 1
      from private.atina_challenges c
      where c.challenge_id = p_challenge_id
        and c.active
        and (
          private.atina_v2_answer_matches(c.answer, p_answer)
          or exists (
            select 1
            from jsonb_array_elements_text(c.accepted_answers) accepted(answer)
            where private.atina_v2_answer_matches(accepted.answer, p_answer)
          )
        )
    )
  end;
$function$;
