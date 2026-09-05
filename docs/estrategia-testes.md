# Estratégia de testes e critérios de aceite dos marcos

Card de origem: **2.8 — Definir estratégia de testes e critérios de aceite dos marcos** (Fase 2,
board Notion).
Base: `docs/modelagem-dados-ddl.md` (2.1), `docs/regras-negocio-funcoes.md` (2.2),
`docs/views-leitura.md` (2.3), `docs/permissoes-matriz.md` (2.4), `docs/regra-virada-rep.md` (2.5),
`docs/projecao-demanda.md` (Ordem 5), `docs/wireframes.md` (2.6), `docs/design-system.md` (2.7) e
`docs/plano-projeto-sistema.md` §9.

Este documento é a fonte da **estratégia de testes** como o 2.1 é a fonte do DDL e o 2.3 a das
views: cada card de implementação recorta daqui a obrigação de teste da sua camada (§13 e §17), e
cada card de marco recorta o seu critério de aceite (§15).

---

## 1. Escopo

**Neste documento:** a ferramenta de teste do banco e o porquê da escolha; como um teste "vira" um
usuário para exercitar RLS; a família de testes de catálogo que este card cria; a obrigação de teste
por tipo de card; o que roda no CI e quando; o mapa decisão → teste que protege as decisões já
tomadas nos cards 2.1–2.7; e os critérios de aceite dos quatro marcos do plano §9.

**Não está neste documento, de propósito:**

| Assunto | Dono |
|---|---|
| Implementar os workflows do GitHub Actions | card 3.9 — ✅ **feito em 02/09/2026**, em `docs/ci-cd.md`; o Apêndice B virou o registro do que mudou |
| Escrever os helpers e a escola-fixture no repositório | card **3.4.5**, criado por este card (SQL pronto no Apêndice A) |
| Os testes em si de cada regra | o card que cria a regra (§13, §17) |
| Conferência de totais contra a planilha | cards 9.4 (dry-run) e 8.8 (marco 3), com o critério em §15 |
| Recalibração da projeção | card 11.2 — critério objetivo já fechado no card de Ordem 5 |

---

## 2. A pirâmide deste projeto é invertida em relação ao padrão Flutter

A regra de ouro do `CLAUDE.md` — **regras de negócio no banco** — decide sozinha a forma da suíte.
O card 2.6 fechou a consequência do outro lado: *"a tela nunca pré-verifica regra em Dart: chama a
função e reage ao status de retorno"*. Somando as duas, **quase não existe lógica de negócio em Dart
para testar**. Um projeto Flutter comum concentra teste em widget e unidade; aqui isso testaria o
framework.

A distribuição-alvo, em número de asserções:

| Camada | Peso | O que prova |
|---|---|---|
| **Catálogo** (§5) | ~30% | O schema é o que os documentos dizem: RLS ligada, view `invoker`, nenhum `current_date`, todo valor gravado aceito pelo `check` |
| **Comportamento no banco** (§6) | ~45% | A regra faz o que a especificação diz, e o erro certo sai com o `codigo` certo |
| **Concorrência** (§7) e **rotinas** (§8) | ~10% | O advisory lock existe *e funciona*; a rotina é reexecutável e isolada |
| **Flutter** (§9) | ~15% | Guarda de rota, ocultação por permissão, degradação por largura, tradução de erro |
| Ponta a ponta em navegador | 0% | **Decisão: não fazer na v1** (§9.4) |

**Decisão: nenhuma meta percentual de cobertura.** Com uma pessoa desenvolvendo, um portão de "80%
de linhas" premia teste de *getter* e não impede que a regra cara passe sem teste. O portão aqui é
**por obrigação de card** (§13) e pelo mapa de decisões protegidas (§14): um card de função não
fecha sem os testes que a sua linha da tabela exige, independentemente de percentual.

---

## 3. Ferramenta do banco: **pgTAP**, com `supabase test db`

A nota do card oferecia "pgTAP ou suíte SQL própria". **Decidido: pgTAP.**

| Critério | pgTAP | Suíte SQL própria |
|---|---|---|
| Já disponível no Postgres do Supabase | sim, é extensão da imagem | — |
| Comando de primeira classe no CLI que o CI já instala | `supabase test db` | teria de ser escrito |
| Asserção de **exceção com SQLSTATE** (`throws_ok`) | pronta | escrever `begin/exception` à mão em cada teste |
| Asserção de **estrutura** (`has_table`, `has_column`, `policies_are`, `function_returns`, `col_type_is`) | pronta — é metade da suíte deste projeto (§5) | reimplementar consultas ao catálogo |
| Saída padronizada (TAP) para o CI anotar a linha que falhou | sim, via `pg_prove` | teria de ser escrita |

O argumento decisivo é o terceiro e o quarto juntos: este projeto testa **muito mais estrutura e
muito mais exceção** do que resultado de `select`, porque foi assim que os cards 2.1–2.4 desenharam
o sistema (política de RLS como barreira, erro com `SQLSTATE PT<status>`). Escrever isso à mão é
reescrever pgTAP pior.

### 3.1 Onde o pgTAP vive — e onde não vive

⚠️ **`create extension pgtap` nunca entra em `supabase/migrations/`.** Migração é o que o workflow
`db-migrations` empurra para dev e prod (regra inegociável do `CLAUDE.md`); uma extensão de teste em
produção é superfície de ataque sem uso. A extensão e os helpers nascem em **`supabase/seed.sql`**,
que só é aplicado por `supabase db reset` — local e no CI.

⚠️ **Proibido `supabase db reset --linked`** (e qualquer `db reset` apontado para dev ou prod). Ele
aplicaria a fixture e a extensão de teste no banco remoto e apagaria o que estivesse lá. O reset é
sempre local. Registrar na Decisões vigentes junto com as demais regras de migração.

**`seed.sql` de teste ≠ seed do card 3.6.** O seed do 3.6 (unidade, perfis, 50 permissões, matriz
inicial, usuário direção, parâmetros) é **dado de catálogo do sistema** e vai como **migração**,
porque precisa existir em dev e prod. O `seed.sql` é a **escola-fixture** (§4.2): alunos, materiais,
blocos e movimentos inventados, que nunca podem chegar a lugar nenhum além da máquina do dev e do
runner do CI.

### 3.2 Organização dos arquivos

```
supabase/
  migrations/            # só schema — nada de teste aqui
  seed.sql               # extensão pgtap + schema tests + helpers + escola-fixture (card 3.4.5)
  tests/
    010_catalogo_rls.test.sql
    011_catalogo_convencoes.test.sql
    012_catalogo_contratos.test.sql
    020_acesso_tem_permissao.test.sql
    030_alunos_status.test.sql
    040_vagas_admissao.test.sql
    050_trilha_entrega.test.sql
    060_estoque_compras.test.sql
    070_modular.test.sql
    080_projecao.test.sql
    085_rep_virada.test.sql
    090_rotinas.test.sql
    095_views_paridade.test.sql
  tests_concorrencia/    # fora do pgTAP — §7
    entrega_ultimo_exemplar.sh
    admissao_ultima_vaga.sh
```

**Diretório plano com prefixo numérico**, não subpastas por área: o `pg_prove` do `supabase test db`
é chamado sobre `supabase/tests` e não se deve depender de ele recursar. O prefixo dá ordem de
leitura, não dependência — **todo arquivo é independente** e cria o que precisa (§4.3).

---

## 4. O problema central: um teste precisa *ser* um usuário

Tudo o que os cards 2.1 e 2.4 decidiram depende de `auth.uid()`: `fn_unidade_atual()` lê a unidade
do usuário logado, `tem_permissao(codigo)` percorre `usuario_perfil → perfil_permissao`, e cada
política de RLS combina as duas. Numa sessão `psql` não há JWT: `auth.uid()` é nulo,
`fn_unidade_atual()` devolve nulo e **toda** política falha.

Isso tem duas consequências, e a segunda é a que engana:

1. Um teste que não se autentica não testa nada — vai falhar em tudo, o que ao menos é honesto.
2. Um teste que roda como `postgres` **também não testa nada**, e passa. O `postgres` é dono das
   tabelas; o `force row level security` do card 2.1 faz a RLS valer para o dono também, mas as
   funções `security definer` e os `grant` não são exercitados como o PostgREST os exercita. O teste
   ficaria verde e a tela quebraria.

Daí o primeiro entregável de infraestrutura de teste: **helpers que reproduzem exatamente o contexto
que o PostgREST monta** — papel `authenticated` e `request.jwt.claims` com o `sub`.

### 4.1 Os helpers

> **Implementados no card 3.4.5** (01/09/2026). O SQL vigente está em `supabase/seed.sql` — este
> parágrafo descreve o contrato; o Apêndice A registra o que mudou em relação ao desenho original e
> por quê.

```sql
tests.criar_usuario(p_email text, p_perfil text,
                    p_unidade uuid default null, p_ativo boolean default true) returns uuid
tests.uid(p_email text) returns uuid               -- chave natural → id, sem UUID literal em teste
tests.unidade(p_codigo text) returns uuid
tests.autenticar(p_usuario uuid) returns void      -- vira 'authenticated' com o sub no JWT
tests.como_anonimo() returns void                  -- papel 'anon', sem claims
tests.como_rotina(p_unidade uuid) returns void     -- contexto de rotina por GUC (card 2.2 §2.2)
tests.encerrar_sessao() returns void               -- reset role + claims (voltar a postgres)
tests.conta_como(p_usuario uuid, p_sql text) returns bigint  -- conta linhas na pele do usuário
tests.codigo_do_erro(p_sql text, p_usuario uuid default null) returns text  -- `codigo` do DETAIL
```

**A regra que organiza o uso: `tests.*` só é alcançável a partir do papel `postgres`.** O schema é
fechado para `anon` e `authenticated` (fail-closed, como toda a superfície deste projeto), então
depois de `tests.autenticar(...)` a sessão está em `authenticated` e não alcança mais o schema. Para
trocar de usuário, `reset role;` — comando SQL puro, sempre disponível — e autenticar de novo.
Esquecer a linha dá `permission denied for schema tests`: erro alto, não silêncio.

Três detalhes que, errados, produzem suíte verde e sistema quebrado:

- **`set_config(..., true)`** (`is_local`) em tudo: o efeito morre no `rollback` do arquivo de teste.
  Sem o `true`, um teste vaza identidade para o seguinte.
- **A ordem é claims primeiro, `set role` depois.** Depois de `set role authenticated` o teste perde
  privilégio para várias coisas; `reset role` é o caminho de volta, e é o que `tests.encerrar_sessao`
  faz.
- **`tests.criar_usuario` é `security definer`**, porque insere em `auth.users` (dona é
  `supabase_auth_admin`) e em `usuario`, que tem RLS. Fica no schema `tests`, sem `grant` para
  `authenticated`, e **não existe** em dev nem em prod.

