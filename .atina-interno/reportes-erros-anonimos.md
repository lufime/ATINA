# Reportes anónimos de erros — proposta de implementação

## Objetivo
Permitir que qualquer jogador reporte um erro durante ou depois do jogo, sem interromper a partida e sem recolher dados pessoais.

## Privacidade obrigatória
- O reporte inclui o pseudónimo atual do jogador, preenchido automaticamente pelo jogo, para a administração identificar quem reportou.
- Não recolher email, IP, nome real/conta, ID de jogador, identificadores persistentes, fingerprint ou tokens da partida.
- Não guardar user-agent completo nem headers da requisição.
- Não ligar o reporte à partida, sala, sessão, desafio ou IDs do jogador; guardar apenas o pseudónimo apresentado.
- A screenshot é opcional e deve mostrar aviso para ocultar informação pessoal antes do envio.
- Remover metadados EXIF da screenshot no cliente antes de upload; limitar tipo e tamanho.
- Guardar categoria, descrição, pseudónimo, versão pública do jogo, área/modo selecionado opcional, timestamp de servidor e screenshot opcional.
- Evitar registo de IP nos logs de aplicação; confirmar limites e retenção dos logs da plataforma antes de ativar.
- Não enviar email.

## Categorias
- Visual
- Jogo
- Pontuação/XP
- Técnico
- Outro

## Fluxo do jogador
1. Acesso a “Reportar erro” no menu/rodapé e nos ecrãs relevantes, sem bloquear a partida.
2. O pseudónimo é obtido automaticamente do perfil atual e apresentado no formulário como referência (não editável), sem recolher outros dados de conta.
3. Categoria obrigatória, descrição obrigatória e screenshot opcional.
4. Aviso visível: não incluir emails, dados pessoais ou informação sensível na screenshot/descrição.
5. Envio com estado e confirmação; se falhar, manter descrição no formulário para nova tentativa.
6. Limitação de spam não baseada em identificador persistente: limite global por janela temporal e throttle apenas em memória no browser.

## Administração (integrada em admin-images.html)
- Secção protegida de reportes, sem página Admin nova.
- Contador de reportes por estado e destaque de novos.
- Lista com pseudónimo do jogador, categoria, data, versão, área, descrição e screenshot.
- Filtro e pesquisa por pseudónimo.
- Estados: Novo, Em análise, Em correção, Resolvido, Arquivado.
- Agrupar reportes semelhantes por fingerprint calculado apenas a partir de categoria + texto normalizado; o fingerprint não é um identificador de pessoa.
- Ações para mudar estado e adicionar nota interna (nota administrativa não enviada aos jogadores).
- Atualização em tempo real ou refresh controlado.

## Dados e segurança — desenho proposto
Tabela separada de reportes, RLS ativada.
- Inserção anónima limitada a campos permitidos, validação de comprimento/categoria e proteção contra spam.
- Leitura/alteração apenas por administradores autorizados.
- Não permitir acesso público a reportes ou screenshots.
- Screenshots armazenadas em bucket privado, com validação de MIME/tamanho e URLs assinadas de curta duração.
- Admin Push opt-in, com subscrição separada dos reportes; não associar subscrição a jogadores nem incluir dados do reporte na notificação push.
- A autorização administrativa tem de reutilizar uma regra de admin server-side verificada; não assumir que qualquer sessão autenticada é administradora.

## Estados
Novo → Em análise → Em correção → Resolvido → Arquivado.

## Dependências antes de ativar
- Verificar o mecanismo atual de autorização Admin server-side, porque a página existente autentica via Supabase mas a autorização não deve ser inferida apenas de uma sessão.
- Rever os logs/retention do Supabase para confirmar que não são guardados IPs/identificadores por este fluxo.
- Criar migration, funções server-side e testes automatizados de RLS/rate limit.
- Testar fluxo em browser, mobile e desktop.
- Não aplicar migration nem deploy diretamente ao projeto Supabase de produção.

## Critérios de aceitação
- Reporte anónimo, sem identificadores pessoais ou de partida.
- Reporte opcional de screenshot, com remoção de EXIF e aviso de privacidade.
- O envio não pausa nem altera jogo, pontuação, XP ou progresso.
- Reportes visíveis apenas na Administração existente e por admins autorizados.
- Agrupamento e estados funcionam.
- Falhas de envio não apagam o texto preenchido.
- Sem email, sem Render, sem deploy de produção durante esta fase.


