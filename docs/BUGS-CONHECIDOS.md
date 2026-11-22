# ATINA — Erros conhecidos e limitações

**Versão do jogo:** v0.1.218  
**Última atualização do documento:** 21/11/2026

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

## Reports de erros — alteração em validação
O fluxo de reportes está a receber correções num PR ainda não publicado: pré-visualização de screenshots na Administração, captura de ecrã diretamente no formulário, opção de eliminar reportes e retoma automática do relógio após envio bem-sucedido. Até os CI e testes de navegador terminarem, estas correções não são consideradas validadas nem disponíveis na versão online.

## Como reportar
Indica o modo, o passo em que ocorreu, o resultado esperado e o que aconteceu. Se possível, junta uma captura de ecrã pelo ficheiro ou pela opção de captura no formulário. Não incluas palavras-passe, tokens ou dados privados.

## Estado das correções
Uma correção só é considerada concluída após implementação e validação.

---

[Voltar ao ATINA](../index.html)