### 4.2 A escola-fixture

Uma escola pequena e **fixa**, com números escolhidos para exercitar as bordas — não uma cópia da
planilha. A planilha entra em cena no dry-run do card 9.4, com dados reais; aqui o que se quer é
determinismo.

| Elemento | Quantidade | Por quê exatamente isso |
|---|---|---|
| Unidade | 2 (`ESCOLA_A` ativa, `ESCOLA_B`) | multi-unidade é a decisão de arquitetura que só um segundo tenant testa; toda asserção de RLS confere que `ESCOLA_B` **não** aparece |
| Usuários | 4, um por perfil, + 1 sem perfil nenhum | o quinto é o teste de "sem política = sem acesso" |
| Sala/PCs | 1 sala com **10** PCs, 1 com 6 | 10 é a capacidade real do laboratório; a borda 10/11 é o teste de lotação |
| Blocos | 3 (um vazio, um com 9 alunos, um com 10) | 9 → aceita o 10º; 10 → recusa o 11º, sem depender de ordem de execução |
| Materiais | 6 (2 com saldo 0, 1 com saldo 1, 3 com saldo folgado) | saldo 1 é o teste de concorrência; saldo 0 é o `REORDENADA` e o `BLOQUEADA_SEM_ESTOQUE` |
| Alunos | 12, cobrindo os 4 degraus da cascata da projeção, 1 em FIM, 1 em STANDBY antigo, 1 com débito REP na borda | um aluno por caso que alguma decisão criou |

A fixture é **datada em relativo** (`fn_hoje() - interval 'N days'`), nunca em datas absolutas: uma
fixture com `'2026-09-01'` começa a falhar sozinha em janeiro.

#### A fixture nasce em camadas, e o portão impede que ela fique para trás (card 3.4.5)

Quatro dos seis elementos do quadro acima moram em tabelas que **ainda não existem**: `material`,
`aluno`, `sala`/`pc` e `bloco_horario`/`bloco_aluno` nascem nos cards 4.1, 4.2, 4.3, 5.1 e 6.1.
Escrevê-los agora derrubaria `supabase db reset` no primeiro `insert`; deixá-los comentados
produziria o artefato que este documento inteiro combate — algo que existe no papel e não exercita
nada.

A saída é declarar cada camada com a **condição que a torna devida**, em `tests.fixture_camada`:

| Camada | Card | Devida quando |
|---|---|---|
| `acesso` | 3.4.5 | ✅ aplicada |
| `acesso_seed_real` | 3.6 | existir permissão em unidade que não é da fixture |
| `catalogo_curricular` | 4.1 | ✅ aplicada (seis materiais, quatro cursos, três módulos e três combos por unidade; os três métodos vêm de `public.fn_seed_metodos()`, a mesma função da migração) |
| `alunos` | 4.2 | existir `public.aluno` |
| `infra_fisica` | 4.3 | existir `public.pc` |
| `turmas` | 5.1 | existir `public.bloco_aluno` |
| `trilha_estoque` | 6.1 | ✅ aplicada (trilha dos alunos derivada do combo, três pedidos — um por estado que muda alguma conta — e os movimentos que produzem os saldos 0/0/1/n/n/n; João Pedro fica em FIM) |
| `modular` | 7.1 | existir `public.turma_modular_aluno` |

`001_infra_teste.sql` reprova a suíte quando uma camada devida continua sem ser escrita — ou seja, o
card 4.1 **não fecha verde** sem trazer a camada de catálogo junto. E o próprio portão tem asserção
de que reprova: o teste cria a tabela sentinela dentro da própria transação e confere que a camada é
acusada. Portão que nunca foi visto vermelho é decoração.

A camada `acesso_seed_real` é a que evita o pior desses casos. Enquanto o card 3.6 não existe, a
fixture declara ela mesma o catálogo e a matriz — só as sete permissões que as políticas das
migrações 3.3/3.4 citam, porque código sem consumidor não entra (card 2.4 (a)). No dia em que o
3.6 seedar as 50 de verdade, a fixture passa a ter uma matriz **de mentira** ao lado da real, e o
teste de paridade do §6.3 compararia a tela contra ela e passaria. Daí a camada existir e o portão
acusá-la sozinho.

### 4.3 Isolamento

Cada arquivo de teste é `begin; select plan(n); … select * from finish(); rollback;`. **Nenhum teste
enxerga o que outro escreveu**, e a ordem dos arquivos não importa. O que um teste precisa além da
fixture, ele cria dentro da própria transação — inclusive `create or replace function`, que dentro
da transação é revertido junto (usado no teste de isolamento das rotinas, §8).

---

## 5. Testes de catálogo — o achado deste card

Somando os quatro documentos anteriores, o projeto já acumula **~35 "ajustes que o DDL precisa
receber"**, dos quais 15 marcados como bloqueantes: §14 do card 2.2, §8 do 2.5, §10 do 2.3, §7 do
2.4 e §11 do card de Ordem 5. Lendo os quinze juntos, quase todos são a **mesma falha**, em três
formatos:

1. **Uma função grava um valor que o `check` da tabela não aceita.** `FALTOU` em
   `bloco_aluno_reposicao.status`; sete tipos novos em `pendencia.tipo`;
   `TURMA_MODULAR_SEM_CRONOGRAMA`; severidade `INFO` que não existe.
2. **Uma função ou política exige um código de permissão que o seed não cria** — ou o seed cria um
   código que ninguém consome (o card 2.4 proibiu o segundo caso na decisão (a)).
3. **Uma função está com a volatilidade, o `security` ou o `search_path` errados** —
   `fn_capacidade_efetiva` como invoker, `fn_param_int` como invoker.

Nenhuma dessas aparece em teste de caminho feliz. Pior: a maioria **falha em silêncio na produção**,
porque acontece dentro de `rt_diaria`, que por decisão do card 2.2 (j) captura a exceção de cada
sub-rotina, abre uma pendência `ROTINA_FALHOU` e segue. O sintoma é uma pendência que ninguém lê às
03:10 da manhã, e a projeção de demanda simplesmente para de existir.

Todas as três, porém, são **verificáveis contra o catálogo do Postgres**, sem executar regra
nenhuma, em dezenas de linhas de SQL. É o teste mais barato e o de maior retorno do projeto.

**Decisão: a suíte de catálogo é obrigatória desde a primeira migração (card 3.3) e cresce com o
schema. Nenhum card de migração fecha com ela vermelha.**

### 5.1 Os treze testes de catálogo

