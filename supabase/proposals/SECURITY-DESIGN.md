# ATINA — plano de reforço de segurança do multiplayer

Estado: proposta de implementação numa branch isolada. Não aplicar à produção sem revisão e testes.

## Branch
`security/server-side-validation`

## Diagnóstico confirmado no Supabase ligado
- As funções `atina_submit_room_answer` e `atina_submit_team_proposal` recebem `p_correct` e `p_points` fornecidos pelo cliente.
- `atina_vote_team_proposal` não verifica o deadline da partida.
- `atina_publish_game_state` permite ao anfitrião publicar o estado JSON completo; o cliente anfitrião controla deadline, fila e estado de ronda.
- `atina_room_state` devolve o estado global do jogo aos jogadores da sala.
- As funções atuais usam `SECURITY DEFINER` com `search_path=''`, o que deve ser preservado e revisto cuidadosamente.

## Inventário do banco de desafios
A extração do array `games` no commit de origem encontrou 802 posições: 753 desafios válidos e 49 posições nulas preservadas no array esparso. Existem 15 modalidades; 14 têm 50 desafios e “Detetive” tem 53. Os identificadores abaixo preservam o índice original do array, importante porque a fila multiplayer atual usa esses índices.

O ficheiro `public-challenges.json` contém apenas campos públicos (modalidade, emoji, pistas e URL de imagem). Não contém resposta nem respostas alternativas. As respostas secretas não devem ser adicionadas a este repositório público.

## Arquitetura proposta

1. Manter um catálogo público de pistas sem respostas.
2. Criar `private.atina_challenges` para resposta principal e alternativas aceites, com RLS ativado e sem permissões de leitura para `anon`/ `authenticated`.
3. Criar uma RPC autenticada por token de sala que devolva apenas a modalidade, emoji, pistas e imagem do desafio ativo.
4. Alterar submissão individual para receber apenas `p_answer`; a função consulta o segredo, normaliza a resposta, valida o deadline com `clock_timestamp()`, calcula pontos e atualiza score atomicamente.
5. Alterar proposta de equipa para receber apenas `p_answer`; a validação e os pontos são guardados pelo servidor. A votação exige deadline ainda válido, bloqueia o proponente e termina de forma atómica.
6. Retirar segredos do bundle público e exigir ligação à Internet em todos os modos, incluindo Individual, Duelo, Mix, Equipas/Party e Multijogador. Não existe fallback de validação local: sem ligação ao servidor, não se inicia uma partida nem se submete uma resposta.
7. Tornar o relógio do servidor autoritativo. O cliente deixa de poder definir o deadline através de `atina_publish_game_state`; publicar apenas ações permitidas, com transições validadas no servidor.
8. Mímicas: recalcular os pontos na RPC com base no deadline, pista atual e duração; ignorar `p_points` recebido do cliente.

## Compatibilidade e migração
- Preservar os IDs originais dos desafios para não quebrar filas já em curso.
- Não alterar salas que estejam atualmente em jogo; migrar apenas novas partidas para a versão de protocolo nova.
- Definir versão do protocolo no estado da sala e rejeitar chamadas com versão incompatível.
- Manter a modalidade Imagem misteriosa com seis pistas; restantes modalidades têm cinco.
- Não publicar as respostas na pasta `public`, em ficheiros estáticos ou no bundle JavaScript.

## Trabalho ainda necessário antes de ativar
- Gerar carga privada de respostas a partir da fonte original, por canal privado e fora deste repositório público.
- Rever a função de normalização/fuzzy matching para reproduzir o comportamento atual `answerMatches`.
- Implementar novas assinaturas RPC e revogar as assinaturas antigas que aceitam `p_correct`/`p_points`.
- Atualizar o frontend para consumir o catálogo público e pedir validação ao servidor.
- Criar testes SQL de deadline, concorrência, duplicação, votos, pontuação, isolamento de segredos e permissões.
- Executar advisors de segurança e testes end-to-end antes de qualquer merge/deploy.

## Critério de aceitação
Nenhuma chamada do navegador pode escolher se uma resposta está correta, atribuir pontos, alargar um prazo ou ler respostas secretas. Todas as transições que afetam pontuação e deadline devem ser validadas e persistidas numa única transação no servidor.

## Decisão de produto — validação online obrigatória

Decisão confirmada pelo utilizador em 2026-10-31: **todos os modos exigem ligação à Internet para validar respostas**. A validação local/offline deixa de ser suportada. Esta decisão permite retirar integralmente as respostas do HTML/JavaScript público, em vez de manter uma cópia local vulnerável.

### Modos locais (Individual, Duelo, Mix e Party)

