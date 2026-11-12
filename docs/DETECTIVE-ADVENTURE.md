# ATINA — Aventura Detetive (sem IA paga)

## Objetivo

Acrescentar à modalidade Detetive uma aventura narrativa e explorável, mantendo intactos os 50 desafios Detetive existentes. A nova experiência é original e integrada no ATINA; não reproduz personagens, cenários, nomes ou textos de jogos comerciais.

## Regras confirmadas

- Até 8 participantes humanos por partida.
- Existe exatamente um detetive humano por partida.
- Os restantes papéis são personagens do caso; uma dessas personagens é secretamente culpada.
- O adjunto é sempre a lógica automática do ATINA e não ocupa um lugar de jogador.
- Em single-player, a pessoa é sempre o detetive e todas as personagens são controladas pelo jogo.
- Em multiplayer, os lugares disponíveis podem ser preenchidos por personagens automáticas até ao limite de 8 participantes humanos.
- A escolha do detetive pode ser manual ou por sorteio.
- O detetive pode deslocar-se pelo cenário 2D, entrar em divisões, examinar objetos, recolher provas e interrogar personagens.
- A investigação inclui inventário, quadro de pistas, testemunhos, álibis, contradições e acusação final.
- O adjunto só analisa informação que já tenha sido legitimamente revelada ao detetive. Não identifica automaticamente o culpado nem revela segredos por descobrir.

## Inteligência sem serviços pagos

Não usar OpenAI API, modelos externos, serviços de geração de texto, chaves de API ou chamadas a fornecedores de IA.

A inteligência é implementada com lógica determinística e conteúdo original:
- árvores de diálogo e respostas condicionadas por pistas, local, hora e perguntas já feitas;
- perfis de personagem com objetivos, temperamento, conhecimento, relações e limites do que podem revelar;
- regras de mentira/omissão específicas para o culpado e segredos pessoais não criminosos para inocentes;
- memória de interrogatórios e reações a provas já apresentadas;
- álibis e cronologias com verificações de consistência;
- adjunto baseado em regras que organiza factos conhecidos, aponta incompatibilidades e sugere linhas de investigação sem extrapolar para informação secreta.

A aleatoriedade deve ser semeada por partida para que as decisões possam ser reproduzidas em testes. A lógica não deve depender de chamadas de rede a serviços externos.

## Arquitetura proposta

### Cliente ATINA

- Interface e identidade visual atuais.
- Mapa 2D com movimento por teclado/toque e pontos interativos.
- Diálogos, inventário, quadro de provas, cronologia e painel do adjunto.
- O cliente recebe apenas a projeção pública e os elementos privados autorizados ao detetive.

### Supabase

- Reutilizar o mecanismo de salas/token do ATINA como base de lobby, sem reutilizar o estado genérico atual como fonte de segredos.
- Criar estado privado próprio da aventura, em schema privado, com RLS ativo e sem acesso direto por anon/authenticated.
- Guardar culpado, papéis, segredos, conhecimento das personagens, provas ainda não descobertas e estado de progressão exclusivamente no servidor.
- Expor operações limitadas por RPCs tokenizadas: criar/iniciar partida, consultar estado autorizado, mover/interagir, interrogar, recolher prova, pedir análise ao adjunto e apresentar acusação.
- Validar no servidor as transições, o acesso a divisões/objetos, os requisitos de pistas e a acusação.
- O estado público nunca inclui a solução, os segredos das personagens ou pistas não descobertas.
- Começar por sincronização através das RPCs/polling já usadas no ATINA; avaliar Realtime apenas se os testes demonstrarem necessidade e se os limites do plano o permitirem.

### Custos e limites

- Sem custos de API de IA: não existe integração com OpenAI ou outro modelo pago.
- O jogo reutiliza o alojamento estático GitHub Pages e o projeto Supabase existente.
- Isto evita novos fornecedores pagos, mas não garante custo operacional total zero: quotas, tráfego, armazenamento e limites do plano Supabase/GitHub continuam aplicáveis.
- Não criar nem aplicar alterações na base de dados de produção sem migration versionada, revisão de segurança e testes.

## Fases de implementação

1. **Fundação segura:** modelo de dados privado, regras de papéis, estado autoritativo e testes que provem que o culpado/segredos não aparecem nas respostas públicas.
2. **Caso-piloto single-player:** um cenário original, mapa 2D, personagens, diálogos, objetos, provas e adjunto determinístico.
3. **Motor de investigação:** cronologia, álibis, contradições, inventário e acusação com regras de vitória.
4. **Multiplayer:** lobby, até 8 humanos, eleição/sorteio do detetive, personagens automáticas para lugares vagos, sincronização e permissões por participante.
5. **Integração ATINA:** entrada na modalidade Detetive sem remover os 50 desafios, interface responsiva e testes funcionais em telemóvel/desktop.

## Critérios de aceitação

- Os 50 desafios atuais continuam disponíveis e sem alterações.
- Não existem chamadas a APIs de IA, chaves externas ou dependências pagas de geração de texto.
- Nunca é possível obter o culpado ou segredos não descobertos através do estado público, do browser ou das RPCs de outro participante.
- O adjunto não usa informação que o detetive ainda não descobriu.
- Single-player inicia sempre com o humano como detetive.
- Nenhuma partida ultrapassa 8 participantes humanos.
- Uma partida termina com vitória do detetive/adjunto se a acusação correta for validada, ou vitória do culpado se a acusação final falhar/escapar segundo as regras do caso.
- As migrations são reproduzidas em ambiente descartável e passam os testes automatizados antes de qualquer publicação.
