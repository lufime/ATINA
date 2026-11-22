# ATINA — Erros conhecidos e limitações

**Versão do jogo:** v0.1.218  
**Última atualização do documento:** 22/11/2026

Esta página separa limitações e situações que podem ocorrer de erros reproduzidos e confirmados. Nesta revisão documental não foram reproduzidos testes de jogo; por isso, os pontos abaixo não são apresentados como bugs confirmados.

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

## Problemas ainda não verificados
Esta revisão não incluiu testes end-to-end em dispositivos nem reproduziu falhas adicionais. Não se adicionam problemas como confirmados sem evidência.

## Reportes de erros — em validação
O PR #358 acrescenta reporte transversal em todos os ecrãs, contexto automático e screenshot por upload/captura. No modo Solo, o relógio pausa e retoma com o tempo preservado; nos modos online não pausa o relógio partilhado. Esta implementação ainda está em CI e não está publicada. As correções anteriores do fluxo administrativo continuam por validar na versão online.

## Como reportar
Indica o modo, o passo em que ocorreu, o resultado esperado e o que aconteceu. Se possível, junta uma captura de ecrã pelo ficheiro ou pela opção de captura no formulário. Não incluas palavras-passe, tokens ou dados privados.

## Estado das correções
Uma correção só é considerada concluída após implementação e validação.

---

[Voltar ao ATINA](../index.html)
