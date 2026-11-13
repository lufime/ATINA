# ATINA — arquitetura dos oito jogos

Estado: âmbito consolidado e preparação técnica; **não aplicar em produção**.
Branch: `atina-social-games-beta`.
Data: 2026-11-13.

## Âmbito confirmado

O ATINA terá oito jogos/experiências no conjunto:

### Três experiências já existentes no ATINA
1. **Jogo principal ATINA** — as modalidades e desafios atuais (inclui os modos já existentes, como individual, duelo, mix, party e multiplayer).
2. **Mímicas** — jogo multijogador com representante por ronda e palavra secreta privada.
3. **Aventura Detetive — O Último Farol** — aventura narrativa de investigação, com papéis humanos/NPC, pistas, interrogatórios e adjunto determinístico.

### Cinco novos jogos sociais
4. **Quanto Achas?** — `quanto_achas`
5. **Associação de Palavras** — `associacao_palavras`
6. **Isto ou Aquilo** — `isto_ou_aquilo`
7. **Mistério Impossível** — `misterio_impossivel`
8. **Palavra Proibida** — `palavra_proibida`

Os cinco jogos sociais novos têm um catálogo conjunto de **2.150 conteúdos**, com rondas à escolha do jogador, níveis de dificuldade, modo individual/equipas e distribuição automática/manual de equipas. Estas decisões não alteram retroativamente as regras específicas do jogo principal, Mímicas ou Detetive.

## Objetivo técnico

Construir a fundação isolada para os cinco jogos sociais novos, garantindo que podem coexistir com os três jogos existentes sem duplicar nem substituir os seus motores, salas, pontuação, conteúdos ou regras. O âmbito global é de oito jogos; a primeira implementação de backend descrita neste documento cobre apenas os cinco novos jogos.

## Estado de segurança e ambiente

- Branch de trabalho: `atina-social-games-beta`.
- Projeto Supabase isolado de testes: `atina-social-games-test` (`wmparhejigqjoqgsxrtp`), região `eu-west-1`.
- A página `jogos-sociais.html` não contém URL nem chave do Supabase de produção.
- Sem credenciais de teste configuradas, o cliente online não é criado e nenhuma RPC é chamada.
- A demonstração `jogos-sociais-demo-local.html` usa dados fictícios e não liga ao backend.
- O projeto Supabase de teste foi criado vazio: sem migrações, tabelas, funções ou dados adicionados até à última inspeção.
- Não alterar `main`, não fazer merge e não aplicar alterações no Supabase de produção.
- Não criar recursos pagos nem ativar serviços pagos sem autorização explícita.

## Separação dos motores

- **Jogo principal ATINA:** manter o motor existente de desafios, validação server-side, sessões, progressão, ranking e respetivos modos.
- **Mímicas:** manter o motor próprio, a palavra secreta privada, o representante por ronda e as regras de validação humana.
- **Detetive:** manter o motor privado da aventura, os papéis, culpado, provas, diálogos e adjunto; nunca expor segredos ainda não descobertos.
- **Cinco jogos sociais novos:** construir um backend social próprio e isolado. Não reutilizar migrações antigas em bloco nem assumir que as RPCs chamadas pelo HTML já existem no novo projeto.

A integração visual pode partilhar navegação, identidade, lobby ou componentes quando os contratos forem compatíveis, mas não pode fundir estados privados nem reduzir as fronteiras de segurança dos três motores existentes.

## RPCs referenciadas pelo cliente social

A lista seguinte é inventário do frontend, não confirmação de que as funções existam no Supabase de teste:

- Sala e estado: `atina_v2_room_state`, `atina_social_game_start_room`, `atina_social_game_get_state`, `atina_social_game_get_results`.
- Respostas e justificações: `atina_social_game_submit`, `atina_social_game_submit_justification`, `atina_social_game_vote_justification`.
- Mistério: `atina_social_game_mystery_get_events`, `atina_social_game_mystery_question`, `atina_social_game_mystery_solve`, `atina_social_game_mystery_answer`.
- Palavra Proibida: `atina_social_game_taboo_round_state`, `atina_social_game_taboo_start_next_turn`, `atina_social_game_taboo_get_turn`, `atina_social_game_taboo_clue`, `atina_social_game_taboo_pass`, `atina_social_game_taboo_guess`.
- Fases e resolução: `atina_social_game_advance_isto_phase`, `atina_social_game_resolve_round`.

