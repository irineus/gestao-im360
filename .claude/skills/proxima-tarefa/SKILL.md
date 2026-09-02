---
name: proxima-tarefa
description: Avança o trabalho no board do Gestão IM360 no Notion — database "Gestão Interativo — Roadmap de Construção". Use sempre que Irineu disser "próxima tarefa", "próximo item", "o que fazer agora", "concluí essa tarefa", "marca como concluído/em andamento", "como está o board", "status do projeto", "cria um card para X", ou qualquer pedido para consultar, atualizar ou expandir o roadmap do Gestão IM360 — mesmo que não mencione o Notion explicitamente.
---

# Próxima tarefa — Gestão IM360

Este projeto é rastreado no Notion. Este repositório contém o código e os documentos de apoio; **o board e as Decisões vigentes no Notion são a fonte da verdade** sobre o que fazer e o que já foi decidido.

## Identificadores

- Board (data source): `e50abe7f-1688-402a-96b5-c6049b24ce82`
- Database (página): `f3bd0f112cde4ed699d616fc7fc30dff`
- Decisões vigentes (página): `3cd2f3f4-b9b2-8106-95cd-fc8d937bd953`
- Repositório: `github.com/irineus/gestao-im360` — branches `main` (prod) e `develop` (dev)
- Propriedades do card: `Tarefa` (título — **não existe coluna `Nome`**), `Fase` (select, prefixo numérico e acentos exatos), `Ordem` (número, aceita decimal), `Status` ("A fazer" / "Em andamento" / "Concluído"), `Prioridade` ("Alta" / "Média" / "Baixa"), `Notas` (texto), e as três da estimativa (card 3.13, 02/09/2026): `Concluído em` (data — na query use `date:Concluído em:start`), `Tamanho` ("P"/"M"/"G"/"GG" = 1/3/5/8 pontos) e `Tipo` ("Documento/decisão" / "Schema/migração" / "Função/regra" / "View" / "Tela" / "Infra/CI" / "Marco/validação" / "Externo").
- NÃO confundir com o board do Desmalha (`d50a2925-fb74-4f67-b0db-af03ef41d1b4`) — projeto diferente. Se o pedido citar carnê-leão/Desmalha, esta skill não se aplica.

## Pré-requisito

MCP do Notion conectado na sessão. Se não estiver, parar e avisar Irineu (sem ele não há board).

## Passos obrigatórios no início

1. Ler `docs/README-continuidade.md` e `CLAUDE.md` do repositório.
2. Buscar a página Decisões vigentes no Notion e ler por completo. Em conflito com os documentos do repo, ela vence.

## Consultar o board

Consultar os cards via query no data source, ordenando por fase e ordem. As fases têm nomes **"01. …" a "11. …"**, com zero à esquerda. Usar SEMPRE esta expressão de ordenação:

```sql
ORDER BY CAST(substr("Fase", 1, 2) AS INTEGER), "Ordem"
```

⚠️ Corrigido em 01/09/2026 (card 2.3). A expressão anterior lia `substr("Fase", 1, 1)`, escrita quando se supunha "1." a "11." sem zero: com o zero à esquerda ela devolve **0 para todas as fases**, a ordenação vira arbitrária e o "primeiro card não concluído" sai errado. Conferir o resultado: se `CAST(...)` der 0 em toda linha, os nomes das fases mudaram de novo.

A query é tarifada — buscar tudo o que a sessão precisa em **uma** chamada. A página Decisões vigentes é filha do database e aparece nos resultados com `Fase` nula: ignorar essa linha.

## Escolher a tarefa

**Cards "Em andamento" vêm primeiro e Irineu decide.** Antes de propor qualquer card "A fazer":

1. Listar TODOS os cards com `Status = 'Em andamento'`, na ordenação acima, com as Notas completas (elas dizem o que falta e de quem depende).
2. Perguntar a Irineu, com **AskUserQuestion**, em qual seguir — uma opção por card em andamento, mais a opção de seguir para o próximo "A fazer". Não escolher sozinho: card em andamento costuma estar parado por dependência de terceiro (pedagógico, dono do produto), e só Irineu sabe se já destravou.
3. Se não houver nenhum "Em andamento", a próxima tarefa é o primeiro card não concluído na ordenação, respeitando as dependências anotadas nas Notas.

Apresentar o card escolhido com as **Notas completas** antes de começar — elas carregam a decisão bloqueante.

## Renomear a sessão

Assim que a tarefa estiver escolhida, renomear a sessão para **`<Fase>.<Ordem> — <Tarefa>`** (ex.: `2.2 — Especificar regras de negócio como funções e triggers`). Sem isso a sessão fica com nome genérico e a lista de sessões não diz em que se trabalhou.

`set_session_title` exige o **id real** da sessão — `session_id: "self"` é recusado com `target session could not be verified` (corrigido em 01/09/2026, depois de a renomeação falhar em silêncio na sessão do card 2.5). O `"self"` só vale no `get_session`, que é justamente de onde o id sai:

1. `get_session` **sem** `session_id` → devolve `ccr.id` (`session_...`) desta sessão;
2. `set_session_title` com esse `session_id` e o título.

