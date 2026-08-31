> **Nota (31/08/2026):** as decisões em aberto da seção 11 foram respondidas pelo dono do produto e por Irineu. O registro atualizado está na página Notion "Gestão Interativo — Decisões vigentes", que prevalece sobre este documento.

# Plano de Projeto — Sistema de Gestão Pedagógica e de Material Didático

Substituto da planilha "Gestão Interativo". Versão 1.0 — 30/08/2026.
Base: `claude/analise-planilha-entendimento.md` (18 pontos validados com Irineu).

---

## 1. Visão e objetivos

Construir um web app (também publicável como app Android/iOS) que substitua a planilha na gestão dos alunos dos três métodos de ensino — Interativo, Inglês e Modular — resolvendo os problemas estruturais da planilha: dados de aluno redigitados em vários lugares, capacidade de turma controlada "no olho", demanda de apostilas calculada só pelo próximo livro, e regras de negócio escondidas em fórmulas.

Objetivos mensuráveis do sistema:

1. **Aluno único**: um cadastro, referenciado por turmas, trilha, estoque e certificados. Zero redigitação de nome/código.
2. **Vagas confiáveis**: capacidade de cada bloco de horário derivada da sala/PCs, com bloqueio de admissão quando lotado e alertas quando a capacidade cai.
3. **Compra de apostilas planejada**: pedido sugerido = demanda imediata + projeção por período + estoque mínimo − estoque atual.
4. **Entrega em um ato**: registrar a entrega de uma apostila baixa o estoque, marca a trilha e alimenta o histórico de ritmo do aluno.
5. **Pendências visíveis**: aluno ativo sem turma, STANDBY prolongado, previsão vencida, turma acima da capacidade, aluno no último livro sem checklist de certificado.
6. **Permissões configuráveis** por perfil, sem deploy.

## 2. Escopo

**Dentro do escopo (v1):**
- Cadastro de alunos (com código SGF como referência externa), status e histórico de status.
- Catálogo curricular: combos → cursos → materiais (apostilas), inclusive estrutura livro → módulos do Modular.
- Turmas por horário (Interativo/Inglês) e turmas por curso (Modular) com progressão de módulo em conjunto.
- Salas, PCs e manutenção; capacidade de turma derivada dos PCs.
- Estoque de apostilas: movimentos, pedidos de compra, estoque mínimo, demanda imediata e projetada.
- Trilha do aluno com entregas.
- Checklist de certificado disparado ao chegar no último livro.
- Dashboard (equivalente ao atual, melhorado) e central de pendências/alertas.
- Administração: usuários, perfis, matriz de permissões, parâmetros.
- Migração inicial da planilha (etapa própria, após a estrutura pronta).

**Fora do escopo (v1), mas previsto no modelo:**
- Integração com o SGF (futuro, assíncrona — o modelo guarda `codigo_sgf` e há ponto de importação).
- Multi-unidade operacional (o modelo já nasce com `unidade_id` em tudo; a UI trata uma unidade).
- Catálogo MSE (encerrado em 31/08/2026 — não migrar títulos nem estoque MSE).
- Financeiro, frequência/chamada por aula, portal do aluno.

## 3. Perfis e permissões

Quatro perfis iniciais: **direção**, **pedagógico**, **secretaria**, **monitor**. As permissões são registros no banco (matriz perfil × permissão), editáveis pela direção em tela própria. O código verifica *permissões*, nunca *perfis* — assim novos perfis ou rearranjos não exigem deploy.

Permissões (granularidade sugerida — verbo por recurso):

| Recurso | Permissões |
|---|---|
| Alunos | ver, criar, editar, alterar status, excluir |
| Turmas / horários | ver, alocar aluno, remover aluno, editar bloco (professor, sala) |
| Trilha do aluno | ver, editar trilha, registrar entrega |
| Estoque | ver, lançar entrada, lançar saída/ajuste, gerir pedidos de compra |
| Materiais / cursos / combos | ver, editar |
| Salas / PCs | ver, editar, registrar manutenção |
| Certificados | ver, marcar pedagógico, marcar financeiro, marcar formatura, gerir certificado |
| Dashboard / relatórios | ver |
| Administração | gerir usuários, gerir perfis e permissões, gerir parâmetros, gerir unidades |

Matriz inicial proposta (ajustável na UI): direção tem tudo; pedagógico gere alunos, turmas, trilhas, certificados (pedagógico/formatura) e vê estoque; secretaria gere alunos, turmas, materiais, estoque, pedidos e o certificado (pedido/entrega); monitor registra entregas, lança saídas de estoque, marca "financeiro OK" e vê turmas e alunos.

No Supabase, isso se traduz em: tabela `permissao`, `perfil`, `perfil_permissao`, `usuario_perfil`; função SQL `tem_permissao(codigo)` usada nas políticas de RLS e nos guards do app Flutter. As políticas de RLS filtram também por `unidade_id` do usuário.

## 4. Arquitetura e stack

Escolhas alinhadas às preferências (Flutter/Dart, Supabase, Cloudflare) e ao custo próximo de zero:

| Camada | Tecnologia | Custo esperado |
|---|---|---|
| Front-end | Flutter (web + Android + iOS, um código) | 0 |
| Hospedagem web | Cloudflare Pages (build Flutter web estático) | 0 |
| Banco, auth, API | Supabase (Postgres + Auth e-mail/senha + PostgREST + RLS) | 0 no free tier; ~US$ 25/mês no Pro se necessário |
| Lógica de servidor | Funções SQL/PL-pgSQL e triggers no Postgres; Edge Functions só quando indispensável; `pg_cron` para rotinas (alertas diários, recálculo de projeção) | 0 |
| Publicação em lojas | Google Play (US$ 25 único) e Apple App Store (US$ 99/ano) — únicos custos inevitáveis | — |
| Observabilidade | Logs do Supabase; opcionalmente Sentry (free tier) no Flutter | 0 |

Diretrizes de arquitetura:

- **Regras de negócio no banco** (funções e triggers), para valerem igualmente na web, nos apps e em futuras integrações: cálculo de capacidade, bloqueio de admissão, entrega em um ato, disparo do checklist, geração de pendências.
- **Views SQL para leitura** (dashboard, demanda, pendências) — o Flutter consome tabelas/views via `supabase_flutter`, sem camada de API própria.
- **Multi-unidade desde o schema**: todas as tabelas de negócio têm `unidade_id`; RLS restringe pela unidade do usuário; a v1 cria uma única unidade.
- **Auditoria mínima**: `criado_em/por`, `atualizado_em/por` em tudo; histórico explícito de status do aluno e de movimentos de estoque (imutáveis; correções por estorno).
- **Mitigação do free tier**: projetos Supabase gratuitos pausam após 7 dias sem uso; um Cloudflare Worker agendado fazendo um `select` diário evita a pausa. Backups: `pg_dump` semanal via GitHub Action para um bucket R2 (grátis até 10 GB).
- **Flutter**: `go_router`, gerenciamento de estado simples (Riverpod), `supabase_flutter`; layout responsivo (desktop-first para secretaria, mobile-friendly para monitor).

## 5. Modelo de dados (conceitual)

Nomes em português, snake_case. Todas as tabelas de negócio: `id uuid`, `unidade_id`, auditoria.

### 5.1 Organização e acesso
- `unidade` — nome, ativo.
- `usuario` (espelha `auth.users`) — nome, e-mail, unidade_id, ativo.
- `perfil`, `permissao`, `perfil_permissao`, `usuario_perfil`.
- `parametro` — chave/valor por unidade (ex.: dias para alerta de STANDBY, horizonte da projeção).

### 5.2 Catálogo curricular
- `metodo` — INTERATIVO, INGLES, MODULAR.
- `material` (apostila) — codigo, nome, metodo_id, categoria (Informática, Design, Kids, Programação, Administrativo, Inglês, Modular), estoque_minimo, ativo. Código único **por método** (resolve a colisão de códigos entre catálogos).
- `curso` — nome, metodo_id (ex.: Informática, Gestão Financeira, Inglês, Massagem).
- `curso_material` — curso_id, material_id, ordem. Sequência padrão de apostilas do curso.
- `modulo` — curso_id, material_id (livro ao qual pertence), nome, ordem. Usado pelo Modular (ex.: Massagem V1 → "História, Ética e Higiene"). Substitui `Base Modular`.
- `combo` — nome, metodo_id (produto contratado, ex.: Secretariado Executivo).
- `combo_curso` — combo_id, curso_id, ordem.

