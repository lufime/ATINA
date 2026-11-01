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

## Fonte privada dos 753 desafios — transferida e verificada

A procura read-only encontrou a fonte de dados completa no projeto Supabase existente **`atina-development`** (`qvvlqrgbtjujsejvenld`), tabela `private.atina_challenges`.

Validação efetuada por consulta agregada e comparação dos campos públicos com `supabase/proposals/public-challenges.json` na branch `main`:

- 753 registos e 753 IDs únicos.
- 753 respostas principais não vazias.
- 753 listas `accepted_answers` não vazias.
- 753 dificuldades válidas (`easy`, `medium`, `hard`).
- 753 registos ativos.
- 15 categorias e 3 níveis de dificuldade.
- Zero diferenças em ID, categoria, emoji, pistas ou URL de imagem face ao catálogo público.

Também foram encontradas branches GitHub antigas com arrays `games` de 750 desafios completos, mas são versões incompletas face ao catálogo atual de 753. A branch `main` já não contém respostas no HTML. Por isso, a tabela privada de `atina-development` é a fonte mais completa encontrada.

**Transferência concluída após autorização explícita:** os 753 registos foram copiados para `atina-ranking.private.atina_challenges`. A contagem, os IDs únicos, as respostas, as alternativas, os níveis e uma assinatura MD5 agregada dos dez campos foram comparados entre origem e destino; a assinatura é idêntica. O projeto `atina-development` não foi alterado. A tabela de destino tem RLS ativo e não concede SELECT a `anon` nem a `authenticated`. A comparação confirma consistência entre os dois conjuntos, mas não prova por si só a proveniência editorial original de cada resposta.

## Estratégia proposta

### A. Preservar o multiplayer legado

- Não renomear, apagar, truncar ou recriar as tabelas atuais.
- Não substituir as RPCs de sala existentes enquanto o cliente legado depender delas.
- Implementar a nova geração de multiplayer em objetos isolados, com nomes/versionamento próprios (por exemplo, tabelas internas `private.atina_v2_*` e RPCs públicas `atina_v2_*`).
- Migrar ou adaptar dados apenas com mapeamento explícito, transacional e reversível; manter as salas existentes legíveis pelo cliente antigo durante a transição.
- Atualizar o cliente para o contrato v2 apenas numa alteração separada, com testes de compatibilidade.
- Definir uma estratégia explícita para a sequência de migrações: manter um histórico único compatível com instalações novas e existentes, ou documentar um processo suportado de baseline por ambiente. Não usar `migration repair` como substituto da execução das migrações.

### B. Modos locais

A tabela `private.atina_challenges` já existe no projeto de ranking e contém os 753 registos privados. A tabela `private.atina_local_sessions` e as RPCs de jogo local continuam por integrar. Podem ser preparadas como extensão aditiva, desde que:
- a migração verifique pré-condições e não altere objetos homónimos inesperados;
- os helpers privados e RPCs sejam revistos e testados contra o frontend atual;
- o seed privado dos 753 desafios seja gerado a partir da fonte original, fora do repositório;
- a migração e o seed sejam validados em ambiente de desenvolvimento antes de qualquer aplicação ao projeto de ranking.

A cópia foi autorizada e concluída. O SQL privado dos desafios não é guardado no GitHub.

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

## Atualização após a transferência e próxima fase

- Migração `20261101073917_atina_private_challenges_753.sql` adicionada ao repositório para documentar exatamente o DDL já aplicado no projeto `atina-ranking`.
- A migração foi registada no histórico remoto como `20261101073917`; a tabela contém 753 registos e a assinatura agregada dos campos coincide com a origem.
- A aplicação ainda não foi adaptada: o cliente já contém chamadas às RPCs de jogo local, mas essas RPCs e a tabela de sessões ainda não existem em `atina-ranking`.
- O multiplayer novo também não está integrado. As RPCs existentes em `atina-ranking` usam o esquema legado; as migrações atuais `007–019` não podem ser aplicadas diretamente.
- **Bloqueio operacional adicional:** no histórico de `atina-ranking`, a migração `20261101073917` aparece depois das migrações antigas e antes de quaisquer migrações futuras. Contudo, as migrações da branch `main` `001–019` continuam pendentes e têm versões anteriores. Antes de executar migrações adicionais com o Supabase CLI, é necessário definir e testar uma estratégia de baseline/upgrade que não marque versões como aplicadas sem equivalência comprovada.

## Estado desta branch

- Branch criada a partir de `main`.
- Inventário confirmado por leitura do esquema detalhado do projeto `atina-ranking`; nenhuma tabela, linha, função, configuração PostgREST ou projeto Supabase foi alterado.
- A migração da tabela privada de desafios foi aplicada no projeto `atina-ranking` com autorização e está agora representada no repositório.
- Nenhuma outra migração foi aplicada; nenhum deploy foi feito.
- Este documento regista a análise e a estratégia; não afirma que a compatibilidade já está implementada ou testada.


## Implementação incremental — camada local v2 (2026-11-01)

Foi preparada na branch desta PR uma primeira camada aditiva para os modos locais:

