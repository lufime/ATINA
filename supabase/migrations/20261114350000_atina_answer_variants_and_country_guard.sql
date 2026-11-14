-- Add well-established title/name translations and block a known country-name false positive.
update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["National Library of Portugal"]'::jsonb)
  ) s
)
where challenge_id = 204
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'National Library of Portugal');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Dead Sea Scrolls"]'::jsonb)
  ) s
)
where challenge_id = 463
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Dead Sea Scrolls');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Ariadne''s thread"]'::jsonb)
  ) s
)
where challenge_id = 611
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Ariadne''s thread');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Optical character recognition"]'::jsonb)
  ) s
)
where challenge_id = 944
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Optical character recognition');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["The Metamorphosis"]'::jsonb)
  ) s
)
where challenge_id = 1018
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'The Metamorphosis');

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
