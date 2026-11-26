-- Histórico auditável de desactivações e reativações de desafios ATINA.
-- Executar apenas após revisão e autorização explícita para alterar a produção.

create table if not exists private.atina_challenge_deactivation_history (
  id bigint generated always as identity primary key,
  challenge_id integer not null
    references private.atina_challenges(challenge_id) on delete cascade,
  action text not null
    check (action in ('deactivated', 'reactivated')),
  reason text,
  admin_user_id uuid,
  created_at timestamptz not null default clock_timestamp(),
  constraint atina_challenge_deactivation_history_reason_check
    check (
      (action = 'deactivated' and reason is not null and char_length(btrim(reason)) between 1 and 1000)
      or (action = 'reactivated' and reason is null)
    )
);

create index if not exists atina_challenge_deactivation_history_challenge_created_idx
  on private.atina_challenge_deactivation_history (challenge_id, created_at desc);

alter table private.atina_challenge_deactivation_history enable row level security;
revoke all on table private.atina_challenge_deactivation_history from public, anon, authenticated;

comment on table private.atina_challenge_deactivation_history is
  'Append-only administrative history for challenge deactivation/reactivation. Never exposed to public game clients.';