Estes modos são atualmente executados no navegador. Não basta trocar a comparação local por uma RPC stateless: o cliente poderia falsificar o ID do desafio, a quantidade de pistas reveladas, o tempo restante, a sequência de respostas, os bónus ou o resultado final. A implementação deve criar uma sessão de jogo autoritativa no servidor:

1. Uma RPC inicia a sessão e recebe o modo, dificuldade, duração e categoria pretendidos. O servidor valida os parâmetros, gera a fila aleatória e guarda a sessão, o token opaco, o desafio atual, o deadline, as pistas reveladas, os jogadores/equipas, a pontuação, a sequência e o estado de conclusão.
2. O cliente recebe apenas dados públicos do desafio ativo: ID, categoria, emoji, pistas e imagem. Não recebe os campos `answer` nem `accepted_answers`.
3. RPCs separadas avançam a pista, submetem a resposta, passam o desafio e avançam para o seguinte. Cada operação bloqueia a sessão (`FOR UPDATE`), valida o token, o estado e o deadline com o relógio do servidor, e persiste a transição atomicamente.
4. A RPC de resposta recebe apenas o texto escrito. O servidor normaliza e compara com a resposta principal e alternativas, aplica a regra fuzzy equivalente a `answerMatches`, calcula pontos e penalizações e atualiza o estado. O cliente nunca envia `p_correct`, `p_points`, tempo restante ou contagem de pistas como autoridade.
5. O servidor também calcula os bónus de rapidez, sequência, dificuldade, cartas especiais e final de Party, bem como a meta de 250 pontos e o vencedor. A implementação deve reproduzir as regras atuais; não simplificar silenciosamente a pontuação.
6. Ao terminar ou passar um desafio, o servidor pode devolver a solução desse desafio. A solução só é divulgada depois de a resposta/passe/timeout estar definitivamente fechado.
7. O token de sessão deve ter entropia criptográfica suficiente, ser tratado como credencial bearer e nunca ser colocado em URLs ou logs. Prever expiração, rate limiting e limpeza de sessões abandonadas.

### Multijogador

As RPCs atuais de sala devem convergir para as mesmas regras de validação e pontuação. As respostas não podem estar no `game_state`, na resposta de `atina_room_state`, nem em qualquer payload público. O anfitrião pode pedir uma ação (revelar pista, passar, avançar), mas o servidor valida e executa a transição; não aceita um JSON de estado arbitrário como fonte de verdade.

### UX e comportamento sem ligação

- Antes de iniciar qualquer modo, confirmar que o serviço está acessível.
- Se a ligação cair durante a partida, bloquear submissões e transições e mostrar uma mensagem clara para restabelecer a ligação; nunca validar no navegador como fallback.
- Ao recuperar a ligação, consultar o estado persistido no servidor e retomar apenas se a sessão ainda for válida.
- O ranking só pode receber pontuações calculadas e confirmadas pelo servidor; não aceitar valores arbitrários do cliente.

### Trabalho de implementação ainda necessário

- Desenhar a tabela privada de sessões e as RPCs transacionais para os modos locais.
- Migrar a lógica de pontos e as regras de cada modo para funções SQL testáveis.
- Implementar os endpoints autoritativos de estado/ações do multijogador e Mímicas.
- Remover do `index.html` todo o array de respostas, incluindo respostas alternativas, e carregar apenas o catálogo público de pistas.
- Carregar os 753 registos de resposta para a tabela privada através de um canal privado de desenvolvimento, nunca através de commit num repositório público.
- Testar concorrência, repetição de chamadas, deadlines, sessões expiradas, pontuação, bónus, votos de equipa e ausência de fuga de segredos.
- Só depois de testes completos, rever e autorizar separadamente qualquer migração/deploy em produção.

**Estado:** decisão de arquitetura registada; ainda não implementada no frontend nem no Supabase. A migration SQL existente continua a ser apenas uma proposta e não foi aplicada.

## Incremento de implementação — comparador de respostas

Foi acrescentada a proposta `003-server-answer-matching.sql`, com normalização de texto em português e correspondência fuzzy por palavra, alinhada com os limites de distância da função JavaScript atual. O helper que consulta `private.atina_challenges` é interno e tem `EXECUTE` revogado para `public`, `anon` e `authenticated`; não existe uma RPC pública que permita enumerar respostas por tentativa.

Os testes propostos estão em `003-server-answer-matching.test.sql` e cobrem acentos/pontuação, correspondência exata, tolerância a pequenos erros em palavras longas, palavras curtas e contagem de palavras.

**Limite deste incremento:** são propostas SQL ainda não executadas. A tabela privada precisa de dados e os helpers ainda têm de ser chamados pelas RPCs autoritativas das sessões locais e salas multiplayer. O frontend continua sem alteração nesta fase.

