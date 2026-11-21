# ATINA — Instruções permanentes para imagens

**Versão:** 1.1  
**Última atualização:** 21/11/2026

## 1. Projeto e acessos
- GitHub: https://github.com/lufime/ATINA.git
- Supabase: projeto `atina-development`, ref `qvvlqrgbtjujsejvenld`.
- Plataforma: https://lufime.github.io/ATINA/index.html#dashboard
- Gestão: https://lufime.github.io/ATINA/comparar-imagens.html
- Usar GitHub para consultar/alterar código quando solicitado e Supabase para consultar dados reais, quando autorizado. Nunca pedir ou divulgar palavras-passe, tokens ou chaves secretas.

## 2. Consulta
- Consultar a gestão ou Supabase para verificar apenas imagem registada, estado, solução e ID.
- Identificar desafios com e sem imagem; priorizar os que faltam e evitar gerar para os já preenchidos, salvo necessidade concreta.
- Estados: Pending, Approved, Rejected, Broken, Generated e Published.
- Não inventar IDs, soluções, imagens ou estados. Se não houver acesso atual, informar.
- Nesta consulta, não analisar qualidade, autoria, licença ou formato.
- Verificar também se cada desafio está ativo ou desativado. Desafios desativados ficam excluídos da geração, mesmo que não tenham imagem.

## 3. Geração e lotes
- Gerar lotes de 20 imagens, cada lote num ZIP, prosseguindo sem pedir confirmação.
- Se faltarem menos de 20 desafios, gerar apenas os necessários. Nunca inventar desafios para completar lotes.
- Usar apenas desafios e IDs reais. Consultar o estado atual antes de começar.
- Gerar imagens apenas para desafios ativos que ainda precisem de imagem. Nunca gerar, reaproveitar ou incluir num lote imagens destinadas a desafios desativados.
- Se um desafio for desativado durante o trabalho, interromper a geração da respetiva imagem e excluí-lo dos lotes ainda não entregues.
- Retomar do último trabalho concluído, sem repetir imagens nem perder progresso.

## 4. Origem exclusiva
- Utilizar exclusivamente imagens originais geradas aqui para o ATINA.
- Não pesquisar, descarregar, importar ou reutilizar imagens de outros autores, bancos de imagens, sites, páginas ou fontes externas, mesmo que tenham licença ou autorização.
- Todas as imagens finais devem ser criações originais deste processo.

## 5. Reaproveitamento e duplicados
- Se uma imagem não servir para o desafio inicial, verificar se corresponde claramente a outro desafio real ainda sem imagem.
- Reaproveitar apenas com correspondência temática e visual clara; confirmar que o destino não tem imagem e atribuir o ID correto.
- Nunca forçar correspondências nem reutilizar só para completar um lote. Sem correspondência adequada, gerar outra imagem.
- Verificar duplicações com imagens existentes, dentro do lote e entre imagens reaproveitadas. Evitar usar a mesma imagem em vários desafios.
- Registar IDs concluídos, por gerar, em tentativa e reaproveitados.

## 6. Direitos de autor, copyright e propriedade intelectual
Aplicar a filmes, séries, livros, animação, banda desenhada, jogos, marcas e quaisquer obras ou elementos protegidos.
- Todas as imagens finais devem ser criações originais, geradas especificamente para o ATINA.
- Não incluir personagens protegidas por copyright, nem versões redesenhadas, estilizadas, realistas, caricaturadas ou semelhantes que continuem reconhecíveis.
- Não reproduzir objetos icónicos ou distintivos protegidos, adereços exclusivos, itens característicos, símbolos, logótipos, marcas, designs ou elementos identificáveis pertencentes a obras ou terceiros.
- Não copiar cenas específicas, poses, enquadramentos, composições, posters, capas, ilustrações, fotografias ou imagens promocionais.
- Não imitar deliberadamente a assinatura visual de artistas vivos nem replicar uma obra existente.
- Não usar imagens retiradas da Internet, bancos de imagens, outros criadores ou fontes externas, mesmo que aparentem estar licenciadas. Não reutilizar material de terceiros.
- Não assumir que uma imagem gerada por IA é automaticamente livre de direitos, exclusiva ou legalmente irrestrita; evitar elementos que possam infringir direitos de autor, marcas, direitos de imagem ou outros direitos de propriedade intelectual.
- Representar o tema de forma indireta e original, recorrendo a ambientes, paisagens, arquitetura, época, atmosfera, paleta de cores, conceitos e objetos genéricos não protegidos.
- Quando um desafio estiver associado a uma obra protegida, usar referências verificáveis apenas como contexto informativo; nunca copiar personagens, objetos, cenas, ilustrações ou designs da obra.
- Confirmar títulos, autores e relação entre obras quando essa informação for necessária; não inventar referências.
- Preservar a associação clara ao desafio, tema, época ou atmosfera, sem reproduzir a expressão visual distintiva de terceiros.
- Respeitar a linguagem visual adequada (2D, 3D, ilustração ou fotografia cinematográfica); não transformar automaticamente animação em fotorealismo.
- Se algum elemento suscitar dúvidas de copyright, direitos de imagem, marca ou propriedade intelectual, removê-lo e substituí-lo por uma alternativa genérica e original.
- Regra final: a imagem deve ser original, sem personagens nem objetos distintivos protegidos, sem marcas/logótipos e sem cópia reconhecível de obras de terceiros.

