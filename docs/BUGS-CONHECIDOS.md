# ATINA — Erros conhecidos e limitações

**Versão do jogo (código):** v0.1.253  
**Versão online:** não confirmada nesta revisão  
**Última atualização do documento:** 22/11/2026

Esta página distingue situações possíveis de erros reproduzidos. Não foram realizados testes funcionais completos em dispositivos nesta atualização documental.

## Situações a considerar

### Desafios sem imagem
Alguns desafios podem ser apresentados apenas com texto, caso não tenham imagem associada.

### Ligação instável
A perda de ligação pode afetar rondas, validação de respostas e salas online. A recuperação automática após interrupção não foi verificada nesta revisão.

**O que fazer:** recupera a ligação e verifica o estado da partida antes de continuar.

### Perfil ou classificações sem atualização imediata
O carregamento ou atualização pode demorar quando a ligação ou o serviço está instável. Não foi reproduzido um erro persistente nesta revisão.

**O que fazer:** aguarda, volta a abrir o separador ou tenta atualizar.

### Duelo e Modo Festa
Estes modos encaminham para o fluxo online. A experiência depende da sala/partida e dos dispositivos dos participantes; não são descritos aqui como modos locais no mesmo dispositivo.

## Reportar erros — comportamento implementado no código
O botão transversal **Reportar erro** permite enviar uma descrição, contexto automático do ecrã/partida e anexar ou capturar uma imagem, quando o navegador autoriza.

- **Solo:** o relógio pausa durante o reporte e o tempo restante é preservado; o fluxo retoma após fechar ou concluir o reporte.
- **Online:** o relógio partilhado não é pausado.

A presença desta implementação no código não confirma, por si só, que já esteja publicada online.

## Problemas ainda não verificados
Esta revisão documental não incluiu testes end-to-end em dispositivos nem reproduziu falhas adicionais. Não se adicionam problemas como confirmados sem evidência.

## Como reportar
Indica o modo, o passo em que ocorreu, o resultado esperado e o que aconteceu. Se possível, junta uma captura de ecrã. Não incluas palavras-passe, tokens ou dados privados.

## Estado das correções
Uma correção só é considerada concluída após implementação e validação. A versão online deve ser confirmada separadamente.

---

[Voltar ao ATINA](../index.html)
