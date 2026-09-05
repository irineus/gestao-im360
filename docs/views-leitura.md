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

⚠️ **Medido em 04/09/2026 (card 6.4), e o custo de esquecer é ASSIMÉTRICO — não é o que a leitura
ingênua da regra sugere.** Com `alter view … reset (security_invoker)` nas duas pontas da cadeia:

- tirar a opção da view **de baixo** (`v_demanda_imediata_aluno`) **vaza até em cima**: a agregada,
  que continua `invoker`, passa a ler a de baixo como o **dono** dela, que tem `BYPASSRLS` (card
  3.3), e a soma das **duas unidades** chega à tela com a cara de um número certo. Três asserções de
  paridade do teste `095` ficam vermelhas;
- tirar a opção da view **de cima**, sozinha, **não vaza**: com a de baixo ainda `invoker`, as
  tabelas continuam sendo checadas contra o usuário da sessão e a contagem não muda. **Quem acusa
  esse caso é só o C5**, e é por isso que ele não é redundante com o teste de paridade.

Consequência para os cards 8.1 e 8.2, que vão empilhar mais uma view aqui: a opção segue obrigatória
nas duas pontas, mas a que **precisa** de teste de comportamento é a de baixo.

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
                -- piso zero POR ITEM (card 6.5) — ver o item novo abaixo
                sum(greatest(pi.qtd_pedida - pi.qtd_recebida, 0))::integer as qtd_pendente
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
- ⚠️ **`greatest(…, 0)` TAMBÉM POR ITEM (card 6.5, 04/09/2026).** Enquanto `qtd_recebida` não podia
  passar de `qtd_pedida`, a parcela por item nunca era negativa e o piso do total bastava. O card 6.5
  tornou o recebimento com excedente possível — é o que `compras.receber_excedente` significa —, e a
  partir daí um item com 11 de 10 recebidos entra na soma como **−1**. O piso do total não alcança
  isso: ele age sobre a soma, e o −1 já teria abatido a necessidade de **outro material do mesmo
  pedido**, com todas as parcelas parecendo plausíveis ao lado. O teste `060_estoque_compras` mede o
  caso, e a contraprova (view sem o piso por item) o vê **vermelho** com `−1`.

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

✅ **A reserva deixou de ser parágrafo em 04/09/2026 (card 6.4).** O teste `095` assere a **posição**
pelo catálogo — `qtd_projetada` é a 10ª coluna e a view tem 12, com `qtd_sugerida` na última —, que
é a asserção que o card 2.8 §14 pedia para esta decisão. Exercitada: recriando a view com a coluna
**no fim**, que é como ela nasceria se o 6.4 a tivesse deixado para a Fase 8, a asserção fica
vermelha sozinha. É ela que garante ao card 8.2 o `create or replace` de duas expressões.

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

