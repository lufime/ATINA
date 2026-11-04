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

## Avisos automáticos de atualização

O workflow `.github/workflows/atina-update-notice.yml` ativa o aviso global no início de alterações publicadas na branch `main` que afetem o jogo, os recursos ou as migrations. Aguarda 120 segundos para a publicação do GitHub Pages e desativa o aviso se os passos terminarem com sucesso. Se o workflow falhar, o aviso fica ativo para não deixar os jogadores sem informação.

### Configuração obrigatória (uma vez)

No GitHub, abre **Settings → Secrets and variables → Actions → New repository secret** e cria:

- Nome: `ATINA_SUPABASE_SERVICE_ROLE_KEY`
- Valor: a chave **service_role** do projeto Supabase usado pelo ATINA.

Esta chave é confidencial: guarda-a apenas como GitHub Actions secret. Nunca a coloques no HTML, JavaScript ou neste repositório.

O workflow cobre commits na branch `main`, incluindo alterações em `supabase/migrations/**`. Alterações feitas manualmente no Dashboard do Supabase, fora de um workflow/migration commit, não geram um evento GitHub e não são detetadas por este mecanismo; para garantir avisos também nesses casos, as alterações de produção devem ser aplicadas através do processo de migrations versionadas no repositório.
