# Biblioteca de imagens de solução do ATINA

As imagens de revelação são registadas em `solution-images.json`. O catálogo é consultado pela resposta canónica e pelos aliases exatos; não deve ser usado para revelar pistas antes de a ronda terminar.

Cada registo em `images` deve conter:

- `challengeId`: identificador da ficha (recomendado para auditoria).
- `answer`: resposta canónica exata.
- `aliases`: nomes alternativos exatos (opcional).
- `image`: caminho local, por exemplo `./assets/solution-images/abelha.jpg`, ou URL HTTPS direta de `upload.wikimedia.org/wikipedia/commons/`.
- `author`: autor/fotógrafo ou atribuição transparente quando não está identificado.
- `license`: licença explícita.
- `licenseUrl`: URL HTTPS da licença.
- `sourceUrl`: página original da imagem (recomendado).
- `sourceName`: origem, por exemplo `Wikimedia Commons`.
- `width`, `height`: dimensões da imagem.
- `title`: descrição curta e específica.

Só adicionar imagens cuja correspondência com a resposta, origem, licença e disponibilidade tenham sido verificadas. A atribuição deve ser apresentada junto da imagem. Não usar imagens genéricas quando a resposta exige um objeto, pessoa, local ou conceito específico.

A biblioteca tem prioridade. Se não houver correspondência exata, o jogo tenta Wikimedia Commons e mantém a validação de relevância/licença. Se nenhuma fonte for segura, não apresenta imagem.

As referências externas do piloto apontam para os ficheiros originais no Wikimedia Commons; não são cópias binárias alojadas no repositório. Se o projeto passar a alojar cópias locais, manter a atribuição e respeitar as condições de partilha pela mesma licença (ShareAlike).
