# Auditoria global de qualificação dos desafios ATINA

**Data:** 25/11/2026  
**Fonte de dados:** Supabase produção `atina-development` (`qvvlqrgbtjujsejvenld`)  
**Âmbito:** todos os desafios ativos e inativos; classificação geográfica, campos editoriais, dificuldade e filtro.

## 1. Integridade do catálogo

| Verificação | Resultado |
|---|---:|
| Desafios totais | 1089 |
| Ativos / inativos | 1.044 / 45 |
| Sem resposta | 0 |
| Sem pistas ou pistas inválidas | 0 |
| Sem descrição da solução | 0 |
| Sem dificuldade | 0 |
| Classificação geográfica vazia ou inválida | 0 |
| IDs sem correspondência entre catálogo CSV e produção | 0 |

Todos os 1.089 registos têm uma categoria geográfica e um nível de dificuldade preenchidos. Isto confirma integridade dos campos, não valida por si só a fundamentação factual de cada classificação nem a calibração editorial de cada nível.

## 2. Classificação geográfica na produção

| Categoria | Todos os desafios |
|---|---:|
| Portugal | 47 |
| Internacional | 660 |
| Universal | 382 |
| **Total** | **1.089** |

A função pública de leitura usada pelo jogo devolve apenas os desafios ativos: **Portugal 44, Internacional 625, Universal 375 (total 1.044)**.

### Divergências entre CSV e produção

Foram encontradas **177 divergências** entre o ficheiro `.atina-interno/classificacao-tematica-desafios.csv` e a classificação atual da produção. Todas têm o mesmo ID nos dois lados; não há registos em falta nem IDs extra.

