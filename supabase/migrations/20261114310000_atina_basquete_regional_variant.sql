-- Accept the common Brazilian Portuguese regional equivalent for basketball.
update private.atina_challenges
set accepted_answers = case
  when accepted_answers @> '["Basquete"]'::jsonb then accepted_answers
  else accepted_answers || '["Basquete"]'::jsonb
end
where challenge_id = 159 and active;
