# ATINA — desenho de segurança

## Âmbito e estado

Este documento descreve a arquitetura de segurança atualmente integrada na branch `main`. A publicação de cada versão deve ser confirmada pelo resultado do workflow GitHub Pages; a presença do código em `main`, por si só, não prova que uma versão específica esteja publicada.

**É necessária ligação à Internet para iniciar e jogar qualquer modo. Não existe fallback de validação offline.** Sem acesso ao Supabase, a partida não pode começar nem aceitar respostas.

## Catálogo público e dados privados

O cliente recebe apenas os dados necessários à apresentação dos desafios, mantendo os identificadores/posições históricas. As respostas principais e alternativas não devem ser incluídas no HTML ou JavaScript servido ao browser.

As pistas são entregues à medida que são reveladas pelo servidor. O catálogo público mantém as posições históricas, incluindo slots vazios, para não alterar os IDs. A classificação de dificuldade por índice não contém respostas.

Palavras, cartões e pistas de Mímicas são mantidos no schema privado do Supabase. A palavra secreta só deve ser devolvida ao representante autorizado da ronda através da RPC própria.

## Modos de desafios

Individual, Duelo, Mix e Party usam sessões locais autoritativas no servidor, através das RPCs de início, estado, revelação de pistas, submissão de resposta, passagem e avanço.

O browser envia o texto da resposta. O servidor compara-o com a chave privada e aplica penalizações, bónus, alternância de jogadores e pontuação. Os tokens de sessão são aleatórios e apenas o respetivo hash é guardado na base de dados.

Party limita a fila a 10 desafios, alterna entre as duas equipas e aplica o bónus final no servidor.

A dificuldade adaptativa usa o histórico recente de resultados de jogadores registados. A qualificação exige um mínimo de observações; mais erros podem elevar a dificuldade e poucos erros podem reduzi-la. A rotação tenta evitar desafios apresentados recentemente quando o conjunto disponível o permite. A alteração aplica-se à seleção de uma nova partida, não altera uma ronda em curso. O perfil Admin é excluído da aprendizagem através do nome apresentado, o que não equivale a uma autorização baseada em papel/identidade autenticada.

## Multiplayer e equipas

As salas usam tokens bearer aleatórios, guardados como hashes. O estado público é projetado pelo servidor e não deve incluir a fila completa nem respostas durante uma ronda ativa.

As RPCs de respostas, propostas e votos validam o token da sala, o jogador/equipa, o desafio, o prazo e as regras de pontuação no servidor. As propostas de equipa são submetidas como texto e a votação é validada no servidor. A decisão de correção em Mímicas é humana, tomada pelo anfitrião; não existe reconhecimento semântico automático do gesto.

## Proteções transversais

- RLS está ativo nas tabelas privadas; o acesso é feito através de RPCs controladas.
- As funções privilegiadas devem usar `search_path` controlado e validar os tokens e os parâmetros relevantes.
- Rate limiting está implementado no acesso RPC do ATINA. Não substitui WAF/DDoS nem limites por conta/token; utilizadores atrás do mesmo NAT podem partilhar quota.
- O frontend não deve publicar estados arbitrários de jogo. As operações de Mímicas são limitadas às transições previstas pelo fluxo.
- O cliente não decide se uma resposta textual está correta nem calcula pontuação.

### Notas de auditoria

Os advisors do Supabase assinalaram funções `SECURITY DEFINER` executáveis por `anon` e/ou `authenticated`, tabelas sem políticas RLS e a extensão `pg_net` no schema `public`. Estes avisos exigem revisão função a função e tabela a tabela: algumas RPCs são endpoints intencionais para sessões anónimas autenticadas por token, e tabelas no schema privado podem não precisar de acesso direto pela API. Não se deve aplicar revogações globais ou políticas genéricas sem verificar o contrato de cada fluxo.

O advisor de performance também identificou índices em falta para chaves estrangeiras da fila de matchmaking e recomenda otimizar duas políticas de `atina_site_notice` para evitar reavaliações de funções de autenticação. Estas otimizações devem ser aplicadas por migration versionada e verificadas com os advisors e testes, sem remover índices apenas por aparecerem como pouco utilizados.

A proteção de palavras-passe comprometidas do Supabase Auth está desativada no projeto auditado. A relevância depende dos métodos de autenticação efetivamente usados; deve ser revista antes de introduzir autenticação por palavra-passe.

## Verificações automáticas e limites

Os workflows existentes verificam o catálogo público, a sintaxe JavaScript, a ausência de respostas/alternativas e segredos de Mímicas no cliente, a ligação das submissões às RPCs server-side e o replay de migrations com testes pgTAP.

Estas verificações não equivalem a uma suite E2E completa. Continuam por cobrir de forma abrangente testes em browser real, dispositivos móveis, reconexão, salas multiplayer, votação por equipa, deadlines e Mímicas.

A auditoria de advisors é indicativa e não prova, por si só, a existência ou ausência de uma vulnerabilidade explorável. Cada função exposta e cada tabela sem política devem ser avaliadas de acordo com as permissões efetivas, o corpo da função e o modelo de tokens.

## Operação segura

- Aplicar alterações de schema através de migrations versionadas e rever o diff antes de produção.
- Não expor chaves `service_role` no cliente ou no repositório; usar secrets do GitHub Actions.
- Confirmar os workflows de validação e deploy após cada alteração.
- Não revogar permissões, alterar políticas RLS ou mover extensões sem testar os fluxos que dependem delas.
