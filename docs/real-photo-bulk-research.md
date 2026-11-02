# Pesquisa em lote de fotografias reais para o ATINA

O script `scripts/find-real-photo-candidates.mjs` pesquisa candidatos gratuitos na Wikimedia Commons. Não gera imagens, não escreve na base de dados e não publica automaticamente fotografias.

## Preparar a lista privada

Exportar localmente os desafios ativos da tabela privada `private.atina_challenges` com, pelo menos, `challenge_id` e `answer`. Guardar o ficheiro fora do repositório, por exemplo `private-challenges.json`.

Formato:

```json
[
  {
    "challenge_id": 12,
    "answer": "Lisboa",
    "searchTerms": ["Lisbon streets", "Lisbon viewpoint"]
  },
  {
    "challenge_id": 34,
    "answer": "Sherlock Holmes",
    "searchTerms": ["Basil Rathbone Sherlock Holmes", "Sherlock Holmes museum props"]
  },
  {
    "challenge_id": 56,
    "answer": "Atravessar a ponte",
    "searchTerms": ["pedestrian crossing bridge", "person walking across bridge"]
  }
]
```

Os termos adicionais são opcionais e servem para procurar representações contextuais: atores e interpretações de personagens, locais, objetos e situações que materializem uma solução de lógica. Não se deve excluir uma resposta apenas por ser abstrata ou fictícia.

## Executar

Requer Node.js 20 ou superior e ligação à Internet:

```sh
node scripts/find-real-photo-candidates.mjs private-challenges.json
```

O resultado é escrito em `photo-candidates-review.json` no diretório atual. Este ficheiro contém as respostas privadas: não o adicionar ao Git, não o publicar e apagá-lo depois da revisão.

## Critérios e revisão

- Só são considerados JPEG, PNG e WebP.
- Só são aceites licenças Public Domain, CC0, CC BY e CC BY-SA com autor e URL da licença.
- O resultado é uma fila de candidatos, nunca uma aprovação automática.
- Cada fotografia tem de ser aberta e verificada visualmente quanto à identidade, contexto e adequação ao desafio.
- Para personagens, a imagem pode representar uma interpretação/adaptação identificável; para lógica, pode representar o objeto, local ou ação que concretiza a solução.
- A pesquisa textual não prova que a imagem é uma fotografia nem que representa corretamente a resposta. Se houver dúvida, rejeitar o candidato.
- Guardar sempre a página do ficheiro Commons e os dados de atribuição. Não usar apenas o URL direto da imagem como prova da licença.
- Se não houver candidato adequado, deixar a imagem em branco. Nunca preencher por aproximação.

A pesquisa usa a API pública da Wikimedia Commons e é gratuita, sujeita aos limites de utilização do serviço. A lista pode ser processada por lotes reduzidos para respeitar esses limites.