Antes de escrever migrações, fechar para cada função: assinatura/tipos, validação de sala e jogador, autorização do anfitrião, transições permitidas, idempotência, concorrência, payload, erros e limites de frequência.

## Inspeção das migrações existentes

A branch inclui migrações do motor principal ATINA, Mímicas, salas V2 e Detetive. A família de RPCs `atina_social_game_*` não foi encontrada nas migrações ativas inspecionadas.

- A fundação antiga `007_multiplayer_room_foundation`/`008_multiplayer_lobby_rpcs` usa o namespace legado `atina_rooms` e não corresponde diretamente ao contrato V2 do frontend social.
- A migração grande `20261101081410_atina_ranking_v2_multiplayer_mimicas.sql` tem pré-condições e dependências próprias de Mímicas; não é uma fundação mínima para os cinco jogos novos.
- O Detetive tem o seu próprio conjunto de migrações e tabelas privadas; não o copiar nem misturar com o estado social novo.
- Não aplicar migrações antigas em bloco ao projeto vazio.

## Arquitetura proposta para os cinco jogos novos

1. Usar exclusivamente o projeto Supabase isolado de testes.
2. Construir uma fundação social v2 mínima, independente e versionada.
3. Implementar salas e jogadores com tokens aleatórios, guardando apenas hashes.
4. Aplicar RLS e privilégios mínimos; o browser não acede diretamente às tabelas privadas.
5. Implementar RPC de estado da sala compatível com `atina_v2_room_state`, sem assumir que a sala contém segredos de jogo.
6. Validar anfitrião no servidor.
7. Suportar equipas automáticas e manuais, incluindo número ímpar de jogadores e alterações de equipa antes do arranque.
8. Suportar modo individual/equipas, dificuldade e número de rondas configurável.
9. Guardar catálogo, respostas e estado privado sem expor soluções antes do momento certo.
10. Carregar e validar os 2.150 conteúdos do conjunto dos cinco jogos.
11. Só configurar o frontend com URL e chave publicável do projeto de teste depois de as migrações e RPCs estarem instaladas e testadas. Nunca colocar chave `service_role` no browser.

Projetos Supabase novos não expõem automaticamente novas tabelas do schema `public` à Data API. As migrações futuras devem definir explicitamente privilégios e políticas RLS; preferir RPCs controladas e não conceder acesso direto desnecessário.

## Requisitos de segurança e consistência

- Todas as RPCs validam sala existente, jogo ativo, estado atual e pertença do jogador.
- Ações exclusivas do anfitrião validam o anfitrião no servidor.
- Respostas e votos são idempotentes ou rejeitam duplicados deterministicamente.
- Mudanças de fase e pontuação são transacionais.
- Soluções de Mistério e palavras secretas de Palavra Proibida não são expostas antes do momento devido.
- Limites de payload e frequência.
- `SECURITY DEFINER` apenas quando necessário, com `SET search_path = ''`, privilégios revogados por defeito e grants explícitos.
- Testes apenas com salas, contas e conteúdos fictícios.

## Plano de validação

- [ ] Confirmar que o jogo principal, Mímicas e Detetive continuam sem alterações funcionais.
- [ ] Rever os contratos e o esquema da fundação social nova.
- [ ] Testar permissões, estados inválidos, duplicados, concorrência e rollback.
- [ ] Testar os cinco jogos sociais novos e os seus fluxos específicos.
- [ ] Testar equipas automáticas/manuais, jogadores ímpares, rondas e dificuldade.
- [ ] Testar reconexão, atualização da página e abandono.
- [ ] Testar em dois ou mais browsers/dispositivos com dados fictícios.
- [ ] Confirmar que o catálogo contém exatamente 2.150 conteúdos válidos, sem duplicados indevidos nem soluções expostas.
- [ ] Só depois ligar a página beta ao projeto de testes.

## Critérios para produção

A passagem para produção exige revisão explícita, backup, migrações versionadas, testes de regressão dos oito jogos, aprovação do utilizador e plano de reversão. Este documento não autoriza alterações à produção.


## Modelo de dados proposto — revisão antes de SQL

O modelo abaixo é a proposta de implementação inicial. Mantém os dados operacionais no schema `private`; só as funções RPC ficam no schema `public`. Nenhuma tabela privada recebe grants diretos a `anon` ou `authenticated`.

### Tabelas privadas

