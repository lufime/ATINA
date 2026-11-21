# Reportes anónimos de erros — proposta de implementação

## Objetivo
Permitir que qualquer jogador reporte um erro durante ou depois do jogo, sem interromper a partida e sem recolher dados pessoais.

## Privacidade obrigatória
- Não recolher email, IP, nome/conta, ID de jogador, identificadores persistentes, fingerprint ou tokens da partida.
- Não guardar user-agent completo nem headers da requisição.
- Não ligar o reporte à partida, sala, sessão, desafio ou jogador.
- A screenshot é opcional e deve mostrar aviso para ocultar informação pessoal antes do envio.
- Remover metadados EXIF da screenshot no cliente antes de upload; limitar tipo e tamanho.
- Guardar apenas categoria, descrição, versão pública do jogo, área/modo selecionado opcional, timestamp de servidor e screenshot opcional.
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
2. Categoria obrigatória, descrição obrigatória e screenshot opcional.
3. Aviso visível: não incluir nomes, emails, dados pessoais ou informação sensível na screenshot/descrição.
4. Envio com estado e confirmação; se falhar, manter descrição no formulário para nova tentativa.
5. Limitação de spam não baseada em identificador persistente: limite global por janela temporal e throttle apenas em memória no browser.

## Administração (integrada em admin-images.html)
- Secção protegida de reportes, sem página Admin nova.
- Contador de reportes por estado e destaque de novos.
- Lista com categoria, data, versão, área, descrição e screenshot.
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