| ID | Solução | Categoria anterior no CSV | Categoria atual na produção |
|---:|---|---|---|
| 12 | Futebol | Universal | Internacional |
| 36 | Ténis | Universal | Internacional |
| 37 | Maratona | Universal | Internacional |
| 50 | Fotografia | Universal | Internacional |
| 60 | Triatlo | Universal | Internacional |
| 135 | Saudade | Internacional | Portugal |
| 140 | Ornitorrinco | Universal | Internacional |
| 161 | Râguebi | Universal | Internacional |
| 180 | Polo aquático | Universal | Internacional |
| 185 | Binóculos | Universal | Internacional |
| 195 | Atletismo | Universal | Internacional |
| 200 | Sextante | Universal | Internacional |
| 210 | Ciclismo | Universal | Internacional |
| 229 | Microscópio | Universal | Internacional |
| 254 | Girafa | Universal | Internacional |
| 255 | Panda-gigante | Universal | Internacional |
| 257 | Pavão | Universal | Internacional |
| 258 | Coala | Universal | Internacional |
| 260 | Urso-polar | Universal | Internacional |
| 263 | Camaleão | Universal | Internacional |
| 264 | Zebra | Universal | Internacional |
| 265 | Guaxinim | Universal | Internacional |
| 266 | Elefante | Universal | Internacional |
| 267 | Leopardo | Universal | Internacional |
| 270 | Tucano | Universal | Internacional |
| 271 | Camelo | Universal | Internacional |
| 272 | Baobá | Universal | Internacional |
| 327 | Fernão de Magalhães | Internacional | Portugal |
| 393 | Rádio | Universal | Internacional |
| 404 | Frigorífico | Universal | Internacional |
| 406 | Bicicleta | Universal | Internacional |
| 417 | Rato de computador | Universal | Internacional |
| 539 | Tabela periódica | Universal | Internacional |
| 544 | Teatro | Universal | Internacional |
| 563 | Câmara fotográfica | Universal | Internacional |
| 566 | Televisão | Universal | Internacional |
| 599 | O dominó | Universal | Internacional |
| 600 | O xadrez | Universal | Internacional |
| 614 | O zero | Universal | Internacional |
| 616 | Acordeão | Universal | Internacional |
| 617 | Clarinete | Universal | Internacional |
| 618 | Oboé | Universal | Internacional |
| 620 | Fagote | Universal | Internacional |
| 622 | Trombone | Universal | Internacional |
| 623 | Tuba | Universal | Internacional |
| 625 | Contrabaixo | Universal | Internacional |
| 626 | Viola de arco | Universal | Internacional |
| 627 | Violoncelo | Universal | Internacional |
| 629 | Marimba | Universal | Internacional |
| 630 | Xilofone | Universal | Internacional |
| 631 | Órgão | Universal | Internacional |
| 632 | Bandolim | Universal | Internacional |
| 633 | Ukulele | Universal | Internacional |
| 640 | Ópera | Universal | Internacional |
| 641 | Musical | Universal | Internacional |
| 642 | Sinfonia | Universal | Internacional |
| 644 | Sonata | Universal | Internacional |
| 645 | Fuga | Universal | Internacional |
| 646 | Contraponto | Universal | Internacional |
| 691 | Andebol | Universal | Internacional |
| 692 | Voleibol | Universal | Internacional |
| 693 | Badminton | Universal | Internacional |
| 694 | Squash | Universal | Internacional |
| 695 | Golfe | Universal | Internacional |
| 696 | Hóquei em patins | Universal | Internacional |
| 697 | Hóquei no gelo | Universal | Internacional |
| 698 | Basebol | Universal | Internacional |
| 699 | Softbol | Universal | Internacional |
| 700 | Críquete | Universal | Internacional |
| 701 | Polo | Universal | Internacional |
| 702 | Esgrima | Universal | Internacional |
| 706 | Boxe | Universal | Internacional |
| 707 | Luta greco-romana | Universal | Internacional |
| 709 | Surf | Universal | Internacional |
| 710 | Windsurf | Universal | Internacional |
| 711 | Kitesurf | Universal | Internacional |
| 715 | BTT | Universal | Internacional |
| 716 | BMX | Universal | Internacional |
| 717 | Esqui alpino | Universal | Internacional |
| 718 | Snowboard | Universal | Internacional |
| 719 | Patinagem artística | Universal | Internacional |
| 720 | Ginástica artística | Universal | Internacional |
| 721 | Ginástica rítmica | Universal | Internacional |
| 722 | Trampolins | Universal | Internacional |
| 723 | Pentatlo moderno | Universal | Internacional |
| 724 | Decatlo | Universal | Internacional |
| 725 | Heptatlo | Universal | Internacional |
| 726 | Marcha atlética | Universal | Internacional |
| 727 | Orientação | Universal | Internacional |
| 802 | Axolote | Universal | Internacional |
| 803 | Narval | Universal | Internacional |
| 804 | Pangolim | Universal | Internacional |
| 805 | Ocapi | Universal | Internacional |
| 806 | Fossa | Universal | Internacional |
| 807 | Suricata | Universal | Internacional |
| 808 | Kiwi | Universal | Internacional |
| 809 | Diabo-da-Tasmânia | Universal | Internacional |
| 811 | Albatroz-errante | Universal | Internacional |
| 813 | Salamandra-de-fogo | Universal | Internacional |
| 814 | Pavão-indiano | Universal | Internacional |
| 815 | Dugongo | Universal | Internacional |
| 816 | Sapo-parteiro | Universal | Internacional |
| 817 | Arara-azul-grande | Universal | Internacional |
| 818 | Celacanto | Universal | Internacional |
| 820 | Órix-de-cimitarra | Universal | Internacional |
| 821 | Panda-vermelho | Universal | Internacional |
| 822 | Rinoceronte-negro | Universal | Internacional |
| 823 | Aie-aie | Universal | Internacional |
| 824 | Cacatua-de-crista-amarela | Universal | Internacional |
| 825 | Avestruz | Universal | Internacional |
| 826 | Tatu-bola | Universal | Internacional |
| 827 | Capivara | Universal | Internacional |
| 828 | Canguru-vermelho | Universal | Internacional |
| 829 | Vombate | Universal | Internacional |
| 830 | Equidna | Universal | Internacional |
| 831 | Camelo-bactriano | Universal | Internacional |
| 832 | Dromedário | Universal | Internacional |
| 833 | Calau-rinoceronte | Universal | Internacional |
| 834 | Peixe-serra | Universal | Internacional |
| 835 | Nautilus | Universal | Internacional |
| 844 | Formiga-cortadeira | Universal | Internacional |
| 845 | Polvo-mímico | Universal | Internacional |
| 847 | Peixe-pedra | Universal | Internacional |
| 848 | Peixe-palhaço-de-Clark | Universal | Internacional |
| 849 | Morsa | Universal | Internacional |
| 850 | Boi-almiscarado | Universal | Internacional |
| 851 | Saiga | Universal | Internacional |
| 902 | Transístor | Universal | Internacional |
| 904 | Impressão 3D | Universal | Internacional |
| 906 | Fibra ótica | Universal | Internacional |
| 907 | Bluetooth | Universal | Internacional |
| 908 | Código de barras | Universal | Internacional |
| 909 | Bateria de iões de lítio | Universal | Internacional |
| 910 | Microchip | Universal | Internacional |
| 911 | Robô industrial | Universal | Internacional |
| 912 | Realidade aumentada | Universal | Internacional |
| 913 | Realidade virtual | Universal | Internacional |
| 914 | Computação em nuvem | Universal | Internacional |
| 915 | Inteligência artificial | Universal | Internacional |
| 916 | Aprendizagem automática | Universal | Internacional |
| 918 | Impressora laser | Universal | Internacional |
| 919 | Ecrã tátil | Universal | Internacional |
| 920 | Drone | Universal | Internacional |
| 921 | Painel solar fotovoltaico | Universal | Internacional |
| 922 | USB | Universal | Internacional |
| 923 | Wi-Fi | Universal | Internacional |
| 924 | NFC | Universal | Internacional |
| 927 | Navegador web | Universal | Internacional |
| 928 | Computador quântico | Universal | Internacional |
| 929 | Lâmpada LED | Universal | Internacional |
| 931 | Satélite artificial | Universal | Internacional |
| 932 | Foguetão | Universal | Internacional |
| 934 | Radar | Universal | Internacional |
| 935 | Sonar | Universal | Internacional |
| 936 | Máquina de escrever | Universal | Internacional |
| 937 | Fotografia digital | Universal | Internacional |
| 940 | Telégrafo elétrico | Universal | Internacional |
| 941 | Semáforo de trânsito | Universal | Internacional |
| 942 | Relógio atómico | Universal | Internacional |
| 943 | GPS diferencial | Universal | Internacional |
| 944 | Reconhecimento ótico de caracteres | Universal | Internacional |
| 945 | eSIM | Universal | Internacional |
| 946 | Impressão offset | Universal | Internacional |
| 947 | Código binário | Universal | Internacional |
| 948 | Protocolo HTTP | Universal | Internacional |
| 949 | Endereço IP | Universal | Internacional |
| 950 | Código de barras bidimensional Data Matrix | Universal | Internacional |
| 1167 | Frigorífico | Universal | Internacional |
| 1173 | Máquina de lavar roupa | Universal | Internacional |
| 1181 | Televisão | Universal | Internacional |
| 1182 | Computador pessoal | Universal | Internacional |
| 1184 | Motor elétrico | Universal | Internacional |
| 1185 | Turbina eólica | Universal | Internacional |
| 1188 | Câmara digital | Universal | Internacional |
| 1192 | Aço inoxidável | Universal | Internacional |
| 1195 | Câmara escura | Universal | Internacional |
| 1198 | Díodo emissor de luz | Universal | Internacional |

