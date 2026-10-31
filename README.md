# ATINA — Pensa. Descobre. Atina.

Jogo de desafios em português (pt-PT), pensado para telemóveis.

## Funcionalidades atuais
- Apagamento definitivo da conta disponível na área autenticada, com confirmação explícita e execução segura no servidor.
- Indicador visual verde no menu e no cabeçalho quando existe uma sessão iniciada, identificando o pseudónimo ou email da conta.
- Indicador verde no cabeçalho quando existe sessão iniciada, com pseudónimo ou email da conta.
- Menu inicial reorganizado para telemóveis: modo de jogo, modalidades em destaque, temporizador e atalhos de conta/ranking em secções separadas.
- Corrigido erro de JavaScript que impedia a apresentação das 15 modalidades no menu inicial.
- 15 modalidades e mais de 70 desafios.
- Cinco pistas progressivas por desafio (seis na modalidade Imagem Misteriosa).
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
