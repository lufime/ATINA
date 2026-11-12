# Estado da implementação — Aventura Detetive

Atualizado em 12-11-2026.

## Implementado no branch `feature/detetive-aventura-sem-ia-paga`

- Migration aditiva com seis tabelas privadas de casos, sessões, personagens, provas, descobertas e interações.
- RLS ativo e sem privilégios diretos para `anon`/`authenticated` nessas tabelas.
- Caso-piloto original **O Último Farol**, com quatro locais, sete suspeitos, um culpado e quatro provas.
- RPCs tokenizadas:
  - `atina_detective_start`: arranque por anfitrião, detetive manual/aleatório, máximo de oito humanos, papéis atribuídos aleatoriamente e lugares de personagens preenchidos por IA local determinística do jogo.
  - `atina_detective_state`: estado filtrado por participante; provas descobertas apenas são devolvidas ao detetive.
  - `atina_detective_move`: valida deslocação para uma localização existente.
  - `atina_detective_discover`: só o detetive pode recolher uma prova e apenas quando está na localização correspondente; valida pré-requisitos configurados.
- O estado público não devolve a solução nem o estado privado das personagens.

## Verificações executadas

Testes SQL transacionais com rollback:
- Arranque de partida e leitura do estado.
- Partida com oito participantes humanos: oito personagens (detetive + sete suspeitos), exatamente um culpado.
- Movimento do detetive entre locais.
- Descoberta de uma prova no local correto.
- Verificação de que outro participante não recebe a lista de provas do detetive.
- Verificação de que a solução não aparece no estado devolvido.
- Os dados temporários de teste foram revertidos; não ficaram sessões de teste na base de dados.

## Ainda não implementado

- Interface 2D integrada no `index.html` do ATINA.
- Movimento gráfico, hotspots clicáveis e animações.
- Interrogatórios ligados ao motor determinístico JavaScript.
- Quadro de pistas, adjunto, cronologia e acusações.
- Fluxo de lobby/convites dedicado e sincronização visual em tempo real.
- Testes automatizados do módulo JavaScript executados num runtime Node.
- Deploy para GitHub Pages.

## Custos

Não existe integração com OpenAI ou outro serviço de IA. As respostas das personagens serão geradas pelo motor determinístico local do ATINA. O Supabase e o alojamento continuam sujeitos às quotas/limites dos planos existentes.


## Atualização — interface inicial e investigação (12-11-2026)

### Novos componentes implementados no branch

- Entrada própria «Jogar a aventura O Último Farol» dentro do separador Modalidades, sem substituir o botão/categoria Detetive existente.
- Interface de configuração para iniciar sozinho, criar sala ou entrar por código.
- Fluxo de lobby com até oito lugares humanos, partilha de código e atualização periódica.
- Ecrã da aventura com mapa de quatro locais, deslocação validada pelo servidor, objetos examináveis, quadro de provas, interrogatório por suspeito/tema, adjunto e acusação final.
- O jogador recebe apenas o papel que lhe foi atribuído; o detetive não recebe o papel secreto dos restantes participantes.
- O adjunto é consultado no servidor e recebe exclusivamente provas descobertas pelo detetive.
- As operações de diálogo, adjunto e acusação são RPCs tokenizadas e executadas no servidor.

### RPCs adicionais

- `atina_detective_interrogate`
- `atina_detective_adjunct`
- `atina_detective_accuse`

### Testes SQL executados com rollback

- Resposta determinística do culpado a uma pergunta sobre localização.
- Rejeição de apresentação de prova não descoberta.
- Adjunto com apenas a prova legitimamente recolhida.
- Acusação correta, validada pelo servidor, com revelação da solução apenas no fim.
- Testes executados em transação revertida; não ficaram sessões de QA na base de dados.

### Limitações ainda existentes

- A interface foi adicionada ao `index.html` na branch de desenvolvimento, mas ainda não foi testada visualmente num browser/telemóvel.
- No modo multijogador, os participantes recebem papel privado; a comunicação/roleplay entre jogadores ainda não tem chat dedicado.
- Não há animação livre de personagem no mapa: a navegação é por seleção de divisões.
- As respostas dos NPCs são determinísticas e ainda têm um conjunto inicial limitado de falas.
- O adjunto apresenta provas e perguntas sugeridas; a análise avançada de cronologias/contradições entre testemunhos está por desenvolver.
- Não foi feito deploy nem merge para a branch principal.