### 5.3 Alunos
- `aluno` — codigo_sgf (único por unidade, opcional), nome, metodo_id, combo_id, status (ATIVO, ACELERAR, STANDBY, TRANCADO, CANCELADO, FORMADO), prev_conclusao_curso (informada), data_inicio, observacoes, conferido (bool).
- `aluno_status_hist` — aluno_id, status_anterior, status_novo, data, usuario, motivo.
- `aluno_material` (trilha) — aluno_id, material_id, ordem, origem (COMBO | MANUAL), entregue (bool), data_entrega, movimento_estoque_id. Gerada a partir do combo na matrícula e editável individualmente. "Livro atual" = primeiro não entregue; "próximo" = o seguinte; "FIM" = nenhum pendente.

### 5.4 Infraestrutura física
- `sala` — nome, tipo (LABORATORIO, SALA_MODULAR), capacidade_nominal.
- `pc` — sala_id, identificador, status (OPERACIONAL, MANUTENCAO, DESATIVADO), e-mail/credenciais **em campo criptografado ou fora do sistema** (recomendação: não armazenar senhas em texto).
- `pc_manutencao` — pc_id, tipo (PREVENTIVA, CORRETIVA, CONFIGURACAO), data_inicio, data_fim, descricao, pc_substituto_id.

### 5.5 Turmas por horário (Interativo e Inglês)
- `professor` — nome, ativo.
- `bloco_horario` — dia_semana, hora_inicio, metodo_id, professor_id, sala_id, capacidade_override (nullable), ativo. Substitui os 6 blocos × 6 abas.
- `bloco_aluno` — bloco_id, aluno_id, tipo (REM, PRE, REP, NOVO), data_inicio_prevista (para NOVO), ativo. Um aluno pode estar em mais de um bloco (aceleração).

Capacidade efetiva do bloco = `capacidade_override` se definido, senão número de PCs OPERACIONAIS da sala (mín. com capacidade_nominal). Aluno remoto ocupa vaga.

### 5.6 Turmas Modular
- `turma_modular` — curso_id, nome, sala_id, capacidade, data_inicio, ativo.
- `turma_modular_modulo` — turma_id, modulo_id, data_inicio, prev_conclusao, concluido. Cronograma da turma (todos avançam juntos).
- `turma_modular_aluno` — turma_id, aluno_id, data_entrada, ativo.

A trilha do aluno modular (`aluno_material`) contém os livros do curso; a previsão de necessidade de cada livro deriva do `turma_modular_modulo` do primeiro módulo daquele livro.

### 5.7 Estoque e compras
- `movimento_estoque` — material_id, tipo (ENTRADA, SAIDA, AJUSTE, ESTORNO), quantidade, data, aluno_id (saídas), pedido_item_id (entradas), usuario, observacao. Imutável.
- `pedido_compra` — numero, status (RASCUNHO, ENVIADO, PARCIAL, RECEBIDO, CANCELADO), data_envio, fornecedor, observacao.
- `pedido_item` — pedido_id, material_id, qtd_pedida, qtd_recebida.
- Views: `v_estoque_atual` (soma dos movimentos), `v_demanda_imediata`, `v_demanda_projetada`, `v_pedido_sugerido`.

### 5.8 Certificados e pendências
- `certificado_checklist` — aluno_id, data_fim_curso, pedagogico_ok, financeiro_ok, formatura (bool), certificado_status (NAO_PEDIDO, PEDIDO, ENTREGUE), observacoes, e quem/quando marcou cada item.
- `pendencia` — tipo, referencia (aluno/bloco/material), descricao, severidade, criada_em, resolvida_em, resolvida_por. Gerada por rotina/trigger; a UI lista e permite resolver ou ignorar com justificativa.