## Auditoria técnica (2026-11-21)
- A página `admin-images.html` confirma a sessão Supabase no cliente, mas uma sessão autenticada não é prova de autorização administrativa.
- O endpoint de gestão chamado pela página (`atina-image-manage`) não tem implementação disponível no código versionado inspecionado; por isso não foi possível validar a autorização server-side nem reutilizar com segurança a sua lógica.
- **Bloqueio de implementação:** não criar acesso administrativo com base em verificações de cliente, sessão genérica, user metadata ou email não verificado. A leitura/alteração de reportes só pode ser ligada depois de existir uma função server-side com autorização administrativa comprovável.
- A implementação de submissão também depende do esquema persistente (tabela e armazenamento privado) e das políticas de acesso. Não criar um formulário que simule sucesso ou perca reportes sem persistência.
- Próximos passos seguros: identificar ou implementar um mecanismo server-side de admin com política comprovada; preparar tabela/RLS e armazenamento privado; Edge Function de submissão com validação e limitação de abuso; integração UI do jogador e secção admin; testes automatizados de autorização, validação, privacidade e fluxo de falhas.
- Esta auditoria é apenas no repositório/PR. Nenhuma migration foi aplicada, nenhuma alteração de Supabase produção, deploy, merge ou uso de Render.


## Segunda verificação de permissões
- Revistos os SQL de contas de jogador, notificações e subscrições Push e as Edge Functions versionadas. Estes mecanismos autenticam/identificam jogadores ou protegem operações específicas, mas não fornecem uma autorização de administrador verificável reutilizável para reportes.
- A administração chama `atina-image-manage` com JWT de sessão; o código da Edge Function não está no repositório versionado consultado, pelo que a autorização desse endpoint não pode ser auditada.
- Não reutilizar tokens de jogador, sessão normal, email, user metadata ou simples estado de login para dar acesso aos reportes.
- Recomendação para desbloquear: estabelecer uma autorização administrativa explícita validada no servidor (por exemplo, claim/role de admin em JWT assinado e emitido pelo sistema de autenticação, com origem e processo de atribuição auditáveis; nunca user_metadata editável pelo utilizador), e exigir essa autorização em cada operação de leitura/alteração. Só depois ligar a UI admin.
- A autorização e o endpoint de gestão não podem ser testados funcionalmente até existir implementação acessível e ambiente de testes. Nenhuma mudança de backend ou banco foi aplicada.


## Alternativa de autorização investigada — allowlist server-side
A alternativa mais simples de auditar, sem depender de claims que possam demorar a refletir-se nos tokens, é uma allowlist privada de utilizadores administradores autenticados:
- Guardar apenas os UUIDs Auth dos administradores numa tabela do schema privado, sem acesso direto pela API pública. A tabela não contém dados dos reportes nem do jogador.
- A atribuição/removal de admin é feita apenas por operação privilegiada de confiança (migration reviewed ou ferramenta administrativa server-side), nunca por frontend, RPC pública, user_metadata ou auto-registo.
- Criar uma função de verificação SECURITY DEFINER de leitura, com search_path fixo, que verifica auth.uid() contra a allowlist. Não devolver a lista de administradores ao cliente.
- Reforçar com RLS: SELECT e UPDATE dos reportes exigem a função de verificação; os jogadores não têm SELECT/UPDATE/DELETE. INSERT público deve passar por RPC/Edge Function de submissão com campos allowlisted, validação e throttling; não conceder acesso de leitura ao storage.
- Para screenshots, bucket privado, validação do conteúdo/tamanho, remoção EXIF, e URLs assinadas curtas geradas apenas depois de verificação admin.
- Testes obrigatórios: utilizador anónimo, jogador autenticado normal, administrador autorizado e admin removido (token antigo também não deve manter acesso); validar leitura, atualização de estado, notas e acesso ao screenshot. O check admin deve ser reavaliado no servidor em cada chamada.
- Esta abordagem é apenas proposta de arquitetura. Não foi criada tabela, função, política, secret, nem aplicada/testada em Supabase. Antes de implementação, confirmar se o mecanismo existente de admin pode ser reutilizado; se não, obter autorização explícita para estabelecer a allowlist.