⚠️ **As três views desta seção são do card 8.7, e o 5.9 não tocou em nenhuma (04/09/2026).** A v1 do
dashboard é **vaga**: totais por método e grade dia × horário, tudo lido de `v_bloco_vagas_semana`
(§7) e somado na tela a partir de parcelas que já vieram prontas. Ela saiu **sem migração** — o §12
já dizia "o 5.9 já cria as de vaga", e a leitura certa daquela linha é que as de vaga nasceram no
5.6. Alunos por método, conclusões por semestre e tipos por bloco continuam integralmente no 8.7, e
a tela do 5.9 **diz isso em rodapé** em vez de deixar o espaço vazio parecendo defeito.

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
| 2 ✅ | **Fechado em 05/09/2026 (card 7.1), o último dos quatro.** `default current_date` → `default public.fn_hoje()` em `aluno.status_desde` e `aluno.data_inicio` (4.2), `bloco_aluno.tipo_desde` (5.1) e `turma_modular_aluno.data_entrada` (7.1). O C6 prova que `current_date` não está escrito; o `070` §2 prova que o valor gravado é o de `fn_hoje()` | 2.1 §7, §8, §9 | 4.2 / 5.1 / 7.1 | alta — data errada gravada, não só exibida |
| 3 | ✅ **Feito em 03/09/2026 (card 5.2).** `fn_capacidade_efetiva` e `fn_ocupacao_bloco` são `security definer` + `search_path` fixo + filtro `unidade_id = fn_unidade_atual()` no corpo, e entraram na lista fechada do C8. `fn_vagas_livres` ficou **invoker**: não lê tabela, só compõe as duas | 2.2 §4.1, §4.2 | 5.2 | **bloqueante** — como invoker, a grade mostra tudo lotado para quem não tem `salas.ler` (§3.4) |
| 4 ✅ | **Feito em 03/09/2026 (card 5.5).** Severidade `INFO` de `ACELERAR_SEM_2O_BLOCO` no catálogo do card 2.2 **não existe** no `check` do DDL (`BAIXA`,`MEDIA`,`ALTA`) — adotado `BAIXA`. Exercitado: escrito `INFO`, `rt_pendencias_diaria` morre no `check` já na primeira execução | 2.2 §10.1 | 5.5 | **bloqueante** — o insert falharia no `check` de `pendencia.severidade` |
| 5 ✅ | **Feito em 03/09/2026 (card 5.5):** `pendencia_severidade_ix` | 2.1 §10 | 5.5 | baixa — desempenho |
| 6 | `aluno_status_ix` de `(unidade_id, status)` para `(unidade_id, metodo_id, status)`, que é como o dashboard agrupa | 2.1 §7 | 4.2 | baixa — desempenho |
| 7 | `permissao.dominio` no DDL exemplifica singular (`aluno`, `turma`); o card 2.2 fixou plural (`alunos.`, `turmas.`). Adotar **plural** e corrigir o comentário do DDL | 2.1 §4 | 2.4 | baixa — consistência |
| 8 ✅ | **Feito em 03/09/2026 (card 5.5):** vale o DDL, `ACELERAR_SEM_2O_BLOCO` | — | 5.5 | baixa — consistência |

---

## 11. Permissões de leitura por view — entrada para o card 2.4

O card 2.2 entregou as 15 permissões de **ação**; faltavam as de leitura. Cada view abaixo só devolve
o número certo se o leitor tiver **todo** o conjunto (§3.4), e é esse conjunto que guarda a rota.

| View | Permissões de leitura exigidas |
|---|---|
| `v_estoque_atual` | `materiais.ler`, `estoque.ler` |
| `v_demanda_imediata_aluno` / `v_demanda_imediata` | `alunos.ler` — ⚠️ ~~`materiais.ler`~~, ver a correção abaixo |
| `v_demanda_projetada` | `materiais.ler`, `estoque.ler` |
| `v_pedido_sugerido` | `materiais.ler`, `estoque.ler`, `alunos.ler`, `compras.ler` |
| `v_bloco_vagas_semana` | `turmas.ler`, `salas.ler`, **`materiais.ler`** |
| `v_turma_modular_lotacao` | `turmas.ler`, `salas.ler`, **`materiais.ler`** |
| `v_dashboard_alunos_metodo` | `alunos.ler`, **`materiais.ler`** |
| `v_dashboard_conclusoes_semestre` | `alunos.ler`, **`materiais.ler`** |
| `v_dashboard_tipos_bloco` | `turmas.ler`, **`materiais.ler`** |
| `v_pendencias_abertas` | `pendencias.ler` (as referências degradam para nulo sem as demais) |

⚠️ **Correção de 04/09/2026 (card 5.9), fechando o bloqueante nº 1 de `docs/permissoes-matriz.md` §7
para a primeira das cinco views.** As cinco linhas em negrito acima omitiam `materiais.ler`, e as
cinco fazem `join` **interno** em `metodo`/`curso`/`modulo`: sem a permissão a view não vem errada,
vem **vazia** — grade sem uma turma, dashboard sem uma vaga, e nada em tela dizendo que a causa é
permissão. `professores.ler` entrou por outro motivo, o achado nº 2 do mesmo §7: ali o `left join`
não esvazia, **mente** (a grade vem cheia e sem professor nenhum). As rotas do app já exigiam os dois
desde os cards 5.6 e 3.7 (`docs/permissoes-matriz.md` §6 e `app/lib/rotas/rotas.dart`) — o que estava
errado era só esta tabela, que é o contrato declarado. ✅ Para `v_bloco_vagas_semana` isto deixou de
ser parágrafo em 04/09/2026: `supabase/tests/095_views_paridade.sql` ganhou o perfil `SEM_MATERI`, que
vê a grade **vazia** e a recebe **inteira** de volta assim que `materiais.ler` é concedida. As outras
quatro continuam com os cards 7.4 e 8.7.

