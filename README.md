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

O jogo é uma aplicação web estática. O duelo é local, no mesmo dispositivo; não existem ainda salas remotas nem torneios online.


## Termos e privacidade
O ATINA é um jogo pessoal e gratuito. Não é necessário fornecer email nem criar conta para jogar ou guardar pontuações. O ranking guarda o pseudónimo escolhido, a pontuação e o modo de jogo através do Supabase. Os dados não são vendidos nem usados para publicidade. As pontuações enviadas podem permanecer visíveis no ranking.


## Nota sobre o menu
O menu inicial apresenta as modalidades de jogo e o ranking sem exigir conta ou email.

Correção adicional: removidas referências residuais à antiga interface de autenticação, para o menu funcionar sem contas.
