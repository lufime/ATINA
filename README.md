# ATINA — Pensa. Descobre. Atina.

Jogo de desafios em português (pt-PT), pensado para telemóveis.

## Funcionalidades atuais
- Apagamento definitivo da conta disponível na área autenticada, com confirmação explícita e execução segura no servidor.
- Indicador visual verde no menu e no cabeçalho quando existe uma sessão iniciada, identificando o pseudónimo ou email da conta.
- Indicador verde no cabeçalho quando existe sessão iniciada, com pseudónimo ou email da conta.
- Menu inicial reorganizado para telemóveis: modo de jogo, modalidades em destaque, temporizador e atalhos de conta/ranking em secções separadas.
- Corrigido erro de JavaScript que impedia a apresentação das 15 modalidades no menu inicial.
- 15 modalidades e 190 desafios preenchidos, sem respostas principais repetidas dentro da mesma modalidade; a meta de expansão é 50 por modalidade, num total de 750 desafios.
- Cinco pistas progressivas por desafio (seis na modalidade Imagem Misteriosa); a última pista dá uma orientação adicional sem revelar diretamente a resposta.
- As pistas reveladas permanecem visíveis.
- Resposta errada: menos 10 pontos; é possível tentar novamente.
- PASSO revela a resposta sem penalização.
- Pontuação variável conforme a pista usada e bónus de rapidez.
- Modo individual e duelo local para dois jogadores no mesmo dispositivo.
- Temporizador opcional: 60 segundos, 90 segundos ou sem limite.
- Avisos sonoros nos últimos 10 segundos e ao terminar o tempo.
- Resposta por voz, quando suportada pelo navegador.
- Leitura da resposta correta em voz alta.
- Imagem Misteriosa com revelação progressiva.
- Ranking online (individual e duelo), com consulta dos 10 melhores resultados.

## Ranking sem email
O ranking online pode ser usado sem criar conta e sem fornecer email. No fim de cada jogo, basta escolher um pseudónimo (até 20 caracteres) e guardar a pontuação. São enviados para o Supabase apenas o pseudónimo, a pontuação e o modo de jogo. Como não existe conta, não há recuperação de acesso nem garantia de que um pseudónimo pertence sempre à mesma pessoa. O ranking público é recreativo e não deve ser considerado inviolável contra resultados falsos.

## Publicar com GitHub Pages
1. Abre **Settings** no repositório.
2. Entra em **Pages**.
3. Em **Build and deployment**, escolhe **Deploy from a branch**.
4. Seleciona a branch main e a pasta / (root).
5. Guarda e aguarda a publicação.

O jogo é uma aplicação web estática. O duelo local continua disponível no mesmo dispositivo. O multiplayer remoto está a ser desenvolvido por fases.


## Termos e privacidade
O ATINA é um jogo pessoal e gratuito. Não é necessário fornecer email nem criar conta para jogar ou guardar pontuações. O ranking guarda o pseudónimo escolhido, a pontuação e o modo de jogo através do Supabase. Os dados não são vendidos nem usados para publicidade. As pontuações enviadas podem permanecer visíveis no ranking.


## Nota sobre o menu
O menu inicial apresenta as modalidades de jogo e o ranking sem exigir conta ou email.

Correção adicional: removidas referências residuais à antiga interface de autenticação, para o menu funcionar sem contas.


### Robustez do arranque
O menu e as modalidades do jogo não dependem do carregamento da biblioteca externa de autenticação. Se esse serviço ou a respetiva CDN estiver indisponível, o jogo continua a arrancar; as funcionalidades de conta ficam indisponíveis, mas o modo individual, o duelo e o ranking por pseudónimo mantêm-se separados.


### Menu de modalidades
As 15 modalidades são agora apresentadas diretamente no HTML inicial, para continuarem visíveis mesmo que um serviço externo ou uma falha de JavaScript impeça a renderização dinâmica. A seleção continua a ser feita pelos botões de cada modalidade.