Usar só o número da fase e a ordem, não o nome inteiro da fase. Se a sessão tratar de mais de um card, nomear pelo principal.

Se a ferramenta de renomear não estiver exposta na sessão, dizer isso **uma vez** e pedir que Irineu renomeie na UI — nunca pular em silêncio.

## Executar

1. Marcar o card como **Em andamento** ao começar.
2. Criar a branch de tarefa **sempre a partir de `origin/develop`**, seja qual for a branch designada da sessão:
   `git fetch origin develop && git checkout -B tarefa/<fase>-<ordem>-<slug> origin/develop` (ex.: `tarefa/2-2-regras-negocio`). Nunca trabalhar direto em `main` nem em `develop`.
   - **De `develop`, nunca de `main`** (acordo de 01/09/2026). Irineu passou a abrir as sessões com `main` como branch designada, e `main` só recebe conteúdo na promoção: enquanto houver tarefa mergeada em `develop` e ainda não promovida, uma branch criada a partir de `main` nasce **sem os documentos mais recentes** — e a tarefa seguinte é escrita em cima de uma base velha. Foi exatamente o que aconteceu em 31/08 (a sessão clonou só a `main` e concluiu, errado, que os entregáveis dos cards 2.1 e 1.9 nunca tinham sido commitados). `git checkout -B <branch> origin/develop` funciona igual em qualquer sessão e resolve.
   - **Em sessão na nuvem, criar branch nova funciona** (verificado em 01/09/2026, card 2.4: `git push -u origin tarefa/2-4-permissoes-matriz` foi aceito numa sessão cuja branch designada era `develop`). A instrução anterior dizia que o *push protection* do proxy só aceitava push contra a branch de trabalho da sessão, e isso está errado para **criação** de branch — o que o proxy recusa de forma determinística é **apagar** ref de outra branch (ver "Limpeza de branch depois do merge"). Então vale a regra normal: branch `tarefa/<fase>-<ordem>-<slug>` e PR contra `develop`.
   - Se a branch designada da sessão for uma `claude/<algo>` e o push da branch nova for recusado mesmo assim, aí sim usar a designada reapontada para `origin/develop` (`git checkout -B <branch-designada> origin/develop`) e abrir o PR a partir dela. Se o PR anterior dessa branch já foi mergeado, reapontar de novo — nunca empilhar em cima de história já mergeada.
   - Quando a branch designada da sessão é a própria `develop` **ou a `main`**, **não commitar nela**: fazer o commit na branch de tarefa e devolver a local ao remoto (`git branch -f develop origin/develop`), senão a próxima sessão clona uma branch com commit que não passou por PR. Aconteceu em 01/09/2026 no card de Ordem 5: a sessão tinha `develop` designada e o entregável foi empurrado direto, sem PR.
3. Executar respeitando as regras do `CLAUDE.md`: migrações só via CI/CD; regras de negócio no banco; RLS em toda tabela; nomes em português snake_case; credenciais nunca em texto puro.
4. Se a nota do card divergir do que faz sentido (ex.: pedir um entregável que já é de outro card), **não seguir em silêncio nem inventar escopo**: fazer o que é coerente, registrar a divergência e o motivo na subpágina de resultado e nas Notas.

## Encerrar a tarefa

1. **Resultado extenso** (especificação, DDL, relatório): criar como **subpágina do card** (`parent: {page_id: <card-id>}`), nunca solta na raiz.
2. **Notas do card**: `update_properties` **sobrescreve** o campo — buscar o valor atual primeiro e reenviar o texto completo, preservando a linha "Origem:". Prefixar o que foi feito com `CONCLUÍDO <data>:`.
3. **Decisões vigentes**, se a tarefa gerou decisão (arquitetura, schema, regra, parâmetro, risco): `update_content` na seção correspondente (**nunca** `replace_content`) + linha no Histórico com data e card de origem. Decisão revogada vai para "Decisões superadas" com o motivo.
4. **Continuidade**: atualizar `docs/README-continuidade.md` (tabela de documentos, marcos) quando a tarefa criar documento novo ou mudar o estado do projeto.
5. **Status = Concluído** e **`Concluído em` = a data de hoje**. As duas coisas, sempre — a data alimenta a estimativa de entrega (`docs/estimativa-entrega.md`), e card concluído sem data é um buraco na série. Se o card ainda não tiver `Tamanho` e `Tipo`, preencher também.
6. **Fechar o ciclo do Git — faz parte da tarefa, não é extra.** São duas perguntas clicáveis a Irineu, na ordem: PR + merge em `develop`, depois promoção para `main`.

## Ciclo do Git ao concluir — acordo de 01/09/2026

**Nenhum merge acontece sem Irineu clicar, e nenhuma tarefa termina sem as duas perguntas serem
feitas.** O acordo existe porque as duas falhas que já aconteceram foram de esquecimento, não de
julgamento: PR não aberto (card de Ordem 5) e merge feito antes do OK. Pergunta em texto solto no
resumo final não resolve — ela se perde no meio do relatório. As duas são **`AskUserQuestion`**.