| Tabela | Finalidade e campos principais |
|---|---|
| `atina_social_rooms` | `id uuid`, `code`, `status` (waiting/playing/completed), `host_player_id`, `game_code`, `play_mode`, `difficulty`, `total_rounds`, `current_round`, `phase`, `deadline_at`, `state_version`, timestamps |
| `atina_social_players` | `id uuid`, `room_id`, `token_hash bytea`, `nickname`, `is_host`, `team_id`, `ready`, `score`, `last_seen_at`; token original nunca é persistido |
| `atina_social_teams` | `id uuid`, `room_id`, `label`, `sort_order`; equipa pertence a uma sala |
| `atina_social_content` | `id bigint`, `game_code`, `difficulty`, `content_version`, `payload jsonb`, `active`; catálogo de 2.150 conteúdos |
| `atina_social_rounds` | `id uuid`, `room_id`, `round_number`, `content_id`, `phase`, `prompt_public jsonb`, `secret_payload jsonb`, `started_at`, `deadline_at`, `resolved_at`; solução/segredo separado da projeção pública |
| `atina_social_submissions` | `id uuid`, `round_id`, `player_id`, `answer_payload jsonb`, `normalized_answer`, `score_awarded`, timestamps; unicidade por ronda/jogador quando o jogo só admite uma resposta |
| `atina_social_justifications` | `id uuid`, `round_id`, `player_id`, `text`, `created_at`; texto validado e limitado |
| `atina_social_votes` | `round_id`, `justification_id`, `voter_player_id`, `created_at`; uma escolha por votante e ronda |
| `atina_social_mystery_events` | `id uuid`, `round_id`, `player_id`, `event_type`, `question_text`, `answer_code`, `solution_guess`, `accepted`, timestamp; respostas oficiais do mistério só são escritas por anfitrião/RPC autorizada |
| `atina_social_taboo_turns` | `id uuid`, `round_id`, `active_player_id`, `content_id`, `status`, `clue_text`, `forbidden_violation`, `score`, `deadline_at`; palavra e lista proibida só são devolvidas ao jogador ativo |
| `atina_social_action_log` | `id bigint`, `room_id`, `player_id`, `action_key`, `request_id`, `created_at`; idempotência, auditoria técnica mínima e prevenção de repetição |

Índices e restrições obrigatórios:
- Código de sala único, normalizado e com entropia adequada.
- Hash de token único; FK composta garante que jogador e equipa pertencem à mesma sala.
- `game_code` limitado aos cinco códigos conhecidos.
- `play_mode` apenas `individual` ou `teams`; dificuldade limitada ao catálogo aprovado.
- Ronda única por `(room_id, round_number)`; submissão única por `(round_id, player_id)`; voto único por `(round_id, voter_player_id)`.
- Conteúdo associado tem de pertencer ao mesmo jogo e dificuldade selecionados.
- Restrições de comprimento para nickname, resposta, justificação, pergunta e palpite.
- Não guardar dados pessoais; usar pseudónimos temporários.

### Conteúdo dos 2.150 itens

Cada item tem identificador estável, código do jogo, dificuldade, versão e payload estruturado. O conteúdo específico é validado por jogo:
- `quanto_achas`: enunciado e valor numérico de referência, com unidade/contexto e tolerância ou regra de pontuação.
- `associacao_palavras`: estímulo e critérios/aliases aceites; a lista de respostas aceites fica privada.
- `isto_ou_aquilo`: duas opções e texto de enquadramento; sem resposta certa obrigatória, salvo regra editorial explícita.
- `misterio_impossivel`: enunciado público, solução privada e regras de resposta/validação.
- `palavra_proibida`: palavra-alvo e lista de palavras proibidas, ambas privadas para todos exceto o jogador ativo durante o seu turno.

O importador deve validar exatamente 2.150 registos, distribuição por jogo/dificuldade aprovada, IDs únicos, campos obrigatórios, JSON válido e ausência de duplicados de conteúdo não intencionais. A distribuição por jogo não será inventada: fica fechada a partir do ficheiro/catalogação editorial aprovado antes do seed.

## Contratos RPC — compatibilidade do frontend

Todas as funções recebem `p_room_id uuid` e `p_token text`, exceto quando indicado. As assinaturas abaixo definem o contrato funcional; tipos/ordem finais serão fixados na migration e testados com o frontend.

