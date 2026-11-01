# Compatibilidade de migrações com atina-ranking

## Estado e objetivo

Esta proposta prepara a integração da arquitetura server-authoritative da branch `main` com o projeto Supabase `atina-ranking` sem substituir a estrutura multiplayer que já existe.

**Este documento não é uma migração executável.** Não aplicar SQL remoto nem fazer deploy com base neste plano. A migração final exige revisão do mapeamento, testes numa cópia descartável do esquema legado e aprovação própria.

## Inventário confirmado em 2026-11-01

O projeto `atina-ranking` já contém dados e objetos que têm de ser preservados:

- `public.atina_rooms`: 4 linhas; contém `host_player_id`, `max_players` (default 12, limite 1–12), `status` (waiting/playing/finished), `game_state` e `state_version`.
- `public.atina_room_players`: 4 linhas; contém `token_hash text`, `is_ready`, `joined_at`, `last_seen_at`, `score`; nickname limitado a 20 caracteres.
- `public.atina_room_answers`: existe e está vazia; tem FKs independentes para sala e jogador.
- `public.atina_team_proposals` e `public.atina_team_votes`: tabelas legadas existentes e relacionadas entre si.
- `public.atina_multiplayer_ranking`, `public.atina_room_results` e `public.atina_room_timeout_budgets`: já existem e têm FKs ao esquema legado.
- `private.atina_mime_cards`: 48 linhas; `clues` exige array de exatamente 5 elementos.
- `private.atina_mime_secrets`: tabela existente, ligada às salas, jogadores e cartas.
- Não existem `private.atina_challenges`, `private.atina_local_sessions` nem `public.atina_start_local_game`.

As funções de sala atualmente instaladas consultam e escrevem as colunas legadas. Não podem ser substituídas por funções que assumam outro contrato sem compatibilidade explícita.

## Conflitos que impedem aplicar diretamente as migrações atuais

1. A migração `007_multiplayer_room_foundation` usa `CREATE TABLE IF NOT EXISTS`. Isso não adapta as tabelas legadas já existentes: as colunas e constraints ficam como estão.
2. O esquema novo usa `ready`, `created_at` e `token_hash bytea`; o esquema legado usa `is_ready`, `joined_at` e `token_hash text`, além de `host_player_id` na sala. Também existem diferenças de limites de nickname e número máximo de jogadores.
3. O esquema novo cria `atina_room_team_proposals` e `atina_room_team_votes`; o projeto existente tem `atina_team_proposals` e `atina_team_votes`.
4. As RPCs novas `atina_create_room`, `atina_join_room` e `atina_room_state` têm contratos e pressupostos de colunas diferentes das RPCs atualmente instaladas.
5. A migração `019_atina_rpc_rate_limiting` configura `pgrst.db_pre_request` ao nível do role `authenticator`. É uma alteração global do comportamento PostgREST e não deve ser incluída numa migração de compatibilidade sem revisão específica.
6. **Há também um bloqueio na ordem de migrações.** As migrações `001–019` estão numa única sequência versionada em `supabase/migrations`. Não basta acrescentar uma migração `020` compatível: o CLI tentaria executar primeiro as versões pendentes `007–019`, onde surgem os conflitos. Não se deve contornar isto marcando versões como aplicadas (`migration repair`) sem provar que o respetivo SQL já foi aplicado de forma equivalente.

## Estratégia proposta

### A. Preservar o multiplayer legado

- Não renomear, apagar, truncar ou recriar as tabelas atuais.
- Não substituir as RPCs de sala existentes enquanto o cliente legado depender delas.
- Implementar a nova geração de multiplayer em objetos isolados, com nomes/versionamento próprios (por exemplo, tabelas internas `private.atina_v2_*` e RPCs públicas `atina_v2_*`).
- Migrar ou adaptar dados apenas com mapeamento explícito, transacional e reversível; manter as salas existentes legíveis pelo cliente antigo durante a transição.
- Atualizar o cliente para o contrato v2 apenas numa alteração separada, com testes de compatibilidade.
- Definir uma estratégia explícita para a sequência de migrações: manter um histórico único compatível com instalações novas e existentes, ou documentar um processo suportado de baseline por ambiente. Não usar `migration repair` como substituto da execução das migrações.

### B. Modos locais

Os objetos `private.atina_challenges` e `private.atina_local_sessions` não existem atualmente no projeto de ranking e podem ser preparados como extensão aditiva, desde que:
- a migração verifique pré-condições e não altere objetos homónimos inesperados;
- os helpers privados e RPCs sejam revistos e testados contra o frontend atual;
- o seed privado dos 753 desafios seja gerado a partir da fonte original, fora do repositório;
- a migração e o seed sejam validados em ambiente de desenvolvimento antes de qualquer aplicação ao projeto de ranking.

A existência de 753 desafios noutro projeto não autoriza a sua cópia automática para este projeto.

### C. Mímicas

A migração atual de Mímicas cria objetos com nomes já existentes no projeto de ranking. Não deve ser aplicada diretamente. A integração tem de reutilizar ou mapear com cuidado as 48 cartas existentes e os segredos relacionados, sem substituir a tabela nem expor palavras/segredos ao cliente. A estrutura da migração v2 só deve ser definida depois de comparar todas as colunas, constraints, funções e o contrato frontend.

### D. Rate limiting

Manter a migração `019` fora desta integração inicial. Antes de a considerar, rever a origem do IP fornecida pelo proxy, os limites por RPC, o comportamento de falha e o impacto global do hook PostgREST.

## Critérios obrigatórios antes de produzir/aplicar uma migração

- Reproduzir o esquema legado completo numa base local descartável e executar a migração candidata desde o início.
- Confirmar que as 4 salas, 4 jogadores, 48 cartas e respetivas relações permanecem intactas.
- Testar as RPCs antigas e as novas em paralelo.
- Testar permissões anon/authenticated, RLS, acesso aos segredos e respostas públicas sanitizadas.
- Testar concorrência, deadlines, repetição de pedidos e recuperação de salas.
- Rever advisors e comparar o contrato do frontend com as assinaturas RPC.
- Testar o percurso de upgrade a partir do histórico real de `atina-ranking`, além do replay limpo usado pelo CI.
- Só depois preparar uma PR de migração executável. A aplicação ao projeto Supabase e o deploy continuam a exigir autorização separada.

## Estado desta branch

- Branch criada a partir de `main`.
- Inventário confirmado por leitura do esquema detalhado do projeto `atina-ranking`; nenhuma tabela, linha, função, configuração PostgREST ou projeto Supabase foi alterado.
- Nenhuma migração foi aplicada e nenhum deploy foi feito.
- Este documento regista a análise e a estratégia; não afirma que a compatibilidade já está implementada ou testada.
