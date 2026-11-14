create or replace function private.atina_v2_challenge_answer_matches(p_challenge_id integer, p_answer text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select case
    when p_challenge_id = 1055
      and private.atina_v2_normalize_answer(p_answer) in ('irlanda', 'ireland')
      then false
    when p_challenge_id = 556
      and private.atina_v2_normalize_answer(p_answer) in ('geologia', 'geology')
      then false
    when p_challenge_id = 487
      and private.atina_v2_normalize_answer(p_answer) = 'concessao'
      then false
    when p_challenge_id = 96
      and private.atina_v2_normalize_answer(p_answer) = 'bruna'
      then false
    when p_challenge_id = 114
      and private.atina_v2_normalize_answer(p_answer) = 'lara'
      then false
    when p_challenge_id = 613
      and btrim(p_answer) = 'π'
      then true
    else exists (
      select 1
      from private.atina_challenges c
      where c.challenge_id = p_challenge_id
        and c.active
        and (
          private.atina_v2_answer_matches(c.answer, p_answer)
          or exists (
            select 1
            from jsonb_array_elements_text(c.accepted_answers) accepted(answer)
            where private.atina_v2_answer_matches(accepted.answer, p_answer)
          )
        )
    )
  end;
$function$;
