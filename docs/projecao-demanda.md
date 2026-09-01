# Projeção de demanda de apostilas

Card de origem: **Fase 02, Ordem 5 — Especificar o algoritmo de projeção de demanda de apostilas**
(board Notion). ⚠️ Não confundir com o card de **Ordem 2.5** (virada REP), que a conversa do projeto
também chama de "2.5".
Base: `docs/plano-projeto-sistema.md` §6 (estoque e compras) e §5.7; `docs/modelagem-dados-ddl.md`
(card 2.1); `docs/regras-negocio-funcoes.md` (card 2.2); `docs/views-leitura.md` (card 2.3, §5.3 —
o **contrato** que este documento preenche); `docs/permissoes-matriz.md` (card 2.4).

Este documento é a **fonte do algoritmo**, como o 2.1 é a fonte do DDL e o 2.3 a fonte das views.
A implementação é do card **8.1**; o *drill-down* por aluno é do card **8.5**; a calibração inicial é
do card **9.5** e a recalibração é do card **11.2**. Cada um recorta daqui o que entra na sua
migração (§12).

---

## 1. Escopo

**Neste documento:** como se estima, para cada aluno ativo, a data em que cada apostila **futura**
da trilha será necessária; como essas datas viram `demanda_projetada(material, mês, regra, qtd)`;
quais parâmetros governam a estimativa; e o critério objetivo de recalibração.

**Não está aqui, de propósito:**

| Assunto | Dono |
|---|---|
| Contrato de `v_demanda_projetada` e janela do horizonte | card 2.3 §5.3 — **preservado integralmente** |
| Fórmula do pedido sugerido e `v_pedido_sugerido` | card 2.3 §6; aqui só se confirma o encaixe (§8) |
| Demanda **imediata** | card 2.3 §5.1–5.2 |
| Telas de Compras e de Projeção | cards 6.8 e 8.5 |

**O que este documento decide e o card 2.3 deixou explicitamente em aberto:** se a projeção passaria
a ter `data_prevista` no grão. **Não passa** (§7.4) — o grão continua mensal, como o contrato fixou.

---

## 2. Princípios

### 2.1 A projeção é uma aposta declarada, não uma medição

Nenhum degrau da cascata sabe quando o aluno vai receber a próxima apostila; todos estimam. Três
consequências assumidas em todo o desenho:

- **A regra que produziu cada número acompanha o número** (`regra` está no grão, decisão do card
  2.3). Projeção sem proveniência não é revisável, e a recalibração de §9 depende de saber quanto
  veio de cada degrau.
- **O erro é assimétrico e o arredondamento é para mais.** Sobra de apostila é capital parado;
  falta é aula perdida. Onde há dúvida entre comprar antes e comprar depois, o desenho compra antes
  — é a mesma decisão que o card 2.3 tomou ao arredondar a janela para o mês inteiro.
- **A projeção nunca bloqueia nada.** Ela alimenta uma sugestão de compra. Nenhuma regra de
  admissão, entrega ou status consulta `demanda_projetada`.

### 2.2 Um aluno, uma regra

A cascata escolhe **um** degrau por aluno, não por item da trilha. Se um mesmo aluno pudesse ter o
2º livro por `RITMO_ALUNO` e o 5º por `MEDIA_METODO`, as datas sairiam de duas réguas diferentes na
mesma sequência — e a soma por material deixaria de ter significado. A regra escolhida vale para
todos os itens futuros daquele aluno.

### 2.3 O detalhe e o total saem da mesma expressão

O card 2.3 já tinha fixado o princípio ao criar `v_demanda_imediata_aluno` antes de
`v_demanda_imediata`: "ter duas consultas independentes para o total e para o detalhe é como o total
e o detalhe passam a divergir". Aqui vale igual, e é o que define a arquitetura de §6 e §7:

```
v_ritmo_aluno ─┐
               ├─→ v_projecao_aluno ──→ rt_projecao_demanda ──→ demanda_projetada ──→ v_demanda_projetada
cronograma  ───┘   (ao vivo, 1 linha        (agrega e grava)        (tabela, RLS)         (leitura)
                    por aluno × material
                    × data prevista)
```

A tela de projeção (8.5) mostra o total vindo da tabela e, ao abrir o detalhe, lê
`v_projecao_aluno` — **a mesma expressão** que gerou o total, não uma segunda implementação. A
única divergência possível entre os dois é a hora do dia: a tabela é da última execução da rotina,
o detalhe é de agora. Por isso `calculado_em` é coluna do contrato e a tela **precisa exibi-la**.

### 2.4 A projeção não conta o próximo livro

Decisão do card 2.3, repetida aqui porque é o alicerce aritmético: cada aluno contribui a partir do
**segundo** item pendente da trilha. O primeiro já é `v_demanda_imediata`, e a fórmula
`imediata + projetada + mínimo − estoque − pedido pendente` só está certa com as duas parcelas
disjuntas. Em SQL isso é uma linha (`where k >= 2`), e é a linha que mais importa no documento
inteiro: sem ela todo aluno ativo pesa duas vezes no pedido sugerido.

### 2.5 Só ATIVO e ACELERAR

Mesmo recorte de `v_demanda_imediata_aluno`. Aluno em STANDBY, TRANCADO, CANCELADO ou FORMADO não
gera compra. **Limite assumido:** o aluno que volta de STANDBY aparece na demanda imediata no dia
em que volta, sem ter passado pela projeção — é uma falta de aviso prévio deliberada, porque
projetar quem está parado é comprar apostila para quem talvez não volte. O alerta de
`STANDBY_PROLONGADO` (card 2.2) existe justamente para essa fila não crescer em silêncio.

---

## 3. Parâmetros

Nenhum número mágico dentro de função (regra do card 2.2 §2.3). Tudo o que segue é
`parametro`, editável na tela de Administração, e **entra no seed do card 3.6**.

| chave | valor inicial | tipo | papel |
|---|---|---|---|
| `projecao_horizonte_dias` | `60` | INTEIRO | já existe (card 2.1); define a janela de meses (§7.3) |
| `ritmo_padrao_dias_INTERATIVO` | `30` | INTEIRO | degrau `MEDIA_METODO` do método Interativo |
| `ritmo_padrao_dias_INGLES` | `30` | INTEIRO | idem, Inglês |
| `ritmo_padrao_dias_MODULAR` | `45` | INTEIRO | idem, Modular (só quando não há cronograma — §5.4) |
| `ritmo_padrao_dias_PADRAO` | `30` | INTEIRO | último recurso, se faltar a chave do método |
| `ritmo_janela_entregas` | `4` | INTEIRO | quantas entregas recentes entram na média do aluno (4 entregas = 3 intervalos) |
| `ritmo_intervalo_min_dias` | `7` | INTEIRO | piso: intervalo menor que isto é entrega em lote, não ritmo |
| `ritmo_intervalo_max_dias` | `120` | INTEIRO | teto: intervalo maior que isto é interrupção, não ritmo |
| `projecao_acelerar_pct` | `50` | INTEIRO | ritmo do aluno ACELERAR = este % do ritmo do método |
| `ritmo_calibracao_dias` | `180` | INTEIRO | janela da mediana observada por método (§9) |

⚠️ **Os valores iniciais são leitura conservadora do plano, não medição** — mesma ressalva dos
quatro parâmetros `rep_*` do card 2.5. Uma apostila por mês (30 dias) é o que a planilha sugere no
Interativo; 45 dias no Modular reconhece que o livro se divide em módulos e a turma anda junto.
O card **9.5** substitui os três `ritmo_padrao_dias_<METODO>` pela mediana observada no histórico
migrado, com a função de §9.1, e o **11.2** repete a medição após três meses de uso.

### 3.1 Por que `projecao_acelerar_pct` é inteiro e não fração

`fn_param_int` é o que existe (card 2.2 §2.3); um `fn_param_num` novo só para guardar `0,5`
acrescentaria função de infraestrutura, migração e teste para representar meio. Percentual inteiro
resolve: `ritmo := greatest(round(ritmo_base * pct / 100.0), 1)`. `50` = o aluno em dois blocos por
semana anda no dobro da velocidade — que é a definição de aceleração nas Decisões vigentes.

### 3.2 Todo `fn_param_int` da projeção tem default no código

Contra a regra geral, e de propósito. `fn_param_int` levanta `PT422 / PARAMETRO_AUSENTE` quando não
há valor nem default; dentro de `rt_projecao_demanda` isso não vira erro de tela, vira
`ROTINA_FALHOU` (card 2.2 §11) e a projeção **inteira** desaparece da tela de Compras até alguém
olhar a central de pendências. Um parâmetro esquecido no seed não pode custar isso. O default no
código é o valor da tabela acima, e existe para manter a rotina viva, não para dispensar o seed.

---

## 4. O ritmo do aluno

### 4.1 O que conta como entrega

A fonte é `aluno_material.data_entrega` onde `entregue`, **não** `movimento_estoque`. O estorno
(card 2.2 §6.3) desmarca a trilha e zera `data_entrega`, então a trilha já está limpa; o movimento,
não — ler de lá exigiria casar cada `SAIDA` com o seu `ESTORNO` para não contar uma entrega
desfeita como ritmo.

### 4.2 Média das últimas entregas, com dois filtros

```
ritmo = média dos até (ritmo_janela_entregas − 1) intervalos mais recentes
        entre entregas consecutivas, descartados os intervalos fora de
        [ritmo_intervalo_min_dias, ritmo_intervalo_max_dias]
```

Três decisões dentro dessa linha:

1. **Janela, não vida inteira.** O aluno que passou de um bloco para dois mudou de ritmo; a média
   histórica levaria meses para reconhecer isso. Três intervalos é o menor número que ainda
   amortece um mês atípico.
2. **Teto (`120` dias).** Um aluno que ficou parado quatro meses e voltou tem um intervalo de 130
   dias que, sozinho, empurraria o próximo livro dele para depois do horizonte — ele sairia da
   compra justamente por ter voltado. Intervalo grande é interrupção, e interrupção não é ritmo.
3. **Piso (`7` dias).** Duas apostilas entregues no mesmo dia (acerto de atraso, ou a carga da
   migração, que traz várias entregas com a mesma data) produzem intervalo 0 ou 1 e derrubariam o
   ritmo para perto de zero — o aluno passaria a "precisar" da trilha inteira dentro do horizonte.
   É o risco mais provável logo depois da virada (card 9.7), e o piso é o que o contém.

Se **nenhum** intervalo sobrevive aos filtros, o ritmo é nulo e o aluno desce um degrau. O mínimo de
duas entregas do plano continua valendo — ele é o piso teórico; os filtros são o que o torna útil.

### 4.3 `v_ritmo_aluno` — card 8.1

```sql
create view public.v_ritmo_aluno with (security_invoker = on) as
with entrega as (
  select am.unidade_id,
         am.aluno_id,
         am.data_entrega,
         lag(am.data_entrega) over (partition by am.aluno_id
                                        order by am.data_entrega, am.ordem) as data_anterior
    from public.aluno_material am
   where am.entregue
     and am.data_entrega is not null
),
intervalo as (
  select e.unidade_id,
         e.aluno_id,
         e.data_entrega,
         (e.data_entrega - e.data_anterior) as dias
    from entrega e
   where e.data_anterior is not null
),
valido as (
  select i.*,
         row_number() over (partition by i.aluno_id order by i.data_entrega desc) as recencia
    from intervalo i
   where i.dias between public.fn_param_int('ritmo_intervalo_min_dias', 7)
                    and public.fn_param_int('ritmo_intervalo_max_dias', 120)
),
media as (
  select v.aluno_id,
         round(avg(v.dias))::integer as ritmo_dias,
         count(*)::integer           as intervalos
    from valido v
   where v.recencia <= greatest(public.fn_param_int('ritmo_janela_entregas', 4) - 1, 1)
   group by v.aluno_id
)
select e.unidade_id,
       e.aluno_id,
       max(e.data_entrega)              as ultima_entrega,
       count(*)::integer                as entregas,
       coalesce(m.intervalos, 0)        as intervalos_considerados,
       m.ritmo_dias                     as ritmo_dias        -- null = sem ritmo mensurável
  from entrega e
  left join media m on m.aluno_id = e.aluno_id
 group by e.unidade_id, e.aluno_id, m.intervalos, m.ritmo_dias;
```

```sql
create or replace function public.fn_ritmo_aluno(p_aluno_id uuid)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select r.ritmo_dias from public.v_ritmo_aluno r where r.aluno_id = p_aluno_id;
$$;
```

A função é **uma linha lendo a view**, não uma segunda implementação: é o que a ficha do aluno
(card 4.6, aba Trilha) chama para exibir "ritmo médio: 28 dias", e o que garante que o número da
ficha é o mesmo número que entrou na compra.

---

## 5. A cascata

Ordem de tentativa, por aluno:

| # | Regra | Quando se aplica |
|---|---|---|
| 1 | `MODULAR` | método MODULAR **e** turma Modular ativa com cronograma datado (§5.4) |
| 2 | `RITMO_ALUNO` | método ≠ MODULAR **e** `v_ritmo_aluno.ritmo_dias` não é nulo |
| 3 | `PREVISAO_CURSO` | `aluno.prev_conclusao_curso` informada **e futura** |
| 4 | `MEDIA_METODO` | sempre — é o degrau que não pode falhar |

**O aluno Modular não usa `RITMO_ALUNO`.** No Modular a turma avança em conjunto (Decisões
vigentes): a data em que ele recebe o próximo livro é decidida pelo cronograma da turma, não pela
velocidade dele. O histórico individual de um aluno modular mede o passado da *turma*, e usar isso
como previsão quando a turma já tem cronograma futuro é ignorar o dado melhor. Sem cronograma, ele
cai direto para o degrau 3.

Notação comum: `hoje = fn_hoje()`; `k` = posição do item na trilha pendente (1 = próximo livro,
já contado na demanda imediata); `R` = total de itens pendentes do aluno. Projeta-se `k ≥ 2`.

### 5.1 `RITMO_ALUNO`

```
âncora        = greatest(ultima_entrega, hoje − ritmo)
data_prevista = âncora + k × ritmo
```

A âncora é a última entrega, **limitada a um ritmo no passado**. Sem esse limite, o aluno que está
atrasado (última entrega há três ritmos) teria os próximos três livros com data no passado, todos
despejados no mês corrente — a projeção transformaria atraso em pico de compra. Com o limite, o
atrasado é tratado como quem vai receber o próximo agora e seguir no ritmo dele, que é a leitura
honesta: o sistema não sabe por que ele atrasou.

### 5.2 `PREVISAO_CURSO`

```
passo         = (prev_conclusao_curso − hoje) / R          -- numérico, dias
data_prevista = hoje + round(k × passo)
```

Distribui os `R` itens pendentes uniformemente até a data informada: em `k = R`, a data cai
exatamente na previsão de conclusão, que é o significado do campo.

**Previsão vencida não serve de base.** Com `prev_conclusao_curso` no passado, o passo é negativo e
o degrau despejaria a trilha inteira no mês corrente. Uma data vencida é dado errado, não previsão
apertada — e já existe a pendência `PREVISAO_VENCIDA` (card 2.2 §10.1) pedindo que uma pessoa a
corrija. Enquanto ninguém corrige, o aluno é projetado por `MEDIA_METODO`, que é o comportamento de
quem não tem previsão nenhuma — que é a verdade.

### 5.3 `MEDIA_METODO`

```
ritmo_base    = fn_param_int('ritmo_padrao_dias_' || metodo.codigo,
                             fn_param_int('ritmo_padrao_dias_PADRAO', 30))
ritmo         = ACELERAR ? greatest(round(ritmo_base × projecao_acelerar_pct / 100.0), 1)
                         : ritmo_base
âncora        = greatest(coalesce(ultima_entrega, aluno.data_inicio), hoje − ritmo)
data_prevista = âncora + k × ritmo
```

O fator de aceleração vale **só aqui**. Em `RITMO_ALUNO` a aceleração já está medida (o aluno em
dois blocos entrega mais rápido, e a média mostra isso); em `PREVISAO_CURSO` a data foi declarada
por uma pessoa que sabe se o aluno acelerou; em `MODULAR` quem manda é a turma. Aplicar o fator nos
quatro degraus contaria a aceleração duas vezes.

### 5.4 `MODULAR`

O livro do aluno Modular é necessário quando a turma entra no **primeiro módulo daquele livro**
(plano §6). O cronograma é `turma_modular_modulo`, e **a ordem vem de `modulo.ordem`**, não da
tabela do cronograma (card 2.2 §9).

Data planejada de início de cada módulo:

1. `turma_modular_modulo.data_inicio`, quando informada;
2. senão, `prev_conclusao` do módulo anterior da turma `+ 1 dia`;
3. senão, **extrapolação**: última data conhecida do cronograma `+ passo × (nº de módulos desde
   ela)`, com `passo` = duração média planejada dos módulos datados da turma
   (`prev_conclusao − data_inicio + 1`), ou `ritmo_padrao_dias_MODULAR` se nenhum módulo tiver as
   duas datas.

A extrapolação existe porque o cronograma real vem datado nos primeiros módulos e vazio nos
últimos. Sem ela, ou se perde a demanda dos livros seguintes (silenciosamente — a pior das opções),
ou o aluno inteiro cai de degrau por causa de um módulo sem data, trocando o cronograma real por
uma média de método.

Se a turma **não tem data nenhuma**, não há o que extrapolar: o aluno cai para o degrau 3 e a rotina
abre a pendência `TURMA_MODULAR_SEM_CRONOGRAMA` (severidade BAIXA, §7.5). Cronograma vazio degrada
a projeção sem quebrar nada — exatamente o tipo de falha que precisa de alguém avisado.

**A quantidade continua sendo por aluno**, não por turma: cada aluno ativo da turma com aquele item
ainda pendente conta 1. Contar a turma inteira ignoraria quem já recebeu o livro adiantado ou
entrou depois, e quebraria a disjunção com a demanda imediata de §2.4.

