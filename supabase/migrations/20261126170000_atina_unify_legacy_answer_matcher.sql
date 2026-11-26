-- Unify legacy challenge answer checks with the guarded V2 matcher.
-- This makes accent, punctuation, typo, article/preposition and curated-alias
-- tolerance consistent across legacy local and multiplayer answer flows.
-- V2's challenge-specific false-positive guards and strict letter/numeric
-- handling remain authoritative.

create or replace function private.atina_challenge_answer_matches(
  p_challenge_id integer,
  p_answer text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.atina_v2_challenge_answer_matches(p_challenge_id, p_answer);
$$;

revoke all on function private.atina_challenge_answer_matches(integer, text)
  from public, anon, authenticated;

comment on function private.atina_challenge_answer_matches(integer, text) is
  'Internal-only legacy entry point delegated to the guarded V2 matcher so answer tolerance is consistent across all challenge game modes.';

do $tests$
declare
  v_failures integer;
begin
  -- Every active canonical answer must remain valid.
  select count(*) into v_failures
  from private.atina_challenges c
  where c.active
    and not private.atina_challenge_answer_matches(c.challenge_id, c.answer);

  if v_failures > 0 then
    raise exception 'Canonical-answer regression: % active challenges failed.', v_failures;
  end if;

  -- Regression for the reported Portuguese preposition/article variant.
  if not private.atina_challenge_answer_matches(1505, 'Leitão a Bairrada') then
    raise exception 'Expected harmless preposition variation to be accepted.';
  end if;

  -- Keep meaningful content words and letter riddles protected.
  if private.atina_challenge_answer_matches(1505, 'Leitão')
     or private.atina_challenge_answer_matches(1505, 'Leitão de Lisboa') then
    raise exception 'False-positive guard regression for challenge 1505.';
  end if;

  if not private.atina_challenge_answer_matches(765, 'A letra «o»')
     or private.atina_challenge_answer_matches(765, 'A letra «a»') then
    raise exception 'Single-letter answer guard regression.';
  end if;
end
$tests$;
