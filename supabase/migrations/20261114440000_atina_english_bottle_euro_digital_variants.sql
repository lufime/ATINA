-- Initial targeted addition for the English wording of the two-euro answer.
update private.atina_challenges c
set accepted_answers = coalesce(c.accepted_answers, '[]'::jsonb) || jsonb_build_array('Two euros')
where c.challenge_id = 61
  and c.active = true
  and not exists (
    select 1
    from jsonb_array_elements_text(coalesce(c.accepted_answers, '[]'::jsonb)) e(value)
    where lower(btrim(e.value)) = lower(btrim('Two euros'))
  );
