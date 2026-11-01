# ATINA — desenho de segurança

## Âmbito desta branch

Esta documentação descreve a branch `security/server-side-validation`. As alterações aqui presentes não foram integradas em `main`, publicadas nem aplicadas em produção.

**É necessária ligação à Internet para iniciar e jogar qualquer modo. Não existe fallback de validação offline.** Sem acesso ao Supabase, a partida não pode começar nem aceitar respostas.

## Catálogo público e dados privados

O `index.html` contém apenas os dados necessários à apresentação inicial:
- identificador/posição histórica preservada;
- modalidade e emoji;
- URL de imagem, quando aplicável.

As pistas também não são enviadas antecipadamente: o browser recebe apenas as pistas já reveladas pela RPC de estado.

As 753 respostas principais e as respetivas alternativas foram removidas do cliente. O catálogo mantém os 802 slots históricos, incluindo 49 posições vazias, para não alterar os IDs. A classificação de dificuldade por índice é pré-calculada e não contém respostas.

O array local de cartões de Mímicas está vazio. Palavras, cartões e pistas de Mímicas são mantidos no schema privado do Supabase. A palavra secreta só é devolvida por `atina_get_mime_secret` ao representante da ronda.

## Modos de desafios

Individual, Duelo, Mix e Party usam sessões locais autoritativas:
- `atina_start_local_game`
- `atina_local_game_state`
- `atina_local_reveal_clue`
- `atina_local_submit_answer`
- `atina_local_pass_challenge`
- `atina_local_next_challenge`

O browser envia apenas o texto da resposta. O servidor compara a resposta com a chave privada, aplica penalizações, bónus, cartas especiais, alternância de jogadores e pontuação. Os tokens de sessão são aleatórios e apenas o respetivo hash é guardado na base de dados.

Party limita a fila a 10 desafios, alterna entre as duas equipas e aplica o bónus final no servidor.

## Multiplayer e equipas

As salas são autenticadas por tokens bearer aleatórios, guardados como hashes. O estado público é projetado pelo servidor e não inclui a fila completa nem respostas durante uma ronda ativa.

- `atina_submit_room_answer` recebe apenas `p_answer`; não aceita `p_correct` nem `p_points`.
- `atina_submit_team_proposal` recebe a resposta textual proposta.
- `atina_vote_team_proposal` recebe apenas a decisão de cada membro.
- O servidor valida unanimidade, correção, prazo e pontuação.
- Submissões individuais por membros de uma equipa são bloqueadas.

## Mímicas

Mímicas usa salas multiplayer. O anfitrião escolhe o representante e faz a avaliação humana do gesto — não existe reconhecimento semântico automático da mímica.

- A palavra secreta é obtida apenas pelo representante.
- O servidor controla o relógio, as pistas reveladas, o fecho da ronda e os resultados.
- `p_points` é ignorado pela função de resolução; os pontos são calculados no servidor com base na pista e no tempo restante.
- `p_correct` representa a decisão humana do anfitrião, necessária neste formato de jogo.

## Proteções transversais

- RLS ativo nas tabelas privadas, sem permissões diretas para `anon`/`authenticated`.
- RPCs `SECURITY DEFINER` com `search_path` controlado e autenticação por token.
- Rate limiting PostgREST por IP e RPC, com hash do IP, quotas e resposta HTTP 429.
- O frontend não publica estados arbitrários de jogo. A publicação usada em Mímicas só permite transições estreitas (início do relógio e revelação de uma pista).
- O cliente não decide se uma resposta está correta nem calcula pontuação.

## Verificações automáticas

O workflow de validação verifica:
- integridade do catálogo público (753 desafios, sem pistas não reveladas nem campos de resposta);
- sintaxe JavaScript inline e do cliente separado;
- ausência de respostas e alternativas no array enviado ao browser;
- ausência de cartões secretos de Mímicas no browser;
- ligação das submissões às RPCs server-authoritative.

O workflow de replay cria uma instância Supabase local descartável, aplica as migrations desde uma base vazia e executa a suite pgTAP. Não utiliza o projeto Supabase de produção.

## Limites conhecidos antes de qualquer publicação

- A integração precisa de testes funcionais num browser real, incluindo dispositivos móveis, reconexão, salas, votação por equipa, deadlines e Mímicas.
- O rate limiting por IP não substitui WAF/DDoS nem limites por conta/token; utilizadores atrás do mesmo NAT partilham quota.
- O cliente requer ligação à Internet e acesso ao Supabase.
- Mímicas continua a depender da avaliação humana do anfitrião.
- O cliente antigo e as novas RPCs não devem ser misturados: a versão antiga enviava correção e pontos do browser e é deliberadamente desativada nesta branch.
- Não publicar, fazer merge, criar PR, alterar produção ou aplicar migrations em produção sem autorização explícita.
