-- Add common Portuguese spacing variants for two compound animal names.
update private.atina_challenges
set accepted_answers = (
  select jsonb_agg(distinct value)
  from jsonb_array_elements_text(
    accepted_answers || case challenge_id
      when 255 then '["Panda gigante"]'::jsonb
      when 813 then '["Salamandra de fogo"]'::jsonb
    end
  ) as x(value)
)
where active and challenge_id in (255,813);
