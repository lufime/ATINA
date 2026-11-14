update private.atina_challenges
set accepted_answers = coalesce((
  select jsonb_agg(to_jsonb(a))
  from jsonb_array_elements_text(accepted_answers) a
  where private.atina_v2_normalize_answer(a) not in (
    private.atina_v2_normalize_answer('Gorgon'),
    private.atina_v2_normalize_answer('Titan'),
    private.atina_v2_normalize_answer('Angkor temple'),
    private.atina_v2_normalize_answer('Meringue dessert'),
    private.atina_v2_normalize_answer('Japanese noodle soup')
  )
),'[]'::jsonb)
where challenge_id in (967,992,1060,882,872) and active is true