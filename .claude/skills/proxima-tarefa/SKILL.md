---
name: proxima-tarefa
description: Avança o trabalho no board do Gestão IM360 no Notion — database "Gestão Interativo — Roadmap de Construção". Use sempre que Irineu disser "próxima tarefa", "próximo item", "o que fazer agora", "concluí essa tarefa", "marca como concluído/em andamento", "como está o board", "status do projeto", "cria um card para X", ou qualquer pedido para consultar, atualizar ou expandir o roadmap do Gestão IM360 — mesmo que não mencione o Notion explicitamente.
---

# Próxima tarefa — Gestão IM360

Este projeto é rastreado no Notion. Este repositório contém o código e os documentos de apoio; **o board e as Decisões vigentes no Notion são a fonte da verdade** sobre o que fazer e o que já foi decidido.

## Identificadores

- Board (data source): `e50abe7f-1688-402a-96b5-c6049b24ce82`
- Database (página): `f3bd0f112cde4ed699d616fc7fc30dff`
- Decisões vigentes (página): `3cd2f3f4-b9b2-8106-95cd-fc8d937bd953` — ler as **seções 1 a 6**
- Histórico de decisões (subpágina da anterior, onde entra a linha nova de cada card): `3d12f3f4-b9b2-815e-9643-edc69db65f5c`
- Repositório: `github.com/irineus/gestao-im360` — branches `main` (prod) e `develop` (dev)
- Propriedades do card: `Tarefa` (título — **não existe coluna `Nome`**), `Fase` (select, prefixo numérico e acentos exatos), `Ordem` (número, aceita decimal), `Status` ("A fazer" / "Em andamento" / "Concluído"), `Prioridade` ("Alta" / "Média" / "Baixa"), `Notas` (texto), e as três da estimativa (card 3.13, 02/09/2026): `Concluído em` (data — na query use `date:Concluído em:start`), `Tamanho` ("P"/"M"/"G"/"GG" = 1/3/5/8 pontos) e `Tipo` ("Documento/decisão" / "Schema/migração" / "Função/regra" / "View" / "Tela" / "Infra/CI" / "Marco/validação" / "Externo").
- NÃO confundir com o board do Desmalha (`d50a2925-fb74-4f67-b0db-af03ef41d1b4`) — projeto diferente. Se o pedido citar carnê-leão/Desmalha, esta skill não se aplica.

## Pré-requisito

MCP do Notion conectado na sessão. Se não estiver, parar e avisar Irineu (sem ele não há board).

## Passos obrigatórios no início

1. Ler `docs/README-continuidade.md` e `CLAUDE.md` do repositório.
2. Buscar a página Decisões vigentes no Notion e ler as **seções 1 a 6**, que são as vigentes. Em conflito com os documentos do repo, ela vence.
3. **Não ler o log cronológico na partida** (card 6.1,5, 04/09/2026): ele mora em `docs/historico-marcos.md` e na subpágina **📜 Histórico de decisões**, e se consulta quando a tarefa pedir — rastrear um card, um documento ou um defeito antigo. Ao encerrar a tarefa, é **lá** que entra a linha nova (`insert_content`, `position: start`), não na página-mãe.

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
3. **Decisões vigentes**, se a tarefa gerou decisão (arquitetura, schema, regra, parâmetro, risco): `update_content` na seção correspondente (**nunca** `replace_content`) + linha na subpágina **📜 Histórico de decisões** (`3d12f3f4-b9b2-815e-9643-edc69db65f5c`), com `insert_content` e `position: start`, com data e card de origem. **O log não volta para a página-mãe** — ela é lida em toda sessão e foi enxugada de propósito no card 6.1,5 (04/09/2026). Decisão revogada vai para "Decisões superadas" com o motivo, essa sim na página-mãe.
4. **Continuidade**: atualizar `docs/README-continuidade.md` (tabela de documentos, marcos) quando a tarefa criar documento novo ou mudar o estado do projeto.
5. **Status = Concluído** e **`Concluído em` = a data de hoje**. As duas coisas, sempre — a data alimenta a estimativa de entrega (`docs/estimativa-entrega.md`), e card concluído sem data é um buraco na série. Se o card ainda não tiver `Tamanho` e `Tipo`, preencher também.
6. **Fechar o ciclo do Git — faz parte da tarefa, não é extra.** São duas perguntas clicáveis a Irineu, na ordem: PR + merge em `develop`, depois promoção para `main`.

## Ciclo do Git ao concluir — acordo de 01/09/2026, revisto em 03/09/2026

**`develop` é do CI; `main` é de Irineu.** O merge em `develop` é **automático com o CI verde** e não
se pergunta (mudou em 03/09/2026, card 5.5,5 — o portão que a regra antiga protegia era o CI, e é o
CI que decide). A promoção `develop` → `main` **nunca** é automática: aplica migração em produção.

1. Commit em português, mensagem descrevendo a tarefa do board (ex.: `Card 2.1: modelagem de dados detalhada (DDL Postgres)`).
2. Push da branch de tarefa: `git push -u origin tarefa/<fase>-<ordem>-<slug>`.
3. **PR contra `develop`, sem perguntar.** Corpo: o que foi entregue, link do card e o que ficou em
   aberto. Em sessões do Claude Code na web o `gh` **não** existe — usar as ferramentas MCP do GitHub
   (`create_pull_request`, `merge_pull_request`).
4. **Esperar o CI e mergear no verde.** `gh pr checks <n> --watch`. Sem check nenhum (PR só de
   documento), mergear direto.
5. **Vermelho entra no laço de correção, não para a tarefa.** Ler o log do job que reprovou,
   corrigir, empurrar e esperar de novo. **Parar e não mergear** só quando:
   - a falha se repetir **pela mesma razão** (mesmo job e mesma asserção/erro) depois de uma
     tentativa de correção — insistir sem hipótese nova é gastar rodada de CI;
   - chegar à **terceira** tentativa;
   - o conserto exigir ação que só Irineu pode fazer (secret, conta em serviço externo, decisão de
     produto, disparo manual de workflow).

   Em qualquer um dos três: dizer **qual** dos três foi e **por quê**, com o log.
6. **Promoção para produção — a sessão AVISA, e não pergunta.** ⚠️ Corrigido em 04/09/2026: até
   aqui esta seção mandava usar `AskUserQuestion` em sessão interativa, e a pergunta **não tinha o
   que decidir**. O hook `.claude/hooks/guarda-destrutivos.mjs` (instalado em 03/09/2026 pelo card
   5.5,5) recusa `git push` mirando `main`, `gh pr create --base main` e o merge de um PR cuja base
   seja `main` — em **qualquer** sessão, interativa ou não. Perguntar e depois esbarrar no guarda
   custou duas rodadas na sessão do card 5.11, e a segunda pergunta foi só para corrigir o número de
   migrações da primeira.

   O que fazer, sempre igual: **terminar o resumo com o aviso de promoção pendente**, contendo
   - **quantas migrações** a promoção leva e **os nomes dos arquivos** — `git diff --name-only
     origin/main..origin/develop -- supabase/migrations/` responde, e é o número que vale, não o do
     card que se acabou de fechar;
   - **o que cada uma aplica em produção**, com destaque para o que passa a **rodar sozinho** (rotina
     `pg_cron`, trigger que agenda, Worker) — é o único tipo de mudança que continua agindo depois de
     ninguém estar olhando;
   - o link `https://github.com/irineus/gestao-im360/compare/main...develop`.

   Quem abre o PR e clica no merge é Irineu. Não oferecer para "abrir só o PR": isso também é barrado,
   e oferecer o que não se pode fazer é o defeito que esta correção existe para tirar.
7. Branch empurrada sem PR some. Se houver PR de tarefa anterior ainda não mergeado, dizer no
   resumo final.
