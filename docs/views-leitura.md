# Views de leitura

Card de origem: **2.3 — Especificar views de leitura (estoque, demanda, pedido sugerido, dashboard,
pendências)** (Fase 2, board Notion).
Base: `docs/modelagem-dados-ddl.md` (card 2.1), `docs/regras-negocio-funcoes.md` (card 2.2),
`docs/regra-virada-rep.md` (card 2.5) e `docs/plano-projeto-sistema.md` §§4, 5.7, 6 e 7.

O Flutter consome dados **por estas views**, via `supabase_flutter`/PostgREST, sem API própria.
Escrita nunca passa por view: é sempre função de aplicação do card 2.2. Este documento é a fonte do
SQL das views, como o card 2.1 é a fonte do DDL — cada card das fases 5 a 8 recorta daqui o que
entra na sua migração (§12).

---

## 1. Escopo

**Neste documento:** as cinco famílias que o card nomeia — estoque, demanda, pedido sugerido,
dashboard e pendências — com o SQL pronto para migração, mais as views de vagas que o dashboard
consome.

**Não está neste documento, de propósito:**

| Assunto | Dono |
|---|---|
| Algoritmo da projeção de demanda (a cascata ritmo → previsão → média) | card de **Ordem 5** da Fase 2, implementado em 8.1 |
| Catálogo de códigos de permissão | card 2.4 |
| Views de tela que não são de leitura agregada (lista de alunos, trilha, alunos do bloco…) | os cards das próprias telas — §11 |

Aqui a projeção entra só como **contrato** (§5.3): o formato que `v_pedido_sugerido` já consome hoje
e que o card 8.1 preencherá sem reescrever nada.

---

## 2. Princípios

### 2.1 `security_invoker = on` em toda view, sem exceção

```sql
create view public.v_exemplo with (security_invoker = on) as select …;
```

Sem essa opção a view roda com a identidade do **dono** (`postgres`), e não com a de quem consulta.
O card 2.1 fechou `enable` + `force row level security` em toda tabela justamente para que nem o dono
escape da RLS — mas view não é tabela: uma view sem `security_invoker` seria a porta dos fundos que o
`force` fechou na porta da frente. Com `security_invoker = on`, cada linha que a view devolve passou
pelas políticas do usuário que perguntou.

Vale também para view sobre view: a opção é **por view**, não herdada. `v_demanda_imediata` lê
`v_demanda_imediata_aluno`; as duas declaram.

### 2.2 Nunca `materialized view`

Uma matview **não respeita RLS** — é um instantâneo materializado com a visibilidade de quem deu o
`refresh`, e qualquer `select` nela devolve tudo, de todas as unidades. Além disso `refresh` exige
ser dono e não roda dentro do contexto de rotina do card 2.2.

Quando um número precisar ser pré-calculado (só a projeção de demanda precisa), ele vai para uma
**tabela comum com RLS**, preenchida por rotina `pg_cron` — é o que `demanda_projetada` é (§5.3).
Custo: um `unidade_id` e quatro colunas de auditoria a mais. Ganho: a mesma barreira de todo o resto.

### 2.3 View não filtra regra de negócio, e expõe as parcelas

Uma view que já entrega o resultado filtrado esconde exatamente a linha que interessa: o material que
acabou de zerar sai da lista de compras porque "não tem demanda". Então:

- `v_pedido_sugerido` devolve **todo material ativo**, inclusive com `qtd_sugerida = 0`; quem filtra
  é a tela.
- Toda view de número derivado expõe as **parcelas** ao lado do total (`qtd_imediata`,
  `qtd_projetada`, `saldo`, `qtd_pedida_pendente`), não só o total. Foi a mitigação decidida para o
  risco "projeção imprecisa": o usuário confere a conta em vez de acreditar nela.

Exceção declarada: `v_pedido_sugerido` restringe a `material.ativo` — não se sugere comprar material
aposentado. `v_estoque_atual` não restringe: material aposentado com saldo continua sendo estoque
que a escola tem.

### 2.4 Colunas explícitas, `unidade_id` sempre, `snake_case` em português

Nada de `select *`: view com `*` congela o formato do momento da criação e não acompanha
`alter table` — dá erro silencioso de coluna faltando meses depois. Toda view carrega `unidade_id`,
mesmo com a RLS já filtrando: é o que faz a segunda unidade da Fase 11 não exigir reescrita, e o que
permite conferir um resultado sem adivinhar de que unidade ele é.

### 2.5 Grants

```sql
revoke all on public.v_exemplo from public, anon;
grant select on public.v_exemplo to authenticated;
```

`anon` não lê nada: não há tela pública. Views são somente leitura — nenhuma ganha `instead of`
trigger, porque escrita é função.

---