1. Commit em português, mensagem descrevendo a tarefa do board (ex.: `Card 2.1: modelagem de dados detalhada (DDL Postgres)`).
2. Push da branch de tarefa: `git push -u origin tarefa/<fase>-<ordem>-<slug>`.
3. **Pergunta 1 — PR e merge em `develop`.** Assim que o entregável do card estiver pronto e
   empurrado (antes do resumo final, não depois), perguntar com **`AskUserQuestion`**:
   - *Abrir o PR contra `develop` e mergear com o CI verde* — **recomendada**, é o caminho normal;
   - *Só abrir o PR, sem mergear* — quando Irineu quiser revisar antes;
   - *Nem abrir o PR agora.*

   Corpo do PR: o que foi entregue, link do card e o que ficou em aberto. Em sessões do Claude Code
   na web o `gh` **não** existe — usar as ferramentas MCP do GitHub (`create_pull_request`,
   `merge_pull_request`).
4. **CI antes do merge.** Hoje o único workflow é o `db-migrations`, e ele só dispara quando o push
   toca `supabase/migrations/**` — a maioria dos PRs de documento não tem check nenhum, e aí a
   autorização da pergunta 1 já basta. Havendo check: esperar ficar verde; **vermelho não se
   mergeia** — corrigir, empurrar de novo e só então mergear.
5. **Pergunta 2 — promoção para produção.** Depois do merge em `develop` (e do CI verde, se houver),
   perguntar com **`AskUserQuestion`**:
   - *Promover `develop` → `main` agora* — abre o PR de promoção e mergeia;
   - *Ainda não — acumular mais tarefas em `develop`.*

   ⚠️ Merge em `main` **aplica migração no banco de produção**. Esta pergunta é sempre feita e nunca
   é respondida pelo Claude: sem clique, não há promoção. Se a promoção levar migração, dizer isso
   **dentro da pergunta**, com o nome do arquivo — é a última chance de alguém reparar.
6. **Nunca mergear sem o clique.** A única dispensa é Irineu dizer na própria sessão "pode mergear
   direto" / "não precisa pedir" — e vale só naquela sessão, não nas seguintes.
7. Branch empurrada sem PR some. Se houver PR de tarefa anterior ainda não mergeado, dizer no
   resumo final.
8. Se a sessão acabar sem resposta às perguntas, o resumo final tem de dizer **em que ponto do ciclo
   a tarefa parou** (branch empurrada? PR aberto? mergeado?) — a sessão seguinte começa daí.

### Limpeza de branch depois do merge

Branch mergeada que fica no remoto vira ruído, e com dez branches velhas ninguém repara na décima primeira.

**Não decidir por `git branch --merged`.** Se o merge foi por squash ou rebase, a ponta da branch deixa de ser ancestral e some do `--merged` mesmo com tudo integrado. Usar `git cherry`, que compara por *patch-id*:

```bash
git fetch origin --quiet
git cherry develop origin/<branch> | grep '^+' | wc -l   # 0 = tudo já está em develop
```

O erro é assimétrico: se `--merged` lista a branch, ela está mergeada; se não lista, não se conclui nada. Zero linhas `+` é o que autoriza apagar.

**Em sessão na nuvem, apagar branch remota é impossível — não tentar.** (Corrigido em 01/09/2026; a instrução anterior dizia que o `HTTP 403` era falta de permissão do token, o que está errado.) Todo tráfego de git das sessões hospedadas pela Anthropic passa por um proxy que faz *push protection*: **`git push` só é aceito contra a branch de trabalho da própria sessão**. Apagar a ref de qualquer outra branch devolve `HTTP 403` de forma determinística, e nenhuma configuração de ambiente, de `.claude/settings.json` ou de token muda isso. Repetir não resolve, e o `curl -sS "$HTTPS_PROXY/__agentproxy/status"` vai mostrar o proxy saudável — não é instabilidade.

O que fazer: dizer no resumo final quais branches estão mergeadas e prontas para remoção, com o link `https://github.com/irineus/gestao-im360/branches`, e **nunca dar a limpeza como feita**.

Numa sessão local (terminal, ou depois de `--teleport`) não há proxy no caminho e a remoção funciona normalmente:

```bash
git push origin --delete <branch>
git branch -D <branch>
```

## Criar cards novos

- Sempre no data source do board deste projeto, com Fase e Ordem coerentes, **e já com `Tamanho` e `Tipo`** — card sem tamanho não entra na estimativa e some da conta de prazo.
- Inserção no meio da sequência: `Ordem` decimal (ex.: 2.5) — não renumerar os demais.
- Pendência registrada nas Decisões vigentes que prometa "card na Fase N" deve virar card de verdade; pendência sem card é pendência esquecida.

## Avisos programados

- Ao abrir qualquer card da fase **"10. Publicação nas Lojas"**: lembrar Irineu de cadastrar o app nas lojas (Google Play e App Store) com o id `com.gestaoim360.app` — cadastro ainda não realizado.

## Proibições

Nunca deletar cards. Nunca tocar em outros databases do workspace (Desmalha, Entrelares). IDs de página em UUID hifenizado nas atualizações. Nunca aplicar SQL manualmente em produção.
