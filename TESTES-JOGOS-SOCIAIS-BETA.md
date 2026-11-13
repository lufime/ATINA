# Plano de testes — Jogos Sociais ATINA (beta)

## Decisão de custo e segurança

- A opção de criar uma branch Supabase foi recusada por implicar custo horário.
- Não criar projetos ou branches Supabase pagos.
- Não executar partidas de teste contra o Supabase de produção.
- Não ativar os cinco jogos no catálogo Supabase de produção.
- Não alterar a branch `main` nem a publicação atual do ATINA.
- Todo o trabalho gratuito decorre na branch GitHub `atina-social-games-beta`.

## Limitação técnica atual

A página `jogos-sociais.html` utiliza RPCs Supabase e a sessão de uma sala existente. A função `public.atina_social_game_start_room` exige que o jogo esteja ativo no catálogo. Os cinco jogos continuam inativos em produção.

Por isso, abrir a página beta tal como está não constitui um teste isolado: a configuração atual aponta para o Supabase de produção. Não usar essa página para iniciar partidas, nem introduzir contas, tokens ou dados reais durante os testes.

Sem um backend de teste gratuito, não é possível validar com segurança partidas online reais em dois dispositivos. O trabalho gratuito pode avançar com revisão estática do código, validação de sintaxe, documentação dos cenários e preparação de um modo de demonstração local com dados fictícios, sem chamadas ao Supabase.

## Cenários de teste a validar no modo local/demonstração

1. Abrir a demonstração sem sessão ATINA e sem ligação ao Supabase.
2. Confirmar apresentação dos cinco jogos e respetivas instruções.
3. Testar seleção de modo individual e por equipas.
4. Testar seleção do número de rondas e dificuldade, quando disponível.
5. Testar distribuição automática de jogadores por 2–6 equipas.
6. Testar atribuição manual de jogadores às equipas.
7. Simular submissões e feedback em cada um dos cinco jogos.
8. Simular temporizadores, transição entre rondas e fim de partida.
9. Confirmar classificação individual e por equipa com dados fictícios.
10. Recarregar a demonstração e confirmar que não há dependência de dados de produção.

## Testes de integração futuros (não executados)

Quando existir um backend de teste gratuito e isolado, repetir em dois dispositivos:

1. Anfitrião cria uma sala e convidado entra com o código.
2. Confirmar presença dos dois jogadores e estado da sala.
3. Testar atribuição manual e automática de equipas.
4. Iniciar cada jogo em modo individual e em modo equipas.
5. Confirmar submissões, sincronização, temporizadores e transições.
6. Confirmar pontuação, classificação final e encerramento.
7. Repetir com recarregamento e reconexão.

## Estado

- [x] Código beta presente na branch.
- [x] Funções RPC de jogo instaladas no Supabase de produção.
- [x] Bloqueio de ativação em produção identificado.
- [x] Decisão de não incorrer em custos registada.
- [x] Modo de demonstração local sem chamadas a Supabase implementado.
- [x] JavaScript da demonstração validado sintaticamente; HTML sem dependências externas.
- [ ] Teste visual em navegador e interação manual ainda por executar.
- [ ] Testes reais de dois dispositivos num backend isolado executados.

**Não declarar os jogos testados ou aprovados até os cenários relevantes serem efetivamente executados.**


## Validação técnica efetuada

- JavaScript embutido compilado sem erros de sintaxe.
- Ficheiro verificado sem scripts ou folhas de estilo externos.
- Verificado que o JavaScript não contém chamadas RPC, Supabase ou pedidos de rede.
- Confirmada a presença dos cinco jogos, opções de equipas e aviso de dados fictícios.
- A validação foi estática; não foi executado um navegador nem um teste real em dois dispositivos.
