# Auditoria e plano de reconstrução da interface ATINA

**Versão do jogo:** não identificada  
**Última atualização:** 26/11/2026  
**Âmbito:** interface do jogo e páginas administrativas

## 1. Inventário confirmado

### Aplicação principal

A experiência dos jogadores está concentrada em `index.html`, organizada como aplicação de página única. A navegação principal contém estas 11 áreas:

1. Início
2. Jogar
3. Modos
4. Online
5. Como jogar
6. Perfil
7. Classificação
8. Definições
9. Amigos
10. FAQ
11. Bugs conhecidos

Os modos, o ecrã de desafio, a experiência online, os resultados, as classificações e os painéis auxiliares são componentes/estados dentro de `index.html`, não páginas HTML independentes.

### Administração

Foram identificadas estas páginas HTML:

- `administrator.html` — painel administrativo principal, com áreas de início, gestão/envio de imagens, logótipo, jogadores, catálogo de desafios, reportes e explorador da base de dados.
- `admin-gestao-imagens.html` — gestão de imagens.
- `admin-envio-imagens.html` — envio de imagens.
- `admin-jogadores.html` — área de jogadores.
- `admin-logotipo.html` — encaminhamento para a área de logótipo em `administrator.html#logo`.
- `comparar-imagens.html` — pesquisa, filtragem, comparação e gestão de imagens.

Existem ainda páginas de diagnóstico e protótipos em `error-report-admin-diagnostic.html` e `prototypes/`; não fazem parte da navegação normal do jogo.

## 2. Constatações iniciais

- A aplicação principal já carrega o sistema visual `assets/atina-ui-system-2026.css`. A sua camada de estilos contém regras acumuladas para navegação, páginas, experiência de jogo e HUD; qualquer consolidação deve ser feita com testes de regressão, sobretudo no cronómetro e nos indicadores.
- As páginas administrativas repetem grandes blocos de CSS local e apresentam diferenças de largura, navegação, cartões, campos e grelhas.
- A administração tem uma página central e páginas especializadas/legadas. A navegação e os pontos de entrada devem manter-se funcionais durante a harmonização.
- A interface tem de funcionar em Mobile, Tablet e Desktop, sem scroll horizontal involuntário, sobreposições ou perda de controlos.

## 3. Implementação incluída nesta fase

Foi criado `assets/atina-admin-ui-2026.css`, uma camada visual partilhada para as páginas administrativas, e ligada a:

- `administrator.html`
- `admin-gestao-imagens.html`
- `admin-envio-imagens.html`
- `admin-jogadores.html`
- `comparar-imagens.html`

A camada uniformiza identidade visual, cabeçalhos, navegação, painéis, estatísticas, formulários, botões, cartões e grelhas responsivas. Não altera IDs, eventos, scripts, autenticação, permissões, consultas ou operações de dados.

## 4. Próximas fases

1. Rever e reorganizar cada área da aplicação principal, preservando a lógica existente.
2. Consolidar cuidadosamente as regras visuais acumuladas sem regressões na página de desafios.
3. Harmonizar a navegação entre áreas e reduzir scroll desnecessário, sem esconder informação ou controlos.
4. Rever todas as áreas administrativas e os estados de autenticação, carregamento, sucesso e erro.
5. Validar Mobile estreito, Mobile comum, Tablet e Desktop.
6. Executar os testes disponíveis e rever os fluxos críticos antes da integração.

## 5. Limites de segurança

- Não foram feitas alterações ao Supabase, aos dados, ao schema, às permissões ou à configuração de produção.
- Não foi utilizado Render.
- Não foi feito merge nem deploy nesta fase.
- A implementação visual não deve alterar o comportamento funcional das páginas.