---

## 6. `v_projecao_aluno` — cards 8.1 (rotina) e 8.5 (drill-down)

Uma linha por (aluno, material, data prevista, regra), sem recorte de horizonte — quem recorta é a
rotina (§7.3) e a tela. Assim, mudar `projecao_horizonte_dias` **não** exige tocar na view.

```sql
create view public.v_projecao_aluno with (security_invoker = on) as
with p as (
  select public.fn_hoje()                                        as hoje,
         public.fn_param_int('ritmo_padrao_dias_PADRAO', 30)      as ritmo_padrao,
         public.fn_param_int('projecao_acelerar_pct', 50)         as acelerar_pct,
         public.fn_param_int('ritmo_padrao_dias_MODULAR', 45)     as passo_modular_padrao
),
-- itens pendentes dos alunos ativos, numerados: k = 1 é o próximo livro (demanda imediata)
pendente as (
  select am.unidade_id,
         am.aluno_id,
         am.material_id,
         a.metodo_id,
         a.status,
         a.data_inicio,
         a.prev_conclusao_curso,
         row_number() over (partition by am.aluno_id order by am.ordem) as k,
         count(*)    over (partition by am.aluno_id)                    as pendentes
    from public.aluno_material am
    join public.aluno a on a.id = am.aluno_id
   where not am.entregue
     and a.status in ('ATIVO','ACELERAR')
),
-- turma Modular ativa do aluno (o índice único do DDL garante no máximo uma)
turma_aluno as (
  select tma.aluno_id, tma.turma_id
    from public.turma_modular_aluno tma
    join public.turma_modular tm on tm.id = tma.turma_id and tm.ativo
   where tma.ativo
),
-- passo médio planejado dos módulos datados de cada turma
passo_turma as (
  select tmm.turma_id,
         round(avg(tmm.prev_conclusao - tmm.data_inicio + 1))::integer as passo
    from public.turma_modular_modulo tmm
   where tmm.data_inicio is not null and tmm.prev_conclusao is not null
   group by tmm.turma_id
),
-- cronograma com a data conhecida de início de cada módulo
cronograma as (
  select tmm.turma_id,
         mo.material_id,
         mo.ordem,
         coalesce(tmm.data_inicio,
                  lag(tmm.prev_conclusao) over (partition by tmm.turma_id order by mo.ordem) + 1)
           as data_conhecida
    from public.turma_modular_modulo tmm
    join public.modulo mo on mo.id = tmm.modulo_id
),
-- gaps-and-islands: cada módulo sem data herda a última conhecida e conta os saltos até ela
ilha as (
  select c.*,
         count(c.data_conhecida) over (partition by c.turma_id order by c.ordem
                                       rows between unbounded preceding and current row) as grupo
    from cronograma c
),
cronograma_cheio as (
  select i.turma_id,
         i.material_id,
         i.ordem,
         first_value(i.data_conhecida) over (partition by i.turma_id, i.grupo order by i.ordem) as base,
         i.ordem - first_value(i.ordem) over (partition by i.turma_id, i.grupo order by i.ordem) as saltos
    from ilha i
   where i.grupo > 0                        -- descarta módulos antes da primeira data conhecida
),
-- data em que a turma entra no PRIMEIRO módulo de cada material
modular as (
  select cc.turma_id,
         cc.material_id,
         min(cc.base + cc.saltos * coalesce(pt.passo, p.passo_modular_padrao)) as data_prevista
    from cronograma_cheio cc
    cross join p
    left join passo_turma pt on pt.turma_id = cc.turma_id
   group by cc.turma_id, cc.material_id
),
-- degrau escolhido, uma vez por aluno (§2.2)
aluno_regra as (
  select distinct
         pe.aluno_id,
         pe.metodo_id,
         me.codigo as metodo_codigo,
         pe.status,
         pe.data_inicio,
         pe.prev_conclusao_curso,
         ta.turma_id,
         ra.ritmo_dias,
         ra.ultima_entrega,
         case
           when me.codigo = 'MODULAR'
                and exists (select 1 from modular m where m.turma_id = ta.turma_id)
             then 'MODULAR'
           when me.codigo <> 'MODULAR' and ra.ritmo_dias is not null
             then 'RITMO_ALUNO'
           when pe.prev_conclusao_curso > p.hoje
             then 'PREVISAO_CURSO'
           else 'MEDIA_METODO'
         end as regra
    from pendente pe
    cross join p
    join public.metodo me on me.id = pe.metodo_id
    left join turma_aluno ta on ta.aluno_id = pe.aluno_id
    left join public.v_ritmo_aluno ra on ra.aluno_id = pe.aluno_id
),
-- ritmo efetivo dos degraus que trabalham com ritmo
ritmo_efetivo as (
  select ar.aluno_id,
         ar.regra,
         case ar.regra
           when 'RITMO_ALUNO' then ar.ritmo_dias
           when 'MEDIA_METODO' then
             case when ar.status = 'ACELERAR'
                  then greatest(round(public.fn_param_int('ritmo_padrao_dias_' || ar.metodo_codigo,
                                                          p.ritmo_padrao)
                                      * p.acelerar_pct / 100.0), 1)::integer
                  else public.fn_param_int('ritmo_padrao_dias_' || ar.metodo_codigo, p.ritmo_padrao)
             end
           else null
         end as ritmo,
         greatest(coalesce(ar.ultima_entrega, ar.data_inicio), p.hoje - 400) as ancora_bruta
    from aluno_regra ar
    cross join p
)
select pe.unidade_id,
       pe.aluno_id,
       pe.material_id,
       ar.regra,
       case ar.regra
         when 'MODULAR' then mo.data_prevista
         when 'PREVISAO_CURSO'
           then p.hoje + round(pe.k * (ar.prev_conclusao_curso - p.hoje)::numeric
                                    / pe.pendentes)::integer
         else greatest(re.ancora_bruta, p.hoje - re.ritmo) + pe.k * re.ritmo
       end as data_prevista,
       pe.k,
       pe.pendentes
  from pendente pe
  cross join p
  join aluno_regra   ar on ar.aluno_id = pe.aluno_id
  join ritmo_efetivo re on re.aluno_id = pe.aluno_id
  left join modular  mo on mo.turma_id = ar.turma_id and mo.material_id = pe.material_id
 where pe.k >= 2                                     -- §2.4: o próximo livro é demanda imediata
   and (ar.regra <> 'MODULAR' or mo.data_prevista is not null);
```

