-- Add narrowly scoped spelling variants found during the category audit.
update private.atina_challenges
set accepted_answers = (
  select jsonb_agg(distinct value)
  from jsonb_array_elements_text(
    accepted_answers || case challenge_id
      when 47 then '["Piramide de Gize"]'::jsonb
      when 846 then '["Lula vampiro"]'::jsonb
      when 893 then '["Harrisa"]'::jsonb
    end
  ) as x(value)
)
where active and challenge_id in (47,846,893);
