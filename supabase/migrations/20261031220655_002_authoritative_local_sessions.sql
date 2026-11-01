-- PROPOSTA (não aplicar diretamente): sessões autoritativas para modos locais online.
-- A tabela guarda apenas estado de jogo e IDs; nunca devolver a chave privada de respostas.
-- A implementação das RPCs e os testes transacionais serão adicionados após revisão.

create table if not exists private.atina_local_sessions (
  id uuid primary key default gen_random_uuid(),
  token_hash bytea not null unique,
  game_mode text not null
    check (game_mode in ('solo', 'duel', 'mix', 'party')),
  difficulty text not null
    check (difficulty in ('easy', 'medium', 'hard')),
  category text,
  timed_mode_seconds integer not null default 60
    check (timed_mode_seconds between 0 and 3600),
  challenge_queue integer[] not null
    check (cardinality(challenge_queue) > 0),
  position integer not null default 1
    check (position >= 1),
  revealed_clues integer not null default 1
    check (revealed_clues between 1 and 6),
  current_player smallint not null default 1
    check (current_player in (1, 2)),
  scores integer[] not null default array[0, 0]::integer[],
  streaks integer[] not null default array[0, 0]::integer[],
  round_context jsonb not null default '{}'::jsonb,
  deadline_at timestamptz,
  status text not null default 'active'
    check (status in ('active', 'completed', 'abandoned', 'expired')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  check (position <= cardinality(challenge_queue)),
  check (cardinality(scores) = 2),
  check (cardinality(streaks) = 2)
);

create index if not exists atina_local_sessions_expiry_idx
  on private.atina_local_sessions (expires_at)
  where status = 'active';

alter table private.atina_local_sessions enable row level security;
revoke all on schema private from public, anon, authenticated;
revoke all on table private.atina_local_sessions from public, anon, authenticated;

comment on table private.atina_local_sessions is
  'Authoritative state for online solo, duel, mix and party games; never expose through the Data API.';

-- RPCs planeadas (todas validam token_hash, estado e deadline no servidor):
-- atina_start_local_game(...) -> session_id, token, estado público do desafio atual
-- atina_local_game_state(session_id, token) -> estado persistido + pistas públicas
-- atina_local_reveal_clue(session_id, token) -> avança uma pista
-- atina_local_submit_answer(session_id, token, answer) -> valida, calcula e grava pontuação
-- atina_local_pass_challenge(session_id, token) -> fecha ronda e só então revela solução
-- atina_local_next_challenge(session_id, token) -> avança ou conclui a sessão
-- A implementação deve ainda validar os bónus atuais, a meta de 250 pontos e as regras de cada modo.