O CSV foi sincronizado com os valores atuais da produção e os 177 registos ficaram explicitamente marcados como **pendentes de validação histórica individual**. A sincronização documental não significa que a fundamentação de cada um esteja já confirmada por fontes primárias.

## 3. Dificuldade

| Nível | Total |
|---|---:|
| Fácil | 472 |
| Médio | 599 |
| Difícil | 18 |

A distribuição mostra apenas **18 desafios Difíceis** em 1.089. Não se deve impor uma quota, mas é um sinal para auditoria editorial: confirmar se os níveis correspondem ao raciocínio exigido e à progressão das pistas.

### Desafios atualmente marcados como Difíceis — rever a calibração

- ID 8 — 48 (Lógica e números; Universal)
- ID 15 — Nelson Mandela (Quem sou eu?; Internacional)
- ID 41 — Coliseu (Imagem misteriosa; Internacional)
- ID 42 — Taj Mahal (Imagem misteriosa; Internacional)
- ID 44 — Leão (Imagem misteriosa; Universal)
- ID 46 — Baleia (Imagem misteriosa; Universal)
- ID 49 — Istambul (Onde estou?; Internacional)
- ID 54 — Hino nacional (Cultura geral; Portugal)
- ID 60 — Triatlo (Desporto; Internacional)
- ID 61 — 2 euros (Ilusões e truques mentais; Universal)
- ID 62 — As portas com números quadrados perfeitos (Lógica e números; Universal)
- ID 178 — The Beatles (Música e sons; Internacional)
- ID 195 — Atletismo (Desporto; Internacional)
- ID 210 — Ciclismo (Desporto; Internacional)
- ID 217 — ADN (Ciência e natureza; Universal)
- ID 342 — Muhammad Ali (Quem sou eu?; Internacional)
- ID 441 — Manuscrito Voynich (História e mistérios; Internacional)
- ID 459 — Erupção do Tambora (História e mistérios; Internacional)