## Atualização — compatibilidade V2 e papéis humanos (12-11-2026)

### Compatibilidade com salas ATINA V2

A primeira revisão da integração revelou que a UI usava as salas V2, mas as RPCs do Detetive estavam ligadas às tabelas de salas antigas. Corrigido:

- As seis referências de chaves estrangeiras do motor Detetive foram alinhadas com `atina_v2_rooms` e `atina_v2_room_players`.
- As sete RPCs centrais foram atualizadas para autenticar tokens e consultar participantes V2.
- A criação e entrada na sala continuam a usar as funções V2 com sessão da conta ATINA.
- A correção foi aplicada no projeto `atina-development`.

### Papéis humanos e interrogatórios

- O anfitrião pode escolher o detetive manualmente ou sortear.
- Um participante humano que seja suspeito recebe apenas a sua própria personagem, papel e instruções privadas.
- Quando o detetive interroga um participante humano, a pergunta fica pendente para esse jogador.
- O participante responde no seu próprio ecrã; a resposta fica disponível ao detetive.
- As falas privadas de outros participantes e os segredos do caso não são devolvidos a quem não os pode conhecer.

### Testes de integração SQL executados com rollback

- Sala V2 individual: 1 humano + 7 personagens automáticas.
- Sala V2 com 2 humanos: atribuição de detetive e papel privado.
- Sala V2 com 8 humanos: 8 personagens humanas, zero NPCs de preenchimento e exatamente um culpado.
- Movimento, recolha de prova, interrogatório automático, análise do adjunto e acusação correta.
- Pergunta a personagem humana, visibilidade apenas ao jogador interrogado e envio de resposta ao detetive.
- Tentativa de acesso ao adjunto por não-detetive bloqueada.
- Todas as sessões de QA foram revertidas; não ficaram salas nem partidas de teste na base de dados.

### Estado e limitações

- O backend V2 foi exercitado por SQL com as mesmas RPCs que a interface invoca.
- Ainda não foi possível executar um teste visual real no browser/telemóvel nesta sessão.
- Não foi feito deploy nem merge para a branch principal.
- A interface ainda usa navegação por seleção de divisões, não deslocação livre animada.
- Não existe chat geral; a comunicação atual é através de perguntas/respostas de interrogatório.


## Atualização — teste de fluxo e proteção do adjunto (12-11-2026)

- O modo individual cria uma sala V2 local sem exigir sessão de conta; continua a usar o detetive humano e sete personagens automáticas.
- O modo multijogador mantém autenticação por conta ATINA.
- A seleção manual do detetive foi ligada à lista de participantes da sala; o sorteio continua disponível.
- Os participantes humanos recebem uma pergunta no seu próprio ecrã e podem responder como a personagem. A resposta aparece no registo privado do detetive.
- O estado de cada jogador inclui apenas a sua própria personagem e papel. A lista pública de personagens não contém os papéis secretos.
- O adjunto foi endurecido: uma referência a uma pista ainda não descoberta já não aparece como contradição.
- Foram adicionados índices para as relações de evidências e diálogos.

### Última verificação de backend

Teste SQL integrado, com rollback, executado após estas alterações:
- Criação de sala V2 individual sem sessão de conta.
- Atribuição de 7 NPCs e 1 detetive humano.
- Descoberta de prova e análise sem fuga de referências a pistas ocultas.
- Seleção manual do detetive em sala com dois humanos.
- Interrogatório pendente para personagem humana e resposta enviada pelo jogador.
- Confirmação de que o detetive recebe a resposta e que o jogador interrogado só vê a sua pergunta.

O teste de 8 participantes humanos foi executado separadamente: 8 personagens humanas, sem NPCs de preenchimento e um único culpado.

**Ainda falta:** validação visual/funcional num navegador real. O site público e a branch principal não foram alterados nem publicados.


### Fecho de partida e resultado comum (12-11-2026)

- Quando o detetive acusa, todos os participantes recebem o vencedor e o nome da pessoa acusada.
- A solução detalhada (método e motivo) continua reservada ao detetive no fim da partida.
- Os jogadores que ainda estavam no lobby passam para o ecrã de jogo quando a sala inicia e recebem o estado final quando a partida termina.
- Teste SQL com rollback confirmou que um jogador não-detetive vê o resultado final, mas não recebe o método nem o motivo do crime.
