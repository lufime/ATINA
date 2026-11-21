# ATINA — Erros conhecidos e limitações

Esta página regista limitações confirmadas e áreas em que ainda são necessários testes em dispositivos e browsers reais. Não apresenta hipóteses como falhas confirmadas.

## Limitações atuais

### É necessária ligação à Internet
**Estado:** Limitação confirmada  
Todos os modos dependem da ligação e da validação online. Não existe modo offline nem validação de respostas no browser.

**O que fazer:** confirma que tens Internet e volta a tentar.

### A ligação pode interromper uma ronda ou sala online
**Estado:** Área a validar em testes reais  
A experiência de reconexão, em especial em telemóveis e salas multiplayer, deve ser testada em condições reais. Não se garante que uma ronda interrompida seja retomada automaticamente em todos os cenários.

**O que fazer:** evita fechar a página durante uma ronda. Se perderes a ligação, recupera-a e verifica o estado da sala antes de repetir ações.

### Carregamento de rankings e perfil depende do serviço
**Estado:** Dependência confirmada  
Os rankings e dados de perfil são carregados online; se o serviço falhar ou a ligação estiver instável, os dados podem não aparecer ou não atualizar imediatamente.

**O que fazer:** aguarda alguns segundos e tenta atualizar/reabrir o separador.

### Testes de browser não substituem testes completos em dispositivos
**Estado:** Limitação de validação conhecida  
Os testes automáticos não cobrem toda a utilização em browsers reais, telemóveis, reconexões, salas online, votação e prazos.

## Como reportar um problema

Ao reportar uma falha, inclui:
- modo de jogo e passo em que ocorreu;
- dispositivo e browser;
- o que esperavas que acontecesse;
- o que aconteceu, incluindo mensagem de erro;
- se o problema desapareceu após recarregar.

Não partilhes palavras-passe, tokens, códigos privados de sala ou outros dados sensíveis.

## Estado das correções

Uma falha só deve ser marcada como **corrigida** depois de a alteração estar implementada e validada. A existência de um PR ou de um deploy, por si só, não significa que o problema esteja resolvido para todos os jogadores.

---

[Voltar ao ATINA](../index.html)
