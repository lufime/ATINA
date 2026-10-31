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
6. Retirar segredos do bundle público. O modo offline/local exige uma decisão explícita: ou passa a exigir ligação para validar respostas, ou permanece com validação local assumidamente não segura. Não prometer proteção de respostas enquanto o array completo continuar no HTML.
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
