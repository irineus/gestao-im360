# Wireframes das 13 telas — card 2.6

> **Fonte da estrutura das telas.** O card 1.9 fechou a identidade (cores, tipografia, badges); o
> card 2.3 fechou **o que** cada tela lê (views e conjuntos de permissão); o card 2.4 fechou **quem**
> abre cada rota. Este card fecha **como cada tela se organiza**: layout, hierarquia, navegação,
> estados e o comportamento desktop × mobile. O acabamento visual (componentes Flutter, espaçamentos,
> tema) é do card **2.7**, que consome este documento junto com `docs/identidade-visual.md`.

Data: 01/09/2026. Base: `docs/plano-projeto-sistema.md` §7, `docs/views-leitura.md` (§7–§12),
`docs/permissoes-matriz.md` §6, `docs/regras-negocio-funcoes.md` (§3–§10), `docs/projecao-demanda.md`
§6, `docs/identidade-visual.md`.

---

## 1. Escopo

**Neste documento:** as 13 telas do plano §7, cada uma com o wireframe desktop, a variante mobile
quando o fluxo a exige, as fontes de dados (view/função por região da tela), as ações com suas
permissões e os estados obrigatórios.

**Não está aqui, de propósito:**

| Assunto | Dono |
|---|---|
| Design visual: componentes, tema claro/escuro aplicado, espaçamentos, ícones | card 2.7 |
| SQL das views de tela ainda não escritas (`v_aluno_lista`, `v_bloco_alunos`…) | cards das telas (2.3 §12.1) |
| Conjunto exato da tela de Importação | card 9.1 |
| Textos finais de erro e de estado vazio | card 2.7 (a partir do catálogo de erros do 2.2 §12) |

---

## 2. Princípios transversais

### 2.1 Shell responsivo: um app, duas ergonomias

Dois breakpoints, três faixas (nomenclatura para o card 2.7):

| Faixa | Largura | Navegação | Uso típico |
|---|---|---|---|
| `desktop` | ≥ 1024 px | menu lateral fixo (240 px), conteúdo ao lado | secretaria e direção, no balcão |
| `tablet` | 600–1023 px | menu lateral colapsado em ícones (72 px) | notebook pequeno, tablet |
| `mobile` | < 600 px | barra inferior + gaveta "Mais" | monitor no laboratório, celular |

Desktop-first: as tabelas densas (alunos, estoque, compras) são desenhadas para a faixa `desktop` e
**degradam por prioridade de coluna** (§2.6) — nunca por rolagem horizontal da página inteira.
No `mobile`, as jornadas do monitor (registrar entrega, marcar financeiro OK, abrir manutenção,
consultar a grade) têm alvo de toque ≥ 44 px e cabem em uma mão; as demais telas continuam
acessíveis, apenas menos otimizadas.

### 2.2 Rota, botão e permissão

- **A rota** só aparece na navegação se o usuário tem o **conjunto mínimo** do card 2.4 §6 — o
  conjunto que faz a tela mostrar número certo, não a permissão óbvia.