## 3. Quatro armadilhas que estas views têm de evitar

Não são preciosismo: cada uma já produziu, em algum sistema, um número errado que ninguém percebeu
porque parecia plausível.

### 3.1 `sum()` de conjunto vazio é `null`, não zero

Material sem nenhum movimento tem saldo **`null`** se a conta for `sum(quantidade)` — e `null` some
de qualquer comparação (`null < estoque_minimo` é `null`, não `true`). O material que nunca foi
comprado, que é o mais urgente de todos, desapareceria da lista de compras. **`coalesce(sum(…), 0)`
em toda agregação**, e `left join` (nunca `join`) da tabela de fatos para o catálogo.

### 3.2 `count(*)` sobre `left join` conta a linha nula

`count(*)` devolve 1 para um material sem movimento nenhum, porque o `left join` produziu uma linha
com tudo nulo. Contagem sempre sobre uma coluna que não pode ser nula do lado certo do join
(`count(mov.id)`), ou por subconsulta escalar.

### 3.3 `current_date` não é "hoje" na escola

O Postgres do Supabase roda em **UTC**. Das 21h às 24h em São Paulo, `current_date` já é o dia
seguinte. Isso erra a lotação do bloco (reposições "de hoje"), os dias em STANDBY e a previsão
vencida — sempre no mesmo sentido, e sempre à noite, quando ninguém está conferindo.

```sql
create or replace function public.fn_hoje()
returns date language sql stable set search_path = public, pg_temp
as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;

revoke execute on function public.fn_hoje() from public;
grant  execute on function public.fn_hoje() to authenticated;
```

**Toda view e toda rotina usam `fn_hoje()`, nunca `current_date`.** Os `default current_date` das
colunas do DDL (`aluno.status_desde`, `aluno.data_inicio`, `bloco_aluno.tipo_desde`,
`turma_modular_aluno.data_entrada`) passam a `default public.fn_hoje()` — §10.

### 3.4 RLS reduz em silêncio: ela nega linha, não devolve erro

Uma view com `security_invoker` sobre tabelas que o usuário não pode ler **não dá erro**: devolve
menos linhas. Em `v_pedido_sugerido`, um usuário sem `compras.ler` não veria `pedido_item` e leria
`qtd_pedida_pendente = 0` — ou seja, o sistema sugeriria comprar de novo o que já está a caminho, com
a cara de um número correto.

Daí a regra: **toda view tem um conjunto mínimo de permissões de leitura declarado (§9), e a rota da
tela que a consome é guardada por esse conjunto inteiro.** O guard do Flutter é a proteção contra o
número errado; a RLS continua sendo a última barreira contra o vazamento. São coisas diferentes e as
duas são necessárias.

Corolário para funções que alimentam tela:

> **Número derivado exibido em tela não pode depender do que o leitor enxerga.**
> `fn_capacidade_efetiva` e `fn_ocupacao_bloco` (card 2.2, §4.1 e §4.2) passam a **`security
> definer`** com `search_path` fixo e filtro `unidade_id = fn_unidade_atual()` no corpo — §10.
> Como `security invoker`, um usuário sem `salas.ler` contaria zero PCs, receberia capacidade 0 e
> veria a grade inteira como lotada.
> Funções que decidem **dentro de uma escrita** (`fn_saldo_material` dentro de
> `fn_registrar_entrega`) continuam `security invoker`: ali a permissão já foi exigida na entrada e a
> RLS é a checagem que se quer.

Em `v_pendencias_abertas` a redução é aceitável e por isso a view usa `left join` em todas as
referências: quem não pode ler `material` vê a pendência com o nome do material nulo, em vez de
perder a pendência.

---

## 4. Estoque

### 4.1 `v_estoque_atual` — card 6.4

Estoque é `sum(quantidade)` de `movimento_estoque`, com sinal (ENTRADA +, SAIDA −), como o card 2.1
fechou. Nunca coluna, nunca cache.

```sql
create view public.v_estoque_atual with (security_invoker = on) as
select m.unidade_id,
       m.id             as material_id,
       m.metodo_id,
       m.codigo,
       m.nome,
       m.categoria,
       m.ativo,
       m.estoque_minimo,
       coalesce(sum(mov.quantidade), 0)::integer            as saldo,
       (coalesce(sum(mov.quantidade), 0) < m.estoque_minimo) as abaixo_minimo,
       count(mov.id)::integer                               as qtd_movimentos,
       max(mov.ocorrido_em)                                 as ultimo_movimento_em
  from public.material m
  left join public.movimento_estoque mov
         on mov.material_id = m.id
        and mov.unidade_id  = m.unidade_id
 group by m.unidade_id, m.id, m.metodo_id, m.codigo, m.nome,
          m.categoria, m.ativo, m.estoque_minimo;

comment on view public.v_estoque_atual is
  'Saldo por material = soma com sinal de movimento_estoque. Inclui material sem movimento (saldo 0) e material inativo.';
```

- `left join` + `coalesce` (§3.1) e `count(mov.id)` (§3.2): material recém-cadastrado aparece com
  saldo 0 e `qtd_movimentos = 0`, que é o que a tela de compras precisa ver.
- `saldo` pode ser **negativo**? Não deveria: `fn_registrar_entrega` bloqueia ou pula por falta de
  estoque, e o advisory lock do card 2.2 impede a corrida do último exemplar. Se aparecer negativo, é
  sintoma de `AJUSTE` errado — a tela de estoque destaca, não esconde.
- A conta é idêntica à de `fn_saldo_material` (card 2.2, §7). Duas implementações da mesma soma é
  aceitável porque a soma é trivial e o motivo é diferente (listagem × decisão dentro de transação);
  o que não é aceitável é uma terceira, em Dart.

---

## 5. Demanda

### 5.1 `v_demanda_imediata_aluno` — card 6.4

Detalhe primeiro, agregado depois: a tela de projeção (7.8) pede *drill-down* por aluno, e ter duas
consultas independentes para o total e para o detalhe é como o total e o detalhe passam a divergir.

```sql
create view public.v_demanda_imediata_aluno with (security_invoker = on) as
select distinct on (am.aluno_id)
       am.unidade_id,
       am.aluno_id,
       a.nome        as aluno_nome,
       a.codigo_sgf,
       a.status      as aluno_status,
       a.metodo_id,
       am.material_id,
       am.id         as aluno_material_id,
       am.ordem,
       (select count(*) from public.aluno_material p
         where p.aluno_id = am.aluno_id and not p.entregue)::integer as itens_pendentes
  from public.aluno_material am
  join public.aluno a on a.id = am.aluno_id
 where not am.entregue
   and a.status in ('ATIVO','ACELERAR')
 order by am.aluno_id, am.ordem;
```

`distinct on (aluno_id) … order by aluno_id, ordem` é o "próximo livro" do card 2.2 (§5.2: menor
ordem com `entregue = false`) escrito uma vez para todos os alunos. Só ATIVO e ACELERAR: aluno em
STANDBY não gera compra.

### 5.2 `v_demanda_imediata` — card 6.4

```sql
create view public.v_demanda_imediata with (security_invoker = on) as
select unidade_id,
       material_id,
       count(*)::integer as qtd_alunos
  from public.v_demanda_imediata_aluno
 group by unidade_id, material_id;
```

É a coluna DEMANDA da planilha. Material sem demanda **não tem linha aqui** — quem precisa da lista
completa é `v_pedido_sugerido`, que faz `left join` e `coalesce` (§3.1).

### 5.3 `v_demanda_projetada` — contrato agora, corpo no card 8.1

O algoritmo é do card de Ordem 5 da Fase 2 e a implementação do 8.1. O que o card 2.3 fixa é o
**contrato**, para que `v_pedido_sugerido` já exista completa na Fase 6 e a Fase 8 não a reescreva.

| Coluna | Tipo | Significado |
|---|---|---|
| `unidade_id` | uuid | |
| `material_id` | uuid | |
| `mes` | date | **sempre o dia 1** do mês de competência |
| `quantidade` | integer | nº de exemplares previstos naquele mês |
| `regra` | text | `RITMO_ALUNO` / `PREVISAO_CURSO` / `MEDIA_METODO` / `MODULAR` — qual degrau da cascata produziu |
| `calculado_em` | timestamptz | quando a rotina rodou |

Grão: uma linha por (`material`, `mês`, `regra`). A `regra` fica no grão, e não escondida no
detalhe, porque a tela precisa dizer **por qual regra** cada quantidade apareceu — projeção sem
proveniência não é revisável, e a recalibração dos 3 meses (risco 2 do plano) depende de saber
quanto veio de cada degrau.

Duas decisões que o contrato precisa fixar agora, porque `v_pedido_sugerido` depende delas:

1. **A projeção não conta o próximo livro.** Cada aluno contribui a partir do **segundo** item
   pendente da trilha. O primeiro já é `v_demanda_imediata`, e a fórmula do plano
   (`imediata + projetada + mínimo − …`) só está certa se as duas parcelas forem disjuntas. Sem essa
   regra, todo aluno ativo pesa duas vezes no pedido sugerido.
2. **Janela do horizonte, em mês inteiro.** `projecao_horizonte_dias` (60) é em dias, o grão é mês.
   Entram os meses de `date_trunc('month', fn_hoje())` até
   `date_trunc('month', fn_hoje() + projecao_horizonte_dias)`, **inteiros**. Arredonda para mais:
   com 60 dias em 20/03 entram março, abril e maio completos. O erro é deliberado e para o lado de
   comprar um pouco antes — a escola não dá aula sem a apostila, e sobra de apostila é capital
   parado, não aula perdida. Se o card de Ordem 5 acrescentar `data_prevista` no detalhe, a janela
   passa a ser exata mudando **só o `where`** de `v_pedido_sugerido`.

Armazenamento (tabela com RLS, §2.2), na migração do card 8.1:

```sql
create table public.demanda_projetada (
  id uuid primary key default gen_random_uuid(),
  unidade_id  uuid not null references public.unidade(id),
  material_id uuid not null references public.material(id),
  mes         date not null,
  quantidade  integer not null check (quantidade >= 0),
  regra       text not null
              check (regra in ('RITMO_ALUNO','PREVISAO_CURSO','MEDIA_METODO','MODULAR')),
  calculado_em timestamptz not null default now(),
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint demanda_projetada_mes_ck check (mes = date_trunc('month', mes)::date),
  constraint demanda_projetada_uk unique (unidade_id, material_id, mes, regra)
);
```

`rt_projecao_demanda()` (card 2.2, §11) apaga e regrava as linhas da unidade a cada execução —
projeção é sempre "o que se sabe hoje", não histórico. A view sobre a tabela existe para que a tela e
`v_pedido_sugerido` nunca leiam a tabela direto, e para que o dia em que a projeção deixar de ser
materializada não mude nada acima dela.

---

## 6. `v_pedido_sugerido` — card 6.4, completada em 8.2

```
sugerido = imediata + projetada(H) + estoque_mínimo − estoque_atual − pedido não recebido
```

```sql
create view public.v_pedido_sugerido with (security_invoker = on) as
select e.unidade_id,
       e.material_id,
       e.metodo_id,
       e.codigo,
       e.nome,
       e.categoria,
       e.saldo,
       e.estoque_minimo,
       coalesce(di.qtd_alunos, 0)::integer         as qtd_imediata,
       0::integer                                  as qtd_projetada,   -- card 8.1 substitui (§6.2)
       coalesce(pp.qtd_pendente, 0)::integer       as qtd_pedida_pendente,
       greatest(
         coalesce(di.qtd_alunos, 0)
         + 0                                                            -- idem
         + e.estoque_minimo
         - e.saldo
         - coalesce(pp.qtd_pendente, 0),
         0)::integer                               as qtd_sugerida
  from public.v_estoque_atual e
  left join public.v_demanda_imediata di
         on di.unidade_id = e.unidade_id and di.material_id = e.material_id
  left join (
         select pi.unidade_id, pi.material_id,
                sum(pi.qtd_pedida - pi.qtd_recebida)::integer as qtd_pendente
           from public.pedido_item pi
           join public.pedido_compra pc on pc.id = pi.pedido_id
          where pc.status in ('ENVIADO','PARCIAL')
          group by pi.unidade_id, pi.material_id
       ) pp on pp.unidade_id = e.unidade_id and pp.material_id = e.material_id
 where e.ativo;
```

- **`RASCUNHO` não abate.** Pedido em rascunho não foi feito a ninguém; contá-lo faria o sistema
  parar de sugerir uma compra que nunca vai chegar. `RECEBIDO` e `CANCELADO` também não abatem — o
  primeiro já está no saldo, o segundo não virá.
- `greatest(…, 0)`: a fórmula do plano diz "se ≤ 0, não sugere". Zerar é diferente de esconder — a
  linha continua, com as parcelas visíveis (§2.3).
- Quantidade pendente é `qtd_pedida − qtd_recebida` do item, não do pedido: recebimento parcial é a
  regra, não a exceção.

### 6.2 Por que a coluna `qtd_projetada` já nasce como `0`

O card 6.4 cria esta view sem a projeção existir; o card 8.2 acrescenta a parcela. `create or
replace view` **não permite inserir coluna no meio, renomear nem trocar o tipo** de coluna existente
— só acrescentar no fim. Se a coluna aparecesse só na Fase 8, o card 8.2 teria de `drop view` (o que
derruba em cascata tudo o que depender dela) ou pendurar a projeção no fim, fora de ordem.

Reservando a coluna com o literal `0::integer` na posição certa, o card 8.2 vira um `create or
replace view` que troca **duas expressões** e nada mais:

```sql
-- card 8.2, sobre a mesma view
       coalesce(dp.qtd_projetada, 0)::integer      as qtd_projetada,
       …
       + coalesce(dp.qtd_projetada, 0)
…
  left join (
         select d.unidade_id, d.material_id, sum(d.quantidade)::integer as qtd_projetada
           from public.v_demanda_projetada d
          where d.mes between date_trunc('month', public.fn_hoje())::date
                          and date_trunc('month',
                                public.fn_hoje()
                                + public.fn_param_int('projecao_horizonte_dias'))::date
          group by d.unidade_id, d.material_id
       ) dp on dp.unidade_id = e.unidade_id and dp.material_id = e.material_id
```

O zero é honesto e está documentado como reserva: até a Fase 8, o pedido sugerido é a v1 do plano, e
a tela mostra a coluna projetada zerada em vez de fingir que ela não existe.

> **Consequência para o board:** o card 8.2 deixa de ser "evoluir a view" e passa a ser "preencher a
> parcela e mostrar a coluna na tela de Compras". Registrado nas Notas do card.

---

## 7. Vagas — cards 5.9 (dashboard) e 5.6 (grade)

Bloco é **semanal recorrente** (`dia_semana` + `hora_inicio`), mas a lotação é **de uma data**: a
alocação em `bloco_aluno` vale toda semana e a reposição em `bloco_aluno_reposicao` vale só no dia
(card 2.1, §8). View não recebe parâmetro, então a view fixa a data e a função cobre o resto.

```sql
create view public.v_bloco_vagas_semana with (security_invoker = on) as
select b.unidade_id,
       b.id            as bloco_id,
       b.dia_semana,
       b.hora_inicio,
       ref.data        as data_referencia,
       b.metodo_id,
       me.codigo       as metodo_codigo,
       b.sala_id,
       s.nome          as sala_nome,
       b.professor_id,
       p.nome          as professor_nome,
       b.capacidade_override,
       public.fn_capacidade_efetiva(b.id, ref.data) as capacidade,
       public.fn_ocupacao_bloco(b.id, ref.data)     as ocupacao,
       public.fn_vagas_livres(b.id, ref.data)       as vagas_livres,
       (public.fn_ocupacao_bloco(b.id, ref.data)
        > public.fn_capacidade_efetiva(b.id, ref.data)) as acima_capacidade
  from public.bloco_horario b
  cross join lateral (
         select (date_trunc('week', public.fn_hoje())::date + (b.dia_semana - 1)) as data
       ) ref
  join public.metodo me on me.id = b.metodo_id
  join public.sala   s  on s.id  = b.sala_id
  left join public.professor p on p.id = b.professor_id
 where b.ativo;
```

- `date_trunc('week', …)` devolve a **segunda-feira** ISO, e `dia_semana` é ISO com 1 = segunda
  (card 2.1, §8): `segunda + (dia_semana − 1)` dá a data daquele bloco **na semana corrente**. Um
  bloco de quinta consultado numa sexta traz a quinta que já passou, que é o comportamento certo para
  uma grade semanal — a tela navega semanas, não dias.
- A grade de outra semana usa a função equivalente, com a mesma conta:
  `fn_grade_semana(p_segunda date) returns setof …` — card 5.6. A view é
  `fn_grade_semana(date_trunc('week', fn_hoje()))`; escrever a função primeiro e a view em cima dela
  evita a segunda implementação da mesma aritmética.
- `acima_capacidade` é o mesmo estado que a pendência `BLOCO_ACIMA_CAPACIDADE` registra. A view não
  abre pendência (view não escreve) — mostra. Quem abre é `fn_revalidar_blocos_sala`.
- `fn_capacidade_efetiva`/`fn_ocupacao_bloco` chamadas por linha custam algumas subconsultas cada,
  para ~36 blocos ativos. É irrelevante nessa ordem de grandeza e é o preço de ter **uma** definição
  de capacidade no sistema (card 5.2 é dono da fórmula). Se um dia doer, o alvo é a função, não a
  view.

### 7.2 `v_turma_modular_lotacao` — cards 7.4 e 5.9

```sql
create view public.v_turma_modular_lotacao with (security_invoker = on) as
select t.unidade_id,
       t.id        as turma_id,
       t.nome      as turma_nome,
       t.curso_id,
       c.nome      as curso_nome,
       t.sala_id,
       s.nome      as sala_nome,
       t.capacidade,
       (select count(*) from public.turma_modular_aluno ta
         where ta.turma_id = t.id and ta.ativo)::integer as alocados,
       greatest(t.capacidade
                - (select count(*) from public.turma_modular_aluno ta
                    where ta.turma_id = t.id and ta.ativo), 0)::integer as vagas_livres,
       mc.modulo_id      as modulo_corrente_id,
       mo.nome           as modulo_corrente_nome,
       mo.ordem          as modulo_corrente_ordem,
       mc.data_inicio    as modulo_corrente_inicio,
       mc.prev_conclusao as modulo_corrente_prev_conclusao,
       (mc.prev_conclusao is not null and mc.prev_conclusao < public.fn_hoje()) as modulo_atrasado
  from public.turma_modular t
  join public.curso c on c.id = t.curso_id
  join public.sala  s on s.id = t.sala_id
  left join lateral (
         select tm.modulo_id, tm.data_inicio, tm.prev_conclusao
           from public.turma_modular_modulo tm
           join public.modulo m2 on m2.id = tm.modulo_id
          where tm.turma_id = t.id and not tm.concluido
          order by m2.ordem
          limit 1
       ) mc on true
  left join public.modulo mo on mo.id = mc.modulo_id
 where t.ativo;
```

O módulo corrente vem de `modulo.ordem` por join, não de coluna em `turma_modular_modulo` — é a
regra que o card 2.2 fixou em §9 (o cronograma da turma herda a sequência do catálogo). Turma com
todos os módulos concluídos aparece com `modulo_corrente_id` nulo, que é o estado "turma terminou",
e não some da lotação.

---

## 8. Dashboard — cards 5.9 (v1) e 8.7 (completo)

### 8.1 `v_dashboard_alunos_metodo`

```sql
create view public.v_dashboard_alunos_metodo with (security_invoker = on) as
select a.unidade_id,
       a.metodo_id,
       me.codigo as metodo_codigo,
       count(*) filter (where a.status = 'ATIVO')::integer     as ativos,
       count(*) filter (where a.status = 'ACELERAR')::integer  as acelerar,
       count(*) filter (where a.status = 'STANDBY')::integer   as standby,
       count(*) filter (where a.status = 'TRANCADO')::integer  as trancados,
       count(*) filter (where a.status = 'CANCELADO')::integer as cancelados,
       count(*) filter (where a.status = 'FORMADO')::integer   as formados,
       count(*) filter (where a.status in ('ATIVO','ACELERAR')
                          and pend.qtd = 1)::integer           as em_ultimo_livro,
       count(*) filter (where a.status in ('ATIVO','ACELERAR')
                          and pend.qtd = 0)::integer           as em_fim,
       count(*) filter (where a.status in ('ATIVO','ACELERAR')
                          and a.prev_conclusao_curso is null)::integer as sem_previsao
  from public.aluno a
  join public.metodo me on me.id = a.metodo_id
  cross join lateral (
         select count(*)::integer as qtd
           from public.aluno_material am
          where am.aluno_id = a.id and not am.entregue
       ) pend
 group by a.unidade_id, a.metodo_id, me.codigo;
```

Três colunas merecem explicação:

- **`em_ultimo_livro` (1 item pendente) e `em_fim` (nenhum) são coisas diferentes**, e o plano usa
  "último livro" para as duas. O card da planilha que a secretaria olha é o primeiro: aluno
  *recebendo* a última apostila, ainda com aula pela frente — é ele que dá tempo de pedir o
  certificado. A pendência `ALUNO_ULTIMO_LIVRO` do card 2.2, ao contrário, nasce em
  `fn_registrar_entrega` quando a trilha chega ao FIM: é o segundo. As duas leituras são úteis;
  juntá-las numa coluna só é que seria errado. Nomes diferentes, sem renomear a pendência.
- **`sem_previsao`** existe porque `v_dashboard_conclusoes_semestre` só enxerga quem tem
  `prev_conclusao_curso` preenchida. Sem esta coluna, a soma dos semestres não fecha com o total de
  ativos e ninguém sabe se faltou aluno ou faltou data.

### 8.2 `v_dashboard_conclusoes_semestre`

```sql
create view public.v_dashboard_conclusoes_semestre with (security_invoker = on) as
select a.unidade_id,
       a.metodo_id,
       me.codigo as metodo_codigo,
       extract(year from a.prev_conclusao_curso)::integer as ano,
       (case when extract(month from a.prev_conclusao_curso) <= 6 then 1 else 2 end)::smallint
                                                          as semestre,
       count(*)::integer                                  as qtd_alunos,
       count(*) filter (where a.prev_conclusao_curso < public.fn_hoje())::integer as qtd_vencidas
  from public.aluno a
  join public.metodo me on me.id = a.metodo_id
 where a.status in ('ATIVO','ACELERAR')
   and a.prev_conclusao_curso is not null
 group by a.unidade_id, a.metodo_id, me.codigo, 4, 5;
```

Previsão no passado não é descartada: fica no semestre dela, contada em `qtd_vencidas`. É o mesmo
fato que gera a pendência `PREVISAO_VENCIDA`, visto pelo lado do planejamento. A migração da planilha
vai trazer previsões de 2023 e de 2050 (card 9.3) — some-as e a conferência do dry-run não fecha.

### 8.3 `v_dashboard_tipos_bloco`