## Investigação adicional (2026-11-21)
- Reconsultada a árvore completa do branch do PR: só está versionada a função atina-update-solution-tags; a função atina-image-manage continua ausente.
- Pesquisas no código do repositório por admin role, admin-images admin e is_admin não devolveram resultados indexados. Estas pesquisas não são prova absoluta de inexistência, mas reforçam que não há autorização admin documentada/reutilizável no branch.
- Consultado também SECURITY-DESIGN.md: descreve RLS, RPCs, tokens de sessão e exclusão do perfil Admin de certas aprendizagens, mas não define um sistema de autorização administrativa por papel/identidade. O próprio documento alerta que a exclusão por nome apresentado não é autorização.
- A allowlist privada, com função de verificação server-side e RLS, é a alternativa concreta recomendada neste momento. Continua pendente decidir e autorizar a sua criação em ambiente de teste isolado, antes de tocar na produção.


## Fase de backend — scaffold isolado (2026-11-21)
- Criada proposta SQL `supabase/archive/proposals/023_atina_error_reports_server_only.sql`: tabelas de reportes, allowlist administrativa, contador de limite global por minuto, RLS ativada e grants restritos ao `service_role`. **É proposta, não migration aplicada.**
- Criada Edge Function `atina-error-reports-submit`: valida categoria, pseudónimo, descrição e campos opcionais; usa service role no servidor e limite global de 50 submissões/minuto. Não aceita identificadores de jogador/partida/sessão. Não recolhe IP nem fingerprint por código.
- Criada Edge Function `atina-error-reports-admin`: valida JWT com Auth, verifica UUID do utilizador na allowlist server-only antes de cada GET/PATCH, lista reportes e permite atualizar estado/nota interna. Sem administrador registado, o acesso é recusado.
- A allowlist não tem qualquer admin inicial. A atribuição deverá ser feita apenas por operador de confiança após revisão, fora da interface de jogadores.
- Limitação conhecida do limite global: um cliente abusivo pode esgotar a quota temporária de todos; não guarda IP nem identificador individual.
- O pseudónimo recebido é texto fornecido pelo cliente e, sem associar ID de jogador (proibido pela política de privacidade), não pode ser criptograficamente confirmado. A interface deve preenchê-lo automaticamente e indicar à Administração que é o pseudónimo submetido.
- Screenshots e UI do jogador/admin não estão implementadas nesta fase. A captura/upload de imagem requer desenho adicional de validação, remoção de EXIF, bucket privado e acesso assinado, e não deve ser ativada sem testes.
- O código e SQL são scaffold/proposta e **não foram executados nem testados**. Não há migration, função deployada, dados, secrets ou configuração Supabase alterados. Não afirmar funcionalidade operacional até testes num projeto isolado.
- Plano de validação antes de avançar: requests anónimos e inválidos, limites/categoria/descrição, JWT inválido, jogador autenticado não-admin (403), admin permitido, admin removido, PATCH inválido, notas internas, CORS e rate-limit; depois testes mobile/desktop e revisão dos logs/retention para garantir que a plataforma não guarda metadados proibidos.


### Revisão estática inicial do scaffold
- CORS nas duas Edge Functions limitado às origens GitHub Pages do ATINA e localhost de desenvolvimento, com `Vary: Origin`; a submissão anónima continua sem autenticação, como previsto.
- Erros de persistência da submissão devolvem mensagem genérica, sem expor detalhe interno da base de dados.
- Corrigido o alias do UPSERT do limite global e uma resposta de erro na função Admin durante revisão estática.
- Esta revisão não substitui compilação, testes automatizados, teste em Supabase local/isolado ou revisão de segurança. Nenhum desses testes foi executado nesta sessão.