- **O botão de ação** é guardado pela permissão de ação (`estoque.lancar_saida` no "Registrar
  entrega", `turmas.alocar` no "Adicionar aluno").
- **Decisão deste card: botão sem permissão é *ocultado*, não desabilitado.** Botão desabilitado
  sugere que algo na tela pode destravá-lo (preencher um campo, selecionar uma linha); permissão não
  destrava na tela. A exceção é ação **indisponível pelo estado do dado** (ex.: "Avançar módulo" com
  o último módulo concluído): aí o botão fica visível e desabilitado, com tooltip/legenda do motivo —
  o usuário pode conseguir o estado, não a permissão.
- A tela **nunca** decide regra: chama a função do card 2.2 e reage ao resultado. O guard existe para
  não oferecer o que vai falhar; quem decide é o banco.

### 2.3 Estados obrigatórios de toda tela

Todo wireframe abaixo assume estes quatro estados, que o card 2.7 componentiza uma vez:

1. **Carregando** — skeleton na área de conteúdo; nunca tela branca.
2. **Vazio** — texto curto dizendo *por que* pode estar vazio e qual a próxima ação ("Nenhum aluno
   com esses filtros — limpar filtros"). Estado vazio de tabela nunca é só uma tabela sem linhas.
3. **Erro** — o Flutter trata pelo `codigo` estável do erro (card 2.2 §1.2), nunca pelo texto;
   mensagem em português + ação de repetir. Erro de RLS/permissão inesperado exibe o código para
   diagnóstico.
4. **Sem permissão** — rota guardada nem chega a abrir; se o estado ocorrer (deep-link, permissão
   revogada em sessão aberta), tela inteira de "Sem acesso" com o conjunto que falta, sem vazar dado.

### 2.4 Vocabulário visual (do card 1.9, obrigatório aqui)

- **Status do aluno = badge preenchido tonal** (ATIVO, ACELERAR, STANDBY, TRANCADO, CANCELADO,
  FORMADO). **Tipo na turma = badge de contorno** (NOVO, REM, PRE, REP). Nunca misturar as formas.
- Numerais tabulares em toda tabela, grade e valor de estoque.
- Cor nunca é o único portador: linha em alerta tem ícone além do fundo; badge sempre com rótulo.
- Vermelho só para erro/destrutivo; "acima da capacidade" é erro (vermelho), "abaixo do mínimo" é
  atenção (âmbar).

### 2.5 Convenções dos desenhos

Wireframes em ASCII, sem escala. `[Botão]` = ação; `(•)`/`( )` = seleção; `[v]` = dropdown/filtro;
`▤` = tabela; `⠿` = card; `…` = repetição do padrão. O menu lateral é omitido dos desenhos a partir
da tela 3 — é sempre o mesmo shell. Colunas marcadas com `†` são as primeiras a sair na degradação
para telas estreitas (prioridade de coluna, §2.1).

---

## 3. Navegação

### 3.1 Menu lateral (desktop) — ordem fixa

A ordem segue a frequência de uso da operação diária, não a numeração do plano:

```
┌──────────────────────┐
│ ⌂ [logo horizontal]  │   cabeçalho: logotipo + nome da unidade (unidades.ler)
├──────────────────────┤
│ ▦ Dashboard          │   rota 2
│ ◉ Alunos             │   rota 3
│ ▦ Turmas             │   rota 4 (grade semanal)
│ ▦ Turmas Modular     │   rota 5
│ ⚑ Pendências (12)    │   rota 11 — contador de abertas ALTA
│ ─────────────        │
│ ▤ Materiais/Estoque  │   rota 6
│ ▤ Compras            │   rota 7    ← só direção e secretaria
│ ▤ Projeção           │   rota 8
│ ▤ Certificados       │   rota 9
│ ▤ Salas e PCs        │   rota 10
│ ─────────────        │
│ ⚙ Administração      │   rota 12   ← só direção
│ ⇪ Importação         │   rota 13   ← só direção
├──────────────────────┤
│ 👤 Nome do usuário   │   menu: trocar senha, tema claro/escuro, sair
└──────────────────────┘
```

Item sem o conjunto mínimo da rota **não aparece** (§2.2). O contador de Pendências mostra só as de
severidade ALTA abertas (`v_pendencias_abertas`), para não banalizar o sino.

### 3.2 Barra inferior (mobile) — a jornada do monitor primeiro

```
┌────────────────────────────────────────────┐
│                 (conteúdo)                 │
├──────────┬──────────┬──────────┬───────────┤
│ ◉ Alunos │ ▦ Turmas │ ⚑ Pend.  │ ☰ Mais    │
└──────────┴──────────┴──────────┴───────────┘
```

- **Alunos** é o primeiro item: a jornada mais frequente do monitor é aluno → ficha → aba Trilha →
  Registrar entrega.
- **Mais** abre uma gaveta com as demais telas a que o usuário tem acesso (Dashboard incluído — no
  celular ele é consulta, não ponto de partida).
- Certificados aparece na gaveta; o atalho "financeiro OK" do monitor está na própria fila (tela 9).

### 3.3 Mapa de navegação entre telas

```
Login ─► Dashboard ─┬─ card método ──────────► Alunos (lista filtrada)
                    ├─ grade de vagas ───────► Turmas (grade, mesma célula)
                    ├─ lotação modular ──────► Turmas Modular (curso)
                    └─ pendências ───────────► Pendências
Alunos (lista) ─► Ficha do aluno ─┬─ aba Trilha ─► [Registrar entrega]
                                  ├─ aba Turmas ─► Turmas (bloco do aluno)
                                  └─ aba Certificado ─► checklist
Turmas (grade) ─► Bloco (lista de alunos) ─► Ficha do aluno
Compras ─► Pedido (rascunho/recebimento)
Projeção ─► detalhe por aluno (drill-down) ─► Ficha do aluno
Pendências ─► ação contextual da pendência (§14.3) ─► tela de destino
Salas e PCs ─► manutenção de PC ─► (pendências geradas) ─► Pendências
```

Regra: **toda referência a aluno, bloco, material ou pendência é clicável** e leva à tela
respectiva. É o que faz a central de pendências funcionar como fila de trabalho.

---

## 4. Tela 1 — Login e seleção de unidade

Rota: pública (login) → `unidades.ler` (seleção). Perfis: todos.

```
┌──────────────────────────────────────────────┐
│                                              │
│              [símbolo IM360]                 │
│           GESTÃO  IM360                      │
│                                              │
│   E-mail                                     │
│   ┌────────────────────────────────┐         │
│   └────────────────────────────────┘         │
│   Senha                                      │
│   ┌────────────────────────────────┐  [👁]   │
│   └────────────────────────────────┘         │
│                                              │
│   [        Entrar        ]                   │
│                                              │
│   Esqueci minha senha                        │
└──────────────────────────────────────────────┘
```

- E-mail/senha do Supabase Auth (decisão 18); **sem cadastro público** — usuário é convidado pela
  direção (tela 12). "Esqueci minha senha" dispara o fluxo de recuperação do card 3.5.
- **Seleção de unidade:** com **uma** unidade acessível (v1), a etapa é **pulada em silêncio** — a
  unidade entra na sessão e o nome aparece no cabeçalho. Com mais de uma (Fase 11), lista simples de
  cartões após o login. A tela existe no fluxo desde já para a Fase 11 não redesenhar o login.
- Erro de credencial: mensagem única ("e-mail ou senha inválidos"), sem revelar qual campo errou.
- Mobile: mesmo layout, formulário com corpo 16 px (evita zoom automático no iOS — card 1.9 §4).

---

## 5. Tela 2 — Dashboard

Rota: `alunos.ler + materiais.ler + turmas.ler + salas.ler + pendencias.ler`. Perfis: todos.

```
┌ Dashboard ─────────────────────────────── [semana ◄ atual ►] ┐
│                                                              │
│ ⠿ INTERATIVO        ⠿ INGLÊS           ⠿ MODULAR             │
│   142 ativos          38 ativos          61 ativos           │
│   12 acelerar         3 acelerar         —                   │
│   9 standby ⚠         2 standby          4 standby           │
│   5 último livro      1 último livro     2 último livro      │
│   3 sem previsão†     0 sem previsão†    1 sem previsão†     │
│                                                              │
│ ▤ Conclusões por semestre (por método)                       │
│   2026/2: 14   2027/1: 22   2027/2: 9    (4 vencidas ⚠)      │
│                                                              │
│ ▤ Vagas — Interativo e Inglês (semana corrente)              │
│   ┌────────┬─────┬─────┬─────┬─────┬─────┬─────┐             │
│   │        │ Seg │ Ter │ Qua │ Qui │ Sex │ Sáb │             │
│   │ 08:00  │ 2/10│ 0/10│ 3/10│ 1/10│10/10│ 4/6 │  n vagas/cap│
│   │ 09:30  │  …  │     │     │     │  ⚠  │     │  ⚠ = acima  │
│   └────────┴─────┴─────┴─────┴─────┴─────┴─────┘             │
│                                                              │
│ ▤ Lotação Modular          ⚑ Pendências abertas              │
│   Massagem     8/10        ALTA   3  ──► central             │
│   Eletricista 12/15        MÉDIA  7                          │
│   Depilação    5/6         BAIXA 12                          │
└──────────────────────────────────────────────────────────────┘
```

Fontes, por região: cards por método = `v_dashboard_alunos_metodo` (colunas `em_ultimo_livro` e
`sem_previsao` — **não** usar `em_fim` no card, que é outra leitura, card 2.3 §8.1); conclusões =
`v_dashboard_conclusoes_semestre` (mostrar `qtd_vencidas` junto, nunca escondê-las); tipos por bloco
(REM/PRE/REP/NOVO, linha secundária dos cards, omitida no desenho) = `v_dashboard_tipos_bloco` —
com a legenda "alocações, não alunos"; grade de vagas = `v_bloco_vagas_semana`; lotação Modular =
`v_turma_modular_lotacao`; pendências = `v_pendencias_abertas` agregada por severidade.

- **Toda célula/número é atalho** (§3.3): o "9 standby" abre Alunos filtrado; a célula da grade abre
  o bloco; a linha Modular abre a turma.
- `sem_previsao` fica ao lado das conclusões porque sem ele a soma dos semestres não fecha com o
  total de ativos (card 2.3 §8.1) — o dashboard mostra a conta fechando, não números soltos.
- Mobile: os cards por método empilham; grade de vagas e lotação viram listas verticais por dia.

---

## 6. Tela 3 — Alunos: lista e ficha

Rota: `alunos.ler + materiais.ler` (aba Trilha soma `estoque.ler`). Perfis: todos.

### 6.1 Lista

```
┌ Alunos ──────────────────────────────────────────────────────┐
│ [busca nome/código        ] [método v] [status v] [turma v]  │
│                             [combo v]      [+ Matricular]    │
│ ▤ ┌────────┬───────────────┬────────┬─────────┬────────────┐ │
│   │ Código │ Nome          │ Método†│ Status  │ Turmas†    │ │
│   ├────────┼───────────────┼────────┼─────────┼────────────┤ │
│   │ 4433   │ Afonso …      │ INT    │ [ATIVO] │ Seg 08:00  │ │
│   │ 3527   │ João Pedro …  │ ING    │ [STANDBY]│ —  ⚠      │ │
│   │  …     │               │        │         │            │ │
│   └────────┴───────────────┴────────┴─────────┴────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

- Fonte: `v_aluno_lista` (card 4.6). Filtros = os do plano (método, status, turma, combo) + busca
  por nome/`codigo_sgf`. Aluno ATIVO/ACELERAR sem turma recebe ícone ⚠ na coluna Turmas — é a
  pendência `ALUNO_SEM_TURMA` vista de onde a secretaria olha.
- `[+ Matricular]` exige `alunos.criar`; abre formulário com dados + combo (a trilha nasce do combo
  na matrícula — card 2.2 §5.1).
- Mobile: linha vira cartão (nome, código, badge de status, turmas); filtros numa folha (bottom
  sheet).

### 6.2 Ficha — cabeçalho e abas

```
┌ ◄ Alunos                                                     ┐
│ Afonso Nascimento           [ATIVO]   código SGF 4433        │
│ Interativo · combo Completo · prev. conclusão 2027/1         │
│ [Alterar status v]                       [Editar dados]      │
├──────┬────────┬────────┬───────────┬─────────────────────────┤
│ Dados│ Trilha │ Turmas │ Histórico │ Certificado             │
└──────┴────────┴────────┴───────────┴─────────────────────────┘
```

- `[Alterar status v]` (permissão `alunos.alterar_status`) só oferece as **transições válidas a
  partir do status atual** (card 2.2 §3.1); chama `fn_aluno_alterar_status` e trata os erros pelo
  código. Sair de ATIVO/ACELERAR avisa no diálogo: "o aluno será removido das turmas". FORMADO passa
  pelo gate do certificado; sem checklist ENTREGUE, o diálogo explica e só quem tem
  `alunos.formar_sem_certificado` vê a opção de confirmar mesmo assim.
- Reverter FORMADO/CANCELADO (`alunos.reverter_status`, só direção) fica **dentro** do Histórico
  (§6.5), não no cabeçalho — ação rara não disputa espaço com ação diária.

### 6.3 Aba Trilha — a tela do monitor

```
│ Trilha (combo Completo — 3 entregues, 11 pendentes)          │
│ ritmo: 1 apostila/23 dias†        [Editar trilha]            │
│ ▤ ┌───┬───────────────────┬──────────┬──────────────┐        │
│   │ # │ Apostila          │ Situação │              │        │
│   ├───┼───────────────────┼──────────┼──────────────┤        │
│   │ 1 │ INT-01 Básico 1   │ ✓ 12/05  │              │        │
│   │ 2 │ INT-02 Básico 2   │ ✓ 30/06  │ [Estornar]   │        │
│   │ 3 │ INT-03 Básico 3   │ ✓ 18/08  │ [Estornar]   │        │
│   │ 4 │ INT-04 Interm. 1  │ ► próxima│ [Registrar   │        │
│   │   │                   │ (est. 7) │   entrega]   │        │
│   │ 5 │ INT-05 Interm. 2  │ pendente │              │        │
│   │ … │                   │          │              │        │
│   └───┴───────────────────┴──────────┴──────────────┘        │
```

- Fonte: `v_aluno_trilha` (card 6.6) + saldo do próximo via `v_estoque_atual` (por isso a aba exige
  `estoque.ler`). O ritmo vem de `fn_ritmo_aluno` (ajuste não bloqueante do card de Ordem 5).
- **[Registrar entrega]** (`estoque.lancar_saida`) chama `fn_registrar_entrega` e reage aos três
  status de `tp_entrega_resultado` (card 2.2 §6.1):
  - `ENTREGUE` → confirmação com o próximo material já recalculado;
  - `REORDENADA` → aviso destacado: "Sem estoque de INT-04; entregue INT-05. INT-04 continua
    pendente e volta a ser a próxima quando houver estoque" + link para a pendência `ESTOQUE_ZERO`;
  - `BLOQUEADA_SEM_ESTOQUE` → alerta: nenhuma apostila da trilha tem estoque; pendência
    `COMPRA_SEM_ESTOQUE` aberta, com link.
  **Decisão deste card:** a tela **não pré-verifica saldo em Dart** antes de chamar — seria a
  terceira implementação da soma que o card 2.3 §4.1 proíbe. O saldo exibido ("est. 7") é
  informativo, vem da view, e a função é quem decide na transação. O desfazer imediato é o
  `[Estornar]` (`estoque.estornar`), oferecido nas entregas recentes.
- Se a entrega fecha a trilha (`em_fim = true`), a confirmação diz que o checklist de certificado
  foi aberto, com link para a aba Certificado.
- `[Editar trilha]` (`alunos.editar_trilha`) entra em modo de reordenação (arrastar) + incluir e
  remover item; grava por `fn_trilha_*`, histórico automático em `aluno_material_hist`.
- **Mobile:** esta aba é a jornada nº 1 do monitor — lista vertical, botão `[Registrar entrega]`
  em largura total fixado no rodapé, ≥ 44 px, diálogos de resultado em folha inferior.

### 6.4 Abas Dados e Turmas

- **Dados** (`alunos.editar` para salvar): cadastro, combo (mudar combo **não** regenera a trilha —
  abre `TRILHA_DIVERGENTE_COMBO`, e o formulário avisa isso ao trocar), previsão de conclusão
  (manual, decisão do plano), `codigo_sgf`.
- **Turmas**: blocos do aluno com **badge de contorno** do tipo (REM/PRE/REP/NOVO) e `tipo_desde`;
  reposições pontuais futuras (`bloco_aluno_reposicao`, status PREVISTA/REALIZADA/FALTOU); situação
  REP (`fn_rep_situacao`: débito, prazo da mais antiga) quando houver débito. Ações `[+ Alocar em
  bloco]` e `[Lançar reposição]` (`turmas.alocar`) abrem o seletor de bloco com vagas da grade
  (tela 4); remoção idem.

### 6.5 Aba Histórico

Linha do tempo de `aluno_status_hist` (status, quando, quem, motivo). No rodapé, para
FORMADO/CANCELADO: `[Reverter status]` (`alunos.reverter_status`) com motivo obrigatório.

### 6.6 Aba Certificado

Mesmo componente do checklist da tela 9 (§12.2), embutido na ficha. Existe nas duas telas porque as
jornadas são diferentes: a fila (tela 9) é "quem está chegando ao fim"; a ficha é "este aluno".

---

## 7. Tela 4 — Turmas por horário (grade semanal + bloco)

Rota: `turmas.ler + salas.ler + professores.ler + materiais.ler`. Perfis: todos.

### 7.1 Grade

```
┌ Turmas — grade semanal          [◄ semana 31/08–05/09 ►] ┐
│ [método v] [sala v]                      [+ Novo bloco]  │
│ ▤ ┌───────┬────────┬────────┬────────┬───────┬─────────┐ │
│   │       │ Seg    │ Ter    │ Qua    │ …     │ Sáb     │ │
│   ├───────┼────────┼────────┼────────┼───────┼─────────┤ │
│   │ 08:00 │ INT    │ INT    │ ING    │       │ INT     │ │
│   │       │ 8/10   │ 10/10  │ 4/6    │       │ 9/10    │ │
│   │       │ Marcos │ Marcos │ Paula  │       │ —  ⚠    │ │
│   ├───────┼────────┼────────┼────────┼───────┼─────────┤ │
│   │ 09:30 │ INT    │  ⚠11/10│  …     │       │         │ │
│   └───────┴────────┴────────┴────────┴───────┴─────────┘ │
│   célula: método · ocupação/capacidade · professor       │
└──────────────────────────────────────────────────────────┘
```

- Fonte: semana corrente = `v_bloco_vagas_semana`; outra semana = `fn_grade_semana(p_segunda)`
  (mesma aritmética, card 2.3 §7). A navegação de semana existe porque a **lotação é de uma data**:
  reposições pontuais entram na ocupação do dia.
- Estados da célula: lotado (ocupação = capacidade, neutro), **acima da capacidade** (vermelho + ⚠,
  mesmo fato da pendência `BLOCO_ACIMA_CAPACIDADE`), sem professor (⚠ âmbar). Célula vazia = sem
  bloco naquele dia/horário; com `turmas.criar`, clique oferece criar bloco ali.
- `[+ Novo bloco]` (`turmas.criar`): dia, hora, sala, método, professor, `capacidade_override`
  opcional — o formulário mostra a capacidade derivada dos PCs da sala ao lado, para o override ser
  uma decisão informada.
- Mobile: um dia por vez (abas Seg–Sáb), células em lista.

### 7.2 Bloco (lista de alunos do bloco)

```
┌ ◄ Grade   Seg 08:00 · Interativo · Lab 1 · Prof. Marcos ┐
│ Ocupação 8/10 (7 fixos + 1 reposição hoje)  [Editar]    │
│ ▤ ┌──────────────────┬────────┬───────────┬───────────┐ │
│   │ Aluno            │ Tipo   │ Desde     │           │ │
│   ├──────────────────┼────────┼───────────┼───────────┤ │
│   │ Afonso …         │ (REM)  │ 12/03     │ [Remover] │ │
│   │ Bianca …         │ (REP)  │ 20/08     │ [Remover] │ │
│   │ Caio … (reposição│ (REP)  │ hoje      │ [Remover] │ │
│   │  de Qua 27/08)   │ pontual│           │           │ │
│   └──────────────────┴────────┴───────────┴───────────┘ │
│ [+ Adicionar aluno]  [+ Lançar reposição]               │
└─────────────────────────────────────────────────────────┘
```

- Fonte: `v_bloco_alunos` (card 5.7) — alocações ativas + reposições da data. Reposição pontual
  aparece **na data dela**, marcada, com o bloco de origem da falta.
- `[+ Adicionar aluno]` (`turmas.alocar`) → busca de aluno + tipo; chama `fn_bloco_admitir` e trata
  `BLOCO_LOTADO` (o guard mostra as vagas, o banco decide). `[+ Lançar reposição]`
  (`turmas.alocar`; data passada exige `turmas.lancar_reposicao_retroativa`) chama
  `fn_reposicao_registrar` e **exibe o veredito da virada REP** que ela devolve (ajuste #7 do card
  2.5): se a resposta for "sugerida virada para contínuo", o aviso aparece aqui, na mão de quem
  lançou.
- `[Editar]` (`turmas.editar`): professor, sala, override. `[Remover]` confirma e avisa quando o
  aluno ficará sem turma (abre `ALUNO_SEM_TURMA` no dia seguinte).

---

## 8. Tela 5 — Turmas Modular

Rota: `turmas.ler + salas.ler + materiais.ler`. Perfis: todos.

```
┌ Turmas Modular                           [+ Nova turma] ┐
│ [curso v]                                               │
│ ⠿ Massagem — Turma A · Sala 2 · 8/10        ▼           │
│   módulo corrente: 3. Massoterapia (até 20/09) ⚠ atraso │
│   ▤ Cronograma: 1 ✓ · 2 ✓ · 3 ► (01/08–20/09) · 4 · 5   │
│   ▤ Alunos (8)  [+ Adicionar]                           │
│     │ Ana …    │ desde 01/06 │ [Remover]                │
│     │ …        │             │                          │
│   [Avançar módulo →]                                    │
│ ⠿ Eletricista — Turma B · 12/15             ▶           │
│ ⠿ Depilação — Turma A · 5/6                 ▶           │
└─────────────────────────────────────────────────────────┘
```

- Fonte: `v_turma_modular_lotacao` (cabeçalho e lotação) + cronograma de `turma_modular_modulo`.
  Módulo corrente e atraso vêm da view (`modulo_atrasado`); turma com tudo concluído aparece como
  "turma terminou" e **não some** da lista.
- `[Avançar módulo →]` (`turmas.editar`) chama a função do card 7.2 — avanço é **da turma em
  conjunto** (decisão do plano); o diálogo confirma o módulo que fecha e o que abre, com datas.
  Turma sem cronograma futuro mostra o aviso da pendência `TURMA_MODULAR_SEM_CRONOGRAMA` (card de
  Ordem 5): sem datas, a projeção dela cai para média do método.
- Alocação (`turmas.alocar`) valida vaga por turma (capacidade própria, não derivada de PCs).
- Mobile: cartões colapsados por turma; ações dentro do cartão expandido.

---

## 9. Tela 6 — Materiais e estoque

Rota: `materiais.ler + estoque.ler`. Perfis: todos (escrita conforme ação).

```
┌ Materiais e estoque ─────────────────────────────────────┐
│ [busca] [método v] [categoria v] [só abaixo do mínimo ☐] │
│                            [+ Novo material] [Ajustar]   │
│ ▤ ┌────────┬────────────────┬───────┬───────┬─────────┐  │
│   │ Código │ Material       │ Saldo │ Mínimo│ Último  │  │
│   ├────────┼────────────────┼───────┼───────┼─────────┤  │
│   │ INT-04 │ Intermediário 1│   0 ⚠ │   3   │ 28/08   │  │
│   │ INT-05 │ Intermediário 2│   7   │   3   │ 30/08   │  │
│   │ MOD-12 │ Elétrica básica│  -2 ✖ │   2   │ 15/08   │  │
│   │  …     │                │       │       │         │  │
│   └────────┴────────────────┴───────┴───────┴─────────┘  │
│ ── ao selecionar uma linha ──                            │
│ ▤ Movimentações INT-04     [período v] [tipo v]          │
│   30/08  SAÍDA   −1  Afonso (4433)   por Débora          │
│   28/08  ENTRADA +10 pedido #23      por Célia           │
│   12/08  ESTORNO +1  (estorno de …)  por Débora          │
└──────────────────────────────────────────────────────────┘
```

- Fontes: lista = `v_estoque_atual` (inclui saldo 0 e material inativo — filtro "ativos" ligado por
  padrão, desligável); movimentações = `v_material_movimento` (card 6.7).
- Saldo **negativo é destacado em erro, nunca escondido** (card 2.3 §4.1): é sintoma de AJUSTE
  errado ou de divergência da migração. Abaixo do mínimo = atenção (âmbar).
- Ações: `[+ Novo material]`/edição (`materiais.criar`/`editar`) — cadastro com método, categoria,
  estoque mínimo; `[Ajustar]` (`estoque.ajustar`) exige **motivo obrigatório** e lança AJUSTE via
  função. **Não existe "lançar entrada"** — entrada é sempre recebimento de pedido, na tela 7
  (decisão do card 2.4); o estado vazio das movimentações de um material novo diz isso e aponta
  para Compras.
- Estorno de SAÍDA fica na trilha do aluno (§6.3), onde há contexto; a listagem aqui é conferência.

---

## 10. Tela 7 — Compras

Rota: `materiais.ler + estoque.ler + alunos.ler + compras.ler`. Perfis: **direção e secretaria**
(decisão do card 2.3: sem `compras.ler` a parcela pendente zeraria e o sistema sugeriria comprar de
novo o que já está a caminho).

### 10.1 Pedido sugerido

```
┌ Compras ── [Pedido sugerido] [Pedidos] ──────────────────────┐
│ ▤ ┌────────┬─────────┬──────┬──────┬──────┬───────┬───────┐  │
│   │ Código │ Material│ Sal- │ Imed.│ Proj.│ Pend. │ Suge- │  │
│   │        │         │ do   │      │  †   │       │ rido  │  │
│   ├────────┼─────────┼──────┼──────┼──────┼───────┼───────┤  │
│   │ INT-04 │ Interm.1│  0   │  5   │  0   │  10   │  0    │  │
│   │ INT-06 │ Interm.3│  1   │  4   │  0   │   0   │  6    │  │
│   │  …     │         │      │      │      │       │       │  │
│   └────────┴─────────┴──────┴──────┴──────┴───────┴───────┘  │
│ [só sugerido > 0 ☑]      [Criar pedido com os sugeridos]     │
└──────────────────────────────────────────────────────────────┘
```

- Fonte: `v_pedido_sugerido` — **as parcelas ficam visíveis ao lado do total** (imediata, projetada,
  pedida pendente, saldo, mínimo): o usuário confere a conta em vez de acreditar nela (card 2.3
  §2.3). A coluna Projetada existe desde o primeiro dia mostrando `0` (reserva do card 2.3 §6.2);
  quando o card 8.2 preencher, a tela também mostra o `calculado_em` da projeção.
- O filtro "só sugerido > 0" é **da tela e desligável** — a view devolve tudo, inclusive o material
  que acabou de zerar.
- `[Criar pedido…]` (`compras.criar`) monta um RASCUNHO com os itens sugeridos, editável antes de
  enviar.

### 10.2 Pedidos

```
│ ▤ #24 RASCUNHO  01/09  3 itens          [Editar] [Enviar]    │
│   #23 PARCIAL   28/08  10 de 15 receb.  [Receber]            │
│   #22 RECEBIDO  12/08                   [ver]                │
│   #21 CANCELADO 05/08                   [ver]                │
│ ── recebimento (#23) ──                                      │
│   │ INT-04 │ pedido 10 │ recebido 10 │ [____] receber       │
│   │ INT-07 │ pedido  5 │ recebido  0 │ [__5_] receber       │
│   [Confirmar recebimento]                                    │
```

- Ciclo: RASCUNHO → ENVIADO → PARCIAL → RECEBIDO, ou CANCELADO (sem `delete` — pedido enviado vira
  CANCELADO e fica no histórico). Editar/enviar/cancelar = `compras.editar`; excluir item de
  rascunho = `compras.excluir`.
- `[Confirmar recebimento]` (`compras.receber`) recebe **por item, parcial por padrão** — gera
  ENTRADA via `fn_pedido_receber`. Quantidade acima da pedida só passa com
  `compras.receber_excedente` (direção): o campo aceita, e o erro do banco é traduzido para "acima
  do pedido — requer direção" para quem não tem.

---

## 11. Tela 8 — Projeção de demanda

Rota: `materiais.ler + estoque.ler + alunos.ler + turmas.ler` (o `turmas.ler` entrou pelo card de
Ordem 5 — a parcela MODULAR lê o cronograma). Perfis: todos.

```
┌ Projeção de demanda      calculada em 01/09 03:12 ⓘ ┐
│ [método v] [regra v]                                │
│ ▤ ┌────────┬──────────┬──────┬──────┬──────┬─────┐  │
│   │ Código │ Material │ set  │ out  │ nov  │ Σ   │  │
│   ├────────┼──────────┼──────┼──────┼──────┼─────┤  │
│   │ INT-04 │ Interm. 1│  3   │  2   │  1   │  6  │  │
│   │ INT-05 │ Interm. 2│  1   │  3   │  2   │  6  │  │
│   │  …     │          │      │      │      │     │  │
│   └────────┴──────────┴──────┴──────┴──────┴─────┘  │
│ ── célula INT-04 × out ── (detalhe ao vivo ⓘ)       │
│ ▤ │ Aluno   │ regra        │ prevista │ ritmo │     │
│   │ Afonso  │ RITMO_ALUNO  │ 12/10    │ 23 d  │     │
│   │ Bianca  │ MEDIA_METODO │ 20/10    │ (45 d)│     │
│   │ …       │              │          │       │     │
└─────────────────────────────────────────────────────┘
```

- Fontes: tabela = `v_demanda_projetada` (materializada pela rotina diária); detalhe =
  `v_projecao_aluno` **ao vivo**. O `calculado_em` é **obrigatório no cabeçalho** e o detalhe traz o
  aviso de defasagem: o total é da rotina (madrugada), o detalhe é de agora — podem divergir ao
  longo do dia (card de Ordem 5, §2.3).
- A **regra** (proveniência: RITMO_ALUNO / PREVISAO_CURSO / MEDIA_METODO / MODULAR) aparece no
  detalhe e como filtro — projeção sem proveniência não é revisável.
- Cada linha do detalhe leva à ficha do aluno; ali a previsão vencida (que derruba o aluno para
  média do método) pode ser corrigida.
- Estado vazio com projeção ausente (rotina falhou): aviso apontando a pendência `ROTINA_FALHOU` —
  não uma tabela zerada com cara de "sem demanda".

---

## 12. Tela 9 — Certificados

Rota: `certificados.ler + alunos.ler`. Perfis: todos.

### 12.1 Fila

```
┌ Certificados ────────────────────────────────────────────┐
│ [método v] [situação v]                                  │
│ ▤ ┌───────────────┬───────────┬──────────────┬────────┐  │
│   │ Aluno         │ Situação  │ Checklist    │ Status │  │
│   ├───────────────┼───────────┼──────────────┼────────┤  │
│   │ Afonso …      │ último    │ P ✓ F ✓ Fo ─ │ PEDIDO │  │
│   │               │ livro     │              │        │  │
│   │ Bianca …      │ FIM       │ P ✓ F ─ Fo ─ │ NÃO    │  │
│   │               │           │              │ PEDIDO │  │
│   └───────────────┴───────────┴──────────────┴────────┘  │
└──────────────────────────────────────────────────────────┘
```

- Fonte: `v_certificado_fila` (card 8.6) — inclui **as duas situações**, `em_ultimo_livro` (1
  pendente, dá tempo de pedir) e `em_fim` (0 pendentes), com rótulos distintos (card 2.3 §8.1).
  P/F/Fo = pedagógico, financeiro, formatura.

### 12.2 Checklist (mesmo componente da aba Certificado da ficha)

```
│ Afonso — checklist               fim do curso: 18/08     │
│  ☑ Pedagógico OK    por Paula, 20/08   (marcar_pedagogico)│
│  ☑ Financeiro OK    por Caio, 22/08    (marcar_financeiro)│
│  ☐ Formatura        —                  (marcar_pedagogico)│
│  Status do certificado: [NÃO PEDIDO ▸ PEDIDO ▸ ENTREGUE] │
│                                   (alterar_status)       │
│  ⓘ Com tudo OK e certificado entregue, o sistema sugere  │
│    FORMADO (pendência) — quem forma é uma pessoa.        │
└──────────────────────────────────────────────────────────┘
```

- Cada caixa é guardada pela sua permissão (por **item**, card 2.2 §8): o monitor vê o checklist
  inteiro mas só a caixa Financeiro é interativa para ele. "Quem/quando" aparece ao lado de cada
  item marcado (gravado por trigger, vale até para escrita direta).
- **Mobile (jornada nº 2 do monitor):** a fila filtrada por "financeiro pendente" com a caixa
  Financeiro acionável direto na lista, alvo ≥ 44 px, sem precisar abrir o checklist completo.

---

## 13. Tela 10 — Salas e PCs

Rota: `salas.ler + professores.ler`. Perfis: todos (escrita conforme ação).

```
┌ Salas e PCs                    [+ Nova sala] [+ Novo PC] ┐
│ ⠿ Laboratório 1 — cap. nominal 10 · efetiva 9 ⚠   ▼      │
│   ▤ │ PC-01 │ OPERACIONAL │             │ [Manutenção]   │
│     │ PC-02 │ MANUTENÇÃO  │ até 05/09   │ [Encerrar]     │
│     │       │ sem substituto ⚠          │                │
│     │ PC-03 │ DESATIVADO  │             │ [Reativar]     │
│     │  …    │             │             │                │
│   Blocos desta sala: Seg 08:00 (8/9) · Ter 08:00 (10/9 ✖)│
│ ⠿ Sala 2 (Modular) — cap. 15                      ▶      │
└──────────────────────────────────────────────────────────┘
```

- Fonte: `sala`/`pc`/`pc_manutencao` + `fn_capacidade_efetiva` por bloco. O cartão da sala mostra
  nominal × efetiva e **os blocos afetados com a ocupação atual** — o impacto na capacidade é
  visível antes e depois de registrar a manutenção.
- `[Manutenção]` (`salas.registrar_manutencao` — monitor incluído na matriz inicial, **pendente de
  confirmação do Irineu**, card 2.4 §9.2): formulário com data prevista de fim e substituto
  opcional; ao confirmar, o diálogo lista as consequências que a função disparou (recálculo,
  pendências `BLOCO_ACIMA_CAPACIDADE`/`PC_SEM_SUBSTITUTO` com links). Encerrar manutenção idem.
- Cadastro/edição (`salas.criar`/`editar`), professores no mesmo módulo (aba ou seção própria:
  nome, ativo — `professores.*`). Professor não se exclui, inativa-se.
- **Mobile (jornada nº 3 do monitor):** `[+ Manutenção]` acessível em dois toques a partir da lista
  de PCs; formulário mínimo (PC pré-selecionado, data fim, substituto opcional).
- **Credenciais dos PCs: fora do wireframe.** A política é do card 2.9 (pendente); nenhum campo de
  e-mail/senha de PC aparece em tela até lá — não desenhar o campo é o que impede o uso em texto
  puro enquanto a decisão não sai. **Superado em 01/09/2026 (card 2.9) e implementado no card 4.5:**
  a ficha do PC mostra o carimbo da credencial, e os botões "Ver" / "Gravar credencial" só
  aparecem para quem tem `salas.acessar_credencial` — ver `docs/politica-credenciais-pcs.md` §8.
- **O que o card 4.5 entregou desta tela, e o que ficou para a Fase 5 (02/09/2026):** a lista de
  salas é uma `TabelaIm360` (nominal, PCs operacionais/total, efetiva) e o painel da sala traz os
  PCs com a ação contextual da linha — Manutenção, Encerrar, Reativar — cada uma num formulário
  pequeno. A capacidade efetiva é **derivada na tela** (PCs OPERACIONAIS até o teto nominal) e é
  informativa; a de bloco é `fn_capacidade_efetiva` (card 5.2). "Blocos desta sala" e as
  consequências da manutenção (pendências, recálculo) são dos cards 5.4 e 5.6, e a tela diz isso
  na linha de apoio da seção. Amarrar `pc.status` à manutenção em aberto é o card 5.4; até lá,
  quem tem `salas.editar` escolhe no formulário se o status acompanha, e o monitor registra a
  manutenção com aviso de que o status não muda.

---

## 14. Tela 11 — Pendências (central)

Rota: `pendencias.ler`. Perfis: todos (resolver exige `pendencias.resolver` — monitor não tem).

### 14.1 Lista

```
┌ Pendências (22 abertas)                                  ┐
│ [severidade v] [tipo v] [há quanto tempo v]              │
│ ▤ ┌──────┬──────────────────────┬─────────┬───────────┐  │
│   │ Sev. │ Pendência            │ Aberta  │           │  │
│   ├──────┼──────────────────────┼─────────┼───────────┤  │
│   │ ALTA │ Compra sem estoque — │ há 2 d  │ [Ver] [✓] │  │
│   │      │ Afonso (4433)        │         │           │  │
│   │ ALTA │ Bloco acima da capa- │ há 1 d  │ [Ver] [✓] │  │
│   │      │ cidade — Seg 08:00   │         │           │  │
│   │ MÉDIA│ REP: sugerida virada │ hoje    │ [Executar]│  │
│   │      │ p/ contínuo — Bianca │         │ [Ver] [✓] │  │
│   │ BAIXA│ …                    │         │           │  │
│   └──────┴──────────────────────┴─────────┴───────────┘  │
└──────────────────────────────────────────────────────────┘
```

- Fonte: `v_pendencias_abertas`, ordenada por `ordem_severidade` e idade. Referências nulas (leitor
  sem permissão sobre a referência) degradam para "—", nunca escondem a pendência (card 2.3 §9).

### 14.2 Resolver

`[✓]` abre o diálogo de resolução com **justificativa obrigatória** (`resolucao` é NOT NULL —
card 2.2); chama `fn_pendencia_resolver`. Pendências que o sistema fecha sozinho (dedup/rotina)
exibem "fecha automaticamente quando …" no detalhe, para ninguém resolvê-las à mão sem necessidade.

### 14.3 Ação contextual — a pendência como fila de trabalho

**Decisão deste card:** cada tipo de pendência tem uma **ação primária que leva à tela onde o
problema se resolve**, além do resolver genérico:

| Tipo | Ação primária | Destino |
|---|---|---|
| `ALUNO_SEM_TURMA` | Alocar | ficha do aluno, aba Turmas (§6.4) |
| `COMPRA_SEM_ESTOQUE`, `ESTOQUE_ZERO`, `ESTOQUE_ABAIXO_MINIMO` | Ver compra | tela 7, linha do material |
| `BLOCO_ACIMA_CAPACIDADE` | Ver bloco | tela 4, bloco |
| `PC_SEM_SUBSTITUTO` | Ver PC | tela 10, sala do PC |
| `REP_VIRADA` (`:CONTINUO`) | **Executar** — escolher o bloco e confirmar `fn_rep_virar_continuo` | seletor de bloco com vagas |
| `REP_VIRADA` (`:VOLTA`) | **Executar** — confirmar `fn_rep_voltar_pontual` | diálogo de confirmação |
| `SUGERIR_FORMADO` | Formar | ficha, alterar status (gate do certificado) |
| `PREVISAO_VENCIDA`, `TRILHA_DIVERGENTE_COMBO` | Ver aluno | ficha, aba Dados/Trilha |
| `ACELERAR_SEM_2O_BLOCO` | Ver turmas do aluno | ficha, aba Turmas |
| `CERTIFICADO_INCONSISTENTE` | Ver checklist | ficha, aba Certificado |
| `TURMA_MODULAR_SEM_CRONOGRAMA` | Ver turma | tela 5, cronograma |
| `ROTINA_FALHOU` | (sem ação de tela) | detalhe técnico p/ direção |

O caso `REP_VIRADA` é o motivo da regra: a virada é **sugerida, nunca automática** (card 2.5) —
a pendência é onde a pessoa executa, e o "Executar" da ida abre o seletor de bloco justamente
porque escolher o bloco é a parte que o `pg_cron` não podia fazer. A ação chama a função e trata
`BLOCO_LOTADO` como em qualquer admissão.

---

## 15. Tela 12 — Administração

Rota: `admin.ler`. Perfis: direção.

```
┌ Administração ── [Usuários] [Perfis e matriz] [Parâmetros] ┐
│                                                            │
│ ── Usuários ──                        [+ Convidar usuário] │
│ ▤ │ Débora … │ debora@… │ SECRETARIA      │ [Editar]       │
│   │ Caio …   │ caio@…   │ MONITOR         │ [Editar]       │
│                                                            │
│ ── Perfis e matriz ──          perfil: [SECRETARIA v]      │
│ ▤ Alunos                                                   │
│   ☑ alunos.ler        Ler aluno, histórico e trilha        │
│   ☑ alunos.criar      Matricular aluno                     │
│   ☐ alunos.reverter_status  Sair de FORMADO/CANCELADO …    │
│   … (49 códigos, agrupados pelos 12 domínios)              │
│                                                            │
│ ── Parâmetros ──                                           │
│ ▤ │ projecao_horizonte_dias │ 60  │ [editar] │             │
│   │ standby_alerta_dias     │ 30  │ [editar] │             │
│   │ rep_prazo_dias          │ 30  │ [editar] │             │
│   │ … (com descrição e unidade ao lado)                    │
└────────────────────────────────────────────────────────────┘
```

- **Usuários** (`admin.gerir_usuarios`): convite por e-mail (fluxo do card 3.5 — sem cadastro
  público), atribuição de perfis (`usuario_perfil`, múltiplos), desativação.
- **Perfis e matriz** (`admin.gerir_perfis`): a caixa mostra o código **e a descrição** — é para
  isso que a descrição existe no seed (card 2.4 §8: "`estoque.ajustar` sozinho não diz a ninguém o
  que acontece se a caixa for marcada"). Agrupamento pelos 12 domínios. Desmarcar caixa avisa que a
  mudança vale imediatamente; o histórico de alterações da matriz é o card **4.7.5** e este
  wireframe reserva a aba "Histórico" para ele.
- O catálogo de permissões em si **não é editável** aqui (sem política de escrita em `permissao` —
  só migração cria código); a tela deixa isso dito no cabeçalho da matriz.
- **Parâmetros** (`parametros.gerir`): chave, valor, descrição, unidade. Editar parâmetro `rep_*` ou
  `projecao_*` mostra aviso do efeito (ex.: "vale na próxima execução da rotina diária").
- Cursos/combos/módulos e professores, citados no plano §7 para esta tela, **moram nas telas 6 e
  10** (cadastro junto do uso, guardado por `materiais.*`/`professores.*`) — aqui ficam só acesso e
  configuração. Divergência registrada em §17.

---

## 16. Tela 13 — Importação

Rota: `admin.ler` + domínios do que se importa (conjunto exato no card 9.1). Perfis: direção.

```
┌ Importação ──────────────────────────────────────────────┐
│  ① Upload  →  ② Validação  →  ③ Relatório  →  ④ Aplicar  │
│                                                          │
│ ── ① ──  [Escolher arquivo…]  snapshot da planilha       │
│ ── ② ──  validando…  (barra de progresso)                │
│ ── ③ ──  ▤ 265 alunos lidos · 20 sem turma ⚠             │
│           2 códigos divergentes ✖ · 3 previsões atípicas │
│           [baixar relatório completo]                    │
│           ✖ bloqueia aplicar · ⚠ aplica com pendência    │
│ ── ④ ──  [Aplicar em <ambiente>]  (dry-run primeiro)     │
│           resultado: totais aplicados × totais da        │
│           planilha (conferência do Dashboard)            │
└──────────────────────────────────────────────────────────┘
```

- Assistente de 4 passos, **reexecutável e auditável** (plano §8): reaplicar o mesmo arquivo é
  seguro por desenho; cada aplicação guarda o relatório do que transformou e descartou.
- O passo ③ separa **erro que bloqueia** (código divergente sem resolução) de **exceção que vira
  pendência** (aluno sem turma) — a lista de exceções é a que o Irineu revisa (card 9.3).
- O passo ④ mostra a conferência de totais contra o Dashboard da planilha (card 9.4) antes do
  botão final. Reaproveitável para o SGF na Fase 11 (o formato de arquivo é do card 9.1/11.3).

---

## 17. Decisões e achados deste card

Decisões de wireframe (valem para o card 2.7 e para os cards das telas):

1. **Botão sem permissão é ocultado; botão sem estado é desabilitado com motivo** (§2.2). Um
   critério só, aplicado em todas as telas.
2. **A tela não pré-verifica regra em Dart** — chama a função e reage ao resultado (§6.3). O caso
   da entrega é o canônico: o saldo em tela é informativo; quem decide (e reordena a trilha) é
   `fn_registrar_entrega`, e a tela distingue os três status do retorno. Evita a "terceira
   implementação" que o card 2.3 §4.1 proíbe.
3. **Pendência com ação contextual por tipo** (§14.3): a central é fila de trabalho, não relatório.
   Em particular, `REP_VIRADA` é executada a partir da pendência — coerente com a decisão do card
   2.5 (virada sugerida; a pessoa escolhe o bloco).
4. **Navegação mobile centrada nas três jornadas do monitor:** registrar entrega (Alunos → Trilha),
   financeiro OK (fila de Certificados com caixa acionável na lista), manutenção de PC (dois
   toques). Barra inferior: Alunos · Turmas · Pendências · Mais.
5. **Contador do menu = pendências ALTA abertas**, não o total — sino que dispara sempre não
   dispara nunca.
6. **Seleção de unidade pulada em silêncio na v1** (unidade única), mantida no fluxo para a
   Fase 11 (§4).
7. **Degradação por prioridade de coluna** nas tabelas densas (colunas `†` saem primeiro), nunca
   rolagem horizontal da página.
8. **Credenciais de PC não têm campo em tela** até o card 2.9 decidir a política (§13).

Divergências e apontamentos para outros cards:

| # | Apontamento | Card afetado |
|---|---|---|
| 1 | Cadastro de cursos/combos/módulos e professores desenhado nas telas 6 e 10 (junto do uso), e não na tela 12 como o plano §7 sugere — Administração fica com usuários, matriz e parâmetros. As permissões do card 2.4 já suportam isso (guardas por `materiais.*`/`professores.*`, independentes de `admin.*`) | 4.4 / 4.5 / 4.7 |
| 2 | `v_certificado_fila` (card 8.6) precisa devolver **as duas situações** — `em_ultimo_livro` e `em_fim` — com rótulo distinto (§12.1); o plano fala só em "fila do último livro" | 8.6 |
| 3 | ✅ **Fechado em 03/09/2026 (card 5.7).** `v_bloco_alunos` precisava expor a origem da reposição pontual (bloco/data da falta) para o rótulo "reposição de Qua 27/08" (§7.2) — quem a expõe é **`fn_bloco_alunos`**, com `bloco_origem_dia`/`bloco_origem_hora`/`data_origem` e `left join` no bloco de origem, porque `bloco_origem_id` é nulo de propósito (card 2.5 §3.1) e aí a linha diz "reposição avulsa" em vez de inventar | 5.7 |
| 4 | ✅ **Fechado em 03/09/2026 (card 5.7).** A ficha exibe a situação REP (`fn_rep_situacao`) na aba Turmas, **com os números e não só o veredito** — e só quando há o que dizer: débito, aluno já contínuo, ou veredito diferente de MANTER. Painel permanente dizendo "0 aulas a repor" em toda ficha treina a pessoa a não olhar para ele | 5.7 / 6.6 |
| 5 | Tela de Administração reserva aba "Histórico" da matriz para o card 4.7.5 (§15) | 4.7.5 |
| 6 | O aviso pós-troca de combo ("trilha não regenera; abre pendência") vai no formulário de Dados (§6.4) — texto final no card 2.7 | 4.6 |

Nenhum ajuste bloqueante em documento anterior: este card consome os contratos fechados e não
precisou corrigi-los.

---

## 18. Mapa tela → cards de implementação

| Tela | Wireframe | Cards que a implementam |
|---|---|---|
| 1 Login/unidade | §4 | 3.5 / 3.7 |
| 2 Dashboard | §5 | 5.9 (v1) / 8.7 (completo) |
| 3 Alunos (lista + ficha) | §6 | 4.6 (lista/ficha) / 6.6 (trilha) / 5.7 (turmas do aluno) / 8.6 (certificado) |
| 4 Turmas por horário | §7 | 5.6 (grade) / 5.7 (bloco) |
| 5 Turmas Modular | §8 | 7.3 |
| 6 Materiais e estoque | §9 | 4.4 (catálogo) / 6.7 (estoque) |
| 7 Compras | §10 | 6.8 |
| 8 Projeção | §11 | 8.5 |
| 9 Certificados | §12 | 8.6 |
| 10 Salas e PCs | §13 | 4.5 |
| 11 Pendências | §14 | 5.8 |
| 12 Administração | §15 | 4.7 (+ 4.7.5) |
| 13 Importação | §16 | 9.1 |

---

*Card 2.6 — Fase 2. Os desenhos são estruturais; medidas, componentes e tema são do card 2.7.*
