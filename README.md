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

**Estado da autenticação:** a estrutura de perfis e a ligação entre pontuações e utilizadores foram preparadas na base de dados. Os ecrãs de registo, início de sessão, recuperação de palavra-passe por email e associação automática das pontuações à conta ainda estão em desenvolvimento; não devem ser considerados disponíveis no jogo até serem integrados e testados.

A autenticação planeada usa email e palavra-passe através do Supabase Auth. A recuperação será feita pelo fluxo de email do Supabase. Os jogadores não precisam de conta GitHub.

## Publicar com GitHub Pages
1. Abre **Settings** no repositório.
2. Entra em **Pages**.
3. Em **Build and deployment**, escolhe **Deploy from a branch**.
4. Seleciona a branch main e a pasta / (root).
5. Guarda e aguarda a publicação.

O jogo é uma aplicação web estática. O duelo é local, no mesmo dispositivo; não existem ainda salas remotas nem torneios online.