## Incremento — sessões autoritativas para Individual e Duelo

Foi acrescentada a proposta `004-local-session-rpcs.sql` para os modos **Individual** e **Duelo**. O servidor cria a fila aleatória, gera um token bearer de 256 bits (guarda apenas SHA-256), mantém a ronda/pistas/pontuações e expõe apenas o desafio público. As RPCs recebem o texto da resposta, nunca um booleano de correção ou pontos.

Operações propostas:
- `atina_start_local_game`: cria sessão e fila no servidor.
- `atina_local_game_state`: recupera o estado; se o deadline expirou, fecha a ronda e aplica a penalização.
- `atina_local_reveal_clue`: revela uma pista por chamada.
- `atina_local_submit_answer`: compara com o segredo privado e calcula penalização/pontos/rapidez/sequência/carta especial; fecha a ronda em caso de acerto.
- `atina_local_pass_challenge`: fecha a ronda e revela a solução apenas depois de passar; um passe depois do deadline conta como timeout.
- `atina_local_next_challenge`: alterna o jogador no Duelo e avança/volta a baralhar a fila.

Foi também acrescentado um conjunto inicial de testes pgTAP em `004-local-session-rpcs.test.sql`, com um desafio temporário isolado. Estes testes **não foram executados**.

### Limites e pré-requisitos ainda por resolver

- A coluna privada `difficulty` tem de ser preenchida para os 753 desafios com a classificação exatamente equivalente a `classifyChallenge` do frontend. Sem essa carga, a RPC não encontra desafios e não deve ser ativada.
- A migração da pontuação base, bónus de rapidez, sequência, cartas especiais, penalização, meta de 250 e alternância do Duelo está proposta; precisa de execução de testes comparativos contra o comportamento atual.
- O tempo de corrida acumulado, o ranking e a apresentação de resultados ainda não foram migrados para autoridade do servidor.
- Não há ainda rate limiting por token nem limite de tentativas por ronda; definir estes controlos antes de disponibilizar publicamente.
- O frontend ainda usa o array `games` com respostas e não chama estas RPCs. Esta proposta, isoladamente, **não protege partidas reais**.
- Mix, Party, Mímicas e os modos de sala multiplayer continuam fora deste incremento.

A proposta continua isolada na branch. Nenhuma migration foi executada no projeto Supabase ligado e nenhuma alteração foi feita em produção.


### Revisão de equivalência de pontuação (004)

Foi confirmado no frontend original que a pontuação base é 10/15/20 pontos para Fácil/Médio/Difícil. A RPC usa esses valores. O bónus de rapidez foi ajustado para reproduzir a ordem de arredondamento do cliente: primeiro arredondar os segundos restantes para cima e depois dividir por 10 com arredondamento para baixo. A penalização por resposta errada/timeout continua a ser -10; uma resposta errada repõe a sequência, mas permite nova tentativa; acerto fecha a ronda. O passe não altera pontos e fecha a ronda.

Os testes pgTAP de 004 passaram de 8 para 12 asserções propostas, incluindo rejeição de submissão repetida e timeout autoritativo (penalização e revelação da solução). **Não foram executados** e não demonstram ainda equivalência completa da corrida, da duração entre desafios, do ranking ou dos modos Mix/Party.


## Gerador local da carga privada dos desafios

Foi acrescentado `scripts/generate-private-challenge-seed.mjs`. O script lê o `index.html` original localmente, extrai o array `games`, preserva os índices originais (incluindo os 49 espaços vazios), reproduz a classificação de dificuldade de `challengeDifficultyScore`/`classifyChallenge` e valida categoria, emoji, pistas e imagem contra `public-challenges.json`.

O script gera um SQL com os 753 registos secretos (resposta e alternativas) **apenas num caminho absoluto escolhido fora do repositório**, com permissões de ficheiro `0600` e criação exclusiva para não substituir um ficheiro existente. O SQL inclui a coluna `difficulty` e um `INSERT ... ON CONFLICT` idempotente. O ficheiro gerado nunca deve ser adicionado ao Git nem enviado para o chat.

Uso local:
```sh
node scripts/generate-private-challenge-seed.mjs /caminho/privado/atina-private-seed.sql
```

Depois de rever o ficheiro, a execução deve ser feita manualmente apenas numa instância Supabase de desenvolvimento. O gerador está na branch, mas **não foi executado nesta sessão**, não foi gerado nem carregado qualquer ficheiro de respostas, e não foi feita qualquer ligação/escrita ao Supabase.


