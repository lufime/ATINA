# Plano de testes — Jogos Sociais ATINA (beta)

## Âmbito e segurança

- Branch de trabalho: `atina-social-games-beta`.
- Não publicar esta branch no GitHub Pages principal.
- Não alterar a branch `main`.
- Não ativar os jogos no catálogo Supabase de produção.
- Não executar partidas de teste contra o projeto Supabase de produção.

## Bloqueio técnico confirmado

A função `public.atina_social_game_start_room` valida `atina_social_game_catalog.active = true` antes de criar uma partida. Os cinco jogos continuam com `active = false` no catálogo atual. Por isso, a partida real não pode ser iniciada no projeto atual sem ativar jogos em produção — ação que está fora do âmbito destes testes.

Para testes de integração reais, é necessário um projeto Supabase de staging/teste isolado, com as migrações e conteúdos beta aplicados e as credenciais de teste configuradas na aplicação. A publicação de uma página web beta, por si só, não isola a base de dados.

## Cenários de teste em dois dispositivos

1. Anfitrião inicia sessão e cria uma sala.
2. Convidado inicia sessão noutro dispositivo e entra com o código.
3. Confirmar presença dos dois jogadores e estado da sala.
4. Testar atribuição manual de equipas.
5. Testar distribuição automática de equipas.
6. Iniciar cada um dos cinco jogos em modo individual.
7. Repetir cada jogo em modo equipas.
8. Confirmar submissões, sincronização entre dispositivos, temporizadores e transição de rondas.
9. Confirmar pontuação, classificação final e encerramento da partida.
10. Repetir com interrupção/recarregamento de página e reconexão.

## Estado

- [x] Código beta presente na branch.
- [x] Funções RPC de jogo instaladas no Supabase consultado.
- [x] Bloqueio de ativação em produção identificado.
- [ ] Projeto Supabase de staging criado e configurado.
- [ ] Página beta disponibilizada num host isolado.
- [ ] Testes reais de dois dispositivos executados.
- [ ] Resultados de pontuação e fim de ronda validados.

**Não declarar os testes aprovados até os cenários acima serem executados num ambiente isolado.**