### Sala e configuração
- `atina_v2_create_room(p_nickname text, p_max_players integer) -> jsonb`: cria sala social isolada e anfitrião; devolve `room_id`, token bearer, código e `player_id`.
- `atina_v2_join_room(p_nickname text, p_code text) -> jsonb`: entra numa sala em espera e devolve token novo.
- `atina_v2_room_state(p_room_id uuid, p_token text) -> jsonb`: projeção compatível com o HTML: `room_id`, `code`, `status`, `max_players`, `is_host`, `player_id`, `players[]`, `game_state`. Nunca inclui token hash nem segredos.
- `atina_social_game_start_room(p_room_id uuid,p_token text,p_game_code text,p_play_mode text,p_total_rounds integer) -> jsonb`: só anfitrião; valida sala em espera, jogadores prontos, jogo ativo, rondas permitidas, dificuldade/configuração, equipas completas e conteúdo disponível; cria as rondas e inicia atomicamente.
- `atina_social_game_get_state(p_room_id uuid,p_token text) -> jsonb`: estado público da ronda mais campos privados apenas do próprio jogador, como `submitted`, `justified`, `voted`; nunca devolve soluções privadas.

### Respostas, justificação e votação
- `atina_social_game_submit(p_room_id uuid,p_token text,p_answer jsonb) -> jsonb`: grava uma resposta por jogador/ronda; valida formato pelo jogo; pontuação calculada exclusivamente no servidor.
- `atina_social_game_submit_justification(p_room_id uuid,p_token text,p_text text) -> jsonb`: só na fase `justify`, limite de tamanho e uma justificação por jogador.
- `atina_social_game_vote_justification(p_room_id uuid,p_token text,p_justification_id uuid) -> jsonb`: só na fase `vote`; impede auto-voto e votos fora da ronda/equipa elegível.

### Mistério Impossível
- `atina_social_game_mystery_get_events(p_room_id uuid,p_token text) -> jsonb`: feed de perguntas/hipóteses e respostas já autorizadas; não revela a solução.
- `atina_social_game_mystery_question(p_room_id uuid,p_token text,p_question text) -> jsonb`: cria pergunta limitada por tamanho/frequência.
- `atina_social_game_mystery_solve(p_room_id uuid,p_token text,p_solution text) -> jsonb`: compara no servidor; devolve apenas correto/incorreto e não a solução.
- `atina_social_game_mystery_answer(p_room_id uuid,p_token text,p_event_id uuid,p_answer_code text) -> jsonb`: apenas anfitrião/autoridade designada responde a pergunta pendente; códigos permitidos `yes`, `no`, `irrelevant`.

### Palavra Proibida
- `atina_social_game_taboo_round_state(p_room_id uuid,p_token text) -> jsonb`: estado agregado dos turnos, sem palavra-alvo nem lista proibida.
- `atina_social_game_taboo_start_next_turn(p_room_id uuid,p_token text) -> jsonb`: anfitrião ou avanço automático autorizado; bloqueia turnos simultâneos.
- `atina_social_game_taboo_get_turn(p_room_id uuid,p_token text,p_turn_id uuid) -> jsonb`: só o jogador ativo recebe palavra-alvo e palavras proibidas.
- `atina_social_game_taboo_clue(p_room_id uuid,p_token text,p_turn_id uuid,p_text text) -> jsonb`: apenas jogador ativo; servidor valida limites e violações quando aplicável.
- `atina_social_game_taboo_pass(p_room_id uuid,p_token text,p_turn_id uuid) -> jsonb`: apenas jogador ativo; uma única passagem por turno.
- `atina_social_game_taboo_guess(p_room_id uuid,p_token text,p_turn_id uuid,p_guess text) -> jsonb`: valida palpite, normaliza e calcula pontos no servidor.

### Fases, resultados e encerramento
- `atina_social_game_advance_isto_phase(p_room_id uuid,p_token text) -> jsonb`: só anfitrião/avanço automático; transições answer → justify → vote → resolve, com relógio de servidor.
- `atina_social_game_resolve_round(p_room_id uuid,p_token text) -> jsonb`: resolve apenas após deadline ou condição de conclusão; pontuação e estado final transacionais.
- `atina_social_game_get_results(p_room_id uuid,p_token text) -> jsonb`: resultados finais filtrados por sala; classificação de equipa e individual sem conteúdo secreto.

### Respostas comuns e códigos de erro

- Sucesso: objeto JSON com `ok: true` e estado mínimo atualizado.
- Erros previsíveis: `ROOM_NOT_FOUND`, `INVALID_TOKEN`, `NOT_HOST`, `ROOM_NOT_WAITING`, `ROOM_FULL`, `GAME_NOT_ALLOWED`, `INVALID_MODE`, `INVALID_ROUND_COUNT`, `NOT_READY`, `INVALID_PHASE`, `ALREADY_SUBMITTED`, `INVALID_PAYLOAD`, `RATE_LIMITED`, `ROUND_NOT_EXPIRED`, `SECRET_NOT_AVAILABLE`.
- A implementação deve devolver mensagens seguras sem SQL interno, nomes de tabelas, tokens ou segredos.

