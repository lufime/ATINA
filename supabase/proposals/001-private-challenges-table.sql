-- PROPOSTA (não aplicar diretamente): separar respostas privadas do catálogo público.
-- Esta primeira etapa cria apenas a tabela; o carregamento dos segredos e as RPCs
-- serão adicionados após revisão da compatibilidade e dos testes.

create schema if not exists private;

create table if not exists private.atina_challenges (
  challenge_id integer primary key,
  category text not null,
  emoji text not null,
  clues jsonb not null
    check (
      jsonb_typeof(clues) = 'array'
      and jsonb_array_length(clues) in (5, 6)
    ),
  answer text not null,
  accepted_answers jsonb not null
    check (
      jsonb_typeof(accepted_answers) = 'array'
      and jsonb_array_length(accepted_answers) >= 1
    ),
  image_url text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table private.atina_challenges enable row level security;
revoke all on schema private from public, anon, authenticated;
revoke all on table private.atina_challenges from public, anon, authenticated;

comment on table private.atina_challenges is
  'ATINA challenge answer key; never expose through the Data API or public client.';