| # | Asserção | Protege a decisão |
|---|---|---|
| C1 | Toda tabela de negócio tem `relrowsecurity` **e** `relforcerowsecurity` | 2.1 (b) — RLS em tudo, inclusive para o dono |
| C2 | Toda tabela de negócio tem `unidade_id` e as quatro colunas de auditoria (`criado_em/por`, `atualizado_em/por`) | `CLAUDE.md`; 2.1 |
| C3 | Toda tabela tem trigger de auditoria (`fn_auditoria`) | 2.1 |
| C4 | Nenhuma tabela de negócio sem política, **exceto** a lista fechada de ausências intencionais: `movimento_estoque` (sem `update`/`delete`), `permissao` (sem escrita) | 2.1 (b), 2.4 (c) e (e) — ausência intencional documentada vira asserção, senão vira esquecimento |
| C5 ✅ **5.5** | Toda view tem `security_invoker=on` em `reloptions`; **zero** `relkind='m'` no schema | 2.3 (a) e (b) |
| C6 | Nenhum `current_date` em corpo de função, definição de view ou `default` de coluna | 2.3 (c) — o bug das 21h |
| C7 | Toda função tem `search_path` fixo em `proconfig` | 2.2 §1.1 |
| C8 | Toda função `security definer` está numa **lista fechada** versionada no teste | 2.2 §2.2, 2.3, 2.4 (#9.5) — `definer` novo tem de passar por revisão consciente |
| C9 | Nenhuma função tem `execute` para `public` ou `anon`; nenhuma `rt_*` tem `execute` para `authenticated` | 2.2 §1.1, §11 |
| C10 ✅ **5.5** (metade) | Todo tipo passado a `fn_pendencia_abrir` no código está no `check` de `pendencia.tipo`. A metade da **severidade** ficou de fora do teste estático de propósito: ela é o 4º argumento posicional e o 2º e o 3º são expressões com vírgulas dentro (`format(…)`), então a expressão regular acertaria hoje e passaria a mentir no primeiro `format` novo — teste estático que cega em silêncio. No lugar, uma asserção de **runtime** no `090_rotinas`, depois de a rotina ter escrito: nenhuma severidade fora do `check`. Exercitada: com `INFO` (o caso que o card 2.3 nomeia) a suíte reprova | 2.2 §14, 2.3 (#4), Ordem 5 (#3) — a família inteira do formato 1 |
| C11 | Todo código em `tem_permissao('…')`/`fn_exige_permissao('…')` (em funções e em `polqual`/`polwithcheck`) existe em `permissao`; e todo `permissao` tem ao menos um consumidor | 2.4 (a) — nos dois sentidos |
| C12 | Todo `codigo` de erro levantado no código está no fixture de contrato (§10); nenhum a mais, nenhum a menos | 2.2 §1.2, 2.7 (h) |
| C13 | `pg_advisory_xact_lock` aparece no corpo de `fn_bloco_admitir` e `fn_registrar_entrega` | 2.2 (c) — não prova que funciona (§7), prova que não sumiu num refactor |

### 5.2 A convenção que faz C10, C11 e C12 funcionarem

Os três leem `pg_proc.prosrc` com expressão regular. Isso só é confiável sob uma regra explícita:

> **Constante de contrato aparece sempre como literal na chamada.** Tipo de pendência, código de
> permissão e `codigo` de erro nunca são montados em variável, concatenação ou `format()`.

Não é burocracia: é o que separa um teste estático que enxerga tudo de um que cega em silêncio no
dia em que alguém escreve `perform fn_pendencia_abrir(v_tipo, …)`. A regra entra nas convenções do
card 2.2 (§16, ajuste #4) e o próprio C10 tem uma asserção-espelho: **nenhuma chamada a
`fn_pendencia_abrir` com primeiro argumento não-literal**.

---

## 6. Testes de comportamento no banco

### 6.1 Regra por camada, teste na camada

O card 2.2 §1 organiza as regras em quatro camadas. O teste segue a mesma tabela — testar uma regra
na camada errada dá falso conforto:

| Camada da regra | O teste tem de | Exemplo |
|---|---|---|
| **1. Restrição** | Escrever direto na tabela, sem função, e exigir a violação | `insert` em `pendencia` com `tipo` inventado → `23514` |
| **2. Trigger** | Escrever direto na tabela, **contornando a função de aplicação** | `insert` em `bloco_aluno` no bloco de 10/10 → `BLOCO_LOTADO`, mesmo sem passar por `fn_bloco_admitir` |
| **3. Função** | Chamar por RPC, autenticado como o perfil que a usa, e conferir **retorno** e **efeito** | `fn_registrar_entrega` → `ENTREGUE` + movimento + trilha marcada, numa transação só |
| **4. Rotina** | Fixar a fixture no tempo relativo, rodar a rotina, conferir pendência aberta; rodar de novo e conferir que **não duplicou** (§8) | `rt_pendencias_diaria` e `STANDBY_PROLONGADO` |

O teste de camada 2 é o que costuma faltar e o que mais vale: com "Automatically expose new tables"
ligado nos dois projetos (pendência técnica 3 das Decisões vigentes), **toda tabela é uma API**. O
trigger é o que impede o `POST` direto; o teste que só chama a função nunca descobre que o trigger
não existe.

### 6.2 Erro: sempre `throws_ok` com SQLSTATE **e** `codigo`

```sql
select throws_ok(
  $$ select fn_bloco_admitir('…','…','NOVO', null) $$,
  'PT409',
  null,                                   -- mensagem não é contrato: não asserir texto
  'admissão em bloco lotado devolve PT409'
);
select ok(
  (tests.ultimo_erro_detail() ->> 'codigo') = 'BLOCO_LOTADO',
  'e o codigo estável é BLOCO_LOTADO'
);
```

**Nunca asserir a mensagem em português.** O card 2.2 (d) foi explícito — o Flutter trata pelo
`codigo` — e um teste que exige o texto transforma uma melhoria de redação em falha de CI.
`DATA_PREVISTA_OBRIGATORIA` continua sendo o contrato quando a frase mudar.

### 6.3 Views: o teste é **paridade de linhas**, não ausência de erro

Esta é a segunda inversão que este card fixa. O card 2.3 (§3.4) e o 2.4 documentaram o modo de falha
do sistema: **a RLS não devolve erro, ela reduz linhas em silêncio.** Um usuário sem `materiais.ler`
não vê "acesso negado" na grade semanal — vê a **escola vazia**. Um monitor sem `estoque.ler` não vê
erro na entrega — vê saldo 0 em tudo e bloqueia toda entrega por falta de um estoque que existe.

Logo, "o perfil X consegue ler a view sem erro" é uma asserção quase vazia. O teste correto é:

```
para cada view do card 2.3 §11:
  n_direcao := linhas vistas pela direção
  para cada perfil que o card 2.4 §6 autoriza na tela que consome a view:
      assert linhas vistas pelo perfil = n_direcao        -- senão a tela mente
  para o usuário sem perfil:
      assert linhas vistas = 0                            -- e a rota é barrada
  para um usuário da ESCOLA_B:
      assert nenhuma linha da ESCOLA_A                    -- isolamento de unidade
```

Com `n_direcao > 0` garantido pela fixture — uma paridade de zero contra zero passa sempre e não
prova nada. É a asserção que teria pegado, sozinha, os dois achados mais caros do card 2.4.

### 6.4 Projeção: o teste que protege a aritmética

O card de Ordem 5 gira em torno de uma linha (`where k >= 2`): **as parcelas imediata e projetada só
somam se forem disjuntas**. O teste correspondente não olha a linha — olha a consequência:

```sql
-- nenhum aluno aparece nas duas parcelas para o mesmo material
select is_empty(
  $$ select a.aluno_id from v_demanda_imediata_aluno a
     join v_projecao_aluno p using (aluno_id, material_id) $$,
  'imediata e projetada são disjuntas por aluno × material'
);
```

Mais quatro, um por degrau da cascata: um aluno-fixture por origem (`MODULAR`, `RITMO_ALUNO`,
`PREVISAO_CURSO`, `MEDIA_METODO`) e a asserção de que `v_projecao_aluno.origem` é o degrau esperado —
**uma regra por aluno, nunca por item** (decisão (a) do card de Ordem 5): asserir também que um mesmo
aluno nunca tem duas origens. E os dois filtros do ritmo, que atacam falhas opostas: aluno com três
entregas na mesma data (o caso da migração) **não** cai para ritmo ~0, e aluno que voltou de seis
meses parado **não** sai do horizonte.

### 6.5 REP: as duas bordas

O card 2.5 é aritmético, então o teste é de borda, não de exemplo: fixture com débito **exatamente
no limite** (`debito = capacidade × semanas`) → nenhuma pendência; mais uma aula → `REP_VIRADA`
aberta com `chave_dedup` terminada em `:CONTINUO`. E o teste do pingue-pongue, que é o que a decisão
(f) existe para evitar: virar contínuo, voltar a pontual, rodar `rt_rep_avaliar` no dia seguinte →
**nenhuma** pendência `:VOLTA` antes de `rep_janela_volta_dias`.

---

## 7. Concorrência: fora do pgTAP, por necessidade

O card 2.2 (c) escolheu `pg_advisory_xact_lock` porque **nenhuma constraint protege contra 11 alunos
em 10 PCs nem contra saldo −1**. Um teste pgTAP roda numa conexão só e jamais exercita isso: o
`select` que conta e o `insert` que grava acontecem na mesma transação, e a corrida não existe.

**Decisão: duas sessões de verdade, num script de shell, fora da suíte pgTAP.**

```
tests_concorrencia/entrega_ultimo_exemplar.sh
  material com saldo 1, dois alunos com ele como próximo
  psql A: begin; select fn_registrar_entrega(A);       -- segura o lock
  psql B: begin; select fn_registrar_entrega(B);       -- bloqueia
  psql A: commit;  psql B: (destrava) commit;
  asserção: um 'ENTREGUE' e um 'REORDENADA'/'BLOQUEADA_SEM_ESTOQUE'
            e saldo final = 0, nunca −1
```

O irmão é `admissao_ultima_vaga.sh`: bloco com 9/10, duas admissões simultâneas → uma passa, a outra
recebe `BLOCO_LOTADO`, e `count(*) = 10`, nunca 11.

> ⚠️ **Falta um terceiro, e ele tem card: 7.4,5** (aberto pelo card 7.2 em 05/09/2026). A admissão em
> turma Modular também serializa com `pg_advisory_xact_lock` (card 2.2 §4.5, que cita
> `fn_turma_modular_admitir` nominalmente) e a capacidade da turma é a mesma regra de agregado: sem o
> lock, duas secretarias põem `capacidade + 1` alunos na turma. O C13 do teste `071` é o guarda-chuva
> barato — assere que a chamada não sumiu — e **não substitui** o teste de duas sessões. O motivo de
> ele não ter saído junto com o 7.2 é de FIXTURE: a escola-fixture tem **um** aluno MODULAR e o
> cenário exige dois, e estes scripts são a única suíte do projeto sem rollback — criar aluno neles
> significa apagá-lo à mão depois. O caminho é acrescentar o segundo MODULAR à camada `modular` do
> seed, como as outras duas suítes fazem.

Dois cuidados que decidem se o teste vale alguma coisa: os scripts **não podem** rodar dentro da
transação de teste (por definição), então limpam o que criaram no fim (`delete` explícito num banco
local descartável); e precisam de **timeout** — se o lock não existir, os dois passam e o teste tem
de reprovar por saldo, não por travar o CI para sempre. `statement_timeout` de 10 s nas duas sessões.

Enquanto a suíte não existe, o C13 (§5.1) é o guarda-chuva barato: garante que a chamada do lock não
sumiu. Ele **não substitui** o teste de duas sessões, que é pré-condição do marco 2 (§15.2).

---

## 8. Rotinas agendadas: idempotência e isolamento

Duas propriedades que o card 2.2 decidiu e que só o teste sustenta:

**Idempotência** (decisão (i): dedup por índice único parcial, `on conflict do nothing`). Rodar
`rt_pendencias_diaria()` duas vezes seguidas e asserir que a contagem de pendências abertas é
idêntica. Uma rotina que duplica pendência transforma a central numa lista que ninguém lê — e o
sintoma aparece semanas depois.

**Isolamento** (decisão (j): cada sub-rotina num `exception` próprio). Testável dentro da transação,
porque `create or replace` é transacional:

```sql
create or replace function rt_capacidades() returns void language plpgsql as
  $$ begin raise exception 'falha proposital'; end $$;      -- revertido no rollback
select rt_diaria();
select ok(<pendência ROTINA_FALHOU:rt_capacidades existe>, 'a falha virou pendência');
select ok(<pendências de STANDBY foram abertas>,            'e as rotinas seguintes rodaram');
```

Sem esse teste, "cada uma isolada em `exception` própria" é uma frase no documento. Com ele, é
verificado a cada PR.

**Contexto de rotina** (2.2 §2.2): asserir que `rt_diaria` enxerga as **duas** unidades da fixture, e
que uma chamada a `rt_*` **sem** o GUC de contexto não escreve nada — é o desvio por `set_config`
que faz o `force row level security` do card 2.1 conviver com o `pg_cron`.

**Horário**: asserir que o `cron.schedule` registrado é `'10 6 * * *'`. A decisão diz 03:10 em São
Paulo; um `'10 3 * * *'` lido como local seria o meio do expediente, e a diferença não aparece em
nenhum comportamento — só no catálogo.

---

## 9. Testes no Flutter

### 9.1 O que testar (e é pouco, de propósito)

| Suíte | O que prova | Card |
|---|---|---|
| `catalogo_erros_test.dart` | Todo `codigo` do fixture de contrato (§10) tem mensagem; o caso não mapeado exibe o código | 3.7 |
| `guardas_rota_test.dart` | Cada uma das 13 rotas do card 2.4 §6 abre com o conjunto mínimo de permissões e é barrada faltando **qualquer uma** delas — tabelado, uma linha por rota | 3.7, depois cada card de tela |
| `permissao_widget_test.dart` | Botão sem permissão é **ocultado**; botão sem estado é **desabilitado com motivo** (`DesabilitadoCom`) — as duas metades da decisão 2 do card 2.6 | 3.7 |
| `faixa_test.dart` | `faixaDe(largura)` devolve menu/trilho/barra inferior nos limites 600 e 1024, e a `TabelaIm360` troca linhas por cartões junto | 3.7 |
| `dialogo_resultado_test.dart` | Os três status da entrega abrem **diálogo/folha**, não snackbar (decisão (f) do card 2.7) | 6.6 |
| `tnum_test.dart` | Estilos numéricos carregam `fontFeature tnum` — a coluna de estoque desalinhada é o sintoma que ninguém reporta | 3.7 |

### 9.2 Golden: só componente, nunca tela

**Decisão: golden test apenas para o catálogo de componentes** — badges de status e de tipo nos dois
temas (o contrato visual que o card 2.7 fechou com contraste verificado par a par), e nada mais.
Golden de tela inteira quebra a cada ajuste de espaçamento; com uma pessoa no projeto, o resultado
previsível é `--update-goldens` no automático, e aí o golden deixou de testar. Badge é estável por
definição: se ele mudou, foi de propósito.

### 9.3 Sem mock do Supabase

Widget test com cliente Supabase falso testa o mock. As telas recebem os dados por um repositório
injetado; o teste injeta **dados**, não um cliente HTTP. O acordo tela↔banco quem verifica é a suíte
do banco (§6) mais o fixture de contrato (§10).

### 9.4 O que **não** entra na v1

Sem `integration_test`, sem Playwright, sem teste de ponta a ponta em navegador. Custo alto de
manutenção para uma pessoa, e neste projeto o papel dele já tem dois donos melhores: os **marcos de
validação** com pessoas de verdade (§15) e o **dry-run** do card 9.4, que exercita o caminho inteiro
com dados reais. Reavaliar na Fase 11 se a equipe crescer.

---

## 10. O contrato entre banco e app: um fixture, dois consumidores

O catálogo de erros existe hoje em dois lugares: §12 do card 2.2 (SQL) e §7.1 do card 2.7 (Dart).
Conferidos nesta data, **batem: 21 códigos dos dois lados** (19 do card 2.2 + `REP_JA_CONTINUO` e
`REP_NAO_CONTINUO` do 2.5). Nada garante que continuem batendo — e a falha é silenciosa, com cara de
problema de rede: o usuário vê *"Não foi possível concluir… (código X)"* em vez da instrução certa.

**Decisão: um arquivo versionado, `test/fixtures/codigos_erro.txt`, com um código por linha, é o
contrato.** Dois testes o consomem, de lados opostos:

- **C12** (SQL, §5.1): o conjunto de `codigo` que aparece no `DETAIL` das funções é **exatamente** o
  do arquivo — pega o código novo que ninguém traduziu e o código morto que ficou.
- **`catalogo_erros_test.dart`**: todo código do arquivo tem mensagem em `catalogo_erros.dart`.

Um card que cria um erro novo toca três arquivos (função, fixture, catálogo Dart) e os dois testes
falham enquanto faltar um. É a única forma barata de manter dois repositórios da verdade em dia sem
gerar código.

O mesmo mecanismo, com o mesmo arquivo, poderia valer para tipos de pendência; hoje **não vale a
pena**, porque a tela consome a pendência pelo tipo vindo do banco e o C10 já fecha o lado que erra.

---

## 11. Determinismo: as três fontes de teste instável

Teste que falha uma vez por semana ensina a equipe a reexecutar o CI, e a partir daí nenhum
resultado vermelho significa alguma coisa. As três fontes previsíveis aqui:

| Fonte | Como evitar |
|---|---|
| **Tempo** | Fixture sempre em datas relativas a `fn_hoje()`. **Nunca** asserir `fn_hoje() = current_date` — passa 21 horas por dia e falha 3, e a falha é o comportamento **correto**. O que se testa sobre fuso é o C6 (nenhum `current_date` no schema) e o horário do `cron` (§8) |
| **Ordem** | Cada arquivo em transação própria com `rollback`; nada compartilhado além da fixture, que é recriada pelo `db reset`. **E dentro do arquivo: `limit` sem `order by` é sorteio** — corrigido em 03/09/2026 (card 5.2) em duas consultas do teste 040, escritas como `... and ba.ativo limit 1`. Elas escreviam uma alocação inativa para um aluno **qualquer**; no dia em que o sorteio caísse no `Aluno de Lotação 13`, a asserção de `tipo_desde` 60 linhas adiante lia **duas** linhas e o arquivo inteiro morria em `more than one row returned by a subquery` — 27 dos 43 testes sem rodar, e a mensagem apontando para longe da causa. Passou verde no CI e reprovou no primeiro stack local novo. **Linha de fixture que um teste vai reler se escolhe por chave natural, nunca por `limit`** |
| **Aleatoriedade** | `gen_random_uuid()` nas fixtures só em coluna que o teste não asserta; toda referência é por chave natural (`codigo`, `email`), nunca por UUID literal |

---

## 12. CI: o que roda, quando, e o que bloqueia

✅ **Implementado em 02/09/2026 pelo card 3.9.** Detalhe operacional — versões fixadas, lista de
serviços excluídos, secrets que só Irineu cria — em **`docs/ci-cd.md`**, que passa a ser a fonte do
pipeline. O que segue é a estratégia; onde os dois divergirem, vale o `ci-cd.md`.

Saíram **três** workflows, e não dois: o terceiro é `deploy-web.yml`, que o card 3.8 deixou pendente
(o Pages não tem Flutter no ambiente de build, então quem constrói é o CI).

| Workflow | Dispara | Jobs | Bloqueia |
|---|---|---|---|
| **`testes.yml`** | **todo PR**, todo push em `develop`/`main` e `workflow_call` | `banco` (Postgres limpo → migrações do zero → `seed.sql` → `supabase test db` → concorrência) e `app` (`dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, `flutter test`) | o merge do PR |
| **`db-migrations.yml`** | push em `develop`/`main` tocando `supabase/migrations/**` | job `testes` **antes** do `db push`, com `needs:` | a aplicação em dev/prod |
| **`deploy-web.yml`** | push em `develop`/`main` tocando `app/**` | job `testes` antes de construir e publicar | a publicação no Pages |

Três ajustes no que já existia, todos com motivo próprio, **os três fechados**:

1. ✅ **`supabase/setup-cli` com versão fixa**, não `latest` (pendência técnica 2(d) das Decisões
   vigentes): uma versão nova do CLI quebra o pipeline sem que nada mude no repositório — e
   quebraria a suíte de teste junto, que é justamente o que deveria estar dizendo a verdade.
   Fixado em **2.116.0**, a mesma versão nos dois workflows. O Flutter foi fixado junto, em
   **3.47.2**, pelo mesmo motivo e por um segundo: é a versão que traz o Dart `^3.13.2` que o
   `pubspec.yaml` exige.
2. ✅ **`major_version` do Postgres em `supabase/config.toml`**, igual ao dos projetos remotos.
   Testar em 15 e aplicar em 17 é testar outro banco. Já estava em `17`.
3. ✅ **`required reviewer` no environment `prod`** (pendência 2(c)): ligado por Irineu em
   01/09/2026 e exercitado duas vezes; agora vale também para o **deploy** de produção, não só para
   a migração.

**Rodar do zero, sempre.** O job do banco aplica as migrações desde a primeira, num Postgres vazio.
Isso testa de graça a propriedade que mais importa numa migração: que a sequência inteira sobe
limpa. `db push` incremental nunca descobre que a migração 12 depende de algo que a 7 removeu.

---

## 13. Obrigação de teste por tipo de card

O portão que substitui a meta de cobertura (§2). Um card não é "Concluído" com a sua linha em aberto.

| Tipo de card | Testes obrigatórios |
|---|---|
| **Migração de schema** | Suíte de catálogo (§5) verde com as tabelas novas incluídas; um teste por `check`/`unique` que expresse regra de negócio (camada 1) |
| **Função de aplicação** | Caminho feliz com efeito conferido; **um `throws_ok` por `codigo` que a função pode levantar**; um teste negativo de permissão (perfil sem o código → `PT403`); teste de camada 2 se houver trigger-garantia |
| **View** | Paridade de linhas por perfil + zero para quem não pode + isolamento de unidade (§6.3); as quatro armadilhas do card 2.3 §3 quando aplicáveis (soma de conjunto vazio, `count` sobre `left join`, `fn_hoje`, RLS silenciosa) |
| **Rotina `rt_*`** | Idempotência (rodar duas vezes) + isolamento de falha + contexto de rotina (§8) |
| **Tela** | Guarda de rota tabelada; ocultação por permissão; estado vazio renderizado com o texto do card 2.7 |
| **Migração de dados (Fase 9)** | Reexecutabilidade: importar duas vezes o mesmo snapshot produz os mesmos totais, sem duplicar |
| **Correção de bug** | O teste que reproduz o defeito entra **no mesmo commit** da correção, e falha sem ela |

---

## 14. Testes que protegem decisões

Cada decisão cara já tomada, e o teste sem o qual ela vira comentário. É a tabela para consultar
quando um card perguntar "o que eu preciso testar aqui?".

| Decisão (card) | Teste que a protege |
|---|---|
| RLS com `force`, quatro políticas por tabela (2.1 b) | C1, C4 |
| `movimento_estoque` sem `update`/`delete` para ninguém (2.1 b) | C4 + tentativa de `update` autenticado como direção → recusa |
| Movimento imutável, correção por estorno (`CLAUDE.md`) | Estorno mantém o movimento original e devolve o saldo |
| Contexto de rotina por GUC (2.2 a) | §8 — rotina sem GUC não escreve; com GUC, alcança as duas unidades |
| Falha que precisa deixar rastro é status, não exceção (2.2 b) | Entrega sem estoque nenhum → retorno `BLOQUEADA_SEM_ESTOQUE` **e** pendência `COMPRA_SEM_ESTOQUE` persistida após o `commit` |
| Advisory lock em admissão e entrega (2.2 c) | §7 (duas sessões) + C13 |
| Erro por `codigo`, nunca por texto (2.2 d) | §6.2 + C12 + fixture de contrato (§10) |
| Livro atual/próximo derivados, nunca coluna (2.2 e) | Entrega muda o "próximo" sem `update` em coluna de aluno |
| Um job diário às 03:10 SP (2.2 j) | §8 — `cron.schedule` = `'10 6 * * *'` |
| Dedup de pendência por índice único (2.2 i) | §8 — idempotência |
| `security_invoker` em toda view (2.3 a) | C5 |
| Nenhuma matview (2.3 b) | C5 |
| `fn_hoje()` no lugar de `current_date` (2.3 c) | C6 |
| `qtd_projetada` reservada como 0 na posição definitiva (2.3 d) | Ordem das colunas de `v_pedido_sugerido` conferida em C-view; o card 8.2 só troca a expressão |
| Permissões de leitura declaradas por view (2.3 i) | §6.3 — paridade de linhas |
| Nove tabelas fora do padrão de quatro políticas (2.4 b) | Monitor executa entrega ponta a ponta e as quatro escritas-efeito-colateral gravam |
| `insert` por tipo em `movimento_estoque` (2.4 c) | Monitor tenta `ENTRADA` direto → recusa; `SAIDA` pela função → passa |
| `materiais.ler` e `estoque.ler` para todos (2.4) | §6.3 — grade e dashboard não vêm vazios para pedagógico e monitor |
| RLS não é por coluna; trigger de colunas do checklist (2.4) | Monitor tenta `PATCH` em `pedagogico_ok` → recusa pelo trigger, não pela política |
| Virada REP sugerida, nunca automática (2.5 a) | `rt_rep_avaliar` abre pendência e **não** cria alocação |
| Prazo e gatilho aritmético (2.5 b, c) | §6.5 — borda exata |
| Carência na volta (2.5 f) | §6.5 — pingue-pongue |
| Projeção começa no 2º item (Ordem 5, b) | §6.4 — disjunção |
| Uma regra por aluno (Ordem 5, a) | §6.4 — origem única por aluno |
| Piso 7 / teto 120 dias no ritmo (Ordem 5, c) | §6.4 — entrega em lote e volta de parada |
| `demanda_projetada` escrita só pela rotina (Ordem 5, g) | Direção tenta `insert` pelo PostgREST → recusa; rotina grava |
| Botão sem permissão ocultado; sem estado, desabilitado com motivo (2.6, 2.7 g) | `permissao_widget_test` |
| Tela não pré-verifica regra (2.6 c) | `dialogo_resultado_test` — os três status vêm do banco |
| Resultado que muda a próxima ação é diálogo, não snackbar (2.7 f) | `dialogo_resultado_test` |
| Numerais tabulares em tabela e estoque (1.9, 2.7 e) | `tnum_test` |
| Badges com contraste verificado (2.7 a) | Golden dos badges nos dois temas |

---

## 15. Critérios de aceite dos marcos

Quatro marcos, do plano §9, já com card no board: **M1** = 4.8, **M2** = 6.9, **M3** = 8.8,
**M4** = 9.7 (go-live, com o dry-run 9.4 como pré-requisito).

Três regras valem para os quatro:

1. **Pré-condição automatizada antes de convocar gente.** Marco é validação com pessoas; começar com
   suíte vermelha é gastar a hora do pedagógico procurando bug que o CI acharia sozinho.
2. **Critério de reprovação escrito.** Marco sem condição de reprovação é demonstração, não
   validação — e demonstração sempre passa.
3. **Ajuste vira card, nunca correção no ato** (já na nota do card 4.8). Corrigir ao vivo perde o
   rastro e ninguém sabe o que mudou depois da validação.

### 15.1 M1 — Cadastros e permissões (card 4.8)

**Quem valida:** Irineu + secretaria (usuária principal dos cadastros); direção nas telas de
administração.

**Pré-condições automatizadas:** suítes `010`–`030` verdes; `flutter analyze` limpo; app publicado
no Pages de dev; seed do card 3.6 aplicado em dev pelo pipeline (não à mão).

⚠️ **Duas pré-condições que não são automatizáveis e que o enunciado original não previa** (achado da
sessão do card 4.8, 03/09/2026). As duas são de Irineu, feitas no app de homologação, e sem elas o
marco não roda:

1. **Três usuários em dev, um por perfil.** Os critérios 2, 3 e 4 pedem "quatro logins" e o dev tem
   **um** usuário — a direção do bootstrap do card 3.6. Convidar secretaria, pedagógico e monitor
   pela tela de Administração (card 4.7). A escola-fixture tem os quatro perfis, mas ela **nunca sai
   da máquina local**: em dev não existe.
2. **Os cadastros do roteiro vêm ANTES dos quatro logins.** O dev está sem dado de negócio por
   decisão de 02/09/2026 (nenhuma migração grava dado de negócio; o importador é o card 9.1), então
   toda tela de lista abre vazia lá — por falta de dado, não por RLS. Invertida a ordem, o critério 4
   fica ambíguo justamente no modo de falha que ele existe para pegar.

**Roteiro:** cadastrar um combo real (Secretariado Executivo) com cursos e materiais; cadastrar um
aluno; percorrer ATIVO → STANDBY → ATIVO → CANCELADO; abrir o sistema com um usuário de cada perfil.

**Aprova se, e só se:**

| # | Critério | Como se verifica |
|---|---|---|
| 1 | Os 50 códigos do card 2.4 existem em `permissao` e a matriz inicial confere: direção 50, secretaria 37, pedagógico 22, monitor 14 | consulta, não conferência a olho |
| 2 | Para cada perfil, o menu exibe **exatamente** as rotas do mapa do card 2.4 §6 — nem uma a menos, nem uma a mais | quatro logins |
| 3 | As três permissões de exceção (`alunos.formar_sem_certificado`, `alunos.reverter_status`, `compras.receber_excedente`) só aparecem para a direção | quatro logins |
| 4 | Nenhuma tela abre **vazia** por falta de permissão — o modo de falha do card 2.4 | quatro logins × telas do perfil |
| 5 | Transição inválida devolve a mensagem do catálogo do card 2.7, não texto do Postgres | tentativa deliberada |
| 6 | Toda mudança de status gerou linha em `aluno_status_hist` com quem e quando; toda linha criada tem `criado_por` do usuário do roteiro | consulta ao fim |

⚠️ **Os números do critério 1 foram corrigidos em 03/09/2026 (sessão do card 4.8): eram 49 / direção
49 / monitor 13.** Estavam certos quando este documento foi escrito e envelheceram no card **2.9**,
que acrescentou `salas.acessar_credencial` (direção e monitor) — o próprio `docs/permissoes-matriz.md`
§5 já registra "com `salas.acessar_credencial` (card 2.9): direção 50, secretaria 37, pedagógico 22,
monitor 14, que é o que o seed do card 3.6 grava e a suíte `022_seed_inicial` assere". Medido no dev
nesta data: 50 códigos, 12 domínios, `perfil_permissao` com 123 linhas = 50+37+22+14. **É o critério
que estava errado, não o sistema** — e um critério de aceite errado reprova software correto, que é
o pior desfecho possível para um marco.

**Reprova se:** aparecer qualquer erro cru do PostgREST/Postgres em tela; qualquer tela vazia por
RLS; qualquer política exigindo permissão que o seed não cria (é o C11 — não deveria chegar aqui).

**Fora do marco:** turmas, estoque, dashboard, projeção.

### 15.2 M2 — Fluxo completo de um aluno (card 6.9)

**Quem valida:** Irineu + monitor (é a jornada dele) + secretaria.

**Pré-condições automatizadas:** suítes `010`–`060` verdes **e** a suíte de concorrência (§7) verde —
esta é a única pré-condição que não é negociável por prazo, porque o defeito que ela pega (saldo −1,
11 alunos em 10 PCs) é invisível em uso normal e corrompe dado. ✅ **As duas foram medidas verdes em
04/09/2026 (sessão do card 6.9):** `supabase test db` = 927/927 em 25 arquivos, e os **dois** scripts
de `tests_concorrencia/` (entregáveis dos cards 5.3 e 6.3) saindo `rc=0` — bloco fechando em 10/10 e
saldo fechando em 0. Enquanto a suíte de concorrência não existia, esta linha era o único bloqueante
aberto da pendência 9.8 das Decisões vigentes.

**Roteiro, e AGORA COM O ATOR DE CADA PASSO:**

| # | Passo | Quem |
|---|---|---|
| 1 | Matricular no combo (a trilha nasce sozinha) | secretaria |
| 2 | Alocar em bloco, e depois tentar um bloco **lotado** | secretaria |
| 3 | Criar, enviar e **receber** um pedido (ENTRADA) | secretaria |
| 4 | Registrar entrega (SAIDA) — **no celular** | **monitor** |
| 5 | Registrar entrega de material sem estoque (REORDENADA) | **monitor** |
| 6 | Zerar a trilha inteira e tentar de novo (BLOQUEADA) | **monitor** |
| 7 | Duas entregas simultâneas, em duas janelas | monitor + secretaria |
| 8 | Estornar | secretaria |

⚠️ **A coluna "quem" foi acrescentada em 04/09/2026 (sessão do card 6.9), e a falta dela era um
defeito do critério, não do sistema.** O roteiro original era uma sequência corrida com o critério 8
("o monitor completa a jornada inteira") logo abaixo, e isso se lê como se os oito passos fossem do
monitor. Medida a matriz inicial, **três não são**: o monitor tem `estoque.lancar_saida`,
`estoque.ler` e `alunos.ler`, e **não** tem `estoque.estornar`, `turmas.alocar` nem `compras.receber`.
Sem a coluna, o monitor bate em `SEM_PERMISSAO` no estorno e reporta como defeito a matriz do card
2.4 funcionando exatamente como foi desenhada — a mesma classe de erro do critério 1 do M1, que
reprovava software correto por estar escrito errado. **Isto não muda o critério 8**, que reprova
"passo que exija a **direção** para o que é jornada do monitor": estorno, alocação e recebimento são
da **secretaria** também, então nenhum deles exige direção.

**Aprova se, e só se:**

| # | Critério |
|---|---|
| 1 | A trilha nasce do combo na ordem certa e o "próximo" é o primeiro não entregue, sem coluna que o guarde |
| 2 | Os **três** status de retorno da entrega ocorreram no roteiro (`ENTREGUE`, `REORDENADA`, `BLOQUEADA_SEM_ESTOQUE`), cada um com o diálogo do card 2.7 — e o `REORDENADA` deixou rastro em `aluno_material_hist` com `motivo='SEM_ESTOQUE'` |
| 3 | `BLOQUEADA_SEM_ESTOQUE` **persistiu** a pendência `COMPRA_SEM_ESTOQUE` (a decisão 2.2 (b) conferida na prática) |
| 4 | Saldo pela view = `sum(quantidade)` bruto em cada passo; **nunca negativo** |
| 5 | Estorno devolve o saldo e a trilha ao estado anterior, e o movimento original continua lá |
| 6 | Bloco com 10 PCs aceita o 10º e recusa o 11º com `BLOCO_LOTADO`; PC em manutenção derruba a capacidade e gera `BLOCO_ACIMA_CAPACIDADE` quando já estava cheio |
| 7 | Duas entregas simultâneas do último exemplar, feitas em dois navegadores: uma entrega, a outra reordena ou bloqueia; saldo final 0 |
| 8 | O monitor completa a jornada inteira **no celular** com o seu perfil, sem esbarrar em RLS |

**Reprova se:** saldo negativo em qualquer momento; entrega que grave movimento sem marcar a trilha
(ou o contrário); qualquer passo que exija a direção para o que é jornada do monitor.

⚠️ **Três pré-condições que não são automatizáveis, e são de Irineu** (achado da sessão do card 6.9,
04/09/2026). Valem além das duas do §15.1, que continuam abertas:

1. **O M2 não roda antes dos cadastros do M1.** O roteiro começa em "matricular num combo", e o combo
   é entregável do roteiro do M1. Contado no dev nesta data: `aluno`, `material`, `curso`, `combo`,
   `sala`, `pc`, `professor`, `bloco_horario`, `aluno_material`, `movimento_estoque` e `pedido_compra`
   **todos em 0** (só `metodo` = 3, que é configuração). Não é defeito — é a decisão de 02/09/2026
   funcionando —, mas põe **os dois marcos em fila, não em paralelo**.
2. ⚠️ **Um usuário que seja SÓ monitor, e ele não existe.** Os três usuários do homolog são duas
   direções e uma conta com os **quatro** perfis. `tem_permissao` é a **união** dos perfis, então essa
   conta tem as 50 permissões da direção: com ela o critério 8 ("o monitor completa a jornada **com o
   perfil dele**, sem esbarrar em RLS") **passaria sem medir nada**, porque não haveria RLS de monitor
   agindo. É o modo de falha que este §15 existe para impedir. Vale igual para os critérios 2, 3 e 4
   do M1.
3. **Duas janelas para o critério 7.** Duas anônimas do mesmo navegador bastam; não precisa de duas
   pessoas.

### 15.3 M3 — Dashboard e projeção (card 8.8)

⚠️ **Divergência registrada com o plano §9 e com a nota do card.** O marco pede "dashboard e projeção
comparados à planilha". A metade do dashboard é comparável e tem de bater **exatamente**. A metade da
projeção **não é comparável**: a planilha não projeta demanda — ela tem previsão de conclusão
informada manualmente por aluno e ajustes manuais na aba Pedidos. Exigir uma comparação que não
existe produz um dos dois vícios: aceite de fachada, ou reprovação de um número que está certo. Os
critérios abaixo separam as duas metades; o critério **definitivo** da projeção é o do card 11.2
(viés entre −10% e +25%) e só existe depois de três meses de uso — dizer isso agora é honestidade,
não adiamento.

**Quem valida:** Irineu + dono do produto (é ele quem decide se a compra sugerida é aceitável).

**Pré-condições automatizadas:** suítes `010`–`095` verdes; recorte da planilha importado em dev
pela ferramenta do card 9.1 (não por `insert` à mão — importar à mão testa a mão).

**Metade A — contagens, batem exatamente:**

| Número | Fonte de conferência |
|---|---|
| Alunos por método e status | Dashboard da planilha (161/71/33 no snapshot de 29/08) |
| Alunos sem turma | 20 no snapshot, com os 2 códigos divergentes já tratados |
| Ocupação e vagas por bloco | grade da planilha; capacidades 10 / 15 / 6 |
| Estoque atual por material | aba `Ger. Apost` |
| Demanda imediata | alunos ativos cujo próximo livro é o material |
| Conclusões por semestre | Dashboard da planilha |
| Alunos no último livro | conferindo a distinção do card 2.3: `em_ultimo_livro` (1 pendente) ≠ `em_fim` (nenhum) |

**Metade B — projeção, aceite por reprodução e plausibilidade:**

| # | Critério |
|---|---|
| 1 | Quatro alunos, um por degrau (`MODULAR`, `RITMO_ALUNO`, `PREVISAO_CURSO`, `MEDIA_METODO`): a `origem` é a esperada e a conta refeita à mão bate com `v_projecao_aluno` |
| 2 | Disjunção: nenhum aluno aparece em imediata e projetada para o mesmo material — o teste do §6.4 rodado sobre os dados reais do recorte |
| 3 | Plausibilidade: Σ(imediata + projetada) no horizonte de 60 dias fica entre **0,6×** e **1,6×** a média de saídas do histórico migrado no mesmo número de meses. Fora da banda **não reprova sozinho**, mas exige explicação escrita antes do aceite. A banda é assimétrica de propósito, como o card 11.2: sobra é capital parado, falta é aula perdida |
| 4 | Nenhum material com projeção > 0 e nenhum aluno em `v_projecao_aluno` — projeção sem origem é bug, não estimativa |
| 5 | O dono do produto olha o pedido sugerido e diz se compraria aquilo. Um "não" registrado vira card de calibração, não reprova o marco |

**Reprova se:** qualquer número da metade A divergir sem explicação registrada; a disjunção falhar
(aluno contado duas vezes na compra); a tela de projeção não abrir para algum dos perfis que o card
2.4 autorizou (é o `fn_param_int` invoker — bloqueante conhecido).

### 15.4 M4 — Go-live (card 9.7)

**Quem valida:** Irineu, dono do produto, e as quatro funções em uso real.

**Pré-condições — todas obrigatórias, sem exceção por prazo:**

1. M1, M2 e M3 aceitos, com os cards de ajuste abertos por eles **fechados ou explicitamente adiados
   por escrito**.
2. Dry-run do card 9.4 com **zero divergência não explicada**.
3. Importação **reexecutável** comprovada: o mesmo snapshot importado duas vezes produz os mesmos
   totais e não duplica nada.
4. Backup semanal (card 3.11) com **restauração testada** — um backup nunca restaurado não é backup.
5. Rotina diária tendo rodado com sucesso ao menos uma vez em produção, com `ROTINA_FALHOU` ausente.
6. Sentry recebendo evento de produção (um erro provocado de propósito) sem PII de aluno na carga.
7. Secrets do `db-migrations` validados e `required reviewer` ativo no environment `prod`.
8. `supabase migration list` sem diferença entre repositório e produção.
9. Treinamento do card 9.6 concluído nos quatro perfis, e cada usuário real com primeiro login feito.

**Aprova se:** os totais em produção reproduzem os do dry-run; a planilha foi marcada somente
leitura no dia; o backup pós-carga existe e foi restaurado em teste; e há **plano de volta escrito**
— até quando se volta para a planilha, quem decide e como.

**Reprova se:** qualquer divergência de contagem; qualquer migração pendente; qualquer pendência
`ROTINA_FALHOU` aberta; ausência de plano de volta.

---

## 16. Ajustes que esta especificação exige

Mesmo formato do §14 do card 2.2, do §10 do 2.3 e do §11 do card de Ordem 5.

| # | Ajuste | Onde | Card | Gravidade |
|---|---|---|---|---|
| 1 | Workflow `testes.yml` em **todo PR** (jobs `banco` e `app`) e job de suíte **antes** do `db push` no `db-migrations` | `.github/workflows/` | 3.9 | **bloqueante** para o portão — sem ele a suíte existe e não reprova nada |
| 2 | `supabase/setup-cli` com **versão fixa** no lugar de `latest` | `db-migrations.yml` | 3.9 | **bloqueante** — CLI novo quebra o pipeline sem mudança no repositório (pendência 2(d)) |
| 3 | `major_version` do Postgres em `supabase/config.toml`, igual ao dos projetos remotos | `supabase/config.toml` | 3.9 | alta — testar em versão diferente da que aplica. *(Medido em 01/09/2026, card 3.4.5: sem a chave, `supabase start` subiu `supabase/postgres:17.6.1.165` e o dev remoto é `17.6.1.166` — hoje o default coincide, o que é sorte e não garantia: fixar mesmo assim.)* |
| 4 | **Constante de contrato sempre literal** na chamada (tipo de pendência, código de permissão, `codigo` de erro): nunca variável, concatenação ou `format()` | convenções do 2.2 §1.1 | todos os cards de função | alta — sem isso C10/C11/C12 cegam em silêncio |
| 5 | ~~`create extension pgtap`, schema `tests` e `seed.sql` **nunca** em `supabase/migrations/`; `supabase db reset --linked` proibido~~ | — | 3.4.5 | ✅ **feito em 01/09/2026** — tudo em `supabase/seed.sql`, nada em `migrations/`; `.claude/settings.json` já nega `supabase db reset` e `psql` |
| 6 | Seed do card 3.6 é **migração** (dado de catálogo, precisa existir em prod), não `seed.sql` | nota do card 3.6 | 3.6 | alta — confusão previsível entre os dois "seeds" |
| 7 | Suíte de concorrência de duas sessões é entregável dos cards de admissão e entrega | notas dos cards | 5.3 e 6.3 | **bloqueante** para o marco 2 (§15.2) |
| 8 | `required reviewer` no environment `prod` do GitHub | Settings do repositório | 3.9 | alta — portão humano da migração de produção (pendência 2(c)) |
| 9 | Fixture `test/fixtures/codigos_erro.txt` versionado, consumido pelo C12 e pelo teste Dart | repositório | 3.7 | média — hoje os 21 códigos batem; o teste é o que mantém |
| 10 | Critérios de aceite de §15 copiados para as Notas dos cards 4.8, 6.9, 8.8 e 9.7 **antes** de a fase começar | board | este card | média — critério escrito depois é justificativa, não critério |

---

## 17. Mapa suíte → card

| Suíte / arquivo | Card que cria | Fase |
|---|---|---|
| `seed.sql` (pgTAP, schema `tests`, helpers, escola-fixture) | 3.3 (bootstrap) → **3.4.5** (helpers e camada `acesso`) → cresceu em 3.6, 4.1, 4.2, 4.3, 5.1, 6.1 e **7.1** ✅ (camada `modular`) → cresce em 8.3 (camada `certificados`, declarada pelo 7.1 para o portão do `001` continuar com uma sentinela) | 3+ |
| `001_infra_teste` (helpers, fixture e o portão das camadas) | **3.4.5** | 3 |
| `010_catalogo_rls`, `011_catalogo_convencoes` | 3.3 (nasce) → cresce em toda migração | 3+ |
| `012_catalogo_contratos` (C10, C11, C12, C13) | 3.6 (precisa do seed de permissões) | 3 |
| `020_acesso_tem_permissao` | 3.4 | 3 |
| `023_catalogo_curricular` | **4.1** | 4 |
| `030_alunos_status` | 4.2 | 4 |
| `031_infraestrutura_fisica` (salas, PCs, professores e as duas funções de credencial do card 2.9) | **4.3** | 4 |
| `032_matriz_historico` (trigger de histórico, imutabilidade, seed que não devolve o removido) | **4.7.5** | 4 |
| `supabase/functions/convidar-usuario/logica.test.ts` (`node --test`, lógica pura da Edge Function) | **4.7** | 4 |
| `administracao_test`, `tela_administracao_test`, `link_inicial_test` | **4.7** | 4 |
| `040_blocos_alocacao` (as três tabelas, `tipo_desde`, as guardas de coluna e de exclusão, `tg_aluno_status_desaloca`) | **5.1** | 5 |
| `041_capacidade_vagas` (a fórmula da capacidade, as duas metades do REP na ocupação, e a prova de que o número não depende do que o leitor enxerga) | **5.2** | 5 |
| `042_vagas_admissao` + `tests_concorrencia/admissao_ultima_vaga.sh` — era `040` até o card 5.1 ocupar o número, e `041` até o 5.2 ocupar o seguinte | **5.3** ✅ | 5 |
| `043_bloco_alunos` (`v_bloco_alunos` e `fn_bloco_alunos`: a lista soma o que o cabeçalho diz, a reposição aparece na data dela com o bloco de origem, bloco desativado passa a abrir `ALUNO_SEM_TURMA`, e falta de permissão vira erro em vez de lista vazia) | **5.7** ✅ | 5 |
| `050_trilha_estoque` (as cinco tabelas, a imutabilidade do movimento nas duas camadas, o insert POR TIPO, a guarda de coluna de `aluno_material` e as duas guardas de exclusão) | **6.1** ✅ | 6 |
| `051_trilha_geracao` (fn_trilha_gerar e as três de edição, as três consultas derivadas, e os dois triggers em `aluno` que a matrícula e a troca de combo disparam) | **6.2** ✅ | 6 |
| `052_trilha_entrega` + `tests_concorrencia/entrega_ultimo_exemplar.sh` — era `050` até o card 6.1 ocupar o número, e `051` até o 6.2 ocupar o seguinte; é o mesmo deslocamento que levou o `040` do card 5.3 a `042`. ⚠️ **Divergência registrada** | **6.3** ✅ | 6 |
| `060_estoque_compras` (o ciclo do pedido — criar, enviar, receber parcial e total, cancelar —, o excedente como exceção de PERMISSÃO nas duas camadas, as pendências que a chegada da compra fecha e o ajuste que não deixa o saldo negativo) | **6.5** ✅ | 6 |
| `061_material_movimento` (`v_material_movimento`: uma linha por movimento, a soma do painel fechando com o saldo de `v_estoque_atual`, e a paridade de linhas **perfil a perfil** — o monitor sem `compras.ler` e um perfil só com `estoque.ler` veem as MESMAS linhas que a direção, com o rótulo em branco) | **6.7** ✅. ⚠️ **Divergência registrada:** o §17 não previa arquivo nenhum para o 6.7 — a tela foi planejada sem objeto de banco, e ela tem um, que o `views-leitura.md` §12.1 sempre disse ser deste card. É o mesmo caso do `053` (card 6.6), e a solução é a mesma: o arquivo mora no bloco do domínio (aqui o `06x`, ao lado do `060_estoque_compras`), não no `095`. ⚠️ **A paridade aqui é o CONTRÁRIO da do `053`:** lá se prova que a view vem vazia sem `materiais.ler` (join interno de propósito); aqui, que **nenhum perfil perde linha** (todo join de rótulo é externo). As duas asserções foram vistas vermelhas com o `join` do pedido convertido em interno | 6 |
| `estoque_test` (a lógica pura da tela 6: situação do material com o negativo vencendo o "abaixo do mínimo", os filtros da lista e do painel, e os três rótulos de "existe e você não pode ver") e `tela_estoque_test` (a tela: linha em alerta com fundo tonal **e** ícone **e** palavra, o painel por material, o estado vazio do card 2.7 apontando para Compras, o ajuste chegando ao repositório com sinal e motivo, e a ausência de qualquer caminho de ENTRADA) | **6.7** ✅ | 6 |
| `062_pedidos_compra_tela` (`v_pedido_compra` e `v_pedido_item`: pedido SEM item contando ZERO — a armadilha do §3.2 num caso real, com contraprova na forma ingênua ao lado —, `qtd_pendente` com piso por item, a `data_referencia` no fuso da escola, e a **guarda `tg_pedido_item_edicao`**, que recusa criar item, mudar `qtd_pedida` e mover item fora do RASCUNHO **sem derrubar o recebimento**, que escreve `qtd_recebida` em pedido ENVIADO e PARCIAL) | **6.8** ✅. ⚠️ **Divergência registrada:** o §17 não previa arquivo para o 6.8 — é o mesmo caso do `053` (6.6) e do `061` (6.7): a tela foi planejada sem objeto de banco e tem três, e `views-leitura.md` §12.1 sempre disse que view de tela é do card da tela. Mora no bloco `06x`, ao lado do `060` e do `061`, não no `095`. ⚠️ **Cinco contraprovas vistas vermelhas:** guarda como no-op (3 recusas caem), guarda sem o `of qtd_pedida` (o recebimento inteiro morre, e o `060` junto), `count(*)` sobre `left join` (o pedido sem item conta 1 e soma null), `qtd_pendente` sem o piso (`−2`), e o `join` em `material` externo (a lista de itens deixa de vir vazia sem `materiais.ler`) | 6 |
| `compras_test` (a lógica pura da tela 7: o que cada ESTADO do pedido permite com o motivo palavra por palavra, o filtro "só sugeridos" ligado por padrão e desligável, e o que entra no "criar pedido" — só as linhas EXIBIDAS) e `tela_compras_test` (a tela: guarda de rota tabelada, botão escondido sem `compras.criar` e desabilitado **com motivo** sem sugestão, os dois estados vazios do card 2.7, o recebimento chegando por item e o `RECEBIMENTO_EXCEDE_PEDIDO` virando a frase do catálogo em vez de erro cru) | **6.8** ✅ | 6 |
| `070_turmas_modular` (as três tabelas, os `check`/`unique` de camada 1 — inclusive a unique PARCIAL que permite ao 7.2 reativar em vez de duplicar —, o `default fn_hoje()` de `data_entrada`, a guarda de coluna do `or`, a guarda de exclusão nos dois mundos, a terceira tabela de `tg_aluno_status_desaloca` e as duas formas de turma em `ALUNO_SEM_TURMA`) | **7.1** ✅ | 7 |
| `071_modular_regras` (as duas derivadas do §9, admitir/remover com reativação e motivo, a camada 2 atacada por POST direto — método, status, unidade e CAPACIDADE —, o avanço conjunto com o passo aprendido e a preservação das datas, o motivo na desalocação sem ator, a trilha Modular = livros do curso, e `TURMA_MODULAR_SEM_CRONOGRAMA` no `check`) | **7.2** ✅ — era `070` até o card 7.1 ocupar o número. ⚠️ **Divergência registrada:** o §17 previa um arquivo `070_modular` para o **7.2**, escrito quando se supunha que o 7.1 não teria teste próprio; card de Schema tem obrigação de teste no §13 e ela é cumprida no `070`. É o mesmo deslocamento que levou o `040` do card 5.3 a `042` e o `050` do 6.3 a `052`. `ALUNO_SEM_TURMA` do aluno Modular saiu do escopo deste arquivo porque o **card 7.1** já a entregou e a mede no `070` §6 | 7 |
| `072_modular_views` (as três views da tela 5: a lotação com `vagas_livres` de piso zero e `alocados` sem piso, o `modulo_atrasado` medido nas DUAS turmas da fixture, a turma inativa que sai da lotação, a turma terminada que **fica** com o corrente nulo, e o cronograma com `corrente` comparado às outras DUAS expressões do mesmo fato, turma a turma) | **7.3** ✅. ⚠️ **Divergência registrada:** o §17 não previa arquivo para o 7.3 — é o mesmo caso do `053` (6.6), do `061` (6.7) e do `062` (6.8): a tela foi planejada sem objeto de banco e tem três views. Mora no bloco `07x`, ao lado do `070` e do `071`, não no `095`. ⚠️ **Segunda divergência:** `v_turma_modular_lotacao` estava atribuída aos cards **7.4 e 5.9** e nasceu aqui, porque o `wireframes.md` §8 manda a tela 5 lê-la e o `views-leitura.md` §12.1 é a regra geral. ⚠️ **Duas contraprovas vistas vermelhas:** `atrasado` sem o filtro `not concluido` (o módulo 1 da 2026.1, concluído e com a data REAL no passado, passa a `1=true`) e `corrente` sem a partição por `concluido` (a turma 2026.1 fica **sem** linha corrente e as três expressões divergem) | 7 |
| `080_projecao` | 8.1 | 8 |
| `085_rep_virada` | **5.3** ✅ (funções REP entram na mesma migração) — mede o VEREDITO; a seção 6 era o portão da pendência, **disparou em 03/09/2026 (card 5.5)** e virou a asserção estrutural de que as duas funções da virada fecham a pendência, cada uma com o seu sufixo. O comportamento ponta a ponta ficou no `090_rotinas`, que é o arquivo da pendência | 5 |
| `090_rotinas` (a tabela `pendencia`, as três funções do §10, rt_pendencias_diaria/rt_rep_avaliar/rt_diaria, o job `pg_cron` e a view `v_pendencias_abertas`) | **5.5** ✅ (primeira rotina) → cresce em 8.1 | 5+ |
| `091_manutencao_capacidade` (o status derivado de `pc_manutencao`, a pendência por EVENTO, `rt_pcs_normaliza` e `rt_capacidades`) | **5.4** ✅ — mora ao lado do `090`, que é o arquivo das rotinas: aqui está o que só o caminho por evento prova | 5 |
| `095_views_paridade` (a grade semanal: `fn_grade_semana` e `v_bloco_vagas_semana`; e, desde o **6.4** ✅, as quatro views de estoque, demanda e pedido sugerido — 29 → **86** asserções) | **5.6** ✅ → cresceu em **6.4** ✅ → cresce em 8.7. ⚠️ **Divergência registrada:** esta linha atribuía o nascimento do arquivo ao **6.4** ("primeiras views"), e o 6.4 é da fase 06 — quem chegou primeiro foi o 5.6, e o arquivo nasceu lá. A obrigação de teste de card de View (§13) não mudou; mudou só quem a cumpre primeiro | 5+ |
| `catalogo_erros_test`, `guardas_rota_test`, `permissao_widget_test`, `faixa_test`, `tnum_test` | 3.7 | 3 |
| `badge_status_test` / `badge_tipo_test` | 4.6 (status) e **5.7** ✅ (tipo). ⚠️ **Divergência registrada:** o §9.2 pede *golden* de badge; os dois arquivos asserem o **par de cores e a forma** lidos do tema, e o `badge_tipo_test` acrescenta a asserção que um golden não daria — preenchido × contorno lado a lado, que é a decisão do card 1.9 §6. Golden de 8 badges × 2 temas seriam 16 PNGs que reprovam por *antialiasing* de versão do engine, e o que se quer provar é a regra, não o pixel | 4–5 |
| `053_aluno_trilha` (`v_aluno_trilha`: a view e `fn_trilha_proximo_material` concordam sobre o próximo em todo aluno, `posicao` é 1..n e não a `ordem` de 10 em 10, o saldo é o de `v_estoque_atual`, e as duas reduções silenciosas em formas opostas — sem `materiais.ler` vazia, sem `estoque.ler` cheia com saldo 0) | **6.6** ✅. ⚠️ **Divergência registrada:** este arquivo não estava previsto — a linha do 6.6 abaixo só cita o `dialogo_resultado_test`, porque a tela foi planejada sem objeto de banco. Ela tem um, e `docs/views-leitura.md` §12.1 sempre disse que `v_aluno_trilha` é deste card; card de View tem obrigação própria no §13, e ela é cumprida aqui. Mora no bloco `05x` da trilha (ao lado do 050, 051 e 052) e não no `095`, que é o arquivo das views nascidas com a grade | 6 |
| `dialogo_resultado_test` (o resultado que muda a próxima ação: diálogo no desktop, folha inferior no celular, **nunca snackbar**, ícone de forma própria por tom e alvo de 44 px), `trilha_test` (a lógica pura: os três status, "trilha vazia" ≠ "trilha em fim", e os textos do §7.3 palavra por palavra) e `tela_trilha_test` (a aba: guarda por `estoque.ler`, ocultação por permissão, estado vazio do card 2.7, os três resultados na tela e o botão desabilitado **com motivo**) | **6.6** ✅ | 6 |
| `testes.yml` + gate no `db-migrations` | 3.9 | 3 |
| Reexecutabilidade da importação | 9.1 / 9.4 | 9 |

---

## 18. O que fica em aberto

1. **Teste de desempenho** — sem meta. Com ~265 alunos e uma unidade, nada aqui é problema de
   volume; a decisão consciente é não gastar teste nisso agora. Reavaliar se a Fase 11 trouxer a
   segunda unidade.
2. **Acessibilidade automatizada** — o card 2.7 verificou contraste par a par no papel; um teste
   automático de contraste e de alvo mínimo (44 px) é desejável e não é da v1.
3. **Dados de teste realistas para a projeção** — a escola-fixture é pequena de propósito. A
   avaliação séria da cascata só acontece sobre o recorte importado (M3) e sobre o histórico real
   (cards 9.5 e 11.2).
4. ~~**Quem roda a suíte de concorrência localmente** depende do `supabase start`, que exige
   Docker.~~ — **resolvido em parte no card 3.4.5 (01/09/2026):** `supabase start` + `supabase test
   db` rodaram ponta a ponta **nesta sessão na nuvem**, com pgTAP 1.3.2 de verdade e a imagem
   `supabase/pg_prove:3.36`, sem stub e sem shim. Ou seja, a suíte tem onde rodar mesmo que a máquina
   de Irineu não tenha Docker: basta uma sessão do Claude Code na nuvem. Continua sendo do card 3.9
   decidir o portão do CI e se a suíte de concorrência (dois `psql` simultâneos, §7) roda também
   localmente.

---

## Apêndice A — helpers de teste (`supabase/seed.sql`, card 3.4.5)

> **Implementado em 01/09/2026.** O SQL vigente é `supabase/seed.sql`, e é ele a fonte — não este
> apêndice. O que segue é o registro do que mudou em relação ao desenho original e por quê, para que
> a diferença não pareça descuido depois.

**O que se confirmou.** `tests.autenticar` está certo como foi escrito: `set local role` dentro de
função com cláusula `set search_path` **persiste** depois do retorno (a cláusula `SET` salva e
restaura só as variáveis que nomeia). Verificado no card 3.4 e novamente aqui, com a suíte inteira
dependendo disso.

**O que mudou.**

| # | Mudança | Motivo |
|---|---|---|
| 1 | `tests.conta_como` **não** termina com `perform tests.encerrar_sessao()` | Nessa altura a sessão já está em `authenticated`, que não tem `USAGE` no schema `tests`: a chamada morreria com `permission denied for schema tests` e derrubaria toda paridade. A volta ao papel do chamador é feita com SQL puro dentro da função. |
| 2 | `tests.criar_usuario` ganhou `p_ativo` e virou **idempotente por e-mail** | `usuario.email` é `unique`, e o desenho original repetia `gen_random_uuid()` a cada chamada: reexecutar o seed derrubava o `db reset`. O `on conflict (id) do update` também sobrevive ao trigger de espelhamento `auth.users → usuario` do card 3.5, que passará a criar a linha antes deste `insert` chegar nela. |
| 3 | Nasceram `tests.uid(email)` e `tests.unidade(codigo)`, ambos `security definer` | Sem eles todo arquivo de teste carrega UUID literal — que foi exatamente o que o `020` fazia antes. `definer` porque as duas tabelas têm RLS. |
| 4 | Nasceu `tests.como_rotina(unidade)` | O contexto de rotina do card 2.2 §2.2 é setado em três GUCs; repetir isso em cada suíte de rotina (cards 5.5 e 8.1) convida ao erro de esquecer uma. |
| 5 | `tests.codigo_do_erro(sql, usuario)` substitui o `pg_temp.codigo_do_erro` que o `020` definia | O par canônico de asserção é `throws_ok` para o SQLSTATE **e** este helper para o `codigo` — o texto da mensagem nunca é contrato (card 2.2 §1.2). Ele devolve `null`, e não erro de cast, quando o `DETAIL` vem vazio: erro sem `codigo` é falha de contrato, e quem tem de acusá-la é a asserção. |
| 6 | `tests.encerrar_sessao` limpa também `app.rotina` e `app.rotina_unidade` | Contexto de rotina vazando para o teste seguinte deixaria `tem_permissao` sempre verdadeira — suíte verde sem exercitar permissão nenhuma. |
| 7 | O schema `tests` continua **fechado** para `anon` e `authenticated` | A alternativa era conceder `USAGE` para que `encerrar_sessao` fosse chamável de dentro do papel autenticado. Fechado + `reset role;` explícito no arquivo de teste custa uma linha e mantém o mesmo padrão de todo o resto do projeto. |


## Apêndice B — `.github/workflows/testes.yml` (card 3.9)

⚠️ **Este apêndice deixou de ser o que se copia.** O card 3.9 implementou os workflows em
02/09/2026 e eles estão em `.github/workflows/`, documentados em `docs/ci-cd.md`. O YAML abaixo fica
como **registro do esqueleto original**, porque cinco defeitos dele foram descobertos ao executar —
listados logo depois. Mesmo papel que o Apêndice A ganhou no card 3.4.5.

```yaml
name: testes

on:
  pull_request:
  push:
    branches: [main, develop]

concurrency:
  group: testes-${{ github.ref }}
  cancel-in-progress: true

jobs:
  banco:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
        with:
          version: 2.20.5          # fixa — nunca `latest` (§12, ajuste 2)
      - name: Subir Postgres limpo e aplicar TODAS as migrações do zero
        run: |
          supabase start -x realtime,storage-api,imgproxy,studio,inbucket,edge-runtime,logflare,vector
          supabase db reset          # migrações desde a primeira + seed.sql
      - name: Suíte pgTAP
        run: supabase test db
      - name: Suíte de concorrência (duas sessões)
        run: |
          for s in supabase/tests_concorrencia/*.sh; do bash "$s"; done

  app:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.35.0'   # fixa, pelo mesmo motivo
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze --fatal-infos
      - run: flutter test
```

E, em `db-migrations.yml`, o job existente passa a depender da suíte:

```yaml
jobs:
  testes:
    uses: ./.github/workflows/testes.yml     # ou o job `banco` replicado
  migrate:
    needs: testes                            # vermelho não chega a dev nem a prod
    ...
```

### O que mudou ao implementar (card 3.9, 02/09/2026)

O desenho se sustentou inteiro — dois jobs, do zero sempre, versões fixas, `needs:` antes do
`db push`. O que não se sustentou foram cinco detalhes, **medidos, não deduzidos**:

| # | No apêndice | O que acontece de verdade |
|---|---|---|
| 1 | `version: 2.20.5` | Não existe. A série estável do CLI está em **2.116.0**. Reprova o job na hora — o menos grave, porque é barulhento |
| 2 | `flutter-version: '3.35.0'` | Anterior ao Dart `^3.13.2` que `app/pubspec.yaml` exige; o `pub get` nem resolve. Correto: **3.47.2** (card 3.7) |
| 3 | `-x …,inbucket,…` | `inbucket` era chave do CLI 1.x e hoje se chama `mailpit`. **Chave desconhecida não dá erro:** `supabase start -x inbucket` sai com **0**, sem aviso, e não exclui nada — a exclusão escrita errada deixa de acontecer em silêncio |
| 4 | `for s in …/*.sh; do bash "$s"; done` | Com o diretório vazio, o laço passa o próprio curinga como nome de arquivo e sai com **127** — CI vermelho desde o primeiro dia, e o desfecho pior não é o vermelho, é aprender a ignorá-lo. Corrigido com `nullglob` e mensagem explícita |
| 5 | `uses: ./.github/workflows/testes.yml` | Exige `workflow_call` no chamado, que o esqueleto não tinha; e o `concurrency` sugerido faria a execução chamada e a disparada por push se cancelarem, com o resultado dependendo de qual começou primeiro — que é a definição de teste instável do §11 |

O #3 é o que vale guardar: é a mesma família de falha silenciosa que este projeto já catalogou em
RLS que reduz linhas, em view sem `security_invoker` e em Redirect URL recusada. Por isso o
workflow imprime os contêineres que de fato subiram — não é asserção, é o antídoto contra o
silêncio.

## Apêndice C — anatomia de um arquivo de teste

Atualizado no card 3.4.5 para o contrato real dos helpers: nenhuma fixture local (a escola-fixture
do §4.2 já traz usuários, blocos e alunos), nenhum UUID literal, e `reset role;` sempre que a sessão
precisa voltar a alcançar `tests.*`.

```sql
-- supabase/tests/040_vagas_admissao.sql
begin;
select plan(6);

-- camada 3: a função, no caminho normal
select tests.autenticar(tests.uid('secretaria@escola-a.test'));
select is(
  (public.fn_bloco_admitir(<aluno>, <bloco_com_9>, 'REM', null)).status, 'ADMITIDO',
  'admissão em bloco com vaga devolve ADMITIDO');

-- camada 3: a mesma função, sem vaga
select throws_ok(
  $$ select public.fn_bloco_admitir(<outro_aluno>, <bloco_com_10>, 'REM', null) $$,
  'PT409', null, 'bloco lotado devolve PT409');

-- camada 2: o trigger, escrevendo DIRETO na tabela (o que o PostgREST faria)
select throws_ok(
  $$ insert into public.bloco_aluno (aluno_id, bloco_id, tipo, unidade_id)
     values (<outro_aluno>, <bloco_com_10>, 'REM', <unidade>) $$,
  'PT409', null, 'o trigger barra o insert direto, sem passar pela função');

-- permissão: o monitor não aloca. `reset role;` primeiro — de dentro de
-- `authenticated` o schema `tests` é inalcançável, de propósito (§4.1).
reset role;
select tests.autenticar(tests.uid('monitor@escola-a.test'));
select throws_ok(
  $$ select public.fn_bloco_admitir(<aluno>, <bloco_vazio>, 'REM', null) $$,
  'PT403', null, 'monitor sem turmas.alocar recebe PT403');

-- isolamento de unidade: conta_como troca de papel por dentro, então é chamado
-- a partir de `postgres`.
reset role;
select is(tests.conta_como(tests.uid('direcao@escola-b.test'),
                           'select 1 from public.bloco_aluno'),
          0::bigint, 'usuário da ESCOLA_B não enxerga alocação da ESCOLA_A');

select is(tests.conta_como(tests.uid('secretaria@escola-a.test'),
                           'select 1 from public.bloco_aluno where bloco_id = <bloco_com_10>'),
          10::bigint, 'e o bloco continua com 10, nunca 11');

select * from finish();
rollback;
```

Os blocos e alunos citados como `<...>` vêm das camadas `turmas` e `alunos` da fixture, que os cards
5.1 e 4.2 escrevem — o portão do §4.2 cobra as duas quando as tabelas existirem.
