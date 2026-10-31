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