## 7. Recusas e correções
- Se a geração for recusada por restrições de conteúdo ou direitos de autor, tentar novamente com alternativas originais.
- Reformular composição e substituir elementos problemáticos, preservando a ligação à obra e à solução. Não insistir nos elementos recusados.
- Continuar a adaptar enquanto as ferramentas permitirem.
- Se a imagem estiver quase correta, corrigir apenas o necessário. Se continuar inadequada, verificar se serve para outro desafio, segundo as regras de reaproveitamento.

## 8. Estilo e composição
- Compreender a solução e o contexto antes de gerar. A imagem deve permitir associar facilmente o que representa à resposta correta.
- Evitar imagens genéricas, bonitas mas sem ligação evidente à solução.
- Sem identidade artística específica, preferir estilo realista e cinematográfico, muito detalhado, cores naturais, iluminação adequada e ambiente coerente.
- Usar um elemento principal identificável.
- Não incluir texto, números, títulos, legendas, rodapés, molduras ou logótipos, salvo quando exigidos.
- Variar composição, perspetiva, iluminação e ambientes, mantendo qualidade consistente.
- Garantir leitura à distância em televisões/ecrãs grandes; evitar detalhes essenciais pequenos e manter elementos importantes afastados das margens.

## 9. Especificações técnicas
Todas as imagens finais devem ser:
- WebP, por conversão obrigatória; 1920 × 1080 píxeis; proporção 16:9.
- Qualidade 85%; perfil sRGB; compressão otimizada.
- Tamanho indicativo 150–350 KB. Pode ultrapassar 350 KB para preservar qualidade; nunca sacrificar qualidade para atingir um tamanho.
- Converter e otimizar antes do ZIP.
- Confirmar que a conversão não provoca desfocagem, pixelização, cores incorretas ou artefactos.
- Garantir nitidez em HD e Full HD, incluindo televisões em ecrã inteiro.

## 10. Autoria
- Autor/responsável: «ATINA»; origem: «Gerado por Inteligência Artificial (IA)»; atribuição: «ATINA».
- Não inventar licenças ou direitos exclusivos. Usar apenas a licença definida pelo ATINA e legalmente aplicável.

## 11. Nomes e ZIP
- Começar cada nome pelo ID real, seguido de hífen e descrição curta. Ex.: `0000-einstein.webp`.
- Preservar zeros à esquerda; não colocar texto antes do ID. Usar o ID da solução representada, inclusive em reaproveitamentos.
- Nomear ZIPs: `ATINA_LOTE_001.zip`, `ATINA_LOTE_002.zip`, etc.
- Colocar imagens diretamente no ZIP, sem pastas desnecessárias, duplicados ou ficheiros alheios.
- Cada imagem final deve ser WebP. Embora a plataforma aceite JPEG e PNG, o formato final do ATINA é WebP.

## 12. Validação e entrega
Antes de entregar cada lote:
- Confirmar que cada ID existe, corresponde à solução, está ativo e ainda precisa de imagem.
- Verificar duplicados com imagens existentes e dentro do lote.
- Validar WebP, 1920 × 1080, 16:9, qualidade 85%, sRGB e integridade.
- Verificar nitidez, cores, composição e qualidade visual em tamanho grande.
- Confirmar nomes e integridade do ZIP. Corrigir ou gerar novamente imagens que falhem.
- Imagens de demonstração só estão prontas após conversão, otimização, nomeação e validação.
- Entregar ZIPs prontos para carregamento.

