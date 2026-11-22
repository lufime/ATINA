# ATINA — Procedimento de Merge e Deploy

## Objetivo
Quando uma tarefa de código estiver concluída, não parar na branch ou no CI: avançar até merge, deploy e verificação final sempre que isso seja seguro, aplicável e permitido.

## Fluxo obrigatório
1. **Implementar isoladamente:** trabalhar numa branch apropriada; evitar alterações fora do âmbito.
2. **Validar:** executar os checks, CI e testes relevantes. Analisar logs e corrigir falhas antes de avançar.
3. **Merge:** quando todos os checks obrigatórios estiverem verdes, não houver bloqueios/regressões conhecidos e as restrições da tarefa permitirem, fazer merge para a branch de destino.
4. **Deploy:** após o merge, executar o deploy pelo procedimento/plataforma oficial aplicável, quando necessário e permitido.
5. **Pós-deploy:** verificar estado do deploy, funcionamento da aplicação e regressões relevantes. Se houver falhas, investigar, corrigir e repetir validação.
6. **Relatório final:** comunicar branch/PR, commit, CI, merge, deploy e resultado da verificação pós-deploy. Não declarar qualquer etapa concluída sem confirmação real.

## Bloqueios e segurança
- Restrições explícitas da tarefa/PR (por exemplo, «sem merge», «sem deploy», «apenas branch isolada») prevalecem e devem ser respeitadas.
- Checks obrigatórios falhados, conflitos, revisões obrigatórias, riscos conhecidos ou regressões bloqueiam merge/deploy até resolução.
- **Supabase `atina-development` é produção.** Não executar migrations, alterações de dados, operações destrutivas ou alterações de configuração em produção sem autorização explícita.
- **Não utilizar Render.**
- Nunca contornar CI, proteções da branch, revisões, permissões ou políticas de segurança para acelerar o processo.

## Regra padrão
**CI verde e tarefa permitida → Merge → Deploy (se aplicável) → Verificação pós-deploy → Relatório final.**