8. Se a sessão acabar no meio do ciclo, o resumo tem de dizer **em que ponto parou** (branch
   empurrada? PR aberto? mergeado?) — a sessão seguinte começa daí.

## Modo não interativo (cadeia de execução — card 5.5,5)

Quando a sessão foi aberta pelo driver `automacao/cadeia.ps1` (`claude -p`), **não há quem responda
pergunta**. Nesse modo:

- **Nunca usar `AskUserQuestion`.** Onde o fluxo interativo perguntaria, decidir pelo caminho
  documentado (merge em `develop` no verde) ou parar com veredito.
- **Escolher a tarefa sozinho**, sem a pergunta da seção "Escolher a tarefa": é o primeiro card não
  concluído na ordenação, **pulando** os que estão `Em andamento` com a linha
  `AGUARDANDO RETORNO DOS USUÁRIOS` nas Notas (marco esperando resposta de gente não bloqueia a fila).
- **Nota do card marcada como `DECISÃO`: decidir pela recomendação, não parar** — desde que ela
  exista e a decisão seja reversível. A regra saiu de um custo medido: em 04/09/2026 a cadeia parou
  horas num card cuja `DECISÃO` já trazia a opção recomendada, e Irineu escolheu exatamente as duas
  recomendadas. Parar para confirmar o que já estava escrito é tempo gasto sem informação nova.

  O critério **não** é "tem recomendação", é **quanto custa desfazer**:

  | Marcação na Nota | O que a sessão faz |
  |---|---|
  | `DECISÃO (recomendado: …)` | **adota a recomendação** e segue |
  | `DECISÃO BLOQUEANTE` | **para** com `CARD_PARADO`, sempre |
  | `DECISÃO` sem recomendação | **para** com `CARD_PARADO` — não há o que adotar |

  ⚠️ **É `DECISÃO BLOQUEANTE`, mesmo com recomendação**, o que muda schema ou dado em produção, mexe
  em permissão ou segurança, cria compromisso externo (conta, loja, contrato, e-mail a terceiro), ou
  custa mais para desfazer do que para fazer. Na dúvida entre as duas, é bloqueante: o erro de parar
  custa uma espera; o de seguir custa uma migração em produção.

  **Adotar recomendação obriga a registrar**, nos três lugares, para a reversão sair barata: nas
  Notas do card (o que foi adotado e que foi a sessão que adotou), no corpo do PR, e no resumo final.
  Dizer também **como reverter**.

  **Exceção estreita:** se a sessão tiver evidência MEDIDA de que a recomendação quebra algo — não
  opinião, medida —, ela para com `CARD_PARADO` e mostra a medida. Discordar por preferência não
  vale; para isso existe a divergência registrada.

- **Card de `Tipo` = `Externo`** e qualquer card cuja nota diga que depende de ação de Irineu: **não
  executar** — encerrar com `CADEIA_FIM`.
- **Card de `Tipo` = `Marco/validação`:** executar tudo o que não depende de gente (pré-condições
  medidas, critérios pré-verificados) e **deixar as mensagens de WhatsApp prontas** para Irineu
  encaminhar, no molde do §9.1 da subpágina do card 4.8 — uma mensagem por perfil, passo por linha,
  "você não tem como estragar nada" antes dos passos, o que é normal dito antes de virar defeito
  reportado. Depois: **manter o card `Em andamento`**, com a linha
  `AGUARDANDO RETORNO DOS USUÁRIOS desde <data>` no topo das Notas, e seguir para o próximo card.
- **Terminar a resposta com uma única linha de veredito**, a última de tudo, exatamente num destes
  três formatos (o driver lê por prefixo `>>> `):

  ```
  >>> CARD_OK <fase>.<ordem> pr=<numero> merge=develop
  >>> CARD_PARADO <fase>.<ordem> :: <motivo em uma linha>
  >>> CADEIA_FIM :: <motivo em uma linha>
  ```

  `CARD_OK` só com o merge em `develop` **feito**. PR aberto e não mergeado é `CARD_PARADO`.

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