A lista é uma seleção para revisão, não uma declaração de que estes 18 níveis estão errados. Também será necessário amostrar níveis Fácil e Médio para detetar erros nos dois sentidos; esta auditoria não altera dificuldades na produção.

## 4. Filtro geográfico no jogo

Verificações realizadas no código e na produção:
- O jogo carrega os IDs e categorias através de `atina_public_challenge_geographic_scopes()`.
- A interface só ativa o seletor depois de validar a resposta da função; em caso de falha, desativa o filtro e regressa a “Todos”.
- A seleção geográfica é aplicada à fila local de **Solo e Mix** antes de iniciar a partida.
- A produção contém a sobrecarga server-side de `atina_v2_start_local_game` que recebe e valida `p_geographic_scope` e restringe a seleção.
- A proposta de teste SQL para o filtro server-side existe no repositório; não foi executada contra produção, para não criar sessões nem dados de teste.

A validação automatizada do código e dos testes de browser será feita pelo CI do PR. Não foi criada uma sessão de jogo na produção durante esta auditoria.

## 5. Alterações preparadas

- Atualização do CSV para corresponder aos 1.089 valores atuais da produção.
- Nova migração de reconciliação idempotente para que uma instalação nova reproduza os 177 valores corrigidos; não reescreve linhas que já estejam corretas.
- Teste atualizado para validar a classificação final após as migrações base e de reconciliação.
- CI passa a executar o teste de classificação geográfica.
- Instruções oficiais passam a incluir critérios explícitos de calibração da dificuldade.

## 6. Limites e salvaguardas

- Nenhum desafio foi apagado.
- Nenhuma resposta, pista ou dificuldade foi alterada na produção.
- Nenhuma migração foi executada na produção.
- Nenhuma sessão de jogo foi criada para testar o filtro.
- As 177 justificações históricas permanecem pendentes de validação individual; os campos estão sincronizados, mas não se declara a auditoria factual concluída.
