# Biblioteca própria de imagens do ATINA

As imagens verificadas são registadas em `solution-images.json` e guardadas em `assets/solution-images/`.

Cada registo em `images` deve conter:

- `answer`: resposta canónica do desafio.
- `aliases`: nomes alternativos exatos (opcional).
- `image`: caminho relativo, por exemplo `./assets/solution-images/abelha.jpg`.
- `author`: autor/criador da imagem.
- `license`: licença explícita (por exemplo, CC BY-SA 4.0 ou criação própria).
- `licenseUrl`: URL HTTPS da licença.
- `sourceUrl`: página de origem/crédito (opcional; recomendado).
- `width`, `height`: dimensões (opcionais).
- `title`: descrição curta (opcional).

Só adicionar imagens cuja utilização e licença tenham sido verificadas. Para imagens próprias, usar `license: "Criação própria do ATINA"` e uma página HTTPS do projeto como `licenseUrl`.

A biblioteca tem prioridade. Se não houver correspondência exata, o jogo tenta Wikimedia Commons e mantém a validação de relevância/licença. Se nenhuma fonte for segura, não apresenta imagem.

## Ilustrações originais incluídas

Os ficheiros `abelha.svg`, `regua.svg` e `fio-de-ariadne.svg` são ilustrações esquemáticas criadas para o ATINA. Não são fotografias nem reproduções históricas. Estão identificados no catálogo como **«Ilustração original — uso no projeto ATINA»**. Esta indicação não concede automaticamente uma licença de reutilização a terceiros; qualquer licença pública adicional deve ser decidida pelos responsáveis do projeto.

O suporte a SVG aplica-se apenas a ficheiros locais referenciados no catálogo. A pesquisa externa continua sujeita à validação anterior.
