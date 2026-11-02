# Geração em massa das imagens ATINA

O workflow `.github/workflows/generate-all-solution-images.yml` executa a Edge Function `atina-generate-solution-images` em lotes retomáveis de 1 a 3 desafios.

## Preparação

Configurar estes GitHub Actions secrets no repositório:

- `SUPABASE_URL`: URL do projeto Supabase de produção.
- `SUPABASE_ANON_KEY`: chave pública/anon do projeto (a função também exige JWT válido porque está com `verify_jwt=true`).
- `ATINA_IMAGE_UPLOAD_TOKEN`: o mesmo segredo configurado na Edge Function. Nunca colocar o valor no código.

A Edge Function também precisa de `OPENAI_API_KEY` configurada nos secrets do Supabase e de acesso ao bucket público `atina-solutions`.

## Execução

1. Abrir Actions → Generate all ATINA solution images.
2. Escolher Run workflow.
3. Escrever exatamente `GENERATE-753` na confirmação.
4. Escolher lote 1, 2 ou 3. Recomenda-se começar por 1 para validar custo, qualidade e tempo.
5. O workflow avança pelo cursor `next_after_challenge_id`, mostra o resultado de cada lote e termina quando a função devolve `done: true`. Se falhar, pode ser executado novamente; começa no primeiro ID se for uma nova execução, por isso verificar primeiro os URLs já gerados.

## Atenção antes de executar em produção

A função atualmente implantada deve ser revista antes da primeira execução: confirmar que o identificador de modelo usado em `https://api.openai.com/v1/images/generations` existe e está habilitado na conta, e que o formato/tamanho pedidos são suportados. Não iniciar a geração dos 753 desafios sem um teste de um único desafio e validação visual.

A função atual atualiza `image_url` assim que cada imagem é gerada e carregada. Isto substitui o URL anterior daquele desafio; não elimina o ficheiro antigo. O workflow não faz rollback automático. Para uma migração sem risco, guardar previamente os URLs antigos e testar primeiro com um desafio não crítico.

A execução pode consumir créditos significativos na API de imagens. O workflow é manual, serial e limitado a 300 chamadas por execução; não é agendado.


## Cópia dos ficheiros para GitHub

O workflow também descarrega cada PNG gerado e cria commits em `images/solutions/<challenge_id>.png` na branch do PR. O `GITHUB_TOKEN` automático recebe permissão `contents: write`; não é necessário criar um PAT.

**Nota:** a função Supabase continua a gravar o URL público do bucket em `image_url`. Esta cópia para o repositório coloca os ficheiros no GitHub, mas não muda automaticamente o jogo para usar GitHub Pages. Essa migração de URLs deve ser feita separadamente depois de confirmar o caminho de publicação pretendido.
