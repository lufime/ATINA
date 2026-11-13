# Jogos sociais ATINA — plano de backend isolado

Estado: preparação técnica; **não aplicar em produção**.
Branch: `atina-social-games-beta`.
Data: 2026-11-13.

## Objetivo

Preparar os cinco jogos sociais para partidas online com salas ATINA, mantendo a versão de produção intacta e usando apenas um backend de testes isolado. Os jogos são:

- `quanto_achas`
- `associacao_palavras`
- `isto_ou_aquilo`
- `misterio_impossivel`
- `palavra_proibida`

Decisões funcionais já aprovadas: 2.150 conteúdos no conjunto dos cinco jogos; rondas à escolha; níveis de dificuldade; modo individual e por equipas; distribuição automática ou manual de equipas.

## Estado de segurança

- A página `jogos-sociais.html` foi alterada para não conter URL nem chave do Supabase de produção.
- O cliente Supabase só é criado quando existirem credenciais configuradas para um ambiente de testes.
- Sem essas credenciais, a página informa que o modo online está em preparação e não executa RPCs.
- A demonstração `jogos-sociais-demo-local.html` continua a ser a opção de experimentação sem backend.
- Não foi criado nem configurado qualquer projeto Supabase novo. Não foram executadas migrações nem alterados dados.

## RPCs chamadas pela interface

A implementação online atual referencia estas RPCs. A lista é um inventário do cliente, não uma confirmação de que as funções existam no servidor:

- Sala e estado: `atina_v2_room_state`, `atina_social_game_start_room`, `atina_social_game_get_state`, `atina_social_game_get_results`.
- Respostas e justificações: `atina_social_game_submit`, `atina_social_game_submit_justification`, `atina_social_game_vote_justification`.
- Mistério: `atina_social_game_mystery_get_events`, `atina_social_game_mystery_question`, `atina_social_game_mystery_solve`, `atina_social_game_mystery_answer`.
- Palavra proibida: `atina_social_game_taboo_round_state`, `atina_social_game_taboo_start_next_turn`, `atina_social_game_taboo_get_turn`, `atina_social_game_taboo_clue`, `atina_social_game_taboo_pass`, `atina_social_game_taboo_guess`.
- Fases e resolução: `atina_social_game_advance_isto_phase`, `atina_social_game_resolve_round`.

Antes de escrever migrações, é obrigatório fechar para cada função: assinatura e tipos; validação de sala/jogador; autorização de anfitrião; transições de estado permitidas; idempotência; concorrência; payload devolvido; tratamento de erros; limites de frequência.

## Migrações existentes e arquivo

A branch contém migrações ativas para a fundação de salas ATINA v2, jogos anteriores e o motor de Detetive. A pesquisa da pasta ativa não encontrou uma série de migrações específica `atina_social_game_*` que implemente o conjunto de RPCs listado acima.

Existe material antigo em `supabase/archive/proposals/` sobre sessões locais, salas multijogador, fila, respostas, pistas, equipas e votação. Esses ficheiros estão arquivados e **não são prova de que o código esteja aplicado nem devem ser aplicados em bloco**. Devem ser comparados com o esquema ativo e com as RPCs atuais antes de qualquer reutilização.

## Arquitetura proposta

1. Criar/usar um projeto Supabase de teste independente, sem dados reais e sem ligação à produção.
2. Confirmar que o plano escolhido não gera custos; não ativar recursos pagos nem criar projeto sem confirmação explícita do utilizador.
3. Reproduzir no ambiente de teste apenas a fundação mínima de salas/jogadores/equipas necessária, a partir das migrações ativas revistas.
4. Implementar as RPCs sociais com autoridade no servidor. O cliente nunca decide pontuação, validação de resposta, vencedor, relógio, permissões ou avanço definitivo de fase.
5. Ativar os cinco jogos apenas no catálogo do ambiente de teste.
6. Configurar URL e chave publicável do ambiente de teste por configuração separada da produção. Nunca incluir chave `service_role` no browser.
7. Testar com salas e jogadores fictícios em dois ou mais browsers/dispositivos.

