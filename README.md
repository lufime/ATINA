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

## Ranking online
O ranking atual usa Supabase e permite guardar pontuações associadas a um pseudónimo. Nesta versão, ainda não existe autenticação individual: o registo com palavra-passe e recuperação de conta através de código está planeado, mas ainda não foi implementado.

## Publicar com GitHub Pages
1. Abre **Settings** no repositório.
2. Entra em **Pages**.
3. Em **Build and deployment**, escolhe **Deploy from a branch**.
4. Seleciona a branch `main` e a pasta `/ (root)`.
5. Guarda e aguarda a publicação.

O jogo é uma aplicação web estática. O duelo é local, no mesmo dispositivo; não existem ainda salas remotas nem torneios online.