Notas de leitura:

- `where pe.k >= 2` é a disjunção de §2.4. Nada mais no sistema depende de o número estar certo
  tanto quanto esta linha.
- `ancora_bruta` traz o `greatest(..., hoje − 400)` só para conter data de entrega absurda vinda da
  migração; o limite que importa (`hoje − ritmo`) está aplicado na projeção, onde o ritmo já é
  conhecido.
- O `left join modular` com `mo.data_prevista is not null` na cláusula final cobre o material que a
  turma não tem no cronograma (aluno com item manual fora da grade do curso): ele não é projetado,
  em vez de receber uma data inventada.
- **Custo:** a ordem de grandeza é alunos ativos × itens pendentes — algumas centenas × ~20. A
  rotina roda uma vez por dia e a tela lê a tabela; a view ao vivo só é consultada no *drill-down*
  de um material.

---

## 7. Materialização

### 7.1 Tabela, políticas e por que a escrita é só da rotina

A tabela `demanda_projetada` é a do card 2.3 §5.3, sem alteração de colunas. O que este documento
acrescenta é a RLS dela — que não passa pelo padrão de quatro políticas do card 2.1, porque
**nenhum usuário escreve nesta tabela**:

```sql
alter table public.demanda_projetada enable row level security;
alter table public.demanda_projetada force  row level security;

create policy demanda_projetada_sel on public.demanda_projetada for select
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('estoque.ler'));

create policy demanda_projetada_ins on public.demanda_projetada for insert
  with check (unidade_id = public.fn_unidade_atual() and public.fn_contexto_rotina());

create policy demanda_projetada_del on public.demanda_projetada for delete
  using (unidade_id = public.fn_unidade_atual() and public.fn_contexto_rotina());

-- sem política de update: a rotina apaga e regrava (contrato do card 2.3)
```

`fn_contexto_rotina()` (card 2.2 §2.2) é a única credencial de escrita. Sem política nenhuma nem a
rotina escreveria — `force row level security` alcança o dono da tabela. Com uma política baseada em
permissão de domínio, a tela de Compras poderia gravar projeção via PostgREST.

**Risco residual, já aceito pelo card 2.2:** quem conseguisse `set_config('app.rotina','on',…)`
teria escrita aqui. Só há como fazer isso com conexão SQL direta — as GUCs são escritas dentro das
`rt_*`, que não têm `grant execute` para `anon`/`authenticated`, e o PostgREST não expõe função sem
`grant`. A superfície nova que esta tabela cria é zero: quem chega lá já contornou `tem_permissao`.

### 7.2 Snapshot mensal — o que torna a recalibração possível

```sql
create table public.demanda_projetada_hist (
  id uuid primary key default gen_random_uuid(),
  unidade_id  uuid not null references public.unidade(id),
  material_id uuid not null references public.material(id),
  mes         date not null,
  quantidade  integer not null check (quantidade >= 0),
  regra       text not null
              check (regra in ('RITMO_ALUNO','PREVISAO_CURSO','MEDIA_METODO','MODULAR')),
  snapshot_em date not null,           -- 1º dia do mês em que a foto foi tirada
  criado_em timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid,
  constraint demanda_projetada_hist_mes_ck check (mes = date_trunc('month', mes)::date),
  constraint demanda_projetada_hist_snap_ck check (snapshot_em = date_trunc('month', snapshot_em)::date),
  constraint demanda_projetada_hist_uk unique (unidade_id, snapshot_em, material_id, mes, regra)
);
```

Mesmas políticas de §7.1 (`select` por `estoque.ler`; `insert` por `fn_contexto_rotina()`; sem
`update` nem `delete`).

**Por que existe:** o card 11.2 pede recalibrar a projeção depois de três meses de uso. A tabela
`demanda_projetada` é sobrescrita todo dia — projeção é "o que se sabe hoje", decisão do card 2.3 —
então, sem foto, em janeiro não há como responder "o que a gente previu em novembro para
dezembro?", e a recalibração fica reduzida a opinião. A foto é tirada **uma vez por mês**, na
primeira execução do mês: ~(materiais × 3 meses × 4 regras) linhas, na casa da centena por mês.
É o registro mais barato que transforma o card 11.2 em medição.

### 7.3 `rt_projecao_demanda()` — card 8.1

