-- =============================================================================
-- Views da tela 8 — Projeção de demanda (card 8.5)
-- docs/wireframes.md §11 · docs/views-leitura.md §5.3 e §12.1 · docs/projecao-demanda.md §6
--
-- A tela 8 é a terceira que nasce sem objeto de banco previsto e precisa de
-- views próprias — o mesmo caminho de `v_aluno_trilha` (6.6), `v_material_
-- movimento` (6.7), `v_pedido_compra`/`v_pedido_item` (6.8) e das três do 7.3.
-- `views-leitura.md` §12.1 já é a regra: **view de tela pertence ao card da
-- tela**, e o cuidado do §3 continua valendo.
--
-- O que a tela precisa e o contrato do card 2.3 §5.3 NÃO dá:
--
--   • a grade é `Código │ Material │ set │ out │ nov │ Σ`, e `v_demanda_
--     projetada` tem `material_id` e mais nada do material — sem código, nome,
--     categoria e método não há linha para desenhar nem filtro para oferecer;
--   • o detalhe é `Aluno │ regra │ prevista │ ritmo`, e `v_projecao_aluno` tem
--     `aluno_id` e não tem o ritmo.
--
-- ⚠️ NENHUMA DAS DUAS REFAZ CONTA NENHUMA. As views abaixo são junção de
--    rótulo sobre as expressões que já existem: a grade lê `v_demanda_
--    projetada` (o que a rotina gravou às 03:10) e o detalhe lê
--    `v_projecao_aluno` (a MESMA expressão que `rt_projecao_demanda` agrega).
--    É o que o card 2.3 §5.1 fixou como desenho — "detalhe primeiro, agregado
--    depois" —, e é o que impede o total e o drill-down de divergirem por
--    implementação em vez de por hora do dia.
--
-- Três objetos, nesta ordem:
--   1. `v_projecao_aluno` ganha `ritmo_dias` (create or replace, coluna no fim)
--   2. `v_projecao_material_mes` — a grade
--   3. `v_projecao_aluno_detalhe` — o drill-down
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. v_projecao_aluno — mais UMA coluna, `ritmo_dias`
-- -----------------------------------------------------------------------------
-- O wireframe §11 põe o ritmo na última coluna do detalhe, e ele é o que explica
-- a data: "12/10, ritmo de 23 dias" é revisável, "12/10" não é.
--
-- ⚠️ Ele sai da CTE `ritmo_efetivo`, que JÁ o calcula para produzir
--    `data_prevista` — e é por isso que a coluna nasce aqui dentro, e não numa
--    view de fora. Recompor o ritmo do lado de fora (v_ritmo_aluno para
--    RITMO_ALUNO, `fn_param_int('ritmo_padrao_dias_' || codigo)` para
--    MEDIA_METODO, mais o fator de aceleração) seria a SEGUNDA implementação da
--    mesma conta, que o card 2.3 §4.1 proíbe: no dia em que o fator de
--    aceleração mudasse, a tela mostraria um ritmo que não gerou aquela data.
--
-- ⚠️ NULO em PREVISAO_CURSO e em MODULAR, e isso é correto: nesses dois degraus
--    a data não vem de ritmo nenhum — vem da previsão declarada por uma pessoa
--    e do cronograma da turma. Preencher com o ritmo do método daria à tela um
--    número que não participou da conta.
--
-- `create or replace view` acrescenta coluna NO FIM sem derrubar dependente:
-- `rt_projecao_demanda` lê colunas nomeadas e não vê diferença. O corpo abaixo é
-- cópia do `20260905150000_projecao_demanda.sql`; a única mudança está na última
-- linha da lista de saída.
create or replace view public.v_projecao_aluno with (security_invoker = on) as
with p as (
  select public.fn_hoje()                                    as hoje,
         public.fn_param_int('ritmo_padrao_dias_PADRAO', 30)  as ritmo_padrao,
         public.fn_param_int('projecao_acelerar_pct', 50)     as acelerar_pct,
         public.fn_param_int('ritmo_padrao_dias_MODULAR', 45) as passo_modular_padrao
),
-- itens pendentes dos alunos ativos, numerados: k = 1 é o próximo livro, que é
-- demanda IMEDIATA e não entra aqui
pendente as (
  select am.unidade_id,
         am.aluno_id,
         am.material_id,
         a.metodo_id,
         a.status,
         a.data_inicio,
         a.prev_conclusao_curso,
         (row_number() over (partition by am.aluno_id order by am.ordem))::integer as k,
         (count(*)    over (partition by am.aluno_id))::integer                    as pendentes
    from public.aluno_material am
    join public.aluno a on a.id = am.aluno_id
   where not am.entregue
     and a.status in ('ATIVO','ACELERAR')
),
-- turma Modular ativa do aluno (o índice único do card 7.1 garante no máximo uma)
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
-- cronograma com a data conhecida de início de cada módulo. A ORDEM vem de
-- `modulo.ordem`, nunca da tabela do cronograma (card 2.2 §9)
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
-- gaps-and-islands: cada módulo sem data herda a última conhecida e conta os
-- saltos até ela. É a extrapolação do §5.4, e ela existe porque o cronograma
-- real vem datado nos primeiros módulos e VAZIO nos últimos: sem ela, ou se
-- perde a demanda dos livros seguintes em silêncio — a pior das opções —, ou o
-- aluno inteiro cai de degrau por causa de um módulo sem data, trocando o
-- cronograma real por uma média de método.
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
   where i.grupo > 0
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
-- degrau escolhido, UMA vez por aluno (§2.2). O aluno Modular não usa
-- RITMO_ALUNO: no Modular a turma avança em conjunto, então a data em que ele
-- recebe o próximo livro é decidida pelo cronograma, não pela velocidade dele —
-- o histórico individual de um aluno modular mede o passado da TURMA.
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
-- ritmo efetivo dos degraus que trabalham com ritmo. O fator de aceleração vale
-- SÓ em MEDIA_METODO: em RITMO_ALUNO a aceleração já está medida (o aluno em
-- dois blocos entrega mais rápido, e a média mostra isso), em PREVISAO_CURSO a
-- data foi declarada por uma pessoa que sabe se o aluno acelerou, e em MODULAR
-- quem manda é a turma. Aplicá-lo nos quatro degraus contaria a aceleração duas
-- vezes.
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
         -- o `hoje − 400` contém data de entrega absurda vinda da migração; o
         -- limite que IMPORTA (`hoje − ritmo`) está aplicado na projeção, onde o
         -- ritmo já é conhecido. Sem ele, o aluno atrasado teria os próximos
         -- livros com data no passado, todos despejados no mês corrente — a
         -- projeção transformaria atraso em pico de compra.
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
       pe.pendentes,
       -- A coluna nova do card 8.5. Sai da MESMA CTE que produziu a data acima.
       re.ritmo as ritmo_dias
  from pendente pe
  cross join p
  join aluno_regra   ar on ar.aluno_id = pe.aluno_id
  join ritmo_efetivo re on re.aluno_id = pe.aluno_id
  left join modular  mo on mo.turma_id = ar.turma_id and mo.material_id = pe.material_id
 where pe.k >= 2
   and (ar.regra <> 'MODULAR' or mo.data_prevista is not null);

