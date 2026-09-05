-- =============================================================================
-- Card 8.1 — Projeção de demanda por período
--            (v_ritmo_aluno, fn_ritmo_aluno, v_projecao_aluno,
--             demanda_projetada, demanda_projetada_hist, v_demanda_projetada,
--             rt_projecao_demanda e o ponto de chamada em rt_diaria)
--
-- Fonte: docs/projecao-demanda.md §3 (parâmetros), §4.3 (ritmo), §5 (cascata),
--        §6 (v_projecao_aluno), §7.1 a §7.5 (materialização), §10 (permissões de
--        leitura declaradas) e §11 (ajustes 4, 5, 6 e 7, todos deste card);
--        docs/views-leitura.md §5.3 (o CONTRATO da tabela, escrito no card 2.3);
--        docs/regras-negocio-funcoes.md §11 (ordem das sub-rotinas de rt_diaria);
--        docs/estrategia-testes.md §5 (catálogo), §6.3 (paridade de linhas),
--        §6.4 (a aritmética da projeção) e §8 (rotinas).
--
-- Este card IMPLEMENTA o documento; não redecide nada dele.
--
-- ⚠️ NENHUMA LINHA DE DADO. Migração é o que o CI empurra para produção sozinho
--    no merge em `main` (decisão de 02/09/2026): aqui só entram tabela, view,
--    política, índice e função. As duas tabelas nascem VAZIAS em produção e
--    quem as preenche é a rotina, todo dia, na unidade do contexto.
--
-- ⚠️ ESTA MIGRAÇÃO PÕE UMA ROTINA NOVA PARA RODAR SOZINHA. `rt_diaria` é
--    reescrita com um quinto passo, e o `cron.schedule('gi_rotina_diaria', …)`
--    do card 5.5 continua o mesmo — quer dizer que, a partir do primeiro
--    03:10 depois da promoção, `rt_projecao_demanda` apaga e regrava
--    `demanda_projetada` em toda unidade ativa e pode abrir pendências
--    TURMA_MODULAR_SEM_CRONOGRAMA. É o tipo de mudança que continua agindo
--    depois de ninguém estar olhando, e por isso está dita aqui e no resumo do
--    card.
--
-- As três pré-condições que o §11 marcava como bloqueantes estão CUMPRIDAS e
-- foram conferidas contra o repositório antes de escrever uma linha:
--   • ajuste 1 — `fn_param_int`/`fn_param_txt` são `security definer`
--     (20260901163000_acesso_rls.sql §7). Sem isso `v_projecao_aluno` levantaria
--     PARAMETRO_AUSENTE para secretaria, pedagógico e monitor, que são
--     exatamente os perfis que o card 2.4 autorizou a ver a projeção;
--   • ajuste 2 — os nove parâmetros de §3 estão no seed
--     (20260901200000_seed_inicial_acesso.sql), ao lado do `projecao_horizonte_dias`
--     que já existia;
--   • ajuste 3 — `TURMA_MODULAR_SEM_CRONOGRAMA` está no `check` de
--     `pendencia.tipo` desde o card 7.2 (20260905070000_modular_regras.sql §7),
--     com o teste 071 §7 medindo e a contraprova ao lado.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. demanda_projetada — o contrato do card 2.3 §5.3, sem alteração de colunas
-- -----------------------------------------------------------------------------
-- Tabela COMUM com RLS, nunca `materialized view` (card 2.3 §2.2): matview não
-- respeita RLS — é um instantâneo com a visibilidade de quem deu o refresh — e
-- devolveria todas as unidades a qualquer leitor. E `refresh` não roda no
-- contexto de rotina do card 2.2 §2.2, que é a única credencial de escrita aqui.
--
-- A `regra` fica NO GRÃO, não escondida no detalhe: projeção sem proveniência
-- não é revisável, e a recalibração do card 11.2 depende de saber quanto veio de
-- cada degrau da cascata.
create table public.demanda_projetada (
  id uuid primary key default gen_random_uuid(),
  unidade_id   uuid not null references public.unidade(id),
  material_id  uuid not null references public.material(id),
  mes          date not null,
  quantidade   integer not null check (quantidade >= 0),
  regra        text not null
               check (regra in ('RITMO_ALUNO','PREVISAO_CURSO','MEDIA_METODO','MODULAR')),
  calculado_em timestamptz not null default now(),
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint demanda_projetada_mes_ck check (mes = date_trunc('month', mes)::date),
  constraint demanda_projetada_uk unique (unidade_id, material_id, mes, regra)
);