```sql
create or replace function public.rt_projecao_demanda()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade   uuid := public.fn_unidade_atual();
  v_hoje      date := public.fn_hoje();
  v_mes_ini   date := date_trunc('month', public.fn_hoje())::date;
  v_mes_fim   date := date_trunc('month', public.fn_hoje()
                                 + public.fn_param_int('projecao_horizonte_dias', 60))::date;
begin
  delete from public.demanda_projetada where unidade_id = v_unidade;

  insert into public.demanda_projetada
         (unidade_id, material_id, mes, quantidade, regra, calculado_em)
  select pa.unidade_id,
         pa.material_id,
         date_trunc('month', pa.data_prevista)::date,
         count(*)::integer,
         pa.regra,
         now()
    from public.v_projecao_aluno pa
   where pa.unidade_id = v_unidade
     and date_trunc('month', pa.data_prevista)::date between v_mes_ini and v_mes_fim
   group by pa.unidade_id, pa.material_id, date_trunc('month', pa.data_prevista)::date, pa.regra;

  -- foto mensal (§7.2): só na primeira execução do mês
  if not exists (select 1 from public.demanda_projetada_hist
                  where unidade_id = v_unidade and snapshot_em = v_mes_ini) then
    insert into public.demanda_projetada_hist
           (unidade_id, material_id, mes, quantidade, regra, snapshot_em)
    select unidade_id, material_id, mes, quantidade, regra, v_mes_ini
      from public.demanda_projetada
     where unidade_id = v_unidade;
  end if;

  -- turma Modular ativa sem cronograma datado degrada a projeção em silêncio (§5.4)
  perform public.fn_pendencia_abrir(
            'TURMA_MODULAR_SEM_CRONOGRAMA',
            'CRONOGRAMA:' || tm.id::text,
            'A turma Modular ' || tm.nome || ' não tem nenhum módulo com data planejada; '
              || 'os alunos dela estão sendo projetados pela média do método.',
            'BAIXA')
     from public.turma_modular tm
    where tm.ativo
      and tm.unidade_id = v_unidade
      and not exists (select 1 from public.turma_modular_modulo tmm
                       where tmm.turma_id = tm.id
                         and (tmm.data_inicio is not null or tmm.prev_conclusao is not null));

  perform public.fn_pendencia_resolver('CRONOGRAMA:' || tm.id::text)
     from public.turma_modular tm
    where tm.unidade_id = v_unidade
      and (not tm.ativo
           or exists (select 1 from public.turma_modular_modulo tmm
                       where tmm.turma_id = tm.id
                         and (tmm.data_inicio is not null or tmm.prev_conclusao is not null)));
end;
$$;
```

- **A rotina opera na unidade do contexto**, setado por `rt_diaria` antes da chamada (card 2.2
  §11). Ela não itera unidades por conta própria — ver o ajuste de redação em §11, item 6.
- **`delete` + `insert` na mesma transação** não abre janela de tabela vazia: pelo MVCC, quem
  consultar durante a execução continua vendo o conjunto anterior até o `commit`.
- **A rotina grava só a janela** `[mês corrente, mês de hoje + horizonte]`. Guardar mês fora da
  janela seria guardar linha que nenhuma tela lê e que envelhece na próxima execução. O `where` de
  `v_pedido_sugerido` (card 2.3 §6.2) repete o recorte de propósito: se alguém reduzir o horizonte,
  a view já fica certa antes de a rotina rodar de novo.
- **Abre e fecha** a pendência de cronograma, como `rt_pendencias_diaria` faz com as de tempo: uma
  pendência que só abre vira lista de coisas que já deixaram de ser verdade.

### 7.4 A projeção continua com grão mensal

O card 2.3 deixou a porta aberta: "se o card de Ordem 5 acrescentar `data_prevista` no detalhe, a
janela passa a ser exata mudando só o `where` de `v_pedido_sugerido`". **Não acrescenta.**
`v_projecao_aluno` tem `data_prevista` para quem quiser o detalhe, mas o agregado permanece
`(material, mês, regra)`:

- a precisão diária seria falsa — a estimativa carrega erro de semanas, então recortar em dias é dar
  aparência de exatidão a um número que não a tem;
- o arredondamento para o mês inteiro é a decisão deliberada de comprar um pouco antes (§2.1);
- o contrato do card 2.3 fica intacto, e o card 8.2 continua sendo a troca de duas expressões.

### 7.5 `v_demanda_projetada` — card 8.1

```sql
create view public.v_demanda_projetada with (security_invoker = on) as
select dp.unidade_id,
       dp.material_id,
       dp.mes,
       dp.quantidade,
       dp.regra,
       dp.calculado_em
  from public.demanda_projetada dp;
```

Existe para que tela e `v_pedido_sugerido` nunca leiam a tabela direto (card 2.3 §5.3): o dia em que
a projeção deixar de ser materializada, muda-se o corpo da view e nada acima dela.

---

## 8. Encaixe em `v_pedido_sugerido` (card 8.2)

Nada muda no que o card 2.3 já escreveu. O `create or replace view` do 8.2 troca as duas expressões
previstas, somando `quantidade` sobre **todas as regras e todos os meses da janela**:

```sql
  left join (
         select d.unidade_id, d.material_id, sum(d.quantidade)::integer as qtd_projetada
           from public.v_demanda_projetada d
          where d.mes between date_trunc('month', public.fn_hoje())::date
                          and date_trunc('month', public.fn_hoje()
                                + public.fn_param_int('projecao_horizonte_dias'))::date
          group by d.unidade_id, d.material_id
       ) dp on dp.unidade_id = e.unidade_id and dp.material_id = e.material_id
```

Confirmações que este documento fecha para o card 8.2:

- `sum` sobre a `regra` é correto porque um aluno produz **uma** linha por material (a regra é única
  por aluno, §2.2, e `aluno_material_uk` impede o mesmo material duas vezes na mesma trilha) — não
  há dupla contagem entre degraus;
- a parcela projetada e a imediata são disjuntas (§2.4);
- a tela de Compras exibe as parcelas ao lado do total (card 2.3 §2.3) e, junto delas,
  `calculado_em` — número de projeção sem a data do cálculo é número sem validade.

---

## 9. Calibração (card 9.5) e recalibração (card 11.2)

### 9.1 Medir o ritmo do método

```sql
create or replace function public.fn_ritmo_metodo_observado(p_metodo_id uuid,
                                                            p_dias integer default null)
returns table (ritmo_mediana integer, intervalos integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with i as (
    select (am.data_entrega
            - lag(am.data_entrega) over (partition by am.aluno_id
                                             order by am.data_entrega, am.ordem)) as dias,
           am.data_entrega
      from public.aluno_material am
      join public.aluno a on a.id = am.aluno_id
     where am.entregue
       and am.data_entrega is not null
       and a.metodo_id = p_metodo_id
       and am.unidade_id = public.fn_unidade_atual()
  )
  select percentile_cont(0.5) within group (order by i.dias)::integer,
         count(*)::integer
    from i
   where i.dias between public.fn_param_int('ritmo_intervalo_min_dias', 7)
                    and public.fn_param_int('ritmo_intervalo_max_dias', 120)
     and i.data_entrega >= public.fn_hoje()
                           - coalesce(p_dias, public.fn_param_int('ritmo_calibracao_dias', 180));
$$;
```

