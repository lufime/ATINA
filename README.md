# ATINA — Pensa. Descobre. Atina.

Jogo de desafios em português europeu (pt-PT), com 15 modalidades e 753 desafios identificados por posições históricas estáveis.

## Modos de jogo

- **Individual** — uma pessoa, com pontuação e sequência geridas pelo servidor.
- **Duelo** — dois jogadores no mesmo dispositivo, com alternância de vez.
- **Mix** — desafios de várias modalidades.
- **Party** — duas equipas no mesmo dispositivo, até 10 desafios e bónus de pontos a dobrar na última ronda.
- **Multiplayer** — salas online com código, jogadores, equipas, propostas e votação.
- **Mímicas** — salas online, representante por ronda e palavra secreta visível apenas no dispositivo do representante.

## Ligação obrigatória

**Todos os modos exigem ligação à Internet e validação pelo Supabase. Não existe modo offline nem fallback de validação no browser.**

O cliente envia apenas a resposta textual. A correção, penalizações, pontuação, bónus, prazos, pistas reveladas e transições são controlados pelo servidor. As respostas principais, alternativas aceites e palavras secretas de Mímicas não são incluídas no HTML ou no JavaScript servido ao browser.

Em Mímicas, a decisão de que o gesto foi corretamente adivinhado continua a ser humana e é registada pelo anfitrião; os pontos e o relógio são calculados pelo servidor.

## Segurança e testes

- Dados de desafios e Mímicas guardados em tabelas privadas, sem leitura direta por clientes.
- Sessões e salas autenticadas por tokens aleatórios; apenas hashes dos tokens são guardados.
- RPCs específicas para submissão de respostas, pistas, propostas, votos e transições.
- Rate limiting no acesso RPC do ATINA.
- O workflow de validação verifica o catálogo público, a sintaxe JavaScript e a ausência de respostas, alternativas, pistas não reveladas e palavras secretas no cliente.
- O workflow de replay aplica as migrations numa instância Supabase local descartável e executa os testes pgTAP.

Ver [SECURITY-DESIGN.md](SECURITY-DESIGN.md) para os detalhes, decisões e limitações conhecidas.

## Estado desta branch

Este trabalho está isolado em `security/server-side-validation`. Não foi feito merge para `main`, deploy nem alteração da base de dados de produção. A integração ainda precisa de testes funcionais num browser real, incluindo telemóveis, reconexão, salas multiplayer, votação por equipa, prazos e Mímicas.

## Publicação

Não publicar esta branch diretamente. Qualquer merge, PR, deploy ou alteração em produção exige autorização explícita.
