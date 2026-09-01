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
- Propriedades do card: `Tarefa` (título — **não existe coluna `Nome`**), `Fase` (select, prefixo numérico e acentos exatos), `Ordem` (número, aceita decimal), `Status` ("A fazer" / "Em andamento" / "Concluído"), `Prioridade` ("Alta" / "Média" / "Baixa"), `Notas` (texto).
- NÃO confundir com o board do Desmalha (`d50a2925-fb74-4f67-b0db-af03ef41d1b4`) — projeto diferente. Se o pedido citar carnê-leão/Desmalha, esta skill não se aplica.

## Pré-requisito

MCP do Notion conectado na sessão. Se não estiver, parar e avisar Irineu (sem ele não há board).

## Passos obrigatórios no início

1. Ler `docs/README-continuidade.md` e `CLAUDE.md` do repositório.
2. Buscar a página Decisões vigentes no Notion e ler por completo. Em conflito com os documentos do repo, ela vence.

## Consultar o board

Consultar os cards via query no data source, ordenando por fase e ordem. As fases têm nomes "1. …" a "11. …", que quebram ordenação alfabética ("10." vem antes de "2."). Usar SEMPRE esta expressão de ordenação:

```sql
ORDER BY
  CASE WHEN "Fase" LIKE '10.%' THEN 10
       WHEN "Fase" LIKE '11.%' THEN 11
       ELSE CAST(substr("Fase", 1, 1) AS INTEGER) END,
  "Ordem"
```

A query é tarifada — buscar tudo o que a sessão precisa em **uma** chamada. A página Decisões vigentes é filha do database e aparece nos resultados com `Fase` nula: ignorar essa linha.

## Escolher a tarefa

**Cards "Em andamento" vêm primeiro e Irineu decide.** Antes de propor qualquer card "A fazer":

1. Listar TODOS os cards com `Status = 'Em andamento'`, na ordenação acima, com as Notas completas (elas dizem o que falta e de quem depende).
2. Perguntar a Irineu, com **AskUserQuestion**, em qual seguir — uma opção por card em andamento, mais a opção de seguir para o próximo "A fazer". Não escolher sozinho: card em andamento costuma estar parado por dependência de terceiro (pedagógico, dono do produto), e só Irineu sabe se já destravou.
3. Se não houver nenhum "Em andamento", a próxima tarefa é o primeiro card não concluído na ordenação, respeitando as dependências anotadas nas Notas.

Apresentar o card escolhido com as **Notas completas** antes de começar — elas carregam a decisão bloqueante.

## Renomear a sessão

Assim que a tarefa estiver escolhida, renomear a sessão para **`<Fase>.<Ordem> — <Tarefa>`** (ex.: `2.2 — Especificar regras de negócio como funções e triggers`), usando `set_session_title` com `session_id: "self"`. Sem isso a sessão fica com nome genérico e a lista de sessões não diz em que se trabalhou.

Usar só o número da fase e a ordem, não o nome inteiro da fase. Se a sessão tratar de mais de um card, nomear pelo principal.

Se a ferramenta de renomear não estiver exposta na sessão, dizer isso **uma vez** e pedir que Irineu renomeie na UI — nunca pular em silêncio.

## Executar

1. Marcar o card como **Em andamento** ao começar.
2. Criar branch a partir de `develop`: `git switch develop && git pull && git switch -c tarefa/<fase>-<ordem>-<slug>` (ex.: `tarefa/2-2-regras-negocio`). Nunca trabalhar direto em `main` nem em `develop`.
3. Executar respeitando as regras do `CLAUDE.md`: migrações só via CI/CD; regras de negócio no banco; RLS em toda tabela; nomes em português snake_case; credenciais nunca em texto puro.
4. Se a nota do card divergir do que faz sentido (ex.: pedir um entregável que já é de outro card), **não seguir em silêncio nem inventar escopo**: fazer o que é coerente, registrar a divergência e o motivo na subpágina de resultado e nas Notas.

## Encerrar a tarefa

1. **Resultado extenso** (especificação, DDL, relatório): criar como **subpágina do card** (`parent: {page_id: <card-id>}`), nunca solta na raiz.
2. **Notas do card**: `update_properties` **sobrescreve** o campo — buscar o valor atual primeiro e reenviar o texto completo, preservando a linha "Origem:". Prefixar o que foi feito com `CONCLUÍDO <data>:`.
3. **Decisões vigentes**, se a tarefa gerou decisão (arquitetura, schema, regra, parâmetro, risco): `update_content` na seção correspondente (**nunca** `replace_content`) + linha no Histórico com data e card de origem. Decisão revogada vai para "Decisões superadas" com o motivo.
4. **Continuidade**: atualizar `docs/README-continuidade.md` (tabela de documentos, marcos) quando a tarefa criar documento novo ou mudar o estado do projeto.
5. **Status = Concluído.**
6. **Fechar o ciclo do Git — faz parte da tarefa, não é extra.**

## Ciclo do Git ao concluir

Commit e PR são obrigatórios ao concluir a tarefa; o merge **não**.

1. Commit em português, mensagem descrevendo a tarefa do board (ex.: `Card 2.1: modelagem de dados detalhada (DDL Postgres)`).
2. Push da branch e **abrir o PR contra `develop`** (`gh pr create --base develop`). Corpo do PR: o que foi entregue, link do card e o que ficou em aberto.
3. **Nunca fazer o merge sem OK explícito de Irineu.** A exceção é ele dispensar o OK na própria sessão ("pode mergear direto", "não precisa pedir") — dispensa vale só para a sessão em que foi dada, não para as seguintes.
4. Branch empurrada sem PR some. Se houver PR de tarefa anterior ainda não mergeado, dizer no resumo final.
5. Promoção para produção (`develop` → `main`) é PR próprio e **sempre** exige OK — merge em `main` aplica migração no banco de produção.

### Limpeza de branch depois do merge

Branch mergeada que fica no remoto vira ruído, e com dez branches velhas ninguém repara na décima primeira.

**Não decidir por `git branch --merged`.** Se o merge foi por squash ou rebase, a ponta da branch deixa de ser ancestral e some do `--merged` mesmo com tudo integrado. Usar `git cherry`, que compara por *patch-id*:

```bash
git fetch origin --quiet
git cherry develop origin/<branch> | grep '^+' | wc -l   # 0 = tudo já está em develop
```

O erro é assimétrico: se `--merged` lista a branch, ela está mergeada; se não lista, não se conclui nada. Só apagar com zero linhas `+`:

```bash
git push origin --delete <branch>
git branch -D <branch>
```

Se o push falhar com `HTTP 403`, o token não tem permissão para remover refs — **repetir não resolve**. Dizer que não deu e passar `https://github.com/irineus/gestao-im360/branches` em vez de dar a limpeza como feita.

## Criar cards novos

- Sempre no data source do board deste projeto, com Fase e Ordem coerentes.
- Inserção no meio da sequência: `Ordem` decimal (ex.: 2.5) — não renumerar os demais.
- Pendência registrada nas Decisões vigentes que prometa "card na Fase N" deve virar card de verdade; pendência sem card é pendência esquecida.

## Avisos programados

- Ao abrir qualquer card da fase **"10. Publicação nas Lojas"**: lembrar Irineu de cadastrar o app nas lojas (Google Play e App Store) com o id `com.gestaoim360.app` — cadastro ainda não realizado.

## Proibições

Nunca deletar cards. Nunca tocar em outros databases do workspace (Desmalha, Entrelares). IDs de página em UUID hifenizado nas atualizações. Nunca aplicar SQL manualmente em produção.
