update private.atina_challenges c
set accepted_answers = coalesce(c.accepted_answers, '[]'::jsonb) || jsonb_build_array('Joan of Arc')
where c.challenge_id = 314
  and c.active
  and not exists (
    select 1
    from jsonb_array_elements_text(coalesce(c.accepted_answers, '[]'::jsonb)) existing(answer)
    where private.atina_v2_normalize_answer(existing.answer) = private.atina_v2_normalize_answer('Joan of Arc')
  );
