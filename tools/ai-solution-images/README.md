## Alternativa: executar no Kaggle pelo telemóvel

Foi criado um notebook específico para o Kaggle: `tools/ai-solution-images/ATINA-Kaggle.ipynb`. Abre [o ficheiro no GitHub](https://github.com/lufime/ATINA/blob/feature/ai-solution-images/tools/ai-solution-images/ATINA-Kaggle.ipynb), descarrega o `.ipynb` (botão Raw / Download raw) e, no Kaggle, cria um Notebook e usa **File → Import Notebook** para carregar esse ficheiro. Mantém o notebook privado.

Nas definições do notebook, ativa **Internet** e seleciona **Accelerator → GPU**, se houver uma disponível. O Kaggle documenta GPU NVIDIA P100 gratuita, mas a disponibilidade e a quota semanal são limitadas e pode existir fila. Referência: [Kaggle Notebooks](https://www.kaggle.com/docs/notebooks) e [Efficient GPU Usage](https://www.kaggle.com/docs/efficient-gpu-usage).

Carrega o CSV apenas como input privado em **Input → Add Input → Upload** ou associa um dataset privado. Nunca publiques o CSV. Para upload ao Supabase, configura `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` em **Add-ons → Secrets** e ativa o acesso ao notebook. Não escrevas a chave em células.

## Usar pelo Google Colab (incluindo telemóvel)

Foi preparado um notebook para executar o fluxo no Google Colab:

`tools/ai-solution-images/ATINA-Colab.ipynb`

Abre-o em [Google Colab](https://colab.research.google.com/github/lufime/ATINA/blob/feature/ai-solution-images/tools/ai-solution-images/ATINA-Colab.ipynb). O notebook pede o CSV privado exportado do Supabase, monta o Google Drive para guardar o progresso e lê `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` a partir de Colab Secrets. Não coloques a chave no notebook nem a partilhes.

O Colab gratuito pode não disponibilizar GPU em todas as sessões e pode interromper execuções longas. O notebook foi preparado para retomar imagens já guardadas no Drive; a primeira execução deve ser apenas um teste de 5 imagens.

# Geração local de imagens de solução — ATINA

Este fluxo prepara imagens geradas por IA para os 1.153 desafios ATINA sem recorrer a APIs pagas por imagem.

## Arquitetura

- Modelo: `stable-diffusion-v1-5/stable-diffusion-v1-5` (execução local; licença CreativeML OpenRAIL-M).
- Geração: Diffusers + PyTorch numa máquina com GPU NVIDIA compatível.
- Formato: WebP, 512 × 512 por omissão (fallback automático para 384 × 384 em caso de falta de VRAM).
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

Requisitos: Python 3.10/3.11 e GPU NVIDIA com CUDA. Para a Tesla T4 (16 GB), o script usa Stable Diffusion 1.5 em FP16, `enable_model_cpu_offload()` e attention slicing. É uma configuração mais leve do que FLUX, embora a disponibilidade de memória dependa também das outras células do notebook. A geração de 1.153 imagens pode demorar bastante.

Criar um ambiente virtual e instalar:

```bash
python -m venv .venv
# Windows: .venv\\Scripts\\activate
# Linux/macOS: source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r tools/ai-solution-images/requirements.txt
```

O primeiro arranque descarrega Stable Diffusion 1.5 do Hugging Face. A Tesla T4 usa FP16, offload de componentes para CPU e attention slicing. O modelo é público; se o Hugging Face pedir autenticação, configura um token Read como Secret `HF_TOKEN`. Não há API paga de geração neste fluxo.

## 3. Gerar um lote de teste

```bash
python tools/ai-solution-images/generate.py \
  --manifest tools/ai-solution-images/private/challenges.csv \
  --limit 5
```

As imagens são guardadas em `tools/ai-solution-images/generated/`. Verificar manualmente se cada imagem representa a resposta correta antes de gerar o lote completo.

## 4. Gerar as 1.153 imagens em lotes

Depois de validar as 5 imagens, executar em lotes (por exemplo, 25–50 IDs de cada vez) e manter o diretório `generated/images` persistente entre sessões. O script retoma automaticamente os ficheiros já criados.



```bash
python tools/ai-solution-images/generate.py \
  --manifest tools/ai-solution-images/private/challenges.csv
```

O script ignora imagens já existentes, permitindo retomar uma execução interrompida. Para regenerar uma imagem, usar `--force --ids 123` com o ID pretendido. Na Tesla T4, começa sempre com `--limit 5`. O script usa prompts curtos, 25 passos, 512 × 512 e limpa a cache CUDA após cada imagem. Se ocorrer OOM, tenta novamente a 384 × 384. Para testar outra resolução, define `ATINA_IMAGE_RESOLUTION` no ambiente (por exemplo `384`).

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