comment on column public.v_projecao_aluno.ritmo_dias is
  'Ritmo EFETIVO que gerou data_prevista, em dias (card 8.5): o do próprio aluno em RITMO_ALUNO, o do método — já com o fator de aceleração quando o aluno é ACELERAR — em MEDIA_METODO, e NULO em PREVISAO_CURSO e MODULAR, onde a data não vem de ritmo nenhum. Sai da CTE ritmo_efetivo, a mesma que produziu a data: recompô-lo fora da view seria a segunda implementação da conta que o card 2.3 §4.1 proíbe.';

-- -----------------------------------------------------------------------------
-- 2. v_projecao_material_mes — a grade da tela (wireframe §11)
-- -----------------------------------------------------------------------------
-- Grão idêntico ao de `v_demanda_projetada`: uma linha por (material, mês,
-- regra). Quem pivota material × mês é a tela, e de propósito — o número de
-- meses depende de `projecao_horizonte_dias`, e uma view com colunas fixas
-- `mes_1..mes_3` quebraria no dia em que o horizonte mudasse.
--
-- ⚠️ A `regra` FICA NO GRÃO, e não é agregada aqui. É o que o card 2.3 §5.3
--    decidiu ("projeção sem proveniência não é revisável") e o que faz o filtro
--    por regra do wireframe §11 existir: agregar aqui devolveria a soma e
--    perderia de qual degrau ela veio.
--
-- ⚠️ `join` INTERNO em `material`, e a consequência é a do card 2.3 §3.4: sem
--    `materiais.ler` a grade vem VAZIA, não errada. É aceitável porque a rota da
--    tela exige `materiais.ler` (docs/permissoes-matriz.md §6, linha 8) — e é a
--    mesma redução que `v_projecao_aluno` já tem pelo join em `metodo`.
--
-- ⚠️ NÃO filtra `material.ativo`. Material aposentado que ainda está na trilha
--    de um aluno ativo VAI ser preciso, e escondê-lo aqui esconderia a compra
--    exatamente do caso mais fácil de esquecer. Quem filtra ativo é o pedido
--    sugerido (§2.3), que fala de compra; esta tela fala de demanda.
create view public.v_projecao_material_mes with (security_invoker = on) as
select dp.unidade_id,
       dp.material_id,
       m.metodo_id,
       m.codigo,
       m.nome,
       m.categoria,
       dp.mes,
       dp.quantidade,
       dp.regra,
       dp.calculado_em
  from public.v_demanda_projetada dp
  join public.material m on m.id = dp.material_id;

