-- Regista o motivo administrativo de cada desativação de desafio.
-- A coluna é opcional para preservar os desafios que já estavam inativos antes desta funcionalidade.
alter table private.atina_challenges
  add column if not exists deactivation_reason text;

alter table private.atina_challenges
  add constraint atina_challenges_deactivation_reason_check
  check (
    deactivation_reason is null
    or char_length(btrim(deactivation_reason)) between 1 and 500
  );

comment on column private.atina_challenges.deactivation_reason is
  'Motivo indicado pela administração quando o desafio é desativado; preservado para histórico após reativação.';
