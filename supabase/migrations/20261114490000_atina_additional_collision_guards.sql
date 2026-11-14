-- Additional explicit fuzzy-collision guards found in the global challenge audit.
CREATE OR REPLACE FUNCTION private.atina_v2_challenge_answer_matches(p_challenge_id integer, p_answer text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case
    when p_challenge_id = 1055 and private.atina_v2_normalize_answer(p_answer) in ('irlanda', 'ireland') then false
    when p_challenge_id = 556 and private.atina_v2_normalize_answer(p_answer) in ('geologia', 'geology') then false
    when p_challenge_id = 487 and private.atina_v2_normalize_answer(p_answer) in ('concessao','gravidade') then false
    when p_challenge_id = 96 and private.atina_v2_normalize_answer(p_answer) = 'bruna' then false
    when p_challenge_id = 114 and private.atina_v2_normalize_answer(p_answer) = 'lara' then false
    when p_challenge_id = 613 and btrim(p_answer) = 'π' then true
    when p_challenge_id in (51,352) and private.atina_v2_normalize_answer(p_answer) = 'atena' then false
    when p_challenge_id = 953 and private.atina_v2_normalize_answer(p_answer) = 'atenas' then false
    when p_challenge_id = 22 and private.atina_v2_normalize_answer(p_answer) = 'valencia' then false
    when p_challenge_id = 192 and private.atina_v2_normalize_answer(p_answer) = 'gelo' then false
    when p_challenge_id = 532 and private.atina_v2_normalize_answer(p_answer) = 'selo' then false
    when p_challenge_id = 360 and private.atina_v2_normalize_answer(p_answer) = 'osso' then false
    when p_challenge_id = 408 and private.atina_v2_normalize_answer(p_answer) = 'oslo' then false
    when p_challenge_id = 391 and private.atina_v2_normalize_answer(p_answer) in ('lua','luva') then false
    when p_challenge_id = 401 and private.atina_v2_normalize_answer(p_answer) in ('lua','lupa') then false
    when p_challenge_id = 421 and private.atina_v2_normalize_answer(p_answer) = 'euro' then false
    when p_challenge_id = 551 and private.atina_v2_normalize_answer(p_answer) = 'ouro' then false
    when p_challenge_id in (701,959) and private.atina_v2_normalize_answer(p_answer) in ('polvo','apolo','polo') then false
    when p_challenge_id = 262 and private.atina_v2_normalize_answer(p_answer) = 'polo' then false
    when p_challenge_id = 632 and private.atina_v2_normalize_answer(p_answer) = 'pangolim' then false
    when p_challenge_id = 804 and private.atina_v2_normalize_answer(p_answer) = 'bandolim' then false
    when p_challenge_id = 742 and private.atina_v2_normalize_answer(p_answer) in ('processo','o processo') then false
    when p_challenge_id = 888 and private.atina_v2_normalize_answer(p_answer) = 'baco' then false
    when p_challenge_id = 1112 and private.atina_v2_normalize_answer(p_answer) = 'taco' then false
    when p_challenge_id = 293 and private.atina_v2_normalize_answer(p_answer) = '5' then false
    when p_challenge_id = 493 and private.atina_v2_normalize_answer(p_answer) = 'marte' then false
    when p_challenge_id = 503 and private.atina_v2_normalize_answer(p_answer) in ('arte','mare') then false
    when p_challenge_id = 527 and private.atina_v2_normalize_answer(p_answer) in ('marte','ares') then false
    when p_challenge_id = 957 and private.atina_v2_normalize_answer(p_answer) in ('arte','mare') then false
    when p_challenge_id = 533 and private.atina_v2_normalize_answer(p_answer) = 'bateria' then false
    when p_challenge_id = 628 and private.atina_v2_normalize_answer(p_answer) = 'bacteria' then false
    when p_challenge_id = 574 and private.atina_v2_normalize_answer(p_answer) = 'flamingo' then false
    when p_challenge_id = 256 and private.atina_v2_normalize_answer(p_answer) = 'flamenco' then false
    when p_challenge_id = 616 and private.atina_v2_normalize_answer(p_answer) = 'acordo' then false
    when p_challenge_id = 436 and private.atina_v2_normalize_answer(p_answer) = 'odisseu' then false
    when p_challenge_id = 979 and private.atina_v2_normalize_answer(p_answer) = 'odisseia' then false
    when p_challenge_id = 963 and private.atina_v2_normalize_answer(p_answer) = 'vulcao' then false
    when p_challenge_id in (175,1053) and private.atina_v2_normalize_answer(p_answer) = 'pedra' then false
    when p_challenge_id = 407 and private.atina_v2_normalize_answer(p_answer) = 'petra' then false
    when p_challenge_id = 834 and private.atina_v2_normalize_answer(p_answer) = 'peixepedra' then false
    when p_challenge_id = 847 and private.atina_v2_normalize_answer(p_answer) = 'peixeserra' then false
    when p_challenge_id = 894 and private.atina_v2_normalize_answer(p_answer) = 'tempo' then false
    when p_challenge_id = 965 and private.atina_v2_normalize_answer(p_answer) = 'judo' then false
    when p_challenge_id = 44 and private.atina_v2_normalize_answer(p_answer) = 'lyon' then false
    when p_challenge_id = 369 and private.atina_v2_normalize_answer(p_answer) = 'leao' then false
    when p_challenge_id = 494 and private.atina_v2_normalize_answer(p_answer) = 'aviao' then false
    when p_challenge_id = 1169 and private.atina_v2_normalize_answer(p_answer) = 'anuncio' then false
    when p_challenge_id = 524 and private.atina_v2_normalize_answer(p_answer) = 'semente' then false
    when p_challenge_id = 706 and private.atina_v2_normalize_answer(p_answer) = 'osso' then false
    when p_challenge_id = 738 and private.atina_v2_normalize_answer(p_answer) in ('peste','a peste') then false
    when p_challenge_id = 1026 and private.atina_v2_normalize_answer(p_answer) = 'pente' then false
    when p_challenge_id = 1108 and private.atina_v2_normalize_answer(p_answer) = 'esofago' then false
    when p_challenge_id = 1123 and private.atina_v2_normalize_answer(p_answer) = 'estomago' then false
    when p_challenge_id = 971 and private.atina_v2_normalize_answer(p_answer) = 'cerebro' then false
    when p_challenge_id = 1106 and private.atina_v2_normalize_answer(p_answer) in ('cerbero','cerebelo') then false
    when p_challenge_id = 1148 and private.atina_v2_normalize_answer(p_answer) in ('cerebro','cerbero') then false
    else exists (
      select 1 from private.atina_challenges c
      where c.challenge_id = p_challenge_id and c.active
        and (private.atina_v2_answer_matches(c.answer,p_answer)
          or exists (select 1 from jsonb_array_elements_text(c.accepted_answers) accepted(answer)
                     where private.atina_v2_answer_matches(accepted.answer,p_answer)))
    )
  end;
$function$

