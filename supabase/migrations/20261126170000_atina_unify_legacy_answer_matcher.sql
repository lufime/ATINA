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

  -- Exercise article/preposition tolerance independently of production-only
  -- challenge IDs, which are not guaranteed to exist in a clean migration replay.
  if not private.atina_v2_answer_matches('Leitão da Bairrada', 'Leitão a Bairrada') then
    raise exception 'Expected harmless Portuguese preposition variation to be accepted.';
  end if;

  -- Keep challenge-specific false-positive and letter guards covered whenever
  -- their production challenge records are present in the replay dataset.
  if exists (select 1 from private.atina_challenges where challenge_id = 1505 and active) then
    if not private.atina_challenge_answer_matches(1505, 'Leitão a Bairrada') then
      raise exception 'Expected harmless preposition variation for challenge 1505.';
    end if;
    if private.atina_challenge_answer_matches(1505, 'Leitão')
       or private.atina_challenge_answer_matches(1505, 'Leitão de Lisboa') then
      raise exception 'False-positive guard regression for challenge 1505.';
    end if;
  end if;

  if exists (select 1 from private.atina_challenges where challenge_id = 765 and active) then
    if not private.atina_challenge_answer_matches(765, 'A letra «o»')
       or private.atina_challenge_answer_matches(765, 'A letra «a»') then
      raise exception 'Single-letter answer guard regression.';
    end if;
  end if;
end
$tests$;
