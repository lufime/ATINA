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