comment on view public.v_projecao_material_mes is
  'Grade da tela 8 (docs/wireframes.md §11): v_demanda_projetada com o rótulo do material ao lado — código, nome, categoria e método, que são o que a linha mostra e o que os filtros oferecem. Mesmo grão da view de baixo (material × mês × regra); o pivô material × mês é da tela, porque o número de meses depende de projecao_horizonte_dias. Leitura exige estoque.ler (política de demanda_projetada) e materiais.ler (join interno).';

revoke all   on public.v_projecao_material_mes from public;
revoke all   on public.v_projecao_material_mes from anon;
grant select on public.v_projecao_material_mes to authenticated;

-- -----------------------------------------------------------------------------
-- 3. v_projecao_aluno_detalhe — o drill-down (wireframe §11)
-- -----------------------------------------------------------------------------
-- "Quais alunos geram esta quantidade, e por qual regra." Lê `v_projecao_aluno`
-- AO VIVO — não a tabela materializada —, e é isso que o wireframe §11 manda:
-- o total é da rotina da madrugada, o detalhe é de agora, e os dois podem
-- divergir ao longo do dia. Divergir por HORA é esperado e a tela avisa;
-- divergir por implementação seria defeito, e é o que esta view evita ao ler a
-- mesma expressão que a rotina agrega.
--
-- ⚠️ `mes` é `date_trunc('month', data_prevista)::date`, LETRA POR LETRA a
--    expressão do `group by` de `rt_projecao_demanda`. É ela que faz o
--    drill-down de uma célula (material × mês) devolver exatamente os alunos que
--    somaram naquela célula. Escrever aqui um recorte "entre o dia 1 e o último
--    dia do mês" daria o mesmo resultado hoje e um resultado diferente no dia em
--    que a rotina mudasse de grão.
--
-- ⚠️ Dois `join` INTERNOS, `aluno` e `material`, e os dois já estão no conjunto
--    da rota (alunos.ler, materiais.ler). O de `aluno` é o mesmo desenho de
--    `v_turma_modular_aluno` (card 7.3): a lista de nomes exige a permissão de
--    quem tem nome.
create view public.v_projecao_aluno_detalhe with (security_invoker = on) as
select pa.unidade_id,
       pa.aluno_id,
       a.nome       as aluno_nome,
       a.codigo_sgf,
       a.status     as aluno_status,
       pa.material_id,
       m.metodo_id,
       m.codigo,
       m.nome       as material_nome,
       date_trunc('month', pa.data_prevista)::date as mes,
       pa.data_prevista,
       pa.regra,
       pa.ritmo_dias,
       pa.k,
       pa.pendentes
  from public.v_projecao_aluno pa
  join public.aluno a    on a.id = pa.aluno_id
  join public.material m on m.id = pa.material_id;

comment on view public.v_projecao_aluno_detalhe is
  'Drill-down da tela 8 (docs/wireframes.md §11): v_projecao_aluno com nome do aluno, código SGF, status e rótulo do material, mais `mes` calculado com a MESMA expressão do group by de rt_projecao_demanda. Lê AO VIVO, então o detalhe é de agora e o total é da rotina da madrugada — a tela diz isso em texto. Leitura exige alunos.ler, materiais.ler e turmas.ler, os três do conjunto da rota.';

revoke all   on public.v_projecao_aluno_detalhe from public;
revoke all   on public.v_projecao_aluno_detalhe from anon;
grant select on public.v_projecao_aluno_detalhe to authenticated;