- **Mediana, não média.** A distribuição de intervalos tem cauda longa à direita (paradas,
  férias, atrasos); a média é puxada por ela e superestima o tempo entre livros, o que faz comprar
  tarde demais. No ritmo **individual** (§4.2) a média continua, porque lá são três valores já
  filtrados — mediana de três é quase a mesma conta com menos informação.
- `security definer` com filtro de unidade explícito, pela regra do card 2.3: número derivado
  exibido em tela não pode depender do que o leitor enxerga. Só a direção edita parâmetro, mas o
  número precisa ser o mesmo para quem olhar.

**Card 9.5** roda a função por método sobre o histórico migrado e grava o resultado em
`ritmo_padrao_dias_<METODO>`. **Não é migração**: é `update` em `parametro`, feito na tela.

### 9.2 Critério objetivo de recalibração — card 11.2

Duas medidas, com gatilhos separados:

**(a) Ritmo do método.** Recalibrar `ritmo_padrao_dias_<METODO>` quando

```
intervalos >= 30  e  |mediana_observada − parametro| > 0,20 × parametro
```

Abaixo de 30 intervalos válidos a mediana ainda é ruído e mexer no parâmetro é trocar um palpite por
outro. Os 20% são a faixa em que a mudança de fato desloca um livro de mês dentro de um horizonte de
60 dias — abaixo disso, mexer não muda pedido nenhum.

**(b) Viés da projeção.** Sobre os meses já fechados, comparando o previsto com o realizado:

```
viés = (Σ qtd_projetada − Σ qtd_realizada) / Σ qtd_realizada
```

| Viés | Leitura | Ação |
|---|---|---|
| > +25% | comprando cedo/demais | aumentar `ritmo_padrao_dias_*`, ou reduzir `projecao_horizonte_dias` |
| entre −10% e +25% | dentro do esperado | nada |
| < −10% | faltando apostila | reduzir `ritmo_padrao_dias_*` |

**Os limites são deliberadamente assimétricos.** Sobra de 25% é capital parado numa prateleira;
falta de 10% é aula sem material. O sistema tolera errar mais para o lado de comprar.

### 9.3 `v_projecao_acuracia` — card 11.2

```sql
create view public.v_projecao_acuracia with (security_invoker = on) as
with previsto as (
  select h.unidade_id, h.material_id, h.mes, h.regra,
         sum(h.quantidade)::integer as qtd_projetada
    from public.demanda_projetada_hist h
   where h.snapshot_em = (h.mes - interval '1 month')::date   -- a foto de um mês antes
   group by h.unidade_id, h.material_id, h.mes, h.regra
),
realizado as (
  select am.unidade_id,
         am.material_id,
         date_trunc('month', am.data_entrega)::date as mes,
         count(*)::integer as qtd_realizada
    from public.aluno_material am
   where am.entregue and am.data_entrega is not null
   group by am.unidade_id, am.material_id, date_trunc('month', am.data_entrega)::date
)
select coalesce(p.unidade_id, r.unidade_id)   as unidade_id,
       coalesce(p.material_id, r.material_id) as material_id,
       coalesce(p.mes, r.mes)                 as mes,
       p.regra,
       coalesce(p.qtd_projetada, 0)           as qtd_projetada,
       coalesce(r.qtd_realizada, 0)           as qtd_realizada,
       coalesce(p.qtd_projetada, 0) - coalesce(r.qtd_realizada, 0) as erro
  from previsto p
  full join realizado r
    on r.unidade_id = p.unidade_id and r.material_id = p.material_id and r.mes = p.mes
 where coalesce(p.mes, r.mes) < date_trunc('month', public.fn_hoje())::date;   -- só mês fechado
```

- **Um mês de antecedência** é o recorte que interessa: é o tempo de decidir e receber um pedido de
  compra. A foto do próprio mês responderia "acertamos o que já estava acontecendo".
- **`full join`** de propósito: o material previsto e não entregue (`qtd_realizada = 0`) e o
  entregue sem ter sido previsto (`qtd_projetada = 0`) são os dois lados do erro, e um `left join`
  esconderia justamente o segundo — o que faltou.
- **Limite assumido:** `realizado` conta toda entrega do mês, inclusive a que era demanda imediata
  no início do mês. A parcela projetada e a imediata são disjuntas na *decisão de compra* (§2.4),
  não no consumo — quem consome o estoque é a entrega, venha de onde vier. Para o viés agregado isso
  é o certo; para julgar um material isolado, olhar a coluna `regra` antes de concluir.

---

## 10. Permissões de leitura declaradas

Regra do card 2.3 §9, e o motivo dela: **a RLS reduz linhas em silêncio, não devolve erro**. Uma
tela cuja rota não exija o conjunto abaixo mostra número menor com cara de número certo.

| View / função | Permissões de leitura | Por quê |
|---|---|---|
| `v_ritmo_aluno` | `alunos.ler` | lê `aluno_material` |
| `v_projecao_aluno` | `alunos.ler`, `materiais.ler`, `turmas.ler` | `aluno`/`aluno_material`; **join interno** em `metodo` e `modulo`; `turma_modular*` |
| `v_demanda_projetada` | `estoque.ler` | política de `select` da tabela (§7.1) |
| `v_projecao_acuracia` | `estoque.ler`, `alunos.ler` | histórico + entregas realizadas |
| `fn_ritmo_aluno` | as de `v_ritmo_aluno` (é `invoker`) | número da ficha do aluno |
| `fn_ritmo_metodo_observado` | nenhuma (`security definer`, §9.1) | número de calibração |

Duas observações que mudam o que já estava escrito:

1. **`materiais.ler` aqui é de verdade.** O achado #12 do card 2.4 observou que
   `v_demanda_imediata_aluno` declarava `materiais.ler` sem ler tabela de material. Em
   `v_projecao_aluno` o `join` em `metodo` é **interno** e obrigatório (a chave do parâmetro é
   `ritmo_padrao_dias_' || metodo.codigo`): sem a permissão, a projeção vem **vazia**. Como a matriz
   do card 2.4 já dá `materiais.ler` a todos os perfis, isso não é problema novo — mas o conjunto
   declarado tem de dizer a verdade.