O gerador tem também o modo `--check`, que valida a estrutura, o alinhamento com o catálogo público e a classificação dos 753 desafios sem escrever/exportar o SQL secreto. O workflow inclui `node --check` e `node scripts/generate-private-challenge-seed.mjs --check` na branch de segurança. O caminho de saída é validado com resolução de symlinks, exige diretório existente fora do repositório e usa criação exclusiva para evitar sobrescrever ficheiros.


### Revisão adicional das RPCs locais

Na revisão estática da proposta 004 foi corrigido um problema de deadline sob contenção: `clock_timestamp()` era capturado na entrada das funções de submissão/avanço, antes de obterem o `FOR UPDATE`. Se uma chamada aguardasse pelo lock, poderia usar uma hora desatualizada e aceitar uma resposta após o prazo, ou prolongar ligeiramente a sessão seguinte. Agora a hora é capturada imediatamente depois de o lock da sessão ser obtido e antes de validar expiração/deadline.

Esta correção é apenas uma revisão estática do SQL. Não foi executada em PostgreSQL e não substitui testes concorrentes numa base de desenvolvimento. O âmbito continua limitado a `solo` e `duel`; Mix, Party/Equipas e Mímicas ainda não estão implementados nesta proposta.


### Incremento — suporte inicial de Mix no servidor

A RPC de início de sessão aceita agora `mix`. Quando o cliente pede Mix sem categoria, a fila é gerada aleatoriamente a partir de todos os desafios ativos da dificuldade escolhida. O estado e as respostas continuam a ser controlados pelas mesmas RPCs autoritativas de Individual.

Foi acrescentada uma asserção pgTAP para confirmar que o servidor inicia uma sessão Mix sem filtro de categoria. O teste está escrito, mas **não foi executado** porque não existe uma base Supabase de desenvolvimento autorizada e sem custos.

**Party/Equipas continua por implementar:** antes de codificar a regra, é necessário mapear fielmente o número de equipas/jogadores, alternância, limite de rondas e duplicação de pontos na ronda final, sem inferir regras a partir do nome do modo.


### Incremento — deadlines uniformes nas RPCs locais (2026-10-31)

Foi corrigida a validação temporal de `atina_local_game_state`, `atina_local_reveal_clue` e `atina_local_pass_challenge`:

- Todas obtêm o lock da sessão antes de capturar `clock_timestamp()`.
- A consulta de estado fecha uma ronda expirada e aplica a penalização de timeout.
- Revelar uma pista depois do prazo deixa de devolver apenas um erro: fecha a ronda, aplica a penalização e devolve o estado final.
- Passar depois do prazo também regista timeout e penalização; passar dentro do prazo mantém o resultado `pass`.
- A atualização do estado usa a mesma hora capturada após o lock.

A alteração foi aplicada apenas em `atina-development` e documentada em `005-local-session-deadline-consistency.sql`. O teste transacional pgTAP `005-local-session-deadline-consistency.test.sql` contém seis asserções para os casos de timeout e para confirmar que as três RPCs mantêm `SECURITY DEFINER` com `search_path` vazio.

**Estado da verificação:** a execução de teste terminou com a asserção final `ok 6`; o runner MCP apresenta apenas a última linha de pgTAP no resultado. A operação anterior que usou pistas com três elementos falhou a constraint e foi revertida; a execução seguinte usou cinco pistas e concluiu sem erro. A migration/proposta e o teste foram adicionados à branch isolada.

**Risco ainda por resolver:** as seis RPCs públicas continuam deliberadamente executáveis por `anon` e `authenticated`, protegidas pelo token bearer aleatório de 256 bits. O Advisor continua a assinalar os dois avisos de SECURITY DEFINER. Antes de produção é necessário rever a exposição pública, introduzir rate limiting/limites de criação e chamadas por sessão e executar testes de concorrência. Os avisos RLS sem policies nas duas tabelas do schema privado são esperados com os grants revogados; devem continuar sob monitorização.


### Incremento — modo Party nas sessões locais (2026-10-31)

Foi acrescentado suporte inicial do modo Party nas RPCs locais, mantendo as regras observadas no cliente:
- A fila é aleatória e limitada a 10 desafios (ou menos se o filtro só tiver menos desafios).
- A equipa/jogador alterna entre os dois índices a cada ronda, através da lógica comum de `atina_local_next_challenge`.
- Na última ronda, os pontos totais calculados (base, rapidez, sequência e carta especial) são duplicados antes de serem somados.
- O estado final identifica `party_final_round_bonus` para a interface.

A alteração está em `006-local-party-mode.sql` e o teste transacional em `006-local-party-mode.test.sql`. Foi aplicada apenas em `atina-development`. Quatro asserções pgTAP passaram: limite de 10 desafios, início Party, duplicação da pontuação na última ronda e sinalização do bónus no estado. A chamada do runner apresenta a última asserção como `ok 4`.