## 13. Falhas e progresso
- Se a geração ou preparação falhar, aguardar 5 segundos e tentar novamente enquanto as ferramentas permitirem.
- Resolver a imagem que falhou antes de avançar. Retomar da última concluída, sem duplicar trabalho.
- Atualizar o registo após cada imagem/lote; antes de retomar, consultar o estado atual.
- Se for necessária intervenção externa ou o acesso estiver bloqueado, explicar.
- Não afirmar que o trabalho continua em segundo plano ou foi concluído sem confirmação.

## 14. Supabase e comunicação
- Consultar dados reais do Supabase para confirmar desafios, imagens, estados e progresso.
- Não aprovar, publicar, apagar ou alterar registos sem pedido explícito.
- Distinguir imagem gerada, preparada, entregue, carregada, aprovada e publicada. Nunca afirmar um estado sem confirmação.
- Responder em português de Portugal, de forma clara, direta e prática. Evitar perguntas desnecessárias quando as instruções permitem avançar.
- Priorizar correção, reconhecimento visual, prevenção de duplicações e continuidade.

## 15. Respostas numéricas
- Quando a solução de um desafio for numérica, é permitido representar a resposta através de objetos contáveis e/ou do próprio número escrito em algarismos.
- O número apresentado deve corresponder rigorosamente à solução correta.
- Os algarismos devem ser grandes, nítidos, legíveis e visualmente integrados na composição.
- É permitido combinar a representação visual da quantidade com o número escrito.
- Nunca apresentar números incorretos, aproximados ou ambíguos.
- Em desafios de contagem, apresentar exatamente a quantidade indicada na solução.
- Garantir que todos os elementos são identificáveis, distinguíveis e facilmente contáveis.
- Evitar sobreposições, elementos parcialmente ocultos ou composições que dificultem a contagem.
- Em operações matemáticas, respeitar rigorosamente os valores e as relações matemáticas da solução.
- Não confundir o número da resposta com o ID do desafio.
- Não introduzir algarismos, números escritos ou fórmulas na imagem, salvo quando expressamente exigidos pelo desafio.
- Antes de finalizar, verificar que a representação visual corresponde à resposta numérica correta.
- Nunca alterar, arredondar ou aproximar o valor da solução.

## Objetivo
Construir uma biblioteca exclusiva do ATINA, com imagens originais geradas aqui, corretamente associadas aos desafios, reconhecíveis, coerentes com as obras, tecnicamente uniformes e prontas para carregar na plataforma.

## 16. Originalidade, copyright e propriedade intelectual dos desafios
Estas regras aplicam-se a todos os desafios, perguntas, enunciados, respostas, textos, pistas e mecânicas do ATINA.
- Criar perguntas e enunciados originais, redigidos de forma independente para o ATINA.
- É permitido abordar os mesmos temas, factos de conhecimento público, acontecimentos históricos, ciência, geografia, cultura ou obras, desde que a formulação e a apresentação sejam originais.
- Não copiar perguntas, enunciados, textos, diálogos, poemas, pistas, estruturas distintivas ou bases de dados de outros jogos, aplicações, livros, sites, concursos, serviços ou criadores.
- Não reproduzir excertos protegidos de livros, filmes, séries, músicas, diálogos, artigos ou outros materiais. Usar apenas informação factual necessária e escrever de raiz.
- Não copiar desafios de quiz nem os adaptar superficialmente trocando apenas algumas palavras. Recriar a pergunta, abordagem e estrutura de forma independente.
- Não usar marcas ou nomes comerciais de forma a sugerir que o desafio pertence, é patrocinado ou está afiliado a terceiros.
- Factos e respostas devem ser verificáveis, corretos, inequívocos e coerentes com a pergunta. Consultar fontes fiáveis para confirmar factos, mas não copiar a redação dessas fontes.
- Se um desafio estiver relacionado com uma obra protegida, usar referências factuais sobre a obra, sem copiar texto criativo, diálogos, cenas ou conteúdo distintivo.
- Antes de finalizar, verificar originalidade, clareza, resposta correta, ausência de duplicados e semelhança excessiva com desafios conhecidos ou existentes no ATINA.
- Se houver dúvidas sobre copyright ou propriedade intelectual, reescrever o desafio de raiz, preservando apenas o facto ou conceito necessário.
- Quando for solicitado um controlo de desafios existentes, identificar duplicados, formulações muito semelhantes ou conteúdo potencialmente copiado e propor versões originais. Não alterar, apagar ou publicar desafios sem autorização explícita.
- Objetivo: todos os desafios devem ter redação, identidade e apresentação próprias do ATINA, reduzindo riscos de violação de direitos de autor ou propriedade intelectual.

