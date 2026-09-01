# Gestão IM360 — contexto para o Claude Code

Sistema web/mobile que substitui a planilha "Gestão Interativo" na gestão de alunos, turmas, vagas e material didático de uma escola com três métodos de ensino (Interativo, Inglês e Modular). Irineu é o líder técnico; decisões de negócio são do dono do produto e chegam via Irineu.

**Stack:** Flutter (web + Android + iOS) · Supabase (Postgres, Auth e-mail/senha, RLS) · Cloudflare Pages · Sentry (free tier, desde a Fase 0).

## Início de sessão (obrigatório, nesta ordem)

1. Ler `docs/README-continuidade.md`.
2. Ler a página Notion **"Gestão Interativo — Decisões vigentes"** (id `3cd2f3f4-b9b2-8106-95cd-fc8d937bd953`) via MCP do Notion. Em conflito com qualquer documento deste repositório, **a página do Notion vence** — ela é escrita no momento de cada decisão.
3. Só então executar a tarefa. Para "próxima tarefa" / "concluí" / "status do board", usar a skill `proxima-tarefa` (`.claude/skills/proxima-tarefa/SKILL.md`).

Se o MCP do Notion não estiver disponível na sessão, avisar Irineu antes de prosseguir — o board e as decisões vivem lá.

## Ambientes e identidade

| Item | Valor |
|---|---|
| Supabase produção | ref `aqfuawrygxsiopyppjza` — GestaoIM360ProdDB, org GestaoIM360Prod, sa-east-1 |
| Supabase desenvolvimento | ref `ncdfolxdupbbfvtydngx` — GestaoIM360DevDB, org GestaoIM360Dev, sa-east-1 |
| Domínio | `gestaoim360.com` (base de todos os identificadores) |
| App id | `com.gestaoim360.app` — ⚠️ cadastro nas lojas AINDA NÃO feito; ao chegar na fase de Publicação nas Lojas, avisar Irineu para fazer o cadastro |
| Repositório | `github.com/irineus/gestao-im360` |
| Board Notion | database "Gestão Interativo — Roadmap de Construção", data source `e50abe7f-1688-402a-96b5-c6049b24ce82` |
| Decisões vigentes | página Notion `3cd2f3f4-b9b2-8106-95cd-fc8d937bd953` |

Não confundir com o board do **Desmalha** (outro projeto de Irineu, data source `d50a2925-fb74-4f67-b0db-af03ef41d1b4`) nem com o app **Entrelares** (projeto Supabase EntrelaresProdDB). Nunca tocar neles a partir deste repositório.

## Regras inegociáveis

- **Migrações somente via CI/CD** (`.github/workflows/db-migrations.yml`): novo arquivo em `supabase/migrations/` → push em `develop` aplica no dev → merge em `main` aplica no prod. Nunca aplicar SQL manualmente em prod. Nomear migrações `YYYYMMDDHHMMSS_descricao.sql` (padrão do CLI).
- **Merge só com o clique de Irineu** (acordo de 01/09/2026): branch de tarefa a partir de `origin/develop`, `AskUserQuestion` para abrir o PR e mergear em `develop`, e outra `AskUserQuestion` para promover a `main`. Ver "Fluxo de entrega" abaixo.
- **Regras de negócio no banco** (funções SQL/PL-pgSQL, triggers, `pg_cron`); o Flutter orquestra e consome tabelas/views via `supabase_flutter`. Edge Functions só quando indispensável.
- **RLS em toda tabela.** O código verifica permissões via `tem_permissao(codigo)`, **nunca perfis**. RLS filtra também por `unidade_id` do usuário.
- Toda tabela de negócio: `id uuid`, `unidade_id`, `criado_em/por`, `atualizado_em/por`.
- Movimentos de estoque imutáveis; correções por estorno.
- Nomes em português, snake_case (tabelas, colunas, funções). Documentos e commits em português.
- Credenciais de PCs nunca em texto puro.
- Flutter: `go_router`, Riverpod, `supabase_flutter`; desktop-first para secretaria, mobile-friendly para monitor.

## Fluxo de entrega (acordo de 01/09/2026 — vale para todas as sessões)

**Nenhum merge acontece sem Irineu clicar.** O acordo é fechado e não se renegocia a cada sessão:

1. **Branch de tarefa sempre a partir de `origin/develop`**, qualquer que seja a branch designada da
   sessão — inclusive quando for `main`:
   `git fetch origin develop && git checkout -B tarefa/<fase>-<ordem>-<slug> origin/develop`.
   Nunca commitar direto em `main` nem em `develop`. Branch criada a partir de `main` nasce sem o que
   já está em `develop` e ainda não foi promovido.
2. Concluído o entregável do card: commit, push da branch e **pergunta com `AskUserQuestion`** — abrir
   o PR contra `develop` e, com o CI verde, mergear? A pergunta é clicável e vem **antes** do resumo
   final; pedido em texto solto se perde no relatório.
3. Depois do merge em `develop` e do CI verde, **segunda pergunta com `AskUserQuestion`** — promover
   `develop` → `main`? Merge em `main` **aplica migração no banco de produção**: sem clique, não há
   promoção, e se a promoção levar migração isso é dito dentro da pergunta, com o nome do arquivo.

Vermelho no CI não se mergeia. Dispensa do OK só vale se Irineu der na própria sessão. Detalhe
operacional na skill `proxima-tarefa`, seção "Ciclo do Git ao concluir".

## Workflow do board Notion

- **Ordenação de fases** (nomes "01." a "11.", com zero à esquerda) — usar sempre
  `CAST(substr("Fase", 1, 2) AS INTEGER)`. A forma antiga com `substr(..., 1, 1)` devolve 0 para todas as fases e embaralha o board (corrigido em 01/09/2026, card 2.3).
- Campo `Notas`: buscar o valor atual antes de atualizar e reenviar o texto completo — nunca sobrescrever a linha "Origem:".
- Páginas de resultado de tarefa: sempre **subpáginas do card** (`parent: {page_id: <card-id>}`), nunca soltas na raiz.
- Inserir card no meio da sequência: `Ordem` decimal (ex.: 3.5), sem renumerar os demais.
- Ao encerrar tarefa que gere decisão: atualizar a Decisões vigentes com `update_content` na seção correspondente (nunca `replace_content`) + registrar no Histórico com data e card de origem.

## Estado atual (31/08/2026)

Concepção concluída; plano v1.1 aprovado com as 9 respostas do dono do produto; decisões técnicas fechadas. **Fase 0 (Fundação) em andamento.** Target de go-live: outubro/2026 (adoção provavelmente em fases). Detalhes e pendências: Decisões vigentes no Notion.
