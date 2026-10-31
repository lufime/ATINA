# ATINA — Pensa. Descobre. Atina.

Jogo de desafios em português (pt-PT), pensado para telemóveis.

## Funcionalidades atuais
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

## Backend e contas de jogador
O backend usa Supabase. O ranking guarda pontuações e já tem suporte de base de dados para associar resultados a utilizadores autenticados (user_id).

**Estado da autenticação:** o jogo já inclui ecrãs para criar conta, iniciar sessão e pedir recuperação da palavra-passe por email. A base de dados cria o perfil e valida a unicidade do pseudónimo. A confirmação do email e a recuperação dependem das definições de autenticação do projeto Supabase; é necessário permitir o endereço `https://lufime.github.io/ATINA/` nas URLs de redirecionamento autorizadas. As novas pontuações guardadas a partir do jogo ficam associadas ao utilizador autenticado (`user_id`). No modo individual, o pseudónimo da conta é usado automaticamente. No duelo local, cada jogador pode indicar o seu pseudónimo, ficando os dois resultados associados à conta que iniciou a sessão.

A autenticação usa a biblioteca oficial JavaScript do Supabase e email/palavra-passe através do Supabase Auth. A recuperação usa o fluxo de email do Supabase. Os jogadores não precisam de conta GitHub. Até a configuração de redirecionamento e os testes finais estarem concluídos, a recuperação por email pode não funcionar corretamente.

## Publicar com GitHub Pages
1. Abre **Settings** no repositório.
2. Entra em **Pages**.
3. Em **Build and deployment**, escolhe **Deploy from a branch**.
4. Seleciona a branch main e a pasta / (root).
5. Guarda e aguarda a publicação.

O jogo é uma aplicação web estática. O duelo é local, no mesmo dispositivo; não existem ainda salas remotas nem torneios online.
