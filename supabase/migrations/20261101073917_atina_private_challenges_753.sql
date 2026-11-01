-- Additive compatibility migration for the existing atina-ranking project.
-- This exact migration has already been applied to project qwuxwiurqwfjizkwpmjp.
-- The 753 private rows were copied separately from atina-development and are not
-- included in source control.

create schema if not exists private;

create table if not exists private.atina_challenges (
  challenge_id integer primary key,
  category text not null,
  emoji text not null,
  clues jsonb not null
    check (jsonb_typeof(clues) = 'array' and jsonb_array_length(clues) in (5, 6)),
  answer text not null,
  accepted_answers jsonb not null
    check (jsonb_typeof(accepted_answers) = 'array' and jsonb_array_length(accepted_answers) >= 1),
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  difficulty text check (difficulty in ('easy', 'medium', 'hard'))
);

alter table private.atina_challenges enable row level security;
revoke all on table private.atina_challenges from anon, authenticated, public;

comment on table private.atina_challenges is
  'ATINA challenge answer key; never expose through the Data API or public client.';