comment on table public.demanda_projetada is
  'Projeção de demanda materializada pela rotina diária (card 2.3 §5.3, algoritmo em docs/projecao-demanda.md). Uma linha por (material, mês, regra) da unidade. VAZIA em produção até a primeira execução de rt_diaria depois da promoção. NINGUÉM escreve aqui pela tela: as políticas de insert e delete exigem fn_contexto_rotina().';
comment on column public.demanda_projetada.mes is
  'Sempre o dia 1 do mês de competência — o `check` é o que impede a linha com grão diário que faria a janela de v_pedido_sugerido contar duas vezes. O grão continua mensal por decisão de docs/projecao-demanda.md §7.4: precisão diária seria falsa numa estimativa que carrega erro de semanas.';
comment on column public.demanda_projetada.regra is
  'Degrau da cascata que produziu a quantidade. NO GRÃO de propósito (card 2.3): a tela precisa dizer por qual regra cada número apareceu, e o critério de recalibração do card 11.2 compara por degrau.';
comment on column public.demanda_projetada.calculado_em is
  'Quando a rotina rodou. A tela do card 8.5 PRECISA exibi-la: número de projeção sem a data do cálculo é número sem validade — o total vem da tabela (rotina das 03:10) e o detalhe vem de v_projecao_aluno (de agora), e a única divergência legítima entre os dois é a hora do dia.';

-- -----------------------------------------------------------------------------
-- 2. demanda_projetada_hist — a foto mensal (docs/projecao-demanda.md §7.2)
-- -----------------------------------------------------------------------------
-- `demanda_projetada` é sobrescrita todo dia — projeção é "o que se sabe hoje",
-- decisão do card 2.3. Sem foto, em janeiro não há como responder "o que a gente
-- previu em novembro para dezembro?", e a recalibração do card 11.2 fica
-- reduzida a opinião. A foto é tirada UMA vez por mês, na primeira execução: é o
-- registro mais barato que transforma o 11.2 em medição.
create table public.demanda_projetada_hist (
  id uuid primary key default gen_random_uuid(),
  unidade_id  uuid not null references public.unidade(id),
  material_id uuid not null references public.material(id),
  mes         date not null,
  quantidade  integer not null check (quantidade >= 0),
  regra       text not null
              check (regra in ('RITMO_ALUNO','PREVISAO_CURSO','MEDIA_METODO','MODULAR')),
  snapshot_em date not null,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint demanda_projetada_hist_mes_ck  check (mes = date_trunc('month', mes)::date),
  constraint demanda_projetada_hist_snap_ck check (snapshot_em = date_trunc('month', snapshot_em)::date),
  constraint demanda_projetada_hist_uk
    unique (unidade_id, snapshot_em, material_id, mes, regra)
);

comment on table public.demanda_projetada_hist is
  'Foto mensal de demanda_projetada (docs/projecao-demanda.md §7.2), tirada na primeira execução da rotina em cada mês. Histórico IMUTÁVEL: sem política de update nem de delete, como aluno_status_hist e pc_credencial_acesso. É o insumo de v_projecao_acuracia (card 11.2).';
comment on column public.demanda_projetada_hist.snapshot_em is
  'Primeiro dia do mês em que a foto foi tirada. Com `mes` ao lado, é o par que responde "o que se previa em X para Y" — e o recorte que interessa ao card 11.2 é snapshot_em = mes − 1 mês, que é o tempo de decidir e receber um pedido de compra.';