## 17. Avisos, alertas e respostas — estilo visual
Aplicar a todos os avisos, alertas, respostas, notificações, confirmações, inscrições, pagamentos, sessões, estados e mensagens de erro da plataforma.
- Todas as mensagens devem ser curtas, claras, imediatas e fáceis de compreender.
- Apresentar o texto principal em **negrito**.
- Utilizar caixas visuais com estilo de interface de jogo (game UI), com contraste forte, contorno/borda e destaque suficiente para leitura rápida.
- **Verde:** mensagens positivas, sucesso, ações concluídas, confirmações, aprovações e resultados favoráveis.
- **Vermelho:** mensagens negativas, erros, falhas, rejeições, ações não concluídas e problemas que exigem atenção.
- **Amarelo:** mensagens neutras, informativas, avisos, lembretes, instruções e estados sem sucesso ou falha.
- Usar ícones adequados ao tipo de mensagem, sem depender apenas da cor para transmitir significado.
- Garantir contraste, legibilidade e consistência em telemóveis, computadores e ecrãs grandes.
- Manter o mesmo padrão visual e semântico em toda a plataforma; não usar cores contraditórias para o mesmo tipo de estado.
- Classificação padrão: sucesso/positivo = verde; erro/negativo = vermelho; informação/aviso/neutro = amarelo.
- Esta regra define o padrão visual e de apresentação; não altera por si só a lógica, permissões ou estado funcional das ações.


## 18. Documentação sempre atualizada
- A documentação do ATINA deve acompanhar sempre o estado real do jogo e do projeto; nunca deixar instruções sobre modos, funcionalidades, ecrãs, regras ou fluxos que já tenham sido removidos ou alterados.
- Antes de alterar código ou funcionalidades, consultar a documentação relevante e identificar o que poderá ficar desatualizado.
- Ao implementar, remover ou alterar uma funcionalidade, atualizar no mesmo trabalho todos os documentos afetados (FAQ, guia/como jogar, erros conhecidos, notas de versão e outros documentos relevantes).
- Descrever apenas modos, opções e comportamentos que existam atualmente e tenham sido confirmados no código. Não inventar funcionalidades nem apresentar funcionalidades removidas como disponíveis.
- Distinguir erros confirmados de áreas por testar; retirar limitações que deixaram de se aplicar após validação.
- Após a alteração, pesquisar no repositório referências antigas, nomes, navegação, instruções e exemplos relacionados; corrigir inconsistências e links desatualizados.
- Rever os documentos alterados e validar que correspondem à implementação atual antes de concluir o PR
- Sempre que possível, incluir a atualização documental no mesmo PR da alteração funcional, para evitar divergências entre o jogo e a documentação.
- Não fazer merge nem deploy sem autorização explícita.


## 19. Documentação sempre conforme a versão online atual do jogo
- Toda a documentação do ATINA deve estar alinhada com a versão atual publicada online e com as funcionalidades online que estão realmente disponíveis.
- Antes de escrever, atualizar ou validar documentação, confirmar o código atual e, quando acessível, a versão publicada online.
- Documentar apenas modos, regras, menus, opções, fluxos e recursos online que estejam implementados e operacionais na versão atual.
- Não apresentar funcionalidades antigas, removidas, planeadas, experimentais ou indisponíveis como funcionalidades atuais.
- Quando uma alteração ao jogo afetar comportamentos, interface, regras, funcionalidades online, limitações ou procedimentos, atualizar todos os documentos relevantes no mesmo trabalho sempre que possível.
- FAQ, **Como Jogar**, Erros Conhecidos, guias, instruções, notas de versão e restantes documentos devem ser coerentes entre si e com o jogo publicado.
- A página/seção **Como Jogar** deve explicar apenas o funcionamento, modos, regras, controlos e funcionalidades online existentes na versão atual. Rever e atualizar sempre que a experiência de jogo mudar.
- Os Erros Conhecidos devem incluir apenas problemas confirmados na versão atual, distinguindo falhas confirmadas, limitações atuais, aspetos por testar e correções validadas.
- Se não for possível confirmar a versão online ou determinada funcionalidade, indicar a incerteza e não assumir disponibilidade.
- O código atual e a versão online publicada são a referência; a documentação nunca deve contradizer o comportamento real do jogo.
