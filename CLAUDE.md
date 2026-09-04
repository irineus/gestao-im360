# Gestão IM360 — contexto para o Claude Code

Sistema web/mobile que substitui a planilha "Gestão Interativo" na gestão de alunos, turmas, vagas e material didático de uma escola com três métodos de ensino (Interativo, Inglês e Modular). Irineu é o líder técnico; decisões de negócio são do dono do produto e chegam via Irineu.

**Stack:** Flutter (web + Android + iOS) · Supabase (Postgres, Auth e-mail/senha, RLS) · Cloudflare Pages · Sentry (free tier, desde a Fase 0).

## Início de sessão (obrigatório, nesta ordem)

1. Ler `docs/README-continuidade.md`.
2. Ler a página Notion **"Gestão Interativo — Decisões vigentes"** (id `3cd2f3f4-b9b2-8106-95cd-fc8d937bd953`) via MCP do Notion — as **seções 1 a 6**, que são as vigentes. Em conflito com qualquer documento deste repositório, **a página do Notion vence** — ela é escrita no momento de cada decisão.
3. Só então executar a tarefa. Para "próxima tarefa" / "concluí" / "status do board", usar a skill `proxima-tarefa` (`.claude/skills/proxima-tarefa/SKILL.md`).

**O que NÃO é leitura de partida** (decidido em 04/09/2026, cards 6.1,5 e 6.2,5, e é o que mantém esses dois passos baratos):

- o **log cronológico**, que mora em `docs/historico-marcos.md` e na subpágina **📜 Histórico de decisões** da página do Notion;
- o **detalhe das decisões** — raciocínio, medições e contraprovas —, que mora nas **subpáginas de detalhe por domínio** da própria página Decisões vigentes (Modelagem/views/projeção; Acesso, permissões e RLS; Alunos; Currículo e catálogo; Trilha e estoque; Alocação, blocos, grade e REP; Capacidade, salas, PCs e credenciais; Pendências, rotinas e testes; App, telas e design system).

Os dois se consultam **quando a tarefa pedir** — mexendo em estoque, abre-se a subpágina de estoque; rastreando um card ou um defeito antigo, abre-se o histórico —, e não no início da sessão. O que a §2 da página guarda é o **enunciado** de cada regra (o que vale hoje e onde ela mora no código) mais a **armadilha concreta** que aquela regra já custou, com teto de **6 linhas por regra** escrito na própria seção.

Por que a regra existe: antes desta separação os dois documentos de partida somavam cerca de 430 mil caracteres, e a maior parte era log — as sessões batiam no limite de leitura e fatiavam arquivo só para obedecer a esta regra. O card 6.1,5 tirou o log; a §2 continuava com 146 KB e ainda obrigava a fatiar, e o 6.2,5 desceu o raciocínio para as subpáginas. **Nenhuma linha foi resumida ou apagada em nenhum dos dois — mudou de lugar.**

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
- **Migração nunca grava dado de negócio** (decisão de 02/09/2026; portão do card 4.0,5). Migração é o que o CI empurra para produção sozinho no merge em `main`: nela só entra dado de **configuração** — `unidade`, `perfil`, `permissao`, `perfil_permissao`, `usuario`, `usuario_perfil`, `parametro` e `metodo`. Material, curso, módulo, combo, aluno, sala, PC, professor, bloco, trilha, estoque e pedido vêm pelo importador do card 9.1, carregados só no projeto dev/homolog, e alcançam produção uma única vez na virada (card 9.7); dado de teste vive em `supabase/seed.sql`, que nunca sai do stack local. O job `migrações` do `testes.yml` reprova quem esquecer (`node portao-migracoes/varredor.mjs supabase/migrations`); ampliar a lista permitida é um commit em `portao-migracoes/varredor.mjs`, de propósito.
- **Merge só com o clique de Irineu** (acordo de 01/09/2026): branch de tarefa a partir de `origin/develop`, `AskUserQuestion` para abrir o PR e mergear em `develop`, e outra `AskUserQuestion` para promover a `main`. Ver "Fluxo de entrega" abaixo.
- **Regras de negócio no banco** (funções SQL/PL-pgSQL, triggers, `pg_cron`); o Flutter orquestra e consome tabelas/views via `supabase_flutter`. Edge Functions só quando indispensável.
- **RLS em toda tabela.** O código verifica permissões via `tem_permissao(codigo)`, **nunca perfis**. RLS filtra também por `unidade_id` do usuário.
- Toda tabela de negócio: `id uuid`, `unidade_id`, `criado_em/por`, `atualizado_em/por`.
- Movimentos de estoque imutáveis; correções por estorno.
- Nomes em português, snake_case (tabelas, colunas, funções). Documentos e commits em português.
- Credenciais de PCs nunca em texto puro.
- Flutter: `go_router`, Riverpod, `supabase_flutter`; desktop-first para secretaria, mobile-friendly para monitor.

## Fluxo de entrega (acordo de 01/09/2026, revisto em 03/09/2026 — vale para todas as sessões)