⚠️ **`professores.ler` SAIU da linha de `v_bloco_vagas_semana` em 04/09/2026** (card 5.11, decisão de
Irineu). A permissão foi declarada aqui pelo achado nº 2 do §7 — o `left join` em professor mente em
vez de esvaziar —, mas **o dashboard não mostra professor**: a rota dele (`permissoes-matriz.md` §6)
nunca exigiu a permissão, e `professor_id`/`professor_nome` eram lidos à toa. Das duas saídas
possíveis — mostrar o professor no `Semantics` e passar a exigir a permissão na rota, ou parar de
lê-lo —, Irineu escolheu a segunda: exigir tiraria o dashboard de quem não tem `professores.ler`, e
o professor já aparece na tela de **Turmas**, cuja rota o exige (e onde `fn_grade_semana`, não esta
view, é a fonte). A leitura foi removida de `dashboard_repositorio.dart` no mesmo dia.

⚠️ **`materiais.ler` SAIU da linha das duas views de demanda em 04/09/2026** (card 6.4), fechando o
achado nº 12 de `docs/permissoes-matriz.md` §7, que estava atribuído a este card desde 01/09/2026.
Ao contrário das cinco linhas em negrito acima, `v_demanda_imediata_aluno` **não faz `join` em
material nenhum**: ela lê `aluno_material` e `aluno`, as duas com política de `select` por
`alunos.ler`, e devolve `material_id`. Quem precisa do **nome** do material é a tela, que já carregou
o catálogo. Declarar a permissão a mais não deixava a view errada — deixava o **contrato** errado, e
contrato de permissão errado é o que faz alguém guardar uma rota por um conjunto que não é o mínimo
(ou enxugar a matriz confiando numa linha que nunca foi medida). Agora foi: `supabase/tests/095_views_paridade.sql`
ganhou o perfil `SO_ALUNOS`, que tem **só** `alunos.ler` e recebe as duas views **inteiras** — e o
mesmo perfil vê `v_estoque_atual` vazia, que é a coerência do outro lado. Se um dia a view passar a
citar `material`, a asserção cai e diz que a linha voltou a estar errada.

Nove códigos novos, todos no padrão `<dominio>.ler`: `alunos.ler`, `materiais.ler`, `estoque.ler`,
`compras.ler`, `turmas.ler`, `salas.ler`, `certificados.ler`, `pendencias.ler`, `admin.ler`.
Na matriz inicial do plano, o **monitor** não tem `compras.ler` — logo não recebe a tela de Compras,
e não há como ele ver um pedido sugerido com a parcela pendente zerada.

---

## 12. Mapa view → card

| Objeto | Card | Fase |
|---|---|---|
| `fn_hoje()` | 3.4 | 3 |
| `v_pendencias_abertas` | **5.5** ✅ — a primeira view do projeto, e com ela nasceu o C5 (toda view `security_invoker`, zero matview) | 5 |
| `v_bloco_vagas_semana`, `fn_grade_semana` | **5.6** ✅ (grade) — o **5.9** (dashboard) ✅ é consumidor da view e **não criou objeto nenhum de banco** | 5 |
| `v_bloco_alunos`, `fn_bloco_alunos` | **5.7** ✅ — ver §12.1 | 5 |
| `v_estoque_atual`, `v_demanda_imediata_aluno`, `v_demanda_imediata`, `v_pedido_sugerido` | **6.4** ✅ — `20260904180000_views_estoque_demanda.sql`, as quatro sem uma linha de dado; o teste `095` cresceu de 29 para 86 asserções | 6 |
| `v_aluno_trilha` | **6.6** ✅ — `20260904233000_view_aluno_trilha.sql`, view de listagem (§12.1); o teste nasceu em `053_aluno_trilha`, com 23 asserções | 6 |
| `v_turma_modular_lotacao` | 7.4 | 7 |
| `demanda_projetada`, `v_demanda_projetada` | 8.1 | 8 |
| `v_pedido_sugerido` — troca do literal `0` pela parcela projetada | 8.2 | 8 |
| `v_dashboard_alunos_metodo`, `v_dashboard_conclusoes_semestre`, `v_dashboard_tipos_bloco` | 8.7 (o 5.9 já cria as de vaga) | 8 |

### 12.1 Views de tela, que pertencem aos seus próprios cards

