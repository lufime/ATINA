-- Accept the common Portuguese phonetic spelling of Sydney in the Opera de Sydney challenge.
update private.atina_challenges
set accepted_answers = case
  when accepted_answers @> '["Opera de Sidnei"]'::jsonb then accepted_answers
  else accepted_answers || '["Opera de Sidnei"]'::jsonb
end
where challenge_id = 250 and active;