### Ordem do menu
O menu inicial está organizado pela sequência: 1) Tempo por desafio, 2) Escolhe como jogar, 3) Escolhe uma modalidade.


### Multiplayer em rede — primeira fase
Foi criada a base de salas online para 1 a 12 jogadores, com código de entrada, pseudónimos e lista de participantes atualizada automaticamente. Cada participante usa o seu próprio telemóvel. Esta primeira fase ainda não inicia partidas nem inclui equipas; essas funções serão desenvolvidas na fase seguinte.


### Multiplayer em rede — segunda fase
A sala inclui agora confirmação de prontidão, distribuição automática por duas equipas e atribuição manual de equipa pelo anfitrião. O anfitrião pode iniciar a sala quando houver pelo menos dois jogadores e todos estiverem prontos. O início ainda não sincroniza as perguntas, pistas ou cronómetro; essa é a fase seguinte.


### Multiplayer em rede — preparação da sincronização
Foi acrescentado ao backend um estado partilhado da partida, com versão sequencial, que só o anfitrião pode publicar e que os participantes da sala podem consultar com a respetiva sessão. A leitura e publicação foram testadas com dois jogadores. A interface ainda não usa este estado para sincronizar visualmente desafios, pistas ou cronómetro; essa integração continua pendente.


### Multiplayer em rede — terceira fase (sincronização inicial)
Depois de o anfitrião iniciar, os telemóveis recebem o mesmo desafio, a mesma sequência de pistas e a mesma contagem decrescente, com o anfitrião a controlar a revelação das pistas e a passagem ao desafio seguinte. Nesta fase inicial, as respostas e a pontuação competitiva ainda não estão sincronizadas; o painel dos restantes jogadores é de acompanhamento. A conclusão da lógica de respostas, pontuação por jogador/equipa e ranking multiplayer fica para a fase seguinte.


### Multiplayer em rede — quarta fase (respostas e pontuação individual)
Cada participante pode agora submeter respostas no seu próprio telemóvel. As respostas corretas e erradas são registadas na sala, com pontuação individual e classificação atualizada. A validação da resposta é feita no cliente com a lista de respostas do jogo; por isso, esta versão é recreativa e ainda não tem proteção anti-batota robusta. A pontuação por equipas e o ranking final persistente ficam para a fase seguinte.


### Multiplayer em rede — votação por equipa
Nas partidas por equipas, o primeiro jogador que submete uma resposta apresenta uma proposta à sua equipa. O próprio proponente não vota; todos os restantes colegas têm de escolher «Concordo» ou «Não concordo». A proposta só é aceite quando todos concordam e a resposta está correta. Um voto de discordância rejeita a proposta e permite à equipa tentar novamente. Quando aceite, os pontos são atribuídos aos jogadores dessa equipa. Se a equipa tiver apenas um elemento, não existe votação adicional. A votação e os respetivos votos são guardados no Supabase e consultados pelos telemóveis da sala. A validação da resposta continua a ser feita no cliente, pelo que não existe proteção anti-batota robusta.


### Multiplayer em rede — resultados finais
No fim da sequência de desafios, todos os telemóveis passam para o ecrã de resultados da sala. O ecrã apresenta a classificação individual e, quando existem equipas, a soma dos pontos por equipa. A classificação usa as pontuações registadas na sala; não cria ainda uma entrada no ranking público persistente.


### Multiplayer em rede — ranking persistente
Quando o anfitrião termina o último desafio, fecha a sala através de uma operação protegida no Supabase. Os resultados individuais de todos os participantes são guardados na tabela de histórico da sala, com pseudónimo, equipa, pontuação e data. O ecrã final apresenta a classificação da sala. O histórico não está exposto para consulta pública nesta fase; apenas a função protegida do servidor pode inserir ou atualizar resultados, e a operação de fecho é idempotente para evitar duplicados. A validação das respostas continua a ser feita no cliente, pelo que o sistema não constitui uma solução anti-batota robusta.