Ficam nomeadas aqui só para não nascerem com nome conflitante: `v_aluno_trilha` (6.6) ✅,
`v_bloco_alunos` (5.7) ✅, `v_material_movimento` (6.7) ✅, `v_pedido_compra` e `v_pedido_item`
(6.8) ✅, `v_certificado_fila` (8.6). São views de listagem, sem número derivado — o cuidado de §3
vale, o resto é do card da tela.

⚠️ **`v_pedido_compra` e `v_pedido_item` nasceram em 04/09/2026** (`20260905010000_views_pedidos_compra.sql`,
card 6.8), e as duas trazem o que faltava para a tela 7 não recalcular nada. Três decisões:

- **`v_pedido_compra` tem os agregados numa SUBCONSULTA agrupada, e não num `left join` com
  `count(*)`.** É o §3.2 num caso real, não hipotético: **pedido sem item existe** — é o rascunho
  recém-criado, e `PEDIDO_SEM_ITEM` de `fn_pedido_enviar` só faz sentido porque ele existe. Sobre o
  `left join` direto ele contaria **1** item que não há, e `sum()` do conjunto vazio viria `null`
  (§3.1). O teste `062` mede os dois com a **contraprova ao lado**, escrita na forma ingênua.
- **`data_referencia` é `coalesce(data_envio, criado_em at time zone 'America/Sao_Paulo')`**, e não
  `criado_em::date` (§3.3): o banco roda em UTC, e um rascunho criado às 22h apareceria datado do
  dia seguinte na lista.
- **O `join` em `material` de `v_pedido_item` é INTERNO**, como o de `v_aluno_trilha` (6.6) e ao
  contrário do de `v_material_movimento` (6.7). A diferença é qual permissão está em jogo: a rota da
  tela 7 **exige** `materiais.ler` (permissoes-matriz §6, linha 7), então quem chega sem ela já viu
  a tela "sem acesso". Das duas reduções do §3.4, a menos pior aqui é a lista **vazia**: um pedido
  cheio de itens sem nome seria uma lista de apostilas anônimas para conferir contra a caixa que
  chegou, e conferir apostila pelo id é como se recebe a errada. O `062` prova as duas reações
  opostas com um perfil que tem `compras.ler` e não tem `materiais.ler`, e a asserção da lista vazia
  foi **vista vermelha** com o `join` convertido em externo.

O `qtd_pendente` de `v_pedido_item` repete o `greatest(…, 0)` **por item** de `v_pedido_sugerido`
(§6, card 6.5) e pela mesma razão: item recebido com excedente tem `qtd_pedida − qtd_recebida`
negativo, e "faltam −2" não é frase de painel de conferência. Contraprova no `062`, lendo a
subtração crua ao lado.

⚠️ **`v_material_movimento` nasceu em 04/09/2026** (`20260904235500_view_material_movimento.sql`,
card 6.7), e a decisão dela é **o contrário** da de `v_aluno_trilha`: **todo `join` de rótulo é
externo**. Aluno, pedido, movimento estornado e autor entram por `left join`, e a view leva o **id ao
lado do nome** (`aluno_id`/`aluno_nome`, `pedido_item_id`/`pedido_numero`, `criado_por`/
`criado_por_nome`). O critério é o mesmo do 6.6 — perguntar o que cada forma de errar custa —, e aqui
ele aponta para o outro lado por duas razões: **(a)** o painel é a *conferência* do saldo, e a soma
das linhas exibidas tem de fechar com `v_estoque_atual`; uma linha que sumisse por um rótulo ilegível
quebraria a conta na tela **sem erro nenhum**, e a pessoa concluiria que o sistema perdeu movimento;
**(b)** os quatro rótulos moram atrás de permissões que a rota da tela 6 **não exige** (§6 do card
2.4: só `materiais.ler` + `estoque.ler`) — com `join` interno em `pedido_compra`, o **monitor**, que
não tem `compras.ler`, deixaria de ver *toda ENTRADA vinda de pedido*. Não há `join` em `material`:
o painel é de um material já escolhido na lista de cima, e trazê-lo de volta acrescentaria a única
redução silenciosa que faltava. O que isto obriga na tela está escrito e testado: id preenchido com
nome nulo é *"existe e você não pode ver"*, nunca um traço — um traço faria uma SAIDA de entrega
parecer um ajuste sem dono (a armadilha da pendência 9.13). O teste `061` assere a paridade de linhas
perfil a perfil e a igualdade **soma do painel = saldo**, e as duas foram **vistas vermelhas** com o
`join` do pedido convertido em interno.

