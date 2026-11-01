# Progressão na nuvem por pseudónimo — proposta

Esta migração é uma proposta e **não foi aplicada** a qualquer projeto Supabase.

## Identidade

- Não cria utilizadores Supabase Auth.
- Não pede email nem palavra-passe.
- O dispositivo gera uma chave aleatória de 256 bits.
- A base de dados guarda apenas SHA-256 da chave, nunca o segredo em claro.
- O pseudónimo é apenas o nome público; a chave é a credencial que impede terceiros de alterar a progressão desse jogador.
- Sem cópia da chave, a recuperação entre dispositivos não é possível. A interface deve explicar e permitir exportar um código de recuperação sem email.

## Integridade da progressão

- O browser não envia XP nem pontuação.
- A RPC confirma a sessão de jogo e o token de sessão emitido pelo servidor.
- Só uma ronda bloqueada com resultado `correct` dá XP.
- O evento é único por jogador/sessão/posição, evitando duplicação por refresh ou retry.
- O terceiro desafio correto do dia atribui 60 XP no total (10 XP + bónus de 50), apenas uma vez por dia.
- As tabelas ficam no schema privado, com RLS e sem grants diretos a anon/authenticated.
- As RPCs usam `SECURITY DEFINER`, `search_path = ''`, validação explícita e grants restritos.

## Antes de produção

1. Rever o SQL e testar numa base Supabase isolada.
2. Integrar o cliente web para criar/guardar a chave e chamar as RPCs apenas depois de cada resposta correta.
3. Testar replay, tokens inválidos, pseudónimos duplicados, rollover UTC e bónus diário.
4. Confirmar os advisors de segurança e performance.
5. Só então pedir autorização específica para aplicar a migração em `atina-ranking`.

Não tocar em `atina-development`.
