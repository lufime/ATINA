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