**O que mudou em 03/09/2026 (card 5.5,5):** o merge em `develop` **deixou de exigir clique** e passou
a ser automático com o CI verde. O portão que a regra de 01/09 protegia era o CI, e o CI hoje é o que
decide — a suíte pgTAP, a de concorrência, o `flutter test`, o `analyze`, o `format` e o portão de
migrações. O clique humano continua **exatamente onde o risco está**: a promoção `develop` → `main`,
que aplica migração no banco de **produção**, é manual e de Irineu, sempre, e nenhuma sessão a
executa — nem por engano: desde 03/09/2026 quem garante isso é um hook, e não a boa vontade da
sessão (`.claude/hooks/guarda-destrutivos.mjs`).

**Vermelho no CI se corrige, não se mergeia.** A sessão tenta a correção por conta própria e só para
quando (a) a falha se repete **pela mesma razão** depois da tentativa de correção, (b) chega à terceira
tentativa, ou (c) o conserto exige uma ação que só Irineu pode fazer (secret, conta em serviço externo,
decisão de produto). Nesses casos a sessão para e diz **por quê**, sem mergear.

Regra em uma linha: **`develop` é do CI; `main` é de Irineu.**

O resto do acordo de 01/09/2026 continua fechado e não se renegocia a cada sessão:

1. **Branch de tarefa sempre a partir de `origin/develop`**, qualquer que seja a branch designada da
   sessão — inclusive quando for `main`:
   `git fetch origin develop && git checkout -B tarefa/<fase>-<ordem>-<slug> origin/develop`.
   Nunca commitar direto em `main` nem em `develop`. Branch criada a partir de `main` nasce sem o que
   já está em `develop` e ainda não foi promovido.
2. Concluído o entregável do card: commit, push da branch, PR contra `develop`, **esperar o CI** e
   mergear **assim que ele fechar verde** — sem perguntar. Vermelho entra no laço de correção descrito
   acima.
3. **Promoção `develop` → `main`: a sessão AVISA, não pergunta.** ⚠️ Corrigido em 04/09/2026: até
   aqui esta linha mandava perguntar com `AskUserQuestion` em sessão interativa — e a pergunta não
   tinha o que decidir, porque **nenhuma sessão consegue promover**. O hook
   `.claude/hooks/guarda-destrutivos.mjs`, instalado em 03/09/2026 pelo próprio card 5.5,5, recusa
   `git push` mirando `main`, `gh pr create --base main` e o merge de um PR cuja base seja `main`.
   Perguntar "promover agora?" para depois esbarrar no guarda gasta duas rodadas e ensina a não
   confiar na pergunta seguinte.

   O que a sessão faz, interativa ou não: **encerrar o resumo dizendo que há promoção pendente**, com
   (a) quantas migrações ela leva e **com que nomes de arquivo**, (b) o que cada uma aplica em
   produção — em especial rotina agendada, `pg_cron` ou qualquer coisa que passe a rodar sozinha —, e
   (c) o link de comparação, `https://github.com/irineus/gestao-im360/compare/main...develop`. Quem
   abre o PR e clica no merge é Irineu, sempre.

Detalhe operacional na skill `proxima-tarefa`, seção "Ciclo do Git ao concluir". A cadeia de execução
não interativa (uma sessão por card, em sequência) está em `docs/cadeia-execucao.md`.

## Workflow do board Notion

- **Ordenação de fases** (nomes "01." a "11.", com zero à esquerda) — usar sempre
  `CAST(substr("Fase", 1, 2) AS INTEGER)`. A forma antiga com `substr(..., 1, 1)` devolve 0 para todas as fases e embaralha o board (corrigido em 01/09/2026, card 2.3).
- Campo `Notas`: buscar o valor atual antes de atualizar e reenviar o texto completo — nunca sobrescrever a linha "Origem:".
- Páginas de resultado de tarefa: sempre **subpáginas do card** (`parent: {page_id: <card-id>}`), nunca soltas na raiz.
- Inserir card no meio da sequência: `Ordem` decimal (ex.: 3.5), sem renumerar os demais.
- Ao encerrar tarefa que gere decisão: atualizar a Decisões vigentes com `update_content` na seção correspondente (nunca `replace_content`) + registrar na subpágina **📜 Histórico de decisões** (`3d12f3f4-b9b2-815e-9643-edc69db65f5c`), com `insert_content` e `position: start`, com data e card de origem. A linha nova vai **na subpágina**, nunca de volta na página-mãe (card 6.1,5, 04/09/2026).

## Estado atual (04/09/2026)

Concepção concluída; plano v1.1 aprovado com as 9 respostas do dono do produto; decisões técnicas fechadas. **Fases 0 a 05 concluídas; Fase 06 (Trilha e Estoque) em andamento.** Target de go-live: outubro/2026 (adoção provavelmente em fases). O estado corrente de verdade é o board do Notion — esta linha envelhece, ele não. Detalhes e pendências: Decisões vigentes no Notion.