## 6. Regras de negócio

**Alunos e status**
- Transições permitidas: ATIVO ⇄ ACELERAR; ATIVO/ACELERAR → STANDBY; STANDBY → ATIVO/ACELERAR ou → TRANCADO; qualquer → CANCELADO; ATIVO/ACELERAR → FORMADO (exige checklist de certificado com certificado ENTREGUE ou confirmação da direção).
- Todo aluno ATIVO ou ACELERAR deve estar em ≥ 1 bloco (Interativo/Inglês) ou em 1 turma modular. Caso contrário: pendência "aluno sem turma".
- Ao passar para STANDBY, TRANCADO, CANCELADO ou FORMADO, o aluno é removido das turmas (libera vaga). Voltar a ATIVO exige realocar.
- STANDBY há mais de N dias (parâmetro, sugestão 30) gera pendência "avaliar trancamento".
- Previsão de conclusão do curso anterior à data atual para aluno ativo gera pendência "previsão vencida".
- Aluno ACELERAR sem segundo bloco gera aviso informativo (não bloqueia).

**Vagas e capacidade**
- Capacidade efetiva do bloco conforme 5.5. Admissão de aluno em bloco é bloqueada se `alocados ≥ capacidade efetiva`.
- Quando um PC entra em manutenção sem substituto, a capacidade cai; blocos já acima da nova capacidade **não são reduzidos**: gera pendência "bloco acima da capacidade" e novas admissões ficam bloqueadas até normalizar.
- Dashboard: vagas livres = capacidade efetiva − alocados (mín. 0), por dia/horário e por método.

**Trilha e entrega de apostila**
- Na matrícula, a trilha é gerada a partir do combo (`combo_curso` → `curso_material`, na ordem). Pode ser ajustada por aluno (inserir, remover, reordenar) com registro de origem MANUAL.
- **Registrar entrega** (ação única): cria `movimento_estoque` SAÍDA (qtd 1, aluno), marca `aluno_material.entregue = true` com data, e recalcula livro atual/próximo. Se não houver estoque, a entrega é bloqueada (ou permitida com justificativa e estoque negativo sinalizado — parâmetro).
- Estorno de entrega gera movimento ESTORNO e desmarca a trilha.
- Quando o último item da trilha é entregue (estado "FIM"), o sistema cria automaticamente o `certificado_checklist` e a pendência "aluno no último livro".

**Estoque e compras**
- Estoque atual = Σ entradas − Σ saídas ± ajustes. Nunca editado diretamente.
- **Demanda imediata** por material = nº de alunos ativos cujo *próximo* livro é o material (equivalente à coluna DEMANDA da planilha).
- **Projeção por período** (horizonte H em dias, parâmetro; ex.: 30/60/90): para cada aluno ativo, estimar a data em que cada livro futuro será necessário:
  - ritmo do aluno = média de dias entre entregas consecutivas dos últimos livros (mín. 2 entregas);
  - sem histórico suficiente: (prev_conclusao_curso − hoje) ÷ nº de livros restantes;
  - sem previsão: média de ritmo do método (parâmetro inicial calibrado na migração);
  - Modular: usa a `prev_conclusao` do módulo anterior na turma (o livro é necessário quando a turma entra no primeiro módulo dele).
  - Resultado: `v_demanda_projetada(material, mês, quantidade)`.
- **Pedido sugerido** = demanda imediata + demanda projetada dentro de H + estoque mínimo − estoque atual − quantidade já pedida e não recebida; se ≤ 0, não sugere.
- Receber um pedido (total ou parcial) gera movimentos ENTRADA vinculados ao item.

**Certificados**
- Checklist criado automaticamente no "FIM". Cada item registra quem e quando marcou; permissões distintas por item (financeiro = monitor por padrão).
- Quando todos os itens estão OK e certificado ENTREGUE, o sistema sugere mudar o status para FORMADO.

**PCs**
- Registrar manutenção corretiva muda o PC para MANUTENCAO até `data_fim`; a rotina recalcula capacidades e pendências dos blocos da sala.
- Um `pc_substituto_id` mantém a capacidade.

