-- Add the established Portuguese common-name variant for narwhal.
update private.atina_challenges
set accepted_answers = (
  select coalesce(jsonb_agg(to_jsonb(v) order by v), '[]'::jsonb)
  from (
    select distinct value as v
    from jsonb_array_elements_text(coalesce(accepted_answers, '[]'::jsonb) || '["Unicórnio do mar"]'::jsonb)
  ) s
)
where challenge_id = 803
  and not (coalesce(accepted_answers, '[]'::jsonb) ? 'Unicórnio do mar');