## Equipas, rondas e relógio

- Modo individual: cada jogador pontua individualmente; não se criam equipas.
- Modo equipas: anfitrião escolhe distribuição automática ou manual antes de iniciar.
- Automática: distribuir por ordem estável/aleatória com seed da sala, tentando equilibrar tamanhos; diferença máxima de um jogador.
- Manual: anfitrião atribui cada jogador a uma equipa; não iniciar enquanto existir jogador sem equipa ou equipa vazia.
- Depois de iniciar, equipas e membros ficam bloqueados para preservar justiça e resultados.
- Jogadores ímpares são distribuídos com diferença máxima de um elemento.
- Número de rondas e dificuldade são congelados no início; alterações durante a partida são recusadas.
- Deadline é calculado pelo servidor; o cliente apenas apresenta contagem decrescente. O cliente não pode resolver uma ronda antecipadamente.
- Operações de arranque, avanço de fase e resolução bloqueiam a linha da sala/ronda (`FOR UPDATE`) e usam `state_version` para impedir corridas e duplicação de pontos.

## Idempotência, concorrência e proteção contra abuso

- Cada ação mutável deve aceitar `p_request_id uuid` numa revisão posterior do contrato ou usar chave idempotente determinística por jogador/ronda/ação. A mesma ação repetida devolve o resultado anterior sem duplicar pontos.
- Transações curtas, bloqueios por sala e constraints únicas como última linha de defesa.
- Rate limit por sala/jogador/ação, tamanho máximo de payload e validação de texto.
- Token bearer gerado com fonte criptográfica, transmitido apenas no momento de criação/entrada, guardado no browser local para a sessão e persistido no servidor apenas como hash SHA-256.
- Funções `SECURITY DEFINER` com `SET search_path = ''`; schema e funções sempre qualificados; `REVOKE EXECUTE` por defeito e `GRANT EXECUTE` apenas a `anon`/`authenticated` quando necessário.
- Sem grants de SELECT/INSERT/UPDATE/DELETE às tabelas privadas.
- Testes de fuga de informação com tokens de jogadores diferentes, incluindo jogador ativo de Palavra Proibida, anfitrião do Mistério e jogador comum.

## Decisão de implementação

A próxima entrega técnica será a migration de fundação isolada (salas, jogadores, equipas, catálogo, rondas, submissões e funções de lobby/estado), acompanhada de testes SQL transacionais. As funções específicas de cada jogo serão entregues por blocos e testadas antes de ligar o frontend. **Ainda não aplicar qualquer migration no Supabase nesta etapa de desenho.**


## Primeira migration da fundação — 2026-11-13

Foi criada na branch beta, sem aplicação em qualquer base de dados:

- `supabase/migrations/20261113160000_atina_social_games_foundation.sql`
- Testes estruturais rollback-only: `supabase/tests/20261113160000_atina_social_games_foundation.test.sql`

A migration cria o schema privado `private` e as 11 tabelas do modelo acima, com chaves estrangeiras, restrições, índices, RLS ativado e privilégios diretos revogados para `anon`, `authenticated` e `public`. Não cria ainda RPCs, políticas de acesso direto, nem importa conteúdos.

### Limites da etapa

- A migration foi guardada na branch, mas **não foi aplicada** no Supabase de testes nem em produção.
- O ficheiro de testes foi criado, mas **não foi executado**: a CLI `supabase` não está instalada no ambiente de trabalho disponível e não foi feito deploy de esquema para permitir testes remotos.
- A criação da migration foi feita diretamente pela API de conteúdos do GitHub porque a CLI não está disponível; numa estação com CLI, gerar futuras migrations com `supabase migration new`.
- A compatibilidade de frontend continua pendente: o HTML atual ainda não envia dificuldade no arranque e espera uma sala V2 com campos específicos. O contrato/RPC e o frontend devem ser atualizados em conjunto antes da primeira ativação.
- A próxima revisão deve validar a sintaxe PostgreSQL num ambiente local/isolado, corrigir qualquer erro, executar os testes transacionais e só depois considerar aplicar esta migration no projeto `atina-social-games-test`, mediante confirmação explícita.

Esta migration não altera os motores do jogo principal, Mímicas ou Detetive e não substitui nenhuma migration ativa existente.


