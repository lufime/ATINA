-- Add narrowly curated spelling and naming variants found in the ATINA answer audit.
update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Tajmahal"]'::jsonb)
  ) s
)
where challenge_id = 42
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Tajmahal');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Golden Gate"]'::jsonb)
  ) s
)
where challenge_id = 245
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Golden Gate');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Grande Barreira dos Corais"]'::jsonb)
  ) s
)
where challenge_id = 274
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Grande Barreira dos Corais');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Dispersão luminosa"]'::jsonb)
  ) s
)
where challenge_id = 535
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Dispersão luminosa');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Monte Saint Michel"]'::jsonb)
  ) s
)
where challenge_id = 1086
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Monte Saint Michel');
