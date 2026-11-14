# Plano de testes — ATINA (oito jogos)

## Âmbito

O conjunto ATINA inclui oito jogos/experiências:
- Três existentes: jogo principal ATINA (modalidades atuais), Mímicas e Aventura Detetive — O Último Farol.
- Cinco novos jogos sociais: Quanto Achas?, Associação de Palavras, Isto ou Aquilo, Mistério Impossível e Palavra Proibida.

Os testes desta página incidem prioritariamente nos cinco novos jogos. Os três motores existentes são testes de regressão obrigatórios e não devem ser substituídos nem alterados por esta implementação.

## Decisões de segurança

- Não executar partidas de teste contra o Supabase de produção.
- Não ativar os cinco jogos novos no catálogo Supabase de produção.
- Não alterar a branch `main` nem a publicação atual do ATINA.
- Todo o trabalho decorre na branch GitHub `atina-social-games-beta`.
- Não usar contas, tokens ou dados pessoais reais nos testes.
- Não criar recursos pagos nem ativar serviços pagos sem autorização explícita.

## Ambiente isolado

Foi criado o projeto Supabase de testes `atina-social-games-test` (`wmparhejigqjoqgsxrtp`), na região `eu-west-1`. À data da inspeção, o projeto estava ativo e vazio: sem migrações, tabelas, funções ou dados adicionados. O custo/plano foi consultado no momento da criação e indicado como 0 USD/mês; os limites e condições do fornecedor podem mudar.

A página `jogos-sociais.html` não contém URL nem chave do Supabase de produção. Sem credenciais de teste configuradas, não cria cliente Supabase nem executa RPCs. A demonstração `jogos-sociais-demo-local.html` usa dados fictícios e não liga ao Supabase.

## Cenários de teste dos cinco jogos novos

1. Abrir a demonstração sem sessão ATINA e sem ligação ao Supabase.
2. Confirmar apresentação dos cinco jogos e respetivas instruções.
3. Testar seleção de modo individual e por equipas.
4. Testar seleção do número de rondas e dificuldade.
5. Testar distribuição automática de jogadores por 2–6 equipas.
6. Testar atribuição manual de jogadores às equipas.
7. Simular submissões e feedback em cada um dos cinco jogos.
8. Simular temporizadores, transição entre rondas e fim de partida.
9. Confirmar classificação individual e por equipa com dados fictícios.
10. Recarregar a demonstração e confirmar que não há dependência de dados de produção.
11. Validar o catálogo conjunto de exatamente 2.150 conteúdos, com dificuldade e integridade.

## Regressão dos três jogos existentes

1. Jogo principal ATINA: validar que os modos e modalidades atuais continuam a usar o motor, sessões, pontuação e ranking existentes.
2. Mímicas: validar sala, representante por ronda, segredo privado, relógio e validação humana.
3. Aventura Detetive: validar papéis, culpado, provas privadas, interrogatórios, adjunto e acusação.
4. Confirmar que os estados privados dos três jogos não são expostos pelas novas RPCs sociais.
5. Confirmar que nenhuma migration dos cinco jogos sociais altera ou elimina tabelas, funções ou conteúdos dos três motores existentes.

## Testes de integração futuros (não executados)

Depois de construir e rever a fundação social no projeto isolado:

1. Anfitrião cria uma sala e convidado entra com o código.
2. Confirmar presença dos jogadores e estado da sala.
3. Testar atribuição manual e automática de equipas, incluindo número ímpar de participantes.
4. Iniciar cada jogo social em modo individual e em modo equipas.
5. Confirmar submissões, sincronização, temporizadores e transições.
6. Confirmar pontuação, classificação final e encerramento.
7. Repetir com recarregamento e reconexão.
8. Executar testes de permissões, estados inválidos, duplicados, concorrência e rollback.
9. Executar regressão dos três jogos existentes.

## Estado

- [x] Código beta presente na branch.
- [x] Ligação da página online ao Supabase de produção removida.
- [x] Modo de demonstração local sem chamadas a Supabase implementado.
- [x] Projeto Supabase de testes isolado criado e verificado vazio.
- [x] Âmbito corrigido para oito jogos (três existentes + cinco novos).
- [ ] Teste visual em navegador e interação manual.
- [ ] Esquema e contratos RPC dos cinco jogos novos revistos.
- [ ] Migrações e RPCs aplicadas apenas no ambiente de testes.
- [ ] Testes reais de dois dispositivos num backend isolado.
- [ ] Regressão funcional dos três jogos existentes após integração.

**Não declarar os jogos testados ou aprovados até os cenários relevantes serem efetivamente executados.**

## Validação técnica efetuada anteriormente

- JavaScript embutido compilado sem erros de sintaxe.
- Demonstração offline verificada sem chamadas RPC, Supabase ou pedidos de rede.
- Confirmada a presença dos cinco jogos, opções de equipas e aviso de dados fictícios.
- A validação foi estática; não foi executado um navegador nem um teste real em dois dispositivos.

## Proteção da versão online (2026-11-13)

A página `jogos-sociais.html` não contém a URL nem a chave publicável do Supabase de produção. O cliente Supabase só é criado quando forem configuradas credenciais do ambiente de testes isolado. Sem essas credenciais, a página apresenta uma mensagem de preparação e não executa RPCs. Esta salvaguarda não transforma a versão online numa partida funcional.