## Revisão técnica adicional — 2026-11-13

A revisão estática dos dois ficheiros confirmou delimitadores equilibrados, 11 instruções `CREATE TABLE`, zero funções RPC nesta migration e um teste transacional terminado em `ROLLBACK`. Esta verificação é lexical/estrutural, não é uma validação pelo parser PostgreSQL.

### Bloqueio descoberto antes de qualquer aplicação

A pasta ativa `supabase/migrations/` já contém uma sequência anterior de migrations dos motores e salas existentes, incluindo dependências de ATINA/Mímicas. O Supabase CLI aplica a sequência pendente por ordem; portanto, **não se deve executar simplesmente `db push` ou aplicar esta migration isoladamente sem resolver primeiro a estratégia de histórico**. O projeto de testes está vazio e não tem essas dependências.

Antes de validar ou aplicar no projeto de testes, é necessário escolher e documentar uma estratégia segura:
1. usar uma branch Supabase isolada com baseline/histórico compatível, ou
2. criar um projeto de teste dedicado com histórico completo e preflight das dependências, ou
3. preparar uma pipeline de validação que aplique apenas o conjunto social a uma base PostgreSQL efémera, sem misturar migrations antigas.

Não foi executada nenhuma migration nem teste remoto. O ambiente desta sessão não tem `supabase`, `psql`, servidor PostgreSQL ou Docker disponíveis. Não foi criado nenhum recurso novo nem incorrido qualquer custo.


## Pipeline de validação isolada — 2026-11-13

Para impedir que a migration social entre acidentalmente na sequência antiga do Supabase, foi movida para:

`supabase/social-games/migrations/20261113160000_atina_social_games_foundation.sql`

A pasta ativa `supabase/migrations/` foi verificada e já não contém esta migration. A nova localização é intencional e não é descoberta automaticamente pelo fluxo normal de migrations do Supabase.

Foram acrescentados:
- `.github/workflows/validate-social-games-sql.yml`: inicia PostgreSQL 17 efémero em GitHub Actions, cria os papéis mínimos `anon` e `authenticated`, aplica **apenas** a migration social e executa os testes rollback-only.
- `supabase/social-games/README.md`: explica o isolamento e o processo de validação.

A pipeline não usa secrets, Supabase alojado, dados reais, nem recursos pagos. O resultado só será conhecido depois de a GitHub Actions executar; a criação do workflow não equivale a um teste aprovado.

O projeto Supabase `atina-social-games-test` permanece intocado. A aplicação remota continua dependente de revisão e autorização separadas.


## RPC de salas, jogadores e equipas — 2026-11-13

Foi acrescentada a segunda migration isolada:
`supabase/social-games/migrations/20261113161000_atina_social_games_rooms_teams.sql`

Inclui:
- `atina_v2_create_room`: cria sala e anfitrião; gera código de seis caracteres e token bearer aleatório.
- `atina_v2_join_room`: entrada por código, com bloqueio da sala durante a verificação de lotação.
- `atina_v2_room_state`: devolve estado autorizado ao jogador identificado pelo token; nunca devolve tokens nem hashes.
- `atina_social_team_auto_assign`: distribuição equilibrada em equipas, com diferença máxima de um jogador.

Os tokens têm 256 bits aleatórios; só o hash SHA-256 é persistido. As RPCs usam `SECURITY DEFINER`, `SET search_path = ''`, referências qualificadas e privilégios de execução revogados por defeito e concedidos explicitamente a `anon`/`authenticated`, porque o token bearer é a autorização da sala. As tabelas privadas continuam sem grants diretos.

Testes acrescentados em `supabase/tests/20261113161000_atina_social_games_rooms_teams.test.sql`: criação, entrada, estado para anfitrião/convidado, ausência de fuga do token, distribuição automática e rejeição de token inválido/alteração por não anfitrião.

A pipeline PostgreSQL efémera foi atualizada para aplicar ambas as migrations e executar ambos os ficheiros de teste. A validação da segunda etapa deve ser considerada pendente até a execução correspondente da GitHub Actions terminar com sucesso. Não foi aplicado SQL no projeto Supabase alojado.

Limites conhecidos desta entrega:
- A distribuição automática está implementada; a atribuição manual e criação de equipas manuais ficam para o próximo bloco.
- A página HTML ainda não está ligada a estas RPCs e o contrato de arranque/dificuldade será atualizado em conjunto.
- Ainda faltam limites de frequência e políticas de expiração/limpeza de salas; devem ser fechados antes da ativação online.