**Limite:** este suporte cobre o Party local, não o multiplayer por salas nem Mímicas. O frontend continua sem alterações e ainda valida localmente; não ligar estes modos à UI até completar o contrato e os testes.


**Correção complementar Party:** a primeira versão reutilizava a alternância de Duelo sem incluir explicitamente Party, o que mantinha a Equipa 1 ativa. Foi corrigida `atina_local_next_challenge` para alternar entre as duas equipas em ambos os modos. O teste foi ampliado para cinco asserções e confirmou a mudança para a Equipa 2 após avançar da primeira ronda. A proposta 006 e o teste foram atualizados antes de considerar este incremento concluído.


### Auditoria de Multiplayer e Mímicas — bloqueio de ambiente (2026-10-31)

A revisão do código do cliente confirmou que o protocolo atual chama as RPCs `atina_submit_room_answer`, `atina_vote_team_proposal`, `atina_submit_team_proposal`, `atina_start_room`, `atina_start_mime_round`, `atina_resolve_mime_round`, `atina_get_mime_secret`, `atina_finish_mime_room`, `atina_request_timeout`, `atina_set_room_ready` e `atina_set_room_team`.

A migration existente `supabase/migrations/20261031204614_atina_multiplayer_mimicas.sql` não cria a fundação das salas; pressupõe que já existam `public.atina_rooms`, `public.atina_room_players`, `public.atina_room_answers` e `public.atina_room_results`. A migration de Mímicas atual permite ao anfitrião enviar `p_correct` e `p_points` para `atina_resolve_mime_round`; limita o intervalo de pontos, mas não calcula a pontuação com base na dificuldade/índice de pista e no prazo do servidor. Também depende de `game_state.deadline`, que o protocolo cliente pode publicar/alterar, pelo que não constitui um relógio autoritativo.

**Bloqueio confirmado no projeto de desenvolvimento:** o schema `public` de `atina-development` não contém as tabelas `atina_rooms`, `atina_room_players`, `atina_room_answers` ou `atina_room_results`, nem as RPCs de salas acima listadas. Só estão instaladas as seis RPCs locais. A migration de Mímicas, portanto, não pode ser aplicada nem testada isoladamente nesse projeto. Não foi consultada nem alterada a base de dados de produção para contornar esta ausência.

**Decisão técnica para a próxima fase:** antes de reescrever as RPCs de salas, é necessário reconstruir e versionar a fundação multiplayer no ambiente de desenvolvimento (tabelas, constraints, índices, RLS/grants e RPCs de lobby), confirmar o contrato de cada chamada do cliente e só depois criar estado privado autoritativo para cada ronda. O estado privado deve guardar deadline como `timestamptz` gerado pelo servidor; o anfitrião só poderá comunicar o resultado observado (acerto/passe), nunca pontos nem prazo. As respostas dos desafios também terão de ser comparadas no servidor, sem aceitar `p_correct`/ `p_points` do cliente.

Até essa fundação existir, não é seguro fazer alterações isoladas às funções de Mímicas ou declarar Multiplayer/Mímicas protegidos. Nenhuma migration multiplayer foi aplicada no projeto de desenvolvimento nesta fase.


### Incremento — fundação de dados das salas multiplayer (2026-10-31)

Foi reconstruído o primeiro nível do esquema de salas a partir das chamadas e dos campos efetivamente consumidos pelo cliente existente. A proposta `007-multiplayer-room-foundation.sql` define:
- `atina_rooms`: código de seis caracteres, limite de participantes, estado, versão e timestamps;
- `atina_room_players`: participantes, anfitrião, prontidão, equipa, pontuação e hash do token bearer;
- `atina_room_answers`: ledger de tentativas e pontos;
- `atina_room_results`: resultados finais;
- `atina_room_team_proposals` e `atina_room_team_votes`: propostas e votos de equipa.

Todas as tabelas têm RLS ativo e acesso direto revogado para `public`, `anon` e `authenticated`. Foram acrescentados índices e chaves estrangeiras para manter os registos associados à sala e ao participante. A proposta e o teste estão versionados na branch isolada.

**Aplicação e verificação:** o DDL foi aplicado diretamente apenas em `atina-development` para permitir iteração, sem criar ainda uma entrada de migration. O teste pgTAP executado no mesmo projeto terminou em `ok 14`: seis tabelas presentes, RLS nas seis tabelas e ausência de SELECT direto para anon/authenticated nas tabelas verificadas. O teste foi transacional e revertido; o DDL permanece instalado.

