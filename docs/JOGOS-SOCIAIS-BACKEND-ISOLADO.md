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
