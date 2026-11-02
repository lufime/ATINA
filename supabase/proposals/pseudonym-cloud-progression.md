# Progressão na nuvem por pseudónimo — proposta

Esta implementação foi aplicada e testada apenas em `atina-development`. **Não foi aplicada** a `atina-ranking` nem a qualquer ambiente de produção.

## Identidade

- Não cria utilizadores Supabase Auth.
- Não pede email nem palavra-passe.
- O dispositivo gera uma chave aleatória de 256 bits.
- A base de dados guarda apenas SHA-256 da chave, nunca o segredo em claro.
- O pseudónimo é apenas o nome público; a chave é a credencial que impede terceiros de alterar a progressão desse jogador.
- Sem cópia da chave, a recuperação entre dispositivos não é possível. A interface explica e permite exportar um código de recuperação sem email.
- Se o pseudónimo já existir no dispositivo e a chave tiver desaparecido, a interface exige recuperação; não cria silenciosamente uma identidade nova.

## Integridade da progressão

- O browser não envia XP nem pontuação.
- Cada sessão individual fica ligada ao jogador no arranque; a RPC de XP usa apenas essa associação e não aceita um token de jogador escolhido pelo cliente.
- Só uma ronda bloqueada com resultado `correct` dá XP.
- O evento é único por jogador/sessão/posição, evitando duplicação por refresh ou retry.
- O terceiro desafio correto do dia atribui 60 XP no total (10 XP + bónus de 50), apenas uma vez por dia.
- O XP cloud está ativo apenas em Solo e Mix. Duelo e Party não atribuem a um único pseudónimo os resultados de vários participantes.
- As tabelas ficam no schema privado, com RLS e sem grants diretos a anon/authenticated.
- As RPCs usam `SECURITY DEFINER`, `search_path = ''`, validação explícita e grants restritos.
- O hook PostgREST de rate limiting já instalado aplica 30 pedidos/minuto por IP e por RPC ATINA, por omissão, e falha fechado se não conseguir identificar a origem.

## Testes e estado

- Replay de migrações, validação do banco e upgrade do esquema legado foram aprovados no PR.
- 12 verificações pgTAP passaram.
- Teste transacional no ambiente de desenvolvimento confirmou associação sessão/jogador, XP único e ausência de associação individual em Duelo.
- Advisors: os índices duplicados e a FK sem índice foram corrigidos; os avisos restantes de funções `SECURITY DEFINER` correspondem às RPCs ATINA intencionalmente expostas e aos avisos já existentes no projeto.

## Antes de produção

1. Rever a experiência de recuperação e a política de retenção dos pseudónimos.
2. Integrar progressão individual em Duelo, Party, modos online e Mímicas, com identidade por participante.
3. Fazer revisão final de segurança e performance.
4. Pedir autorização específica antes de aplicar qualquer alteração em `atina-ranking`.

Não fazer deploy nem tocar em `atina-ranking` sem autorização específica.
