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
  -- Every active canonical answer must remain valid. Empty local replay
  -- databases are supported; challenge data is loaded separately.
  select count(*) into v_failures
  from private.atina_challenges c
  where c.active
    and not private.atina_challenge_answer_matches(c.challenge_id, c.answer);

  if v_failures > 0 then
    raise exception 'Canonical-answer regression: % active challenges failed.', v_failures;
  end if;

  -- Exercise article/preposition tolerance independently of optional
  -- challenge seed data so clean migration replays test the same rule.
  if not private.atina_v2_answer_matches('Leitão da Bairrada', 'Leitão a Bairrada') then
    raise exception 'Expected harmless Portuguese preposition variation to be accepted.';
  end if;

  if private.atina_v2_answer_matches('Leitão da Bairrada', 'Leitão')
     or private.atina_v2_answer_matches('Leitão da Bairrada', 'Leitão de Lisboa') then
    raise exception 'Meaningful content words must not be omitted or replaced.';
  end if;

  -- When the separately loaded catalog contains challenge 1505, also
  -- exercise its challenge-specific matcher and false-positive guards.
  if exists (
    select 1 from private.atina_challenges
    where challenge_id = 1505 and active
  ) then
    if not private.atina_challenge_answer_matches(1505, 'Leitão a Bairrada') then
      raise exception 'Expected challenge 1505 to accept the harmless preposition variation.';
    end if;

    if private.atina_challenge_answer_matches(1505, 'Leitão')
       or private.atina_challenge_answer_matches(1505, 'Leitão de Lisboa') then
      raise exception 'False-positive guard regression for challenge 1505.';
    end if;
  end if;

  -- The generic rule is always tested; the challenge-specific guard is
  -- additionally tested when challenge 765 exists in the loaded catalog.
  if not private.atina_v2_answer_matches('A letra «o»', 'A letra «o»')
     or private.atina_v2_answer_matches('A letra «o»', 'A letra «a»') then
    raise exception 'Single-letter answer tolerance regression.';
  end if;

  if exists (
    select 1 from private.atina_challenges
    where challenge_id = 765 and active
  ) and (
    not private.atina_challenge_answer_matches(765, 'A letra «o»')
    or private.atina_challenge_answer_matches(765, 'A letra «a»')
  ) then
    raise exception 'Single-letter challenge-specific guard regression.';
  end if;
end
$tests$;