-- -----------------------------------------------------------------------------
-- 3. Índices — ajuste 7 do §11 e os lados de FK que a unique não cobre
-- -----------------------------------------------------------------------------
-- A leitura do pedido sugerido (card 8.2) filtra por unidade e por MÊS; a unique
-- começa por `unidade_id`, mas tem `material_id` antes de `mes`, então não serve
-- a esse filtro. `material_id` sozinho não é primeira coluna de índice nenhum.
create index demanda_projetada_mes_ix      on public.demanda_projetada (unidade_id, mes);
create index demanda_projetada_material_ix on public.demanda_projetada (material_id);
create index demanda_projetada_hist_material_ix on public.demanda_projetada_hist (material_id);

-- -----------------------------------------------------------------------------
-- 4. Triggers de auditoria (C3 do card 2.8)
-- -----------------------------------------------------------------------------
create trigger tg_auditoria_demanda_projetada
  before insert or update on public.demanda_projetada
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_demanda_projetada_hist
  before insert or update on public.demanda_projetada_hist
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 5. RLS — docs/projecao-demanda.md §7.1, e ela NÃO é o padrão de quatro
-- -----------------------------------------------------------------------------
-- Nenhum usuário escreve nestas duas tabelas. `fn_contexto_rotina()` é a única
-- credencial de escrita, e sem política nenhuma nem a rotina escreveria — `force
-- row level security` alcança o dono da tabela. Com uma política baseada em
-- permissão de domínio, a tela de Compras poderia gravar projeção via PostgREST.
--
-- Sem `update` em nenhuma das duas: a rotina APAGA e regrava (contrato do card
-- 2.3), e a foto mensal é imutável por construção. Sem `delete` na hist pelo
-- mesmo motivo de aluno_status_hist — a imutabilidade AQUI é a ausência.
--
-- Risco residual já aceito pelo card 2.2: quem conseguisse
-- `set_config('app.rotina','on',…)` teria escrita aqui. Só há como fazer isso com
-- conexão SQL direta — as GUCs são escritas dentro das `rt_*`, que não têm
-- `grant execute` para anon/authenticated (C9), e o PostgREST não expõe função
-- sem grant. A superfície nova que estas tabelas criam é zero: quem chega lá já
-- contornou `tem_permissao`.
alter table public.demanda_projetada      enable row level security;
alter table public.demanda_projetada      force  row level security;
alter table public.demanda_projetada_hist enable row level security;
alter table public.demanda_projetada_hist force  row level security;

create policy demanda_projetada_sel on public.demanda_projetada for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('estoque.ler'));

create policy demanda_projetada_ins on public.demanda_projetada for insert
  with check (unidade_id = public.fn_unidade_atual() and public.fn_contexto_rotina());

create policy demanda_projetada_del on public.demanda_projetada for delete
  using (unidade_id = public.fn_unidade_atual() and public.fn_contexto_rotina());

create policy demanda_projetada_hist_sel on public.demanda_projetada_hist for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('estoque.ler'));

create policy demanda_projetada_hist_ins on public.demanda_projetada_hist for insert
  with check (unidade_id = public.fn_unidade_atual() and public.fn_contexto_rotina());