⚠️ **`v_aluno_trilha` nasceu em 04/09/2026** (`20260904233000_view_aluno_trilha.sql`, card 6.6), e
duas coisas dela valem para as duas que faltam. **(a) Ela não recopia número nenhum:** `proximo`
repete o critério de `fn_trilha_proximo_material` como janela (a função responde por um aluno; a
view, por todos de uma vez) e `saldo` **chama** `fn_saldo_material` em vez de somar de novo — a
segunda implementação da soma já existe e é aquela, e uma terceira é o que o §4.1 proíbe. O teste
`053` asserta que view e função concordam aluno a aluno, e essa asserção foi **vista vermelha** com
o `filter (where not entregue)` removido. **(b) O `join` em `material` é interno de propósito:** sem
`materiais.ler` a trilha vem VAZIA, e não "cheia sem o nome". Das duas reduções silenciosas do §3.4,
esta é a menos pior — uma trilha com o nome em branco pareceria uma trilha curta, e a pessoa
entregaria a apostila errada. Sem `estoque.ler` a redução é a **oposta**: vem cheia com saldo 0 em
tudo, que é o motivo escrito de a rota 3b exigir a permissão. As duas estão asseridas no `053` §5,
cada uma com contraprova.

~~`v_aluno_lista` (4.6)~~ — **não existe, e não vai existir.** A lista de alunos lê a tabela `aluno`
e junta método, combo e turmas em memória: a view juntaria os três num objeto de banco a mais sem
tirar nenhuma consulta da tela (decisão do card 4.6). *(O `wireframes.md` §6.1 ainda a citava como
fonte da tela; corrigido em 04/09/2026, na revisão da fase 05.)*

✅ **`v_bloco_alunos` nasceu em 03/09/2026 (card 5.7), e virou DUAS coisas — divergência registrada.**
O nome estava reservado para "a lista de alunos do bloco", que é o wireframe §7.2; mas essa lista é
de uma **data** (alocação vale toda semana, reposição vale só no dia — §7 e card 2.1 §8), e view não
recebe parâmetro. A divisão que saiu, com a mesma lógica do card 5.6 invertida:

- **`v_bloco_alunos`** ficou com a metade **permanente** — uma linha por alocação ativa, com o bloco
  e o aluno resolvidos e `bloco_ativo` como **coluna**. É view porque não depende de data nenhuma, e
  ela tem três consumidores: a aba Turmas da ficha (6.4), a coluna Turmas da lista de alunos (6.1) e
  `rt_pendencias_diaria`, que passou a ler dela o que conta como "estar em turma";
- **`fn_bloco_alunos(bloco, data)`** é a lista da tela — as linhas da view daquele bloco **mais** as
  reposições PREVISTAS do dia —, escrita **em cima da view** pela razão do card 5.6: uma segunda
  implementação de "quem está alocado aqui" divergiria em silêncio.

Sem `join` em `metodo`/`sala`/`professor`, ao contrário de `v_bloco_vagas_semana`: a view devolve os
ids e quem resolve o nome é o catálogo que a tela já carregou (card 4.6 (f)). Cada `join` interno a
mais é mais um modo de a view vir **vazia por permissão** que a tela não pede — e vazia aqui não é
"o bloco está vazio", é "não deu para ver". Os dois `join` que sobram (`bloco_horario` e `aluno`) são
estruturais, e é por eles que `fn_bloco_alunos` exige `turmas.ler` **e** `alunos.ler`
explicitamente, em vez de devolver uma turma de dez como vazia.

⚠️ **`v_aluno_lista` continua sem existir, e agora com motivo medido** (card 5.7): a lista de alunos
lê `aluno` e junta as turmas de `v_bloco_alunos` **na tela**, com método e combo vindos do catálogo
já carregado. Uma view que juntasse os três não tiraria consulta nenhuma da tela — o catálogo e as
turmas já estão carregados por outros motivos — e acrescentaria um objeto de banco com um `join`
interno a mais em `aluno`. Se um dia a lista precisar filtrar **por turma** no servidor, aí ela passa
a valer a pena.

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
