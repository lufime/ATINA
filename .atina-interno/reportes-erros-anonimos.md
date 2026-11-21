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