- Nova migração candidata: `20261101120000_atina_ranking_v2_local_sessions.sql`.
- A tabela de sessões é isolada em `private.atina_v2_local_sessions`; os helpers privados de validação de respostas também usam nomes `atina_v2_*`.
- As seis RPCs locais têm nomes próprios `atina_v2_*`. As RPCs antigas de salas não são substituídas nem redefinidas por esta migração.
- O cliente local em `atina-server-client.js` foi atualizado para chamar as RPCs v2.
- Foram incorporadas as regras mais recentes do modo Party (limite de 10 desafios, alternância de equipas e bónus da última ronda).
- A migração verifica a existência do catálogo privado e da coluna `difficulty`, e recusa criar a tabela v2 se ela já existir. Não exige que o seed privado esteja presente durante um replay limpo; os 753 registos são dados privados e não são incluídos no GitHub.

**Limite importante:** isto é código preparado na branch, não uma migração aplicada. Não foi executado contra PostgreSQL nem contra `atina-ranking`; a verificação feita até agora foi apenas estática (nomes das RPCs e correspondência das chamadas no cliente). A migração ainda depende de uma estratégia de baseline/histórico que impeça o CLI de tentar aplicar primeiro as migrações antigas incompatíveis.

## Estado de validação atualizado (2026-11-01)

- O workflow **Replay Supabase migrations** concluiu com sucesso na head `f3b0a13342442630c741bcf665d494a6ac6ec59d`: todas as migrações do repositório foram aplicadas numa base local descartável vazia, o histórico local foi verificado e a suite pgTAP terminou com `All tests successful` / `Result: PASS`.
- O workflow **Validar banco de desafios** também concluiu com sucesso na mesma head, incluindo a validação estática ampliada das RPCs v2 e das referências às tabelas Mímicas existentes.
- Estes resultados provam que a sequência instala numa base vazia e que os testes pgTAP existentes passam. **Não provam ainda um upgrade seguro do esquema legado de `atina-ranking`**, porque o workflow não reproduz as tabelas/RPCs legadas nem as quatro salas reais.
- As camadas local v2 e multiplayer/Mímicas v2 estão preparadas na branch; não foram aplicadas a nenhum projeto Supabase remoto e ainda não têm testes funcionais dedicados para cada RPC, concorrência, browser ou dispositivos reais.

## Bloqueios antes de produção

- Foi acrescentada uma fixture sintética de compatibilidade e um workflow isolado: `Test legacy schema upgrade`. Na execução `41287466284`, a criação do esquema legado, aplicação exclusiva das duas migrações v2 e asserções terminaram com sucesso. A fixture cobre quatro salas, quatro jogadores, as colunas legadas `is_ready`/`joined_at`/`token_hash text`, 48 cartas, segredos, e sentinelas para `atina_room_state`/`atina_create_room`.
- O teste confirmou a preservação das quatro salas, quatro jogadores, 48 cartas, zero segredos existentes, coluna `is_ready`, RPCs antigas e permissões/RLS das novas tabelas. Também executou Party (fila limitada, bónus da última ronda e alternância de equipas) e Mímicas (início da ronda, estado público sem resposta e entrega da palavra ao representante).
- Limite da prova: a fixture é sintética e centrada nos objetos que a migração v2 toca; não é um clone integral de todas as políticas, funções e constraints do projeto remoto. Por isso, não substitui a revisão final do inventário real nem a validação pós-aplicação read-only.
- Definir uma estratégia de baseline suportada para o histórico real de `atina-ranking`. O replay limpo não resolve a sequência pendente `001–019` que colide com o esquema legado; não usar `migration repair` como atalho.
- Só depois de todos estes critérios passarem, preparar e rever a migração de upgrade e o plano de rollback. A autorização do utilizador permite a execução final quando segura, não justifica aplicar uma sequência já identificada como incompatível.

A PR mantém-se Draft até estes bloqueios estarem resolvidos. Não houve alterações em `main`, `atina-development`, nem no projeto remoto `atina-ranking` para além da transferência dos 753 desafios já documentada. Não houve deploy GitHub Pages.


## Implementação incremental — multiplayer e Mímicas v2 (2026-11-01)

Foi preparada uma segunda migração candidata: `20261101130000_atina_ranking_v2_multiplayer_mimicas.sql`.

- Cria tabelas isoladas `public.atina_v2_*` e `private.atina_v2_*` para salas, jogadores, respostas, resultados, propostas/votos, estado de jogo, rondas de Mímicas e budgets de pausa.
- Cria RPCs novas com prefixo `atina_v2_*`; o cliente em `index.html` e `atina-server-client.js` foi atualizado para chamar esses contratos.
- A camada de Mímicas referencia a tabela já existente `private.atina_mime_cards`; não recria nem volta a inserir as 48 cartas. As rondas e os segredos são tratados na estrutura v2.
- O pedido de pausa passou a usar `atina_v2_request_timeout` e uma tabela privada de budgets v2, separada dos budgets legados.
- A migração verifica a existência do catálogo de desafios, das 48 cartas Mímicas e das tabelas legadas necessárias, e recusa colisões com tabelas v2 já criadas. Não exige o seed privado de desafios no replay limpo.
- Não redefine nem elimina as RPCs antigas nem altera as tabelas de salas legadas.

**Verificação efetuada:** inspeção estática confirmou que os RPCs chamados pelo cliente têm definições correspondentes na migração, que os nomes de RPC antigos deixaram de ser chamados pelo cliente atualizado e que não existe seed de cartas Mímicas na migração. A migração mantém referências às tabelas antigas apenas nas pré-condições que confirmam a sua existência e na tabela de cartas partilhada.

**Ainda não testado:** não foi executado parser PostgreSQL, replay, pgTAP, teste de upgrade ou teste de browser. A migração depende ainda da estratégia de baseline/histórico e de testes numa base descartável que reproduza o esquema legado. Não aplicar no projeto remoto nesta fase.