## 7. Módulos funcionais (telas)

1. **Login e seleção de unidade** (unidade única na v1, mas pronta).
2. **Dashboard** — cards por método: ativos, acelerar, standby, trancados, último livro, conclusões por semestre; grade de vagas por dia/horário (Interativo e Inglês); lotação por curso modular; pendências abertas.
3. **Alunos** — lista com filtros (método, status, turma, combo), ficha do aluno com abas: dados, trilha (com botão "Registrar entrega"), turmas, histórico de status, certificado.
4. **Turmas por horário** — visão semanal (dia × horário) mostrando ocupação/capacidade e professor; ao clicar, lista de alunos com tipo (REM/PRE/REP/NOVO), adicionar/remover com validação de vaga.
5. **Turmas Modular** — por curso: alunos, cronograma de módulos com datas, botão "avançar módulo".
6. **Materiais e estoque** — catálogo (por método/categoria), estoque atual, estoque mínimo, movimentações, lançamento de entrada/ajuste.
7. **Compras** — painel de pedido sugerido (imediato + projeção + mínimo), criação de pedido, recebimento.
8. **Projeção de demanda** — tabela material × mês, com detalhamento por aluno.
9. **Certificados** — fila de alunos no último livro, checklist com quem/quando.
10. **Salas e PCs** — cadastro, status, manutenção, impacto na capacidade.
11. **Pendências** — central com filtros por tipo e severidade; resolver/ignorar com justificativa.
12. **Administração** — usuários, perfis, matriz de permissões, parâmetros, cursos/combos/módulos, professores.
13. **Importação** (usado na migração e reaproveitável para o SGF) — upload de arquivo, validação, relatório de erros, aplicação.

## 8. Migração da planilha (etapa própria)

Executada depois que cadastros, turmas, trilha e estoque estiverem prontos. Princípios: **reexecutável** (dados mudam até a virada), **auditável** (relatório de tudo que foi transformado/descartado) e **ensaiada** (pelo menos um dry-run antes do go-live).

Mapeamento fonte → destino:

| Aba(s) | Destino | Limpezas |
|---|---|---|
| Ger. Apost, Apost. Inglês, Apost. Modular (CADASTRO) | `material` | Descartar títulos MSE; código único por método; "FIM"/"Não recebeu" não são materiais |
| Gerência, Ger. Inglês, Ger. Modular | `aluno`, `aluno_material` | Descartar "MACRO", "Fake 02", "BALANÇO"; trim de nomes; normalizar status ("Faltante" → revisar); prev. 2050/2023 marcadas para revisão |
| Base Modular + validações das abas por curso | `curso`, `modulo`, `curso_material` | Corrigir grafias duplicadas (Terapêutica) |
| Segunda…Sábado | `bloco_horario`, `bloco_aluno`, `professor` | "R" → REP; resolver códigos divergentes por nome (ex.: 4433/3605); "(dd/mm)" no nome → `data_inicio_prevista` e tipo NOVO |
| Massagem…Depilação + Ger. Modular | `turma_modular`, `turma_modular_modulo`, `turma_modular_aluno` | Ger. Modular é a fonte oficial dos alunos; datas de módulo vêm das abas por curso |
| Ger. Apost SAÍDAS/ENTRADAS | `movimento_estoque` | Manter datas; saídas sem aluno viram AJUSTE; conferir com flags "Entregue" da trilha e listar divergências |
| Pedidos | `material.estoque_minimo` | Ajustes manuais (+5, +7…) viram estoque mínimo inicial |
| Certificados | `certificado_checklist` | — |
| PCS | `sala`, `pc`, `pc_manutencao` | Credenciais não migradas em texto puro |
| Dashboard | (nada) — recalculado por views | Servir de conferência: totais do dashboard atual vs. novo |

Passos: (1) script de extração da planilha (Python/openpyxl, já prototipado nesta análise) gera CSVs normalizados + relatório de inconsistências; (2) Irineu revisa a lista de exceções (alunos sem turma, códigos divergentes, previsões atípicas); (3) dry-run em projeto Supabase de homologação; (4) conferência de totais contra o Dashboard da planilha; (5) na data da virada, novo snapshot da planilha, reexecução e congelamento da planilha (somente leitura).

