# ATINA — Plano de testes E2E multiplayer e Mímicas

## Objetivo

Validar a experiência integrada no browser, para além dos testes estáticos, pgTAP e do teste de progressão pseudónima já existente. O foco é encontrar falhas de sincronização entre participantes, transições de ronda, reconexão, prazos e Mímicas.

Este documento é um plano de execução. **Não afirma que os cenários abaixo já foram executados.**

## Regras de segurança do ambiente

1. Executar apenas contra uma instância Supabase local descartável ou um projeto de staging dedicado e sem dados reais.
2. Nunca usar as credenciais, URL ou dados do projeto Supabase de produção.
3. Não aplicar migrations, seeds, fixtures ou testes destrutivos em produção.
4. Não guardar tokens de sessão, códigos de sala ou credenciais em logs, screenshots ou artefactos CI.
5. Usar dados sintéticos e limpar a instância descartável no fim.
6. Não fazer merge nem deploy como parte desta bateria.

## Pré-requisito técnico: separar a configuração Supabase

O HTML e o cliente de servidor devem poder receber URL e chave pública Supabase através de configuração de teste/staging, sem substituir valores de produção no código nem expor secrets. A chave anon/public pode ser usada no browser de teste; nunca colocar service-role keys no browser, nos artefactos ou nos logs.

A bateria E2E só deve ser considerada real se os browsers comunicarem com as RPCs e o estado persistido da instância Supabase de teste. Um mock de `supabase-js` é útil para testes de UI isolados, mas não valida concorrência, autorização, Realtime/polling ou transações SQL.

## Matriz E2E prioritária

| ID | Cenário | Execução | Resultado esperado |
|---|---|---|---|
| MP-01 | Criar sala e entrar com segundo participante | Browser A cria sala; browser B entra com o código | Ambos veem a mesma sala e participantes, sem expor tokens |
| MP-02 | Entrada inválida e sala inexistente | B tenta código inválido/expirado | Erro claro; nenhuma sessão ou participante fantasma |
| MP-03 | Início de jogo sincronizado | Anfitrião inicia após os participantes entrarem | Todos recebem o mesmo modo, ronda e estado inicial |
| MP-04 | Respostas concorrentes | Dois browsers submetem quase em simultâneo | Servidor aceita apenas a ação válida segundo as regras; pontuação não duplica |
| MP-05 | Proposta e votação por equipa | Jogadores propõem respostas e votam | Uma proposta/um voto por jogador conforme as regras; resultado final é autoritativo |
| MP-06 | Passar/avançar e fim da ronda | Participantes passam ou avançam em sequência | Uma única transição; sem saltos nem ronda duplicada |
| MP-07 | Prazo expirado | Deixar a ronda expirar com browsers em estados diferentes | Servidor fecha a ronda uma vez e todos convergem para o mesmo estado |
| MP-08 | Desligar anfitrião | Fechar ou desligar o browser A durante a sala | Comportamento documentado e consistente; sem sala presa indefinidamente |
| MP-09 | Reconexão de participante | Desligar B, aguardar, voltar a ligar | B recupera estado autoritativo ou recebe saída/expiração explícita; não duplica ações |
| MP-10 | Duas ações repetidas (retry) | Reenviar a mesma ação após timeout de rede | Operação idempotente ou rejeição segura; pontuação/transição não duplicada |
| MM-01 | Criar ronda de Mímicas | Anfitrião inicia Mímicas | Palavra secreta só é entregue ao participante autorizado; restantes não a recebem |
| MM-02 | Relógio e preparação | Aguardar countdown e fim de tempo | Servidor controla início/fim; atrasar o relógio do browser não prolonga a ronda |
| MM-03 | Avaliação humana | Anfitrião marca acerto/erro | Só a ação autorizada altera o resultado e pontuação |
| MM-04 | Mudar de intérprete | Concluir ronda e avançar | Palavra e permissões mudam para o novo intérprete sem fuga de segredo |
| MM-05 | Reconexão durante Mímicas | Desligar intérprete ou anfitrião e regressar | Estado recuperado segundo a política definida; nenhuma palavra é revelada indevidamente |

## Estratégia de execução

### Fase A — ambiente e instrumentação

- Iniciar Supabase local com a versão de CLI fixada pelo projeto.
- Reproduzir migrations numa base vazia e correr a suite pgTAP existente.
- Iniciar a aplicação com configuração apontada explicitamente para o Supabase local.
- Criar dois ou mais contextos Playwright independentes, cada um com armazenamento, cookies e sessão isolados.
- Registar apenas eventos não sensíveis: ID de cenário, estado, resultado RPC sanitizado e timestamps.
- Capturar screenshots e traces apenas em falhas, removendo códigos de sala, tokens e palavras secretas.

### Fase B — multiplayer

Executar MP-01 a MP-10 em Chromium. Repetir os cenários de concorrência, timeout e retry pelo menos 10 vezes para detetar condições de corrida. Validar o estado final diretamente na base local, além do que é apresentado na UI.

### Fase C — Mímicas

Executar MM-01 a MM-05 com pelo menos três contextos (anfitrião, intérprete e observador). Inspecionar respostas RPC e payloads de rede para confirmar que a palavra secreta nunca chega ao observador.

### Fase D — dispositivos e rede

- Viewports: 320×568, 360×800, 390×844, 768×1024 e 1280×800.
- Orientações: retrato e paisagem em ecrã estreito.
- Simular latência, perda de ligação e restauro da ligação.
- Verificar scroll horizontal, botões fora do ecrã, sobreposição de diálogos, teclado virtual e alvos de toque.
- Confirmar respeito por `prefers-reduced-motion`.

## Critérios de aprovação

- Todos os cenários prioritários passam em ambiente local descartável.
- Nenhuma palavra secreta, resposta correta, token de sessão ou credencial privada aparece em payloads destinados a participantes não autorizados.
- Nenhuma ação repetida gera XP, pontuação, voto ou transição duplicada.
- Todos os participantes convergem para o mesmo estado autoritativo após timeout e reconexão.
- Não existem erros JavaScript não tratados nem falhas de consola nos cenários aprovados.
- Não existe overflow horizontal nos viewports definidos.
- A suite pgTAP continua verde após replay completo das migrations.

## Relatório obrigatório

Para cada execução, guardar: commit SHA, versões Node/Supabase/Playwright, cenário, resultado, duração, browser/viewport, falha sanitizada e link para artefacto CI. Distinguir sempre testes SQL, testes UI com mocks e E2E reais contra Supabase local.

## Limitações conhecidas da bateria atual

O workflow `test-cloud-progression-browser.yml` cobre progressão pseudónima e usa RPCs simuladas. Não cobre salas multiplayer reais. O workflow `replay-supabase-migrations.yml` executa migrations e pgTAP localmente, mas não conduz browsers através dos fluxos multiplayer. Esta bateria deve ligar essas duas camadas sem recorrer a produção.
