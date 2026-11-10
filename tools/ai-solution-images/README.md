# Geração local de imagens de solução — ATINA

Este fluxo prepara imagens geradas por IA para os 1.153 desafios ATINA sem recorrer a APIs pagas por imagem.

## Arquitetura

- Modelo: `black-forest-labs/FLUX.1-schnell` (execução local; licença do modelo Apache-2.0).
- Geração: Diffusers + PyTorch numa máquina com GPU NVIDIA compatível.
- Formato: WebP, 768 × 768.
- Armazenamento final: bucket público já existente `atina-challenge-images` no Supabase Storage.
- Integração: o script produz um ficheiro SQL local para atualizar `private.atina_challenges.solution_image_url` e `private.atina_image_assets`.
- O repositório contém ferramentas, não os ficheiros de respostas nem o manifesto privado dos desafios.

A execução local evita custo por chamada de geração. Não significa custo zero de eletricidade, hardware ou espaço. O modelo é grande e a velocidade depende da GPU. Não é executado no GitHub Actions.

## 1. Exportar o manifesto privado

No Supabase Dashboard, abrir SQL Editor e executar:

```sql
select
  challenge_id,
  category,
  answer,
  clues::text as clues,
  array_to_string(image_tags, '|') as image_tags,
  coalesce(image_description, '') as image_description
from private.atina_challenges
order by challenge_id;
```

Exportar o resultado como CSV para:

`tools/ai-solution-images/private/challenges.csv`

**Não fazer commit deste CSV.** Contém respostas e pistas que não devem ser publicadas no frontend nem no GitHub.

## 2. Preparar o computador

Requisitos recomendados: Linux ou Windows com Python 3.10/3.11, GPU NVIDIA com CUDA e memória suficiente para FLUX.1-schnell. O modelo pode ocupar bastante espaço em disco e a geração de 1.153 imagens pode demorar.

Criar um ambiente virtual e instalar:

```bash
python -m venv .venv
# Windows: .venv\\Scripts\\activate
# Linux/macOS: source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r tools/ai-solution-images/requirements.txt
```

O primeiro arranque descarrega o modelo do Hugging Face. A conta/token Hugging Face pode ser necessário conforme as condições de acesso em vigor. Não há API paga de geração neste fluxo.

## 3. Gerar um lote de teste

```bash
python tools/ai-solution-images/generate.py \
  --manifest tools/ai-solution-images/private/challenges.csv \
  --limit 5
```

As imagens são guardadas em `tools/ai-solution-images/generated/`. Verificar manualmente se cada imagem representa a resposta correta antes de gerar o lote completo.

## 4. Gerar as 1.153 imagens

```bash
python tools/ai-solution-images/generate.py \
  --manifest tools/ai-solution-images/private/challenges.csv
```

O script ignora imagens já existentes, permitindo retomar uma execução interrompida. Para regenerar uma imagem, usar `--force --ids 123` com o ID pretendido.

## 5. Enviar para o Supabase Storage

Criar variáveis de ambiente apenas na máquina local (nunca no GitHub):

- `SUPABASE_URL`: URL do projeto ATINA.
- `SUPABASE_SERVICE_ROLE_KEY`: chave secreta de servidor do projeto.

Executar:

```bash
python tools/ai-solution-images/generate.py \
  --manifest tools/ai-solution-images/private/challenges.csv \
  --upload
```

O script envia WebP para `atina-challenge-images/solutions/<challenge_id>.webp` e cria o SQL local:

`tools/ai-solution-images/generated/apply-generated-images.sql`

Executar esse SQL no Supabase SQL Editor depois de rever o lote e aprovar as imagens. O SQL marca os registos como `generated`, não como `approved`, e regista que a revisão humana ainda é necessária.

## 6. Revisão antes de publicar

- Confirmar visualmente a correspondência entre imagem e resposta.
- Regenerar imagens ambíguas, com anatomia/arquitetura incorreta ou texto ilegível.
- Não aprovar imagens de pessoas reais se a representação estiver incorreta.
- Não tratar a licença Apache-2.0 do modelo como uma garantia jurídica universal sobre cada imagem gerada.
- Manter o CSV, os prompts e o SQL com respostas fora do repositório público.

## Segurança

A chave `service_role` tem privilégios elevados. Não a colocar em HTML, JavaScript do browser, ficheiros versionados, issues, logs ou Actions. Se for exposta, rodá-la imediatamente.

O cliente ATINA deve receber o URL da imagem apenas depois de o desafio ser bloqueado/concluído. O catálogo público `solution-images.json` não deve ser preenchido com as 1.153 respostas, porque isso publicaria o gabarito completo.