### Multiplayer em rede — até seis equipas
O anfitrião pode distribuir automaticamente os participantes por até seis equipas (A a F). O número de equipas é ajustado ao total de jogadores, mantendo, sempre que possível, pelo menos dois jogadores por equipa: 2–5 jogadores formam 2 equipas; 6–7 formam 3; 8–9 formam 4; 10–11 formam 5; 12 formam 6. Também é possível atribuir manualmente cada participante a qualquer uma das seis equipas antes do início da partida. A votação de respostas é aplicada aos colegas da respetiva equipa.


### Multiplayer — classificação das equipas em direto
Durante os desafios, o painel da sala apresenta duas tabelas atualizadas com os dados recebidos do Supabase: classificação por equipas, calculada pela soma dos pontos dos seus membros, e classificação individual. A ordenação das equipas é atualizada à medida que as pontuações dos jogadores são sincronizadas.


### Multiplayer — recuperar a partida após atualizar a página
A sessão da sala (identificador e token de acesso) fica guardada localmente no navegador. Ao atualizar ou reabrir a página no mesmo telemóvel/navegador, o ATINA tenta recuperar a sala e volta ao lobby ou ao desafio que está atualmente sincronizado no Supabase. A partida não é criada de novo nem regressa ao primeiro desafio. Se a sessão tiver expirado ou a sala já não existir, é apresentada uma mensagem e será necessário entrar novamente com o código.


### Retoma automática de qualquer desafio
O progresso dos modos individual e duelo local é guardado no navegador e recuperado ao atualizar a página, incluindo desafio atual, pistas reveladas, pontuação, jogador da vez, resposta escrita e tempo restante. Nas salas multiplayer, a recuperação continua a usar o estado sincronizado da sala. Começar um novo jogo substitui o progresso local anterior.


### Organização do menu inicial
O menu foi reorganizado por ordem de utilização: tempo por desafio, modo de jogo, modalidades, classificação e jogo em rede. Os blocos têm hierarquia visual e espaçamento consistentes, com grelha adaptável a telemóveis e ecrãs maiores.


### Recuperação após atualizar a página
Ao recarregar, o ATINA tenta primeiro recuperar a sessão multiplayer; caso não exista, recupera o progresso local do desafio individual/duelo. Se não houver jogo em curso, restaura o último ecrã visitado. A resposta em edição também é guardada localmente.


### Correção do relógio em tempo real (31/10/2026)
- O contador das partidas online passa a garantir a atualização contínua do relógio no ecrã, incluindo logo no arranque da partida e após a receção de novos estados.
- A contagem é recalculada a partir do prazo absoluto (`Date.now()`), evitando depender da quantidade de intervalos executados pelo navegador.


## Banco de desafios e meta de expansão

O banco atual contém **190 desafios preenchidos em 15 modalidades**. A meta é chegar a **750 desafios**, com 50 em cada modalidade. Faltam **560 desafios** para atingir essa meta. As contagens são calculadas a partir do array `games` em `index.html`, e o menu atualiza automaticamente o número de desafios por modalidade.

| Modalidade | Atual | Meta |
|---|---:|---:|
| Quem sou eu? | 11 | 50 |
| Onde estou? | 12 | 50 |
| O que sou? | 12 | 50 |
| História e mistérios | 12 | 50 |
| Palavras escondidas | 12 | 50 |
| Ciência e natureza | 12 | 50 |
| Cultura geral | 12 | 50 |
| Imagem misteriosa | 18 | 50 |
| Lógica e números | 14 | 50 |
| Desafio surpresa | 13 | 50 |
| Música e sons | 12 | 50 |
| Cinema e televisão | 12 | 50 |
| Desporto | 12 | 50 |
| Ilusões e truques mentais | 12 | 50 |
| Detetive | 14 | 50 |
| **Total** | **190** | **750** |

### Validar o banco de desafios

Executa `node scripts/validate-challenges.mjs` para verificar a estrutura, a distribuição por modalidade, as pistas, as respostas aceites e as respostas repetidas. Usa `node scripts/validate-challenges.mjs --strict` para fazer das respostas repetidas um erro bloqueante.