```sql
create view public.v_dashboard_tipos_bloco with (security_invoker = on) as
select ba.unidade_id,
       b.metodo_id,
       me.codigo as metodo_codigo,
       count(*) filter (where ba.tipo = 'REM')::integer  as rem,
       count(*) filter (where ba.tipo = 'PRE')::integer  as pre,
       count(*) filter (where ba.tipo = 'REP')::integer  as rep,
       count(*) filter (where ba.tipo = 'NOVO')::integer as novo,
       count(*)::integer                                 as alocacoes
  from public.bloco_aluno ba
  join public.bloco_horario b on b.id = ba.bloco_id
  join public.metodo me on me.id = b.metodo_id
 where ba.ativo
 group by ba.unidade_id, b.metodo_id, me.codigo;
```

⚠️ Conta **alocações, não alunos**: o aluno em aceleração está em dois blocos e aparece duas vezes.
É o que os totais REM/PRE da planilha significam (soma das linhas dos blocos), e é a leitura que a
secretaria usa para dimensionar. `rep` aqui é a alocação REP **contínua**; as reposições pontuais do
dia estão em `bloco_aluno_reposicao` e entram na ocupação de §7, não neste total (card 2.5).

---

## 9. `v_pendencias_abertas` — card 5.5

```sql
create view public.v_pendencias_abertas with (security_invoker = on) as
select p.unidade_id,
       p.id          as pendencia_id,
       p.tipo,
       p.severidade,
       (case p.severidade when 'ALTA' then 1 when 'MEDIA' then 2 else 3 end)::smallint
                     as ordem_severidade,
       p.descricao,
       p.chave_dedup,
       p.criado_em,
       (public.fn_hoje() - p.criado_em::date)::integer as dias_aberta,
       p.aluno_id,    al.nome as aluno_nome, al.codigo_sgf, al.status as aluno_status,
       p.bloco_id,    bh.dia_semana, bh.hora_inicio, sl.nome as bloco_sala_nome,
       p.material_id, mt.codigo as material_codigo, mt.nome as material_nome,
       p.pc_id,       pcs.identificador as pc_identificador
  from public.pendencia p
  left join public.aluno         al  on al.id  = p.aluno_id
  left join public.bloco_horario bh  on bh.id  = p.bloco_id
  left join public.sala          sl  on sl.id  = bh.sala_id
  left join public.material      mt  on mt.id  = p.material_id
  left join public.pc            pcs on pcs.id = p.pc_id
 where p.resolvida_em is null;
```

- `left join` em tudo, pelos dois motivos de §3.4: as quatro referências de `pendencia` são nulas por
  natureza (cada tipo usa uma), e o leitor sem permissão sobre a referência precisa continuar vendo a
  pendência.
- `ordem_severidade` numérica porque `'ALTA' < 'BAIXA'` em ordenação alfabética — o mesmo tipo de
  armadilha que as fases "01." a "11." do board.
- A view **não** filtra por tipo nem por permissão de domínio: a central de pendências (card 5.8) é
  uma tela só, com filtros do usuário.

---

## 10. Ajustes que esta especificação exige — entrada para os cards de migração

Mesmo formato do §14 do card 2.2 e do §8 do card 2.5: o que precisa mudar em documento já fechado.

| # | Ajuste | Onde | Card | Gravidade |
|---|---|---|---|---|
| 1 | Criar `fn_hoje()` e trocar **todo** `current_date` de view, função e rotina por ela | 2.1 §3, 2.2, 2.5 | 3.4 | **bloqueante** para a correção dos números à noite (§3.3) |
| 2 | `default current_date` → `default public.fn_hoje()` em `aluno.status_desde`, `aluno.data_inicio`, `bloco_aluno.tipo_desde`, `turma_modular_aluno.data_entrada` | 2.1 §7, §8, §9 | 4.2 / 5.1 / 7.1 | alta — data errada gravada, não só exibida |
| 3 | `fn_capacidade_efetiva` e `fn_ocupacao_bloco` passam a `security definer` + `search_path` fixo + filtro `unidade_id = fn_unidade_atual()` | 2.2 §4.1, §4.2 | 5.2 | **bloqueante** — como invoker, a grade mostra tudo lotado para quem não tem `salas.ler` (§3.4) |
| 4 | Severidade `INFO` de `ACELERAR_SEM_2O_BLOCO` no catálogo do card 2.2 **não existe** no `check` do DDL (`BAIXA`,`MEDIA`,`ALTA`) — adotar `BAIXA` | 2.2 §10.1 | 5.5 | **bloqueante** — o insert falharia no `check` de `pendencia.severidade` |
| 5 | Índice `pendencia (unidade_id, severidade) where resolvida_em is null` para a central | 2.1 §10 | 5.5 | baixa — desempenho |
| 6 | `aluno_status_ix` de `(unidade_id, status)` para `(unidade_id, metodo_id, status)`, que é como o dashboard agrupa | 2.1 §7 | 4.2 | baixa — desempenho |
| 7 | `permissao.dominio` no DDL exemplifica singular (`aluno`, `turma`); o card 2.2 fixou plural (`alunos.`, `turmas.`). Adotar **plural** e corrigir o comentário do DDL | 2.1 §4 | 2.4 | baixa — consistência |
| 8 | Nome da pendência: o board escreve `ACELERAR_SEM_SEGUNDO_BLOCO` numa nota; DDL e card 2.2 usam `ACELERAR_SEM_2O_BLOCO`. Vale o DDL | — | 5.5 | baixa — consistência |

