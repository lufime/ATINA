# ATINA — Pensa. Descobre. Atina.

Jogo de desafios em português europeu (pt-PT), com 23 modalidades e 1.153 desafios identificados por posições históricas estáveis.

## Modos de jogo

- **Individual** — uma pessoa, com pontuação e sequência geridas pelo servidor.
- **Duelo** — dois jogadores no mesmo dispositivo, com alternância de vez.
- **Mix** — desafios de várias modalidades.
- **Party** — duas equipas no mesmo dispositivo, até 10 desafios e bónus de pontos a dobrar na última ronda.
- **Multiplayer** — salas online com código, jogadores, equipas, propostas e votação.
- **Mímicas** — salas online, representante por ronda e palavra secreta visível apenas no dispositivo do representante.

## Ligação e validação

Todos os modos exigem ligação à Internet e validação pelo Supabase. Não existe modo offline nem fallback de validação no browser.

Nos modos com respostas textuais, o cliente envia a resposta e o servidor valida-a e calcula pontuação, penalizações, bónus, prazos, pistas reveladas e transições. Em Mímicas, a decisão de que o gesto foi corretamente adivinhado continua a ser humana e é registada pelo anfitrião; os pontos e o relógio são calculados pelo servidor.

## Segurança e testes

- Dados privados de desafios e Mímicas não são disponibilizados como catálogo de respostas no cliente.
- Sessões e salas usam tokens aleatórios; os fluxos server-side guardam hashes dos tokens.
- RPCs específicas tratam submissões de respostas, pistas, propostas, votos e transições.
- Rate limiting está implementado no acesso RPC do ATINA.
- A validação automática verifica o catálogo público, a sintaxe JavaScript e a ausência de respostas, alternativas, pistas não reveladas e palavras secretas no cliente.
- O workflow de replay aplica as migrations numa instância Supabase local descartável e executa testes pgTAP.

A validação automática não substitui testes funcionais completos em browser real. Continuam relevantes testes em telemóveis, reconexão, salas multiplayer, votação por equipa, prazos e Mímicas.

Ver [SECURITY-DESIGN.md](SECURITY-DESIGN.md) para a arquitetura, decisões e limitações conhecidas.

## Estado e publicação

O código de validação server-side e a adaptação/rotação de desafios estão integrados na branch `main`. A publicação é feita através do GitHub Pages e as alterações à base de dados devem seguir migrations versionadas.

Não assumir que uma alteração está em produção apenas por existir em `main`: confirmar sempre o resultado do workflow de deploy e, para alterações de base de dados, o estado das migrations no projeto Supabase.

## Avisos automáticos de atualização

O workflow `.github/workflows/atina-update-notice.yml` ativa um aviso global no início de alterações publicadas na branch `main` que afetem o jogo, os recursos, as migrations ou os próprios workflows. Aguarda 180 segundos para a publicação do GitHub Pages e desativa o aviso se os passos terminarem com sucesso. Se o workflow falhar antes da desativação, o aviso poderá permanecer ativo e deverá ser verificado.

### Configuração obrigatória (uma vez)

No GitHub, abre **Settings → Secrets and variables → Actions → New repository secret** e cria:

- Nome: `ATINA_SUPABASE_SERVICE_ROLE_KEY`
- Valor: a chave **service_role** do projeto Supabase usado pelo ATINA.

Esta chave é confidencial: guarda-a apenas como GitHub Actions secret. Nunca a coloques no HTML, JavaScript ou neste repositório.

O workflow cobre commits na branch `main`, incluindo alterações em `supabase/migrations/**`. Alterações feitas manualmente no Dashboard do Supabase, fora de um workflow/migration commit, não geram um evento GitHub e não são detetadas por este mecanismo.
