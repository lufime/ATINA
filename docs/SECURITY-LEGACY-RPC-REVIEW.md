# Revisão de compatibilidade — RPCs multiplayer antigas

## Estado

Esta branch contém apenas uma proposta documental de revisão. Não altera SQL, permissões, migrações executáveis, nem qualquer projeto Supabase.

## Problema observado

Na auditoria read-only do projeto `atina-ranking`, foi observada uma função pública antiga:

```sql
public.atina_submit_room_answer(
  p_room_id uuid,
  p_token text,
  p_challenge integer,
  p_correct boolean,
  p_points integer
)
```

A implementação observada aceita a decisão de correção e os pontos fornecidos pelo cliente. A validação de token limita o jogador que pode invocar a função, mas não transforma esses parâmetros em resultados autoritativos do servidor.

O código/migração mais recente do repositório define a interface segura com outra assinatura:

```sql
public.atina_submit_room_answer(
  p_room_id uuid,
  p_token text,
  p_answer text
)
```

Essa implementação compara a resposta com os dados privados no servidor e calcula a pontuação no servidor.

**Conclusão provisória:** existe divergência entre o estado remoto observado e o contrato esperado no código. Não assumir que aplicar uma migração isolada resolve a divergência.

## Plano de correção em fases

1. **Inventário read-only**
   - Confirmar todas as sobrecargas da função em `pg_proc`, incluindo argumentos, proprietário, `prosecdef`, configuração de `search_path` e ACL.
   - Inventariar funções antigas relacionadas com publicação de estado, propostas de equipa e resolução de Mímicas.
   - Procurar chamadas no frontend atual, branches suportadas, versões em cache e clientes móveis, se existirem.
   - Confirmar a cadeia de migrações registada no projeto e comparar com os ficheiros e respetivos checksums.

2. **Compatibilidade**
   - Identificar clientes ativos que ainda possam invocar a assinatura antiga.
   - Definir uma janela de transição e telemetria para chamadas antigas, sem registar tokens ou respostas sensíveis.
   - Não substituir nem remover a assinatura antiga enquanto a compatibilidade não estiver demonstrada.

3. **Migração proposta (ainda não autorizada para produção)**
   - Preparar uma migração explícita e reversível, com assinaturas totalmente qualificadas.
   - Revogar apenas o privilégio `EXECUTE` da assinatura insegura específica, depois de confirmar que não há dependências legítimas.
   - Preservar a RPC segura `(uuid, text, text)` e confirmar as permissões esperadas para `anon` e `authenticated`.
   - Evitar `DROP FUNCTION` genérico que possa atingir uma sobrecarga diferente.

4. **Testes em ambiente descartável**
   - Confirmar que a assinatura antiga não pode ser executada por `anon`/ `authenticated` após a migração.
   - Confirmar que a assinatura segura aceita texto e calcula correção/pontos no servidor.
   - Confirmar que token inválido, jogador de outra sala, resposta demasiado longa e sala inativa são rejeitados.
   - Confirmar que as restantes RPCs multiplayer e Mímicas continuam a funcionar.
   - Executar os testes de browser e de regressão antes de propor qualquer rollout.

5. **Rollout**
   - Aplicar primeiro num ambiente de desenvolvimento reconciliado.
   - Observar erros e compatibilidade antes de preparar a mudança para produção.
   - A aplicação em produção exige autorização explícita e plano de rollback.

## Bloqueios conhecidos

- A auditoria remota é read-only; não foi executado SQL de alteração.
- Os projetos de desenvolvimento e produção têm históricos de migrações divergentes.
- A execução E2E mais recente confirmou o teste das RPCs, mas falhou no teste da interface ao esperar a transição de feedback após uma resposta errada. Esta falha deve ser resolvida antes de usar a suite como critério de aprovação.
- A migração não deve ser considerada pronta para produção enquanto não houver uma cadeia de migrações reconciliada e uma suite de regressão verde.

## Critério de conclusão

A correção só fica pronta quando a assinatura insegura deixa de estar executável pelos papéis públicos, a assinatura segura permanece funcional, as sessões compatíveis não são interrompidas e os testes relevantes passam num Supabase descartável.