## Requisitos de segurança e consistência

- Todas as RPCs devem validar sala existente, jogo ativo, estado atual e associação do jogador à sala.
- Ações exclusivas do anfitrião devem validar o anfitrião no servidor, não confiar num valor enviado pelo browser.
- Respostas e votos devem ser idempotentes ou rejeitar duplicados de forma determinística.
- Mudanças de fase e pontuação devem ser transacionais.
- Dados privados de mistério/solução não podem ser incluídos em estados públicos antes do momento adequado.
- Aplicar RLS e privilégios mínimos às tabelas; revogar execução pública desnecessária.
- Limitar tamanho de payload e frequência de chamadas.
- Não guardar dados pessoais reais nos testes.

## Plano de validação antes de ligar o frontend

- [ ] Projeto de teste isolado criado e custo/plano confirmado.
- [ ] Migrações revistas contra o esquema de salas/jogadores/equipas.
- [ ] Contratos de todas as RPCs documentados e aprovados.
- [ ] Testes SQL: permissões, estados inválidos, duplicados, concorrência e rollback.
- [ ] Testes de integração dos cinco jogos.
- [ ] Testes de equipa automática e manual, incluindo jogadores ímpares.
- [ ] Testes de rondas configuráveis e níveis de dificuldade.
- [ ] Testes de reconexão, atualização da página e abandono de jogador.
- [ ] Testes em dois dispositivos com contas fictícias.
- [ ] Só depois, configurar credenciais de teste na beta e validar o deploy.

## Critérios para produção

A passagem para produção exige revisão explícita, backup, migrações versionadas, testes de regressão, aprovação do utilizador e um plano de reversão. Este documento não autoriza qualquer alteração à produção.


## Primeira inspeção do projeto Supabase isolado (2026-11-13)

Projeto: `atina-social-games-test` (`wmparhejigqjoqgsxrtp`), região `eu-west-1`, PostgreSQL 17.11.0.019.

- Projeto recém-criado: zero migrações e zero tabelas.
- `pgcrypto` já está instalado no schema `extensions`, necessário para os hashes de tokens usados pelo modelo de salas.
- Advisors de segurança e performance: sem avisos no estado vazio.
- Não foram criados dados, tabelas, funções ou migrações neste passo.

### Decisão de instalação

Não aplicar diretamente as migrações antigas de salas nem a migração grande de Mímicas. A migração `20261101081410_atina_ranking_v2_multiplayer_mimicas.sql` inclui pré-condições e dependências de catálogos privados de desafios/cartões e estruturas de Mímicas. Não é uma base mínima isolada para os jogos sociais e a sua execução sem essas dependências falharia ou instalaria componentes desnecessários.

A fundação antiga `007_multiplayer_room_foundation`/ `008_multiplayer_lobby_rpcs` usa o namespace legado `atina_rooms` e um contrato de sala diferente do cliente social atual, que chama `atina_v2_room_state`. Não misturar esses contratos.

### Compatibilidade Data API

Projetos novos não expõem automaticamente novas tabelas do schema `public` à Data API. Qualquer futura migração deverá definir explicitamente os privilégios necessários para os papéis usados e ativar RLS com políticas apropriadas. Não assumir que criar tabela torna a tabela acessível pelo cliente.

### Próxima unidade de implementação

Construir uma fundação social v2 mínima, versionada e independente, que forneça:
- salas e jogadores com tokens aleatórios, guardando apenas hash;
- RLS e privilégios mínimos, sem acesso direto às tabelas pelo browser;
- RPC de estado da sala compatível com `atina_v2_room_state`;
- validação de anfitrião no servidor;
- atribuição automática/manual de equipas e prontidão;
- configuração do jogo, número de rondas e modo individual/equipas;
- catálogo e estado privado para conteúdos sociais, sem expor respostas/soluções antes do momento certo.

Depois, implementar e testar as RPCs específicas de cada jogo e carregar os 2.150 conteúdos com validação de integridade. Só ligar o frontend quando os contratos e payloads coincidirem. Esta implementação ainda não foi aplicada à base de dados.