-- -----------------------------------------------------------------------------
-- 6. v_ritmo_aluno — docs/projecao-demanda.md §4.3
-- -----------------------------------------------------------------------------
-- A fonte é `aluno_material.data_entrega` onde `entregue`, NÃO `movimento_estoque`:
-- o estorno (card 2.2 §6.3) desmarca a trilha e zera `data_entrega`, então a
-- trilha já está limpa; o movimento, não — ler de lá exigiria casar cada SAIDA
-- com o seu ESTORNO para não contar como ritmo uma entrega desfeita.
--
-- Os dois filtros atacam falhas OPOSTAS, e é por isso que são dois:
--   • piso de 7 dias — duas apostilas entregues no mesmo dia (acerto de atraso,
--     ou a carga da migração do card 9.1, que traz várias entregas com a mesma
--     data) dariam intervalo 0 ou 1 e derrubariam o ritmo para perto de zero: o
--     aluno passaria a "precisar" da trilha inteira dentro do horizonte;
--   • teto de 120 dias — quem ficou quatro meses parado e voltou tem um
--     intervalo de 130 dias que, sozinho, empurraria o próximo livro para depois
--     do horizonte: ele sairia da compra justamente por ter voltado.
--
-- Sem nenhum intervalo sobrevivente o ritmo é NULO, e nulo é o que faz o aluno
-- descer um degrau da cascata — não zero, que seria um ritmo instantâneo.
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
       max(e.data_entrega)       as ultima_entrega,
       count(*)::integer         as entregas,
       coalesce(m.intervalos, 0) as intervalos_considerados,
       m.ritmo_dias              as ritmo_dias
  from entrega e
  left join media m on m.aluno_id = e.aluno_id
 group by e.unidade_id, e.aluno_id, m.intervalos, m.ritmo_dias;

comment on view public.v_ritmo_aluno is
  'Ritmo médio do aluno em dias entre entregas (docs/projecao-demanda.md §4.3): média dos até (ritmo_janela_entregas − 1) intervalos mais recentes, descartados os fora de [ritmo_intervalo_min_dias, ritmo_intervalo_max_dias]. Leitura exige alunos.ler — sem ela a RLS esconde aluno_material e todo ritmo vem nulo, sem erro nenhum.';
comment on column public.v_ritmo_aluno.ritmo_dias is
  'NULO quando nenhum intervalo sobrevive aos dois filtros. Nulo é o que faz o aluno descer para PREVISAO_CURSO ou MEDIA_METODO na cascata — zero seria um ritmo instantâneo e traria a trilha inteira para o mês corrente.';

revoke all   on public.v_ritmo_aluno from public;
revoke all   on public.v_ritmo_aluno from anon;
grant select on public.v_ritmo_aluno to authenticated;

-- Uma linha lendo a view, e não uma segunda implementação: é o que a aba Trilha
-- da ficha do aluno (card 6.6) chama para exibir "ritmo médio: 28 dias", e é o
-- que garante que o número da ficha é o MESMO número que entrou na compra.
-- `invoker` de propósito: quem não pode ler o aluno recebe nulo, não o ritmo.
create or replace function public.fn_ritmo_aluno(p_aluno_id uuid)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select r.ritmo_dias from public.v_ritmo_aluno r where r.aluno_id = p_aluno_id;
$$;

comment on function public.fn_ritmo_aluno(uuid) is
  'Ritmo médio do aluno, em dias (docs/projecao-demanda.md §4.3). Uma linha lendo v_ritmo_aluno: o número da ficha do aluno é o mesmo que entrou na projeção. Invoker — exige alunos.ler, como a view.';

