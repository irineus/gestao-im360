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

- **Próxima tarefa** = primeiro card não concluído nessa ordenação (respeitando dependências anotadas no card).
- **Status do board** = contagem por fase/status + próxima tarefa.

## Executar e encerrar uma tarefa

1. Marcar o card como Em andamento ao começar.
2. Executar respeitando as regras do `CLAUDE.md` (migrações só via CI/CD; regras de negócio no banco; RLS; nomes em português).
3. Resultado extenso (especificação, DDL, relatório): criar como **subpágina do card** (`parent: {page_id: <card-id>}`), nunca solta na raiz.
4. Atualizar o campo `Notas` do card: **buscar o valor atual primeiro** e reenviar o texto completo, preservando a linha "Origem:".
5. Se a tarefa gerou decisão (arquitetura, schema, regra, parâmetro, risco): atualizar a página Decisões vigentes com `update_content` na seção correspondente (nunca `replace_content`) e acrescentar linha no Histórico com data e card de origem. Decisão revogada vai para "Decisões superadas" com o motivo.
6. Marcar o card como Concluído e informar qual é a próxima tarefa.

## Criar cards novos

- Sempre no data source do board deste projeto, com Fase e Ordem coerentes.
- Inserção no meio da sequência: `Ordem` decimal (ex.: 3.5) — não renumerar os demais.

## Avisos programados

- Ao abrir qualquer card da fase **"10. Publicação nas Lojas"**: lembrar Irineu de cadastrar o app nas lojas (Google Play e App Store) com o id `com.gestaoim360.app` — cadastro ainda não realizado.