## Interface — protótipo mobile/desktop (2026-11-21)
- Criado `prototypes/error-reports-ui.html`, protótipo independente para avaliar fluxo do jogador e layout Admin.
- Player: categoria, pseudónimo, descrição com contador, aviso de privacidade e submit desligado (não envia dados).
- Admin: filtros de layout e cartão demonstrativo claramente identificado como mock, sem acesso a dados.
- Responsivo: layout de duas colunas no desktop e coluna única em mobile.
- Pseudónimo nesta demo é manual ou sugestão local; **não está ligado ao perfil ATINA**. A integração real deverá usar a fonte de pseudónimo ativa já existente e evitar persistência duplicada.
- Não foi alterado `index.html` nem `admin-images.html`; protótipo não está integrado nem publicado. Sem screenshots/upload.
- Próximas tarefas: rever pseudónimo source-of-truth no jogo, integrar UI com endpoint, remover mocks, configurar feedback/erros, testes mobile e desktop e testes de autorização num ambiente isolado.


## Regra de relógio ao reportar erro (2026-11-21)
- Ao abrir a interface de reporte durante desafio, congelar o relógio e preservar exatamente o tempo restante.
- O período de reporte não conta como tempo de jogo e não causa penalização, perda de pontos, XP ou streak.
- Cancelar/fechar o reporte: retomar o relógio com o tempo guardado.
- Envio bem-sucedido: manter a pausa até o jogador regressar explicitamente ao desafio; só então retomar.
- Solo: pausa local do relógio; garantir que callbacks/timeout/auto-reveal/aut-next também ficam suspensos e que deadlines são reconstruídos ao retomar.
- Multiplayer/competitivo: não pausar apenas o relógio de um participante, pois o relógio é partilhado e isso cria vantagem. A proposta é pausa sincronizada da sala para todos, com estado de pausa visível e limites anti-abuso; validar o impacto em todos os modos antes da integração.
- Esta regra está registada e mostrada no protótipo; a pausa efetiva do relógio ainda não está implementada nem testada.


## Implementação inicial da pausa Solo
- PR #344 integra no ecrã de jogo um botão de reporte e painel local (envio ainda desligado).
- Abrir o painel em Solo preserva o tempo restante, limpa apenas o intervalo do relógio e suspende o `timerTick` enquanto o painel está aberto.
- Retomar reconstrói a deadline com o tempo restante; não altera pontuação, XP nem streak.
- Para evitar interromper outros fluxos de jogo que usam temporizadores auxiliares, o botão fica indisponível quando há auto-next, auto-reveal, intervalo de auto-reveal, desafio bloqueado, penalização de timeout ou carta especial ativa.
- Multiplayer não é afetado por esta primeira implementação.
- Validação efetuada nesta fase: inspeção estática da integração e dos guards. Ainda não foi executado teste browser automatizado/CI, pelo que a implementação não é considerada validada.


## Integração de formulário e painel Admin (2026-11-21)
- Branch de implementação: `atina/admin-error-reports-inbox`; PR #348 em draft, ainda sem merge/publicação.
- O formulário de reporte no modo Solo foi ligado ao endpoint `atina-error-reports-submit`: categoria, pseudónimo local e descrição; validação mínima de 20 caracteres no cliente; mensagem de sucesso/falha; a descrição é preservada em caso de falha.
- Após envio bem-sucedido, a descrição é limpa e o relógio continua pausado até o jogador retomar explicitamente o desafio.
- O painel existente `admin-images.html` ganhou separador Reports, contadores por estado, filtros de estado/categoria/pseudónimo, descrição, versão/área se presentes, edição de estado e nota interna, com criação de elementos DOM para apresentar conteúdo do reporte.
- A UI usa a Edge Function `atina-error-reports-admin` (GET/PATCH) e submissão usa `atina-error-reports-submit` (POST), que permanecem scaffold no repositório.
- **Não funcional em produção ainda:** as Edge Functions, a tabela e a allowlist não foram aplicadas/deployadas ao Supabase `atina-development`. O painel mostrará erro de ligação até backend ser validado e disponibilizado.
- Não foi adicionado screenshot/upload; sem emails, IPs, IDs de jogador, partida, sessão, fingerprint ou notificações.
- Não foi alterada a base de dados de produção, não houve deploy nem merge, e Render não foi utilizado.
- Versão de jogo referenciada no código atual: v0.1.218 (publicação online não revalidada); data da atualização deste documento: 21/11/2026.
- Testes browser e de integração com Supabase continuam pendentes; validar CI, mobile/desktop, autorização server-side, persistência e falhas antes de ativar.
