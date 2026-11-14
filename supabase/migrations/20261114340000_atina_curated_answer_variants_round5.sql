-- Add established English and spacing variants from the next answer audit.
update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Aye aye"]'::jsonb)
  ) s
)
where challenge_id = 823
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Aye aye');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Mechanical clock"]'::jsonb)
  ) s
)
where challenge_id = 1164
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Mechanical clock');

update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Camera obscura"]'::jsonb)
  ) s
)
where challenge_id = 1195
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Camera obscura');