## 9. Fases e entregas

Estimativas indicativas para uma pessoa desenvolvendo em tempo parcial; ajustar após a Fase 0.

| Fase | Entrega | Conteúdo | Esforço |
|---|---|---|---|
| 0 | Fundação | Projeto Supabase, schema base (unidade, usuários, perfis, permissões, parâmetros), RLS, app Flutter com login, deploy web no Cloudflare Pages, CI (GitHub Actions), backup | 2 sem. |
| 1 | Cadastros | Materiais, cursos, módulos, combos, professores, salas/PCs, alunos (CRUD + status + histórico), tela de administração de permissões | 3 sem. |
| 2 | Turmas e vagas | Blocos de horário, alocação com validação de capacidade, capacidade derivada de PCs, manutenção, pendências básicas (sem turma, acima da capacidade), grade semanal | 3 sem. |
| 3 | Trilha e estoque | Geração da trilha pelo combo, registrar entrega (ato único), movimentos, estoque atual, estoque mínimo, demanda imediata, pedidos de compra e recebimento | 3 sem. |
| 4 | Modular | Turmas por curso, cronograma de módulos, avanço conjunto, trilha modular | 2 sem. |
| 5 | Inteligência | Projeção de demanda por período, pedido sugerido, checklist de certificados automático, alertas de STANDBY/previsão vencida, dashboard completo | 3 sem. |
| 6 | Migração e go-live | Ferramenta de importação, dry-run, revisão de exceções, virada, congelamento da planilha, treinamento por perfil | 2–3 sem. |
| 7 | Apps e evolução | Publicação Android/iOS, ajustes pós-uso, importação assíncrona do SGF quando houver formato | contínuo |

Marcos de validação com o usuário: fim da Fase 1 (cadastros e permissões), fim da Fase 3 (fluxo completo de um aluno: matrícula → turma → entrega → estoque), fim da Fase 5 (dashboard e projeção comparados à planilha), go-live.

## 10. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Free tier do Supabase pausar o projeto por inatividade | Worker agendado no Cloudflare; monitorar; migrar ao Pro se o uso justificar |
| Projeção de demanda imprecisa no início (pouco histórico de entregas) | Estratégia em cascata (ritmo do aluno → previsão do curso → média do método); apresentar sempre a demanda imediata ao lado; recalibrar após 3 meses |
| Dados da planilha inconsistentes na virada | Migração reexecutável com relatório de exceções; revisão humana antes do go-live; planilha congelada após a virada |
| Publicação nas lojas (revisão da Apple, contas de desenvolvedor) | Web primeiro (PWA instalável); lojas na Fase 7 sem bloquear o uso |
| Regras em código Flutter divergirem entre web e app | Regras no banco (funções/triggers/RLS); o app só orquestra |
| Permissões configuráveis mal definidas exporem dados | Matriz inicial conservadora; RLS como última barreira; log de alterações de permissão |
| Credenciais de PCs armazenadas no sistema | Não migrar em texto puro; se necessário, campo criptografado com acesso restrito à direção |

## 11. Decisões em aberto (para a Fase 0)

1. Nome do sistema e identidade visual básica.
2. Política quando não há estoque no momento da entrega: bloquear ou permitir com estoque negativo sinalizado.
3. Horizonte padrão da projeção (30/60/90 dias) e N dias de STANDBY para alerta.
4. Repositório (GitHub) e ambientes: um projeto Supabase de homologação e um de produção, ou branches do Supabase.
5. Se o tipo de presença (REM/PRE/REP/NOVO) é atributo da alocação (aluno × bloco), como modelado, ou se REP deve ser um lançamento pontual por data (reposição em dia específico).

## 12. Próximos passos imediatos

1. Validar este plano (especialmente modelo de dados, regras da seção 6 e faseamento).
2. Fechar as decisões da seção 11.
3. Iniciar a Fase 0: criar projeto Supabase, repositório, esqueleto Flutter e a primeira migração de schema (organização, acesso e permissões).