**Limites importantes:** esta etapa cria apenas o esquema de dados. Ainda não implementa as RPCs de criação/entrada/estado/saída de sala, prontidão, equipas, pausas, propostas ou pontuação. A migration antiga de Mímicas continua sem ser aplicada, e as funções que aceitam estado arbitrário, `p_correct` ou `p_points` não foram expostas nem ativadas. A compatibilidade completa das constraints com todos os fluxos do cliente ainda tem de ser validada através das RPCs e testes de integração.

Nenhuma alteração foi feita à produção, frontend, branch principal, deploy, merge ou PR.


**Revisão dos advisors após a criação do esquema:** o advisor de performance identificou três FKs sem índice de cobertura. Foram adicionados índices em `(room_id, player_id)`, `(room_id, proposer_id)` e `player_id`, tanto no DDL versionado como no projeto de desenvolvimento. O advisor de segurança assinala RLS ativo sem policies nas seis tabelas novas; é intencional nesta fase, porque o acesso direto está revogado e o acesso futuro será exclusivamente através de RPCs token-authenticated. Não se devem criar policies genéricas para contornar estes avisos. Os avisos SECURITY DEFINER existentes dizem respeito às seis RPCs locais já instaladas, não a novas RPCs multiplayer (ainda não criadas).


### Incremento — RPCs de lobby multiplayer (2026-10-31)

Foi implementado e aplicado apenas em `atina-development` o primeiro conjunto de sete RPCs do lobby:
- `atina_create_room` e `atina_join_room`: validam pseudónimo/limites, geram código e token bearer aleatório de 256 bits; apenas o hash SHA-256 do token é guardado.
- `atina_set_room_ready`: cada participante controla a sua prontidão enquanto a sala aguarda.
- `atina_set_room_team`: apenas o anfitrião atribui ou remove equipas no lobby.
- `atina_start_room`: apenas o anfitrião inicia, com pelo menos dois jogadores e todos prontos.
- `atina_room_state`: valida o token e devolve participantes, estado, pontuações e dados da equipa.
- `atina_leave_room`: remove o participante e transfere o anfitrião para o participante mais antigo quando necessário.

As funções usam `SECURITY DEFINER`, `search_path = ''` e referências qualificadas; o acesso às tabelas permanece revogado. O cliente recebe o token uma única vez na criação/entrada e usa-o nas chamadas seguintes.

**Testes:** 12 asserções pgTAP passaram no projeto de desenvolvimento, cobrindo criação, entrada, credenciais, código, atribuição de equipa, prontidão, estado do lobby, rejeição de token inválido, arranque e restrição de permissões do anfitrião, e saída. O teste correu numa transação revertida. A proposta SQL e o teste estão versionados em `008-multiplayer-lobby-rpcs.sql` e `008-multiplayer-lobby-rpcs.test.sql`.

**Limitações deliberadas:** ainda não existem RPCs seguras para publicar o estado de jogo, submeter respostas, votar em propostas, gerir pausas ou finalizar partidas. `atina_publish_game_state` não foi implementada: não aceitaremos um JSON arbitrário do anfitrião, porque isso permitiria manipular fila, pistas, pontuação e deadline. O início do lobby coloca a sala em estado `playing` com modo `pending`; a integração de jogo só deve ocorrer quando o servidor gerar e controlar a fila e o estado privado. O protocolo atual do frontend ainda não é compatível com este contrato seguro e não foi alterado.

As RPCs são executáveis por `anon` e `authenticated` com token bearer, pelo que os avisos SECURITY DEFINER do Advisor continuam a ser relevantes. Antes de produção são necessários rate limiting, proteção contra abuso na criação/junção, testes de concorrência e revisão independente da superfície pública.


**Advisor após as RPCs de lobby:** o Advisor reporta 13 funções SECURITY DEFINER executáveis por anon/authenticated: as sete RPCs de lobby agora adicionadas e as seis RPCs locais já existentes. Isto é esperado pelo modelo atual de token bearer, mas mantém exposição pública e exige mitigação de abuso/rate limiting antes de produção. O Advisor também reporta oito tabelas com RLS sem policies: as seis tabelas de sala e as duas tabelas privadas locais; os grants diretos permanecem revogados. O advisor de performance já não reporta FKs sem índice de cobertura nas tabelas de sala; restam apenas avisos de índices não utilizados, incluindo um índice do ledger que ainda será usado pelas RPCs de submissão.


## Incremento 009 — fila multiplayer privada e estado público sanitizado

Aplicado apenas em `atina-development` através da migration `009_multiplayer_server_queue`. A proposta SQL e os testes estão versionados em `009-multiplayer-server-queue.sql` e `009-multiplayer-server-queue.test.sql`.