2. **A rota da tela 8 (Projeção de demanda) ganha `turmas.ler`.** O card 2.4 §8 registrou
   `materiais.ler + estoque.ler + alunos.ler`. Os quatro perfis já têm `turmas.ler`, então nada
   muda na prática hoje; o que muda é o dia em que alguém restringir a matriz.

E o achado #4 do card 2.4 — `fn_param_int`/`fn_param_txt` como `security definer` — **deixa de ser
alta e passa a bloqueante** para os cards 8.1 e 8.5: `v_projecao_aluno` chama `fn_param_int` quatro
vezes, e só a direção tem `parametros.ler` na matriz inicial. Como `invoker`, a função levanta
`PARAMETRO_AUSENTE` e a tela de projeção **erra para secretaria, pedagógico e monitor** — os três
perfis que o card 2.4 autorizou a ver a tela.

---

## 11. Ajustes que esta especificação exige

| # | Ajuste | Onde entra | Card | Bloqueante |
|---|---|---|---|---|
| 1 | `fn_param_int`/`fn_param_txt` como `security definer` com `search_path` fixo | infraestrutura | 3.4 | **sim** (era "alta" no card 2.4) |
| 2 | Nove parâmetros novos no seed (§3) | seed | 3.6 | **sim** — sem eles a projeção roda pelos defaults do código, não pelo que a escola decidiu |
| 3 | `TURMA_MODULAR_SEM_CRONOGRAMA` no `check` de `pendencia.tipo` | migração de pendências | 5.5 | **sim** — sem o tipo, o `insert` da rotina falha e vira `ROTINA_FALHOU` |
| 4 | Políticas de RLS de `demanda_projetada` por `fn_contexto_rotina()` (§7.1) | migração da projeção | 8.1 | **sim** — sem elas a rotina não escreve (`force` RLS) |
| 5 | Tabela `demanda_projetada_hist` + políticas (§7.2) | migração da projeção | 8.1 | não (mas sem ela o card 11.2 vira opinião) |
| 6 | Card 2.2 §2.2 diz que "cada `rt_*` itera unidades"; §11 diz que `rt_diaria` itera e chama as sub-rotinas. Adotado o §11: as `rt_*` operam na unidade do contexto | redação da especificação | 2.2 / 8.1 | não |
| 7 | Índice `demanda_projetada (unidade_id, mes)` — a leitura do pedido sugerido filtra por mês | migração da projeção | 8.1 | não |
| 8 | Conjunto declarado da tela 8 ganha `turmas.ler` (§10) | matriz/rota | 2.4 / 8.5 | não |
| 9 | `v_ritmo_aluno` e `fn_ritmo_aluno` expostos na aba Trilha da ficha do aluno | tela | 6.6 | não |
| 10 | Card 9.5 passa a ter procedimento objetivo: `fn_ritmo_metodo_observado` por método, `update` em `parametro` (§9.1) | nota do card | 9.5 | não |
| 11 | Card 11.2 passa a ter critério objetivo: `v_projecao_acuracia` + gatilhos de §9.2 | nota do card | 11.2 | não |

---

## 12. Mapa objeto → card

| Objeto | Card | Fase |
|---|---|---|
| Nove parâmetros de §3 no seed | 3.6 | 3 |
| `fn_param_int`/`fn_param_txt` como `security definer` | 3.4 | 3 |
| `TURMA_MODULAR_SEM_CRONOGRAMA` no `check` | 5.5 | 5 |
| `v_ritmo_aluno`, `fn_ritmo_aluno` | 8.1 | 8 |
| `v_projecao_aluno` | 8.1 | 8 |
| `demanda_projetada` (RLS), `demanda_projetada_hist`, `v_demanda_projetada` | 8.1 | 8 |
| `rt_projecao_demanda()` | 8.1 | 8 |
| Parcela projetada em `v_pedido_sugerido` + coluna na tela de Compras | 8.2 | 8 |
| Tela de Projeção (material × mês) e *drill-down* por `v_projecao_aluno` | 8.5 | 8 |
| Ritmo médio na aba Trilha da ficha | 6.6 | 6 |
| `fn_ritmo_metodo_observado` + calibração inicial | 9.5 | 9 |
| `v_projecao_acuracia` + recalibração | 11.2 | 11 |

---

## 13. O que fica em aberto

1. **Os valores iniciais dos `ritmo_padrao_dias_*` são palpite** (§3). Só o card 9.5, com o
   histórico migrado, os transforma em medida. Até lá, o degrau `MEDIA_METODO` é o mais frágil da
   cascata — e é justamente o que atende o aluno recém-matriculado, que é quem mais aparece na
   virada.
2. **Entrega em lote na migração pode inflar a base do ritmo.** O piso de 7 dias contém o caso
   grosseiro (várias entregas na mesma data), mas um histórico importado com datas aproximadas
   ainda produz ritmo aproximado. Conferir na fase 9 quantos alunos caem em `RITMO_ALUNO` com
   `intervalos_considerados = 1`: se for a maioria, o número a olhar é o do método, não o do aluno.
3. **A projeção ignora quem está em STANDBY** (§2.5). Se a escola passar a ter muitos retornos de
   STANDBY, vale medir o impacto pelo viés de §9.2 antes de mudar a regra — mudar sem medir troca
   um erro conhecido por um desconhecido.
4. **A capacidade de turma não limita a projeção.** Um aluno pode ser projetado para avançar mais
   rápido do que a grade permite. Modelar isso exigiria simular a ocupação futura dos blocos, o que
   é caro e provavelmente irrelevante no volume atual da escola. Se aparecer erro sistemático para
   mais no método Interativo, este é o primeiro suspeito.
5. **Turma Modular sem cronograma degrada para média de método** (§5.4). A pendência avisa; o que
   não existe é uma tela dizendo "estes 12 alunos estão projetados por média porque falta
   cronograma". Se a situação for comum, vale uma coluna de aviso na tela 8.5.
