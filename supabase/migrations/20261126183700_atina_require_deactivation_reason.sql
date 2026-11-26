-- Impede desativar desafios sem um motivo administrativo válido.
-- Os registos inativos existentes já foram auditados: todos têm motivo preenchido.
alter table private.atina_challenges
  add constraint atina_challenges_inactive_requires_reason
  check (
    active
    or nullif(btrim(deactivation_reason), '') is not null
  );

comment on constraint atina_challenges_inactive_requires_reason
  on private.atina_challenges is
  'Um desafio inativo tem obrigatoriamente de ter um motivo de desativação não vazio.';