- Criada `private.atina_room_game_state`, com RLS ativo e sem permissões diretas para `anon`/`authenticated`. Guarda a fila completa de IDs, posição, dificuldade, categoria, duração, pistas reveladas, deadline e estado de bloqueio/conclusão.
- Criada a RPC `atina_start_room_challenges(p_room_id,p_token,p_difficulty,p_duration_seconds,p_category)`. Só o anfitrião autenticado pelo token da sala pode inicializar os desafios; os parâmetros são validados e a fila é escolhida aleatoriamente pelo servidor a partir de `private.atina_challenges`.
- O deadline é calculado com `clock_timestamp()` no servidor. Duração 0 representa tempo ilimitado.
- O estado público inicial inclui apenas o ID e os metadados do desafio atual, a primeira pista, a duração, o deadline e o tamanho da fila. Não inclui a fila completa, `answer` nem `accepted_answers`.
- Testes pgTAP cobrem inicialização por anfitrião, seleção da fila, estado público sem fila/segredos, primeira pista, deadline do servidor, armazenamento privado e rejeição de convidado/dificuldade inválida. A última asserção terminou com `ok 10`.
- Verificação de privilégios confirmou que `anon` e `authenticated` não têm SELECT na tabela privada e que `anon` não tem USAGE no schema `private`.

**Limites desta etapa:** o frontend continua inalterado e ainda não chama esta RPC; a antiga função `atina_start_room` continua a iniciar apenas o lobby em modo `pending`. Ainda faltam RPCs de revelar pista, submeter texto e validar resposta, passar desafio, avançar a fila e finalizar resultados. Não considerar o modo multiplayer pronto nem compatível com cliente até essas transições estarem implementadas e o frontend ser migrado para o contrato seguro.

**Advisor após 009:** o Advisor reporta nove tabelas com RLS sem policies (INFO), incluindo a nova tabela privada; os privilégios diretos permanecem revogados. Reporta 14 funções SECURITY DEFINER executáveis por `anon` e por `authenticated` (WARN), incluindo a nova RPC. A autenticação por token bearer é deliberada nesta fase, mas rate limiting e mitigação de abuso continuam obrigatórios antes de produção. Os dois avisos de índices não utilizados permanecem os mesmos; nenhum novo aviso de performance foi introduzido.


## Incremento 010–012 — validação multiplayer e revelação de pistas

Aplicado apenas em `atina-development`:

- `010_multiplayer_answer_and_clues`: cria o helper interno `private.atina_room_public_state(uuid)`, que projeta o desafio atual com apenas as pistas já reveladas e sem resposta/fila. Cria `atina_reveal_room_clue(p_room_id,p_token)`, exclusiva do anfitrião, e `atina_submit_room_answer(p_room_id,p_token,p_answer)`.
- A submissão recebe exclusivamente texto (máximo 300 caracteres). O servidor valida contra `private.atina_challenges` através de `private.atina_challenge_answer_matches`; nunca aceita `p_correct) ou `p_points` do cliente. O servidor calcula pontos conforme o número de pistas reveladas e bónus de rapidez, e aplica penalização de 10 pontos por resposta errada, sem permitir score negativo.
- Cada jogador só pode pontuar uma vez por desafio. Tentativas erradas podem ser repetidas, mantendo a regra observada no cliente; tentativas corretas repetidas devolvem `already_correct` sem atribuir pontos novamente.
- O cálculo de rapidez replica o arredondamento do cliente original (`ceil` dos segundos restantes antes de dividir por 10), corrigido em `011_multiplayer_speed_bonus_rounding`.
- Jogadores atribuídos a uma equipa são bloqueados na RPC individual, até existir o fluxo seguro de propostas e votação. Esta barreira foi aplicada em `012_block_team_individual_submission`, para impedir que jogadores de equipa contornem o mecanismo de consenso.
- A tabela privada mantém RLS e privilégios diretos revogados. Verificação confirmou: `anon` e `authenticated` não conseguem SELECT na tabela privada; `anon` não pode executar o helper privado; as RPCs públicas de submissão e revelação são executáveis com token bearer.
- Testes pgTAP: 14 asserções passaram, incluindo estado público sem resposta, uma pista inicial, revelação exclusiva do anfitrião, resposta errada e penalização, resposta correta e pontos calculados pelo servidor, bloqueio de pontuação duplicada e bloqueio de submissão individual por jogador de equipa.

**Limites:** ainda não há RPC segura de avanço da fila nem finalização de resultados. A expiração é verificada durante submissão e revelação; falta sincronizar a transição de timeout no polling de estado. Propostas/votos de equipa e Mímicas continuam por implementar de forma segura. O frontend não foi alterado e ainda usa os RPCs/protocolo antigos; esta implementação backend ainda não é integrada nem utilizável na interface atual.

**Advisor:** permanecem 16 avisos por grupo (`anon` e `authenticated`) de SECURITY DEFINER executáveis, com autenticação bearer por token aleatório. Rate limiting, proteção contra tentativas automatizadas e testes de concorrência continuam obrigatórios antes de produção. Não foi criado qualquer acesso direto às tabelas privadas.


## Incremento 013 — passar, avançar e concluir a partida multiplayer

Aplicado apenas em `atina-development`:

- `atina_pass_room_challenge(p_room_id,p_token)`: só o anfitrião pode passar; fecha a ronda e revela a solução apenas depois de a ronda estar bloqueada. Se o deadline já expirou, identifica o resultado como timeout.
- `atina_next_room_challenge(p_room_id,p_token)`: só o anfitrião pode avançar. O servidor incrementa a posição da fila privada, repõe a primeira pista e cria o deadline seguinte; o cliente não escolhe o próximo desafio nem publica estado.
- Ao terminar a fila, a função marca a sessão e a sala como concluídas e preenche `public.atina_room_results` com os resultados calculados a partir das pontuações guardadas nos participantes.
- O helper de estado público só inclui a solução quando `round_locked=true`; durante uma ronda ativa não a expõe.
- Testes pgTAP: 10 asserções passaram, incluindo solução apenas após bloqueio, avanço de posição, primeira pista do novo desafio, rejeição de avanço por convidado e persistência de resultados finais para todos os participantes.

**Limites:** o anfitrião ainda pode avançar uma ronda ativa sem a passar; não há penalização automática por skip. O estado de timeout é aplicado quando uma RPC de ronda é chamada; ainda falta reconciliar deadlines no polling de estado. O fluxo seguro de propostas/votos de equipa e Mímicas não está concluído. O frontend continua sem integração e não foi alterado.


## Incremento 014 — reconciliação de deadlines no polling

Aplicado apenas em `atina-development`:

- A RPC `atina_room_state` passou a bloquear as linhas relevantes antes de consultar o relógio do servidor.
- Se a ronda estiver ativa e o deadline tiver expirado, a própria leitura do estado fecha a ronda na tabela privada, gera estado público com solução revelada apenas após o bloqueio e incrementa a versão do estado da sala.
- O cliente já não precisa de publicar um estado de timeout; a leitura periódica torna-se suficiente para reconciliar o prazo no servidor.
- Testes pgTAP: 7 asserções passaram, incluindo expiração forçada, bloqueio privado, revelação da solução após timeout, persistência do status da sala e rejeição de token inválido.

A transição de timeout não aplica penalização de pontos no modo multiplayer atual, alinhada com a lógica observada no relógio multiplayer existente. A conclusão da sala continua a ser feita pela RPC de avanço quando o anfitrião fecha a última ronda.


## Incremento 015 — propostas e votação de equipas com validação autoritativa

Aplicado apenas em `atina-development`:

- `atina_submit_team_proposal` recebe texto da resposta, sala, token e índice de desafio. Para compatibilidade transitória com o cliente antigo, ainda aceita `p_correct` e `p_points`, mas **ignora integralmente ambos**; a verdade e a pontuação são sempre calculadas no servidor.
- A proposta só pode ser criada por participante de uma equipa, para a posição atual da fila privada e enquanto o deadline estiver válido. Só pode existir uma proposta pendente por equipa/desafio. Equipas com menos de dois membros não podem iniciar votação.
- `atina_vote_team_proposal` só aceita votos de membros da equipa, exclui o proponente e impede voto repetido pela chave primária do ledger. Um voto negativo rejeita a proposta por desacordo; não penaliza a equipa.
- Quando todos os restantes membros votam a favor, o servidor valida o texto contra a resposta e respostas aceites privadas. Se estiver correto, calcula base e bónus de rapidez e atribui os mesmos pontos a cada membro da equipa. Se estiver incorreto, rejeita a proposta e aplica a penalização de 10 pontos a cada membro.
- Cada resolução fica registada em `atina_room_team_proposals.resolution_reason`; as tentativas também são escritas no ledger `atina_room_answers`, uma linha por membro, permitindo bloquear pontuação duplicada e auditar o resultado.
- Testes pgTAP: 13 asserções passaram, incluindo tentativa de falsificar `p_correct=true` e `p_points=9999`, voto de outra equipa, voto do proponente, rejeição de resposta errada após unanimidade, penalização por membro, aceitação de resposta correta, cálculo independente de pontos e ledger individual por membro.

**Limites:** a interface atual ainda envia os campos antigos de correção/pontos, que o servidor ignora corretamente; deverá ser simplificada quando o frontend for integrado. A visualização da proposta continua limitada à equipa via `atina_room_state`. Ainda faltam regras completas de timeout/pausa para orçamentos de equipa, e Mímicas continuam por implementar de forma segura.
