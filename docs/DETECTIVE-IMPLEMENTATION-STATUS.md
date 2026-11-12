# Estado da implementação — Aventura Detetive

Atualizado em 12-11-2026.

## Implementado no branch `feature/detetive-aventura-sem-ia-paga`

- Migration aditiva com seis tabelas privadas de casos, sessões, personagens, provas, descobertas e interações.
- RLS ativo e sem privilégios diretos para `anon`/`authenticated` nessas tabelas.
- Caso-piloto original **O Último Farol**, com quatro locais, sete suspeitos, um culpado e quatro provas.
- RPCs tokenizadas:
  - `atina_detective_start`: arranque por anfitrião, detetive manual/aleatório, máximo de oito humanos, papéis atribuídos aleatoriamente e lugares de personagens preenchidos por IA local determinística do jogo.
  - `atina_detective_state`: estado filtrado por participante; provas descobertas apenas são devolvidas ao detetive.
  - `atina_detective_move`: valida deslocação para uma localização existente.
  - `atina_detective_discover`: só o detetive pode recolher uma prova e apenas quando está na localização correspondente; valida pré-requisitos configurados.
- O estado público não devolve a solução nem o estado privado das personagens.

## Verificações executadas

Testes SQL transacionais com rollback:
- Arranque de partida e leitura do estado.
- Partida com oito participantes humanos: oito personagens (detetive + sete suspeitos), exatamente um culpado.
- Movimento do detetive entre locais.
- Descoberta de uma prova no local correto.
- Verificação de que outro participante não recebe a lista de provas do detetive.
- Verificação de que a solução não aparece no estado devolvido.
- Os dados temporários de teste foram revertidos; não ficaram sessões de teste na base de dados.

## Ainda não implementado

- Interface 2D integrada no `index.html` do ATINA.
- Movimento gráfico, hotspots clicáveis e animações.
- Interrogatórios ligados ao motor determinístico JavaScript.
- Quadro de pistas, adjunto, cronologia e acusações.
- Fluxo de lobby/convites dedicado e sincronização visual em tempo real.
- Testes automatizados do módulo JavaScript executados num runtime Node.
- Deploy para GitHub Pages.

## Custos

Não existe integração com OpenAI ou outro serviço de IA. As respostas das personagens serão geradas pelo motor determinístico local do ATINA. O Supabase e o alojamento continuam sujeitos às quotas/limites dos planos existentes.
