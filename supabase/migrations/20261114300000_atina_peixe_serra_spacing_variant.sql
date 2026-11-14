-- Accept the common spacing variant without the hyphen for Peixe-serra.
update private.atina_challenges
set accepted_answers = case
  when accepted_answers @> '["Peixe serra"]'::jsonb then accepted_answers
  else accepted_answers || '["Peixe serra"]'::jsonb
end
where challenge_id = 834 and active;