revoke execute on function public.fn_ritmo_aluno(uuid) from public;
revoke execute on function public.fn_ritmo_aluno(uuid) from anon;
grant  execute on function public.fn_ritmo_aluno(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. v_projecao_aluno — docs/projecao-demanda.md §6
-- -----------------------------------------------------------------------------
-- Uma linha por (aluno, material, data prevista, regra), SEM recorte de
-- horizonte: quem recorta é a rotina (§7.3) e a tela (card 8.5). Assim, mudar
-- `projecao_horizonte_dias` não exige tocar na view.
--
-- Duas linhas desta view carregam quase todo o valor dela:
--
--   • `where pe.k >= 2` é a disjunção do §2.4. O primeiro item pendente JÁ é
--     v_demanda_imediata, e a fórmula `imediata + projetada + mínimo − estoque −
--     pedido pendente` só está certa com as duas parcelas disjuntas. Sem esta
--     linha, todo aluno ativo pesa DUAS vezes no pedido sugerido — e o número
--     continua parecendo plausível ao lado dos outros.
--   • `ar.regra <> 'MODULAR' or mo.data_prevista is not null` cobre o material
--     que a turma não tem no cronograma (aluno com item manual fora da grade do
--     curso): ele não é projetado, em vez de receber uma data inventada.
--
-- A cascata escolhe UM degrau por ALUNO, não por item (§2.2): se um mesmo aluno
-- pudesse ter o 2º livro por RITMO_ALUNO e o 5º por MEDIA_METODO, as datas
-- sairiam de duas réguas diferentes na mesma sequência e a soma por material
-- deixaria de ter significado.
--
-- ⚠️ `k` e `pendentes` saem de `row_number()`/`count(*)`, que devolvem BIGINT, e
--    `date + bigint` não existe no Postgres — o cast para integer está nas duas
--    colunas, na origem. Sem ele a view nem se cria.
create view public.v_projecao_aluno with (security_invoker = on) as
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
       pe.pendentes
  from pendente pe
  cross join p
  join aluno_regra   ar on ar.aluno_id = pe.aluno_id
  join ritmo_efetivo re on re.aluno_id = pe.aluno_id
  left join modular  mo on mo.turma_id = ar.turma_id and mo.material_id = pe.material_id
 where pe.k >= 2
   and (ar.regra <> 'MODULAR' or mo.data_prevista is not null);

comment on view public.v_projecao_aluno is
  'Detalhe da projeção: uma linha por aluno × material × data prevista × regra, a PARTIR do segundo item pendente da trilha (docs/projecao-demanda.md §6). É a mesma expressão que rt_projecao_demanda agrega para produzir o total — o drill-down da tela 8.5 lê daqui, e não de uma segunda implementação. Leitura exige alunos.ler, materiais.ler e turmas.ler: o join em metodo é INTERNO e obrigatório (a chave do parâmetro é ritmo_padrao_dias_<CODIGO>), então sem materiais.ler a projeção vem VAZIA, não errada.';
comment on column public.v_projecao_aluno.k is
  'Posição do item na trilha pendente do aluno. Começa em 2 nesta view: k = 1 é o próximo livro, que já é v_demanda_imediata. É a disjunção de que a fórmula do pedido sugerido depende — sem ela todo aluno ativo pesa duas vezes na compra.';
comment on column public.v_projecao_aluno.regra is
  'Degrau da cascata, escolhido UMA vez por aluno (nunca por item): MODULAR (turma com cronograma datado) → RITMO_ALUNO (método ≠ MODULAR e ritmo mensurável) → PREVISAO_CURSO (prev_conclusao_curso informada e FUTURA) → MEDIA_METODO (o degrau que não pode falhar). Previsão vencida não serve de base: passo negativo despejaria a trilha inteira no mês corrente, e a pendência PREVISAO_VENCIDA do card 8.4 é quem pede que uma pessoa a corrija.';

revoke all   on public.v_projecao_aluno from public;
revoke all   on public.v_projecao_aluno from anon;
grant select on public.v_projecao_aluno to authenticated;

-- -----------------------------------------------------------------------------
-- 8. v_demanda_projetada — docs/projecao-demanda.md §7.5
-- -----------------------------------------------------------------------------
-- Existe para que a tela e v_pedido_sugerido NUNCA leiam a tabela direto (card
-- 2.3 §5.3): o dia em que a projeção deixar de ser materializada, muda-se o
-- corpo da view e nada acima dela.
create view public.v_demanda_projetada with (security_invoker = on) as
select dp.unidade_id,
       dp.material_id,
       dp.mes,
       dp.quantidade,
       dp.regra,
       dp.calculado_em
  from public.demanda_projetada dp;

comment on view public.v_demanda_projetada is
  'Contrato de leitura da projeção (card 2.3 §5.3): material × mês × regra, com calculado_em. Leitura exige estoque.ler, que é o que a política de select da tabela pede. O card 8.2 soma `quantidade` sobre TODAS as regras e todos os meses da janela para preencher a parcela projetada de v_pedido_sugerido.';

revoke all   on public.v_demanda_projetada from public;
revoke all   on public.v_demanda_projetada from anon;
grant select on public.v_demanda_projetada to authenticated;

-- -----------------------------------------------------------------------------
-- 9. rt_projecao_demanda — docs/projecao-demanda.md §7.3
-- -----------------------------------------------------------------------------
-- Opera na unidade do CONTEXTO, setado por rt_diaria antes da chamada (card 2.2
-- §11, ajuste 6 do §11 da projeção: entre "cada rt_* itera unidades" do §2.2 e
-- "rt_diaria itera e chama as sub-rotinas" do §11, vale o §11). Ela não itera
-- unidades por conta própria — e falha FECHADO quando não há unidade, como as
-- outras rt_*: rotina que trata unidade nula como "não faz nada" é um contorno
-- permanente escrito para acomodar quem a chamou errado.
--
-- `delete` + `insert` na mesma transação NÃO abre janela de tabela vazia: pelo
-- MVCC, quem consultar durante a execução continua vendo o conjunto anterior até
-- o commit.
--
-- A rotina grava SÓ a janela [mês corrente, mês de hoje + horizonte]. Guardar
-- mês fora da janela seria guardar linha que nenhuma tela lê e que envelhece na
-- próxima execução. O `where` de v_pedido_sugerido (card 8.2) repete o recorte
-- de propósito: se alguém reduzir o horizonte, a view já fica certa antes de a
-- rotina rodar de novo.
create or replace function public.rt_projecao_demanda()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_mes_ini date;
  v_mes_fim date;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'rt_projecao_demanda: sem unidade no contexto. Chamar de rt_diaria, ou entrar no contexto de rotina antes (card 2.2 §2.2).';
  end if;

  v_mes_ini := date_trunc('month', public.fn_hoje())::date;
  v_mes_fim := date_trunc('month', public.fn_hoje()
                          + public.fn_param_int('projecao_horizonte_dias', 60))::date;

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

  -- Foto mensal (§7.2): só na primeira execução do mês. Idempotente por
  -- construção — a segunda execução do mesmo mês encontra o snapshot e não faz
  -- nada, e não é a unique quem segura isso (ela seguraria com erro, dentro de
  -- uma rotina cujo erro vira ROTINA_FALHOU e apaga a projeção do dia).
  if not exists (select 1 from public.demanda_projetada_hist
                  where unidade_id = v_unidade and snapshot_em = v_mes_ini) then
    insert into public.demanda_projetada_hist
           (unidade_id, material_id, mes, quantidade, regra, snapshot_em)
    select unidade_id, material_id, mes, quantidade, regra, v_mes_ini
      from public.demanda_projetada
     where unidade_id = v_unidade;
  end if;

  -- Turma Modular ativa SEM cronograma datado degrada a projeção em silêncio
  -- (§5.4): os alunos dela caem para a média do método sem que nada avise. Abre
  -- E fecha, como rt_pendencias_diaria faz com as de tempo — pendência que só
  -- abre vira lista de coisas que já deixaram de ser verdade.
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
end $$;

comment on function public.rt_projecao_demanda() is
  'Rotina diária da projeção (docs/projecao-demanda.md §7.3): apaga e regrava demanda_projetada da unidade do contexto dentro da janela [mês corrente, mês de hoje + projecao_horizonte_dias], tira a foto mensal na primeira execução do mês e abre/fecha TURMA_MODULAR_SEM_CRONOGRAMA. Chamada por rt_diaria; sem unidade no contexto, falha fechado.';

revoke execute on function public.rt_projecao_demanda() from public;
revoke execute on function public.rt_projecao_demanda() from anon;
revoke execute on function public.rt_projecao_demanda() from authenticated;

-- -----------------------------------------------------------------------------
-- 10. rt_diaria — o quinto passo, e o portão do teste 090 desarmado
-- -----------------------------------------------------------------------------
-- Reescrita inteira (não há como acrescentar passo a um corpo), preservando o
-- que os cards 5.5 e 5.4 decidiram: cada rt_* no seu `begin … exception when
-- others`, a falha virando pendência ROTINA_FALHOU (ALTA) em vez de log — o log
-- do Supabase no free tier tem retenção de UM DIA (card 3.12 (g)), e uma rotina
-- que falha às 03:10 e some do log às 03:10 do dia seguinte falha em silêncio
-- para sempre, com o sintoma sendo uma central VAZIA.
--
-- A ORDEM é a de docs/regras-negocio-funcoes.md §11, e a projeção é a ÚLTIMA de
-- propósito: ela lê a trilha e as turmas depois de rt_pcs_normaliza/rt_capacidades
-- terem posto capacidade e status em dia, e depois de rt_pendencias_diaria ter
-- feito a varredura de tempo. Rodar a projeção antes não a deixaria errada, mas
-- a faria fotografar um estado que a própria rotina ainda ia mudar.
--
-- É este o portão que o card 5.4 armou no teste 090 e que ESTE card satisfaz:
-- toda `rt_*` do projeto é chamada aqui. Com rt_projecao_demanda, a lista fecha.
create or replace function public.rt_diaria()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  u record;
begin
  for u in select id from public.unidade where ativo order by id
  loop
    -- `is_local => true`: o contexto morre no `commit` mesmo se a rotina falhar
    -- no meio, e não vaza de uma unidade para a seguinte (card 2.2 §2.2).
    perform set_config('app.rotina', 'on', true);
    perform set_config('app.rotina_unidade', u.id::text, true);

    begin
      perform public.rt_pcs_normaliza();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_pcs_normaliza');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_pcs_normaliza',
        format('A rotina rt_pcs_normaliza falhou: %s (SQLSTATE %s). O status dos PCs desta unidade pode estar desatualizado.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

    begin
      perform public.rt_capacidades();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_capacidades');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_capacidades',
        format('A rotina rt_capacidades falhou: %s (SQLSTATE %s). Os blocos acima da capacidade desta unidade podem não estar na central.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

    begin
      perform public.rt_pendencias_diaria();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_pendencias_diaria');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_pendencias_diaria',
        format('A rotina rt_pendencias_diaria falhou: %s (SQLSTATE %s). A lista de pendências desta unidade pode estar desatualizada.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

    begin
      perform public.rt_rep_avaliar();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_rep_avaliar');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_rep_avaliar',
        format('A rotina rt_rep_avaliar falhou: %s (SQLSTATE %s). As sugestões de virada REP desta unidade podem estar desatualizadas.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

    begin
      perform public.rt_projecao_demanda();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_projecao_demanda');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_projecao_demanda',
        format('A rotina rt_projecao_demanda falhou: %s (SQLSTATE %s). A projeção de demanda desta unidade está com os números da última execução bem-sucedida.',
               sqlerrm, sqlstate),
        'ALTA');
    end;
  end loop;

  perform set_config('app.rotina', '', true);
  perform set_config('app.rotina_unidade', '', true);
end $$;

comment on function public.rt_diaria() is
  'Rotina diária única (card 2.2 §11): itera as unidades ativas, entra no contexto de rotina em cada uma e chama, nesta ordem, rt_pcs_normaliza, rt_capacidades, rt_pendencias_diaria, rt_rep_avaliar e rt_projecao_demanda — cada uma isolada num bloco de exceção que registra a falha como pendência ROTINA_FALHOU (ALTA) e segue. Com o card 8.1 a lista fecha: toda rt_* do projeto é chamada aqui, e o portão do teste 090 reprova quem criar a próxima fora daqui.';

revoke execute on function public.rt_diaria() from public;
revoke execute on function public.rt_diaria() from anon;
revoke execute on function public.rt_diaria() from authenticated;