---

## 11. Permissões de leitura por view — entrada para o card 2.4

O card 2.2 entregou as 15 permissões de **ação**; faltavam as de leitura. Cada view abaixo só devolve
o número certo se o leitor tiver **todo** o conjunto (§3.4), e é esse conjunto que guarda a rota.

| View | Permissões de leitura exigidas |
|---|---|
| `v_estoque_atual` | `materiais.ler`, `estoque.ler` |
| `v_demanda_imediata_aluno` / `v_demanda_imediata` | `alunos.ler`, `materiais.ler` |
| `v_demanda_projetada` | `materiais.ler`, `estoque.ler` |
| `v_pedido_sugerido` | `materiais.ler`, `estoque.ler`, `alunos.ler`, `compras.ler` |
| `v_bloco_vagas_semana` | `turmas.ler`, `salas.ler` |
| `v_turma_modular_lotacao` | `turmas.ler`, `salas.ler` |
| `v_dashboard_alunos_metodo` | `alunos.ler` |
| `v_dashboard_conclusoes_semestre` | `alunos.ler` |
| `v_dashboard_tipos_bloco` | `turmas.ler` |
| `v_pendencias_abertas` | `pendencias.ler` (as referências degradam para nulo sem as demais) |

Nove códigos novos, todos no padrão `<dominio>.ler`: `alunos.ler`, `materiais.ler`, `estoque.ler`,
`compras.ler`, `turmas.ler`, `salas.ler`, `certificados.ler`, `pendencias.ler`, `admin.ler`.
Na matriz inicial do plano, o **monitor** não tem `compras.ler` — logo não recebe a tela de Compras,
e não há como ele ver um pedido sugerido com a parcela pendente zerada.

---

## 12. Mapa view → card

| Objeto | Card | Fase |
|---|---|---|
| `fn_hoje()` | 3.4 | 3 |
| `v_pendencias_abertas` | 5.5 | 5 |
| `v_bloco_vagas_semana`, `fn_grade_semana` | 5.6 (grade) / 5.9 (dashboard) | 5 |
| `v_estoque_atual`, `v_demanda_imediata_aluno`, `v_demanda_imediata`, `v_pedido_sugerido` | 6.4 | 6 |
| `v_turma_modular_lotacao` | 7.4 | 7 |
| `demanda_projetada`, `v_demanda_projetada` | 8.1 | 8 |
| `v_pedido_sugerido` — troca do literal `0` pela parcela projetada | 8.2 | 8 |
| `v_dashboard_alunos_metodo`, `v_dashboard_conclusoes_semestre`, `v_dashboard_tipos_bloco` | 8.7 (o 5.9 já cria as de vaga) | 8 |

### 12.1 Views de tela, que pertencem aos seus próprios cards

Ficam nomeadas aqui só para não nascerem com nome conflitante: `v_aluno_lista` (4.6),
`v_aluno_trilha` (6.6), `v_bloco_alunos` (5.7), `v_material_movimento` (6.7),
`v_certificado_fila` (8.6). São views de listagem, sem número derivado — o cuidado de §3 vale, o
resto é do card da tela.

---

## 13. O que fica em aberto

1. **Corpo da projeção** — card de Ordem 5 da Fase 2 (algoritmo) e 8.1 (implementação). O contrato de
   §5.3 é o que este card entrega; se o algoritmo precisar de outro grão, muda a tabela e a view, e
   `v_pedido_sugerido` muda só no `where` (§6.2).
2. **Desempenho** — nenhuma medição foi feita: a base tem ~265 alunos e ~234 movimentos no snapshot
   de 29/08, ordem de grandeza em que qualquer uma dessas views responde em milissegundos. Os índices
   de §10 (#5, #6) são precaução barata, não otimização medida. Rever no card 11.2, junto com a
   calibração dos parâmetros, quando houver uso real.
3. **`v_estoque_atual` com saldo negativo** — não deveria acontecer (§4.1). Se a migração da planilha
   produzir saldo negativo por divergência entre saídas e a flag "Entregue" (card 9.3), a decisão de
   corrigir por `AJUSTE` ou aceitar é do dono do produto, não desta view.
