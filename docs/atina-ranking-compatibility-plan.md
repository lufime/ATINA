# Compatibilidade ATINA com atina-ranking

## Estado atual — 2026-11-01

As duas migrações v2 foram aplicadas ao projeto Supabase `atina-ranking` de forma individual e versionada, evitando a execução da sequência antiga incompatível `001–019`.

Migrações registadas no histórico remoto:
- `20261101073917_atina_private_challenges_753` — tabela privada dos 753 desafios, já existente antes desta fase.
- `20261101081358_atina_ranking_v2_local_sessions` — sessões e RPCs locais v2.
- `20261101081410_atina_ranking_v2_multiplayer_mimicas` — multiplayer, Mímicas e budgets de pausa v2.

Os ficheiros de migração no Git usam exatamente as versões registadas no histórico remoto. Não executar `supabase db push` com a pasta completa atual: as versões `001–019` continuam pendentes no histórico de `atina-ranking` e algumas colidem com o esquema legado. Não usar `migration repair` para as marcar como aplicadas sem equivalência comprovada.

## Dados legados preservados

Verificação read-only após aplicação:
- `public.atina_rooms`: 4 linhas.
- `public.atina_room_players`: 4 linhas.
- `private.atina_mime_cards`: 48 linhas.
- `private.atina_mime_secrets`: 0 linhas.
- `private.atina_challenges`: 753 linhas.
- Tabelas v2 criadas: sessões locais, salas/jogadores/respostas/resultados/propostas/votos v2, estado privado de jogo, rondas Mímicas e budgets de pausa v2.

As RPCs legadas continuam presentes com as assinaturas antigas. Nenhuma tabela ou RPC legada foi renomeada, eliminada ou substituída pelas migrações v2. Os 753 desafios foram copiados previamente de `atina-development`; a assinatura agregada dos dez campos foi comparada e coincidiu com a origem. O projeto `atina-development` não foi alterado.

## Segurança verificada após aplicação

- Todas as 10 tabelas v2 públicas/privadas e as tabelas de sessões/rondas/budgets têm RLS ativo.
- `anon` e `authenticated` não têm SELECT direto nas tabelas v2.
- As 26 RPCs v2 são `SECURITY DEFINER`, com `search_path` vazio, execução concedida explicitamente a `anon` e `authenticated`, e revogada a `PUBLIC`.
- Acesso aos dados é feito através das RPCs token-authenticated; os tokens são validados por hash no servidor.
- O advisor continua a reportar INFO `rls_enabled_no_policy` para tabelas sem políticas (acesso direto revogado) e WARN `anon/authenticated_security_definer_function_executable` para RPCs token-authenticated. Os avisos incluem funções legadas já existentes e as novas RPCs v2; não são motivo para revogar indiscriminadamente o acesso necessário ao cliente. As novas RPCs não têm EXECUTE concedido a PUBLIC.
- A migração `019_atina_rpc_rate_limiting` e o hook global `pgrst.db_pre_request` não foram aplicados nesta fase.

## Testes executados

1. **Replay limpo e pgTAP:** passou em https://github.com/lufime/ATINA/actions/runs/41287793112. Todas as migrações do repositório foram aplicadas numa base Supabase local descartável, o histórico foi verificado e a suite pgTAP completa passou.
2. **Upgrade legado v2:** passou em https://github.com/lufime/ATINA/actions/runs/41287793085. A fixture reproduz as 13 tabelas e 17 FKs observadas no inventário read-only real, com colunas/checks/PKs/FKs e RLS, e usa dados sintéticos equivalentes a quatro salas, quatro jogadores e 48 cartas. Aplicou apenas as duas migrações v2 e confirmou preservação de dados, estrutura e sentinelas das RPCs antigas.
3. **Smoke tests de Party e Mímicas:** no workflow de upgrade, confirmou fila Party limitada, bónus da última ronda, alternância de equipas, início de Mímicas, estado público sem resposta e acesso à palavra apenas pelo representante.
4. **Validação estática:** passou em https://github.com/lufime/ATINA/actions/runs/41287793196.
5. **Smoke test transacional no projeto real:** executou as RPCs primeiro como role de serviço e depois como `anon` (com `SET LOCAL ROLE anon`): criação de sessão Party, criação/entrada/início de sala, início de desafios, revelação de pista e submissão de resposta, e fluxo Mímicas com segredo do representante. Tudo decorreu numa transação terminada com ROLLBACK. A consulta posterior confirmou zero sessões/salas/rondas de teste persistidas e manteve as contagens em 4 salas, 4 jogadores, 48 cartas, 0 segredos e 753 desafios.

Limitações: a fixture usa dados sintéticos e sentinelas para as RPCs antigas, não os corpos reais de todas as funções. Não foram executados testes browser E2E, testes em dispositivos reais, nem uma partida humana completa de ponta a ponta.

## Próximos passos e limites

- A PR #17 continua Draft e ainda não foi merged em `main`.
- Depois de confirmar a CI na head atual, marcar a PR como ready, fazer merge autorizado e verificar a publicação GitHub Pages em https://lufime.github.io/ATINA/.
- Após publicação, executar smoke tests read-only no site e confirmar que os clientes usam apenas os contratos v2.
- Não aplicar `001–019` em `atina-ranking`; não alterar o hook PostgREST global; não fazer reset ou alterações em `atina-development`.
- Para futuras migrações de ranking, continuar a aplicar migrações versionadas individualmente com verificação explícita, ou criar e testar uma linha de baseline separada. Não usar a pasta completa atual com `db push` até resolver a incompatibilidade histórica.
