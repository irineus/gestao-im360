-- =============================================================================
-- v_projecao_acuracia — previsto × realizado (card 11.1,5; spec: projecao-demanda §9.3)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Os meses são RELATIVOS ao mês corrente: M = quatro meses antes dele, sempre
-- fechado, e M+1 também. Esta suíte escreve as fotos mensais à mão (como
-- dono, na transação — a tabela só aceita a rotina), FIXA as datas das
-- entregas que mede e confere a view linha a linha:
--
--   foto M-1 → mês M:    Informática Essencial 1 = 1 (RITMO_ALUNO)
--                                                + 2 (MEDIA_METODO)
--                        Informática Avançada 1  = 2 (PREVISAO_CURSO)
--   foto M-1 → mês M+1:  Informática Avançada 1  = 4  (dois meses antes:
--                                                       NÃO conta)
--   foto M   → mês M:    Informática Essencial 2 = 5  (a foto do próprio
--                                                       mês: NÃO conta)
--   entregas M: IE1 ×1, IE2 ×1, English Book 1 ×1 · M+1: IE1 ×1
--   entregas M-2: IE1, IA2 — sem foto de M-3: mês NÃO medido
--
-- ⚠️ Card 9.2,80 (01/10/2026): esta suíte dizia "a fixture tem entregas com
-- DATA FIXA" e comparava contra '2026-06' e '2026-07' literais. As datas da
-- fixture são `fn_hoje() - N dias` (seed.sql §8.4) — escrita em 24/09, a
-- entrega de 90 dias caía em junho; no dia 1º/10 ela passou para julho, e o
-- `banco (pgTAP)` ficou vermelho em todo PR sem nada ter mudado. É a lição
-- do card 8.7: mês e ano nunca viram literal em teste.
--
-- Tudo na pele do perfil (tests.autenticar), nunca em contexto de rotina.
-- =============================================================================

begin;
select plan(12);

-- O mês de referência M, e os vizinhos por deslocamento.
create function pg_temp.m(p_desloc integer default 0) returns date
language sql stable as $$
  select (date_trunc('month', public.fn_hoje()) - interval '4 months'
          + p_desloc * interval '1 month')::date
$$;
create function pg_temp.ym(p_desloc integer default 0) returns text
language sql stable as $$ select to_char(pg_temp.m(p_desloc), 'YYYY-MM') $$;

create temporary table t_mat as
  select u.codigo as unidade, m.nome, m.id
    from public.material m join public.unidade u on u.id = m.unidade_id;
grant select on t_mat to authenticated;

create function pg_temp.mat(p_unidade text, p_nome text) returns uuid
language sql stable as $$ select id from t_mat where unidade = p_unidade and nome = p_nome $$;

-- ---------------------------------------------------------------------------
-- As entregas medidas, com data FIXADA em relação a M (nas duas escolas). O
-- resto do que a fixture entregou vai para um mês sem foto nenhuma (M-12),
-- que a view não mede. Triggers de usuário desligados em volta do ajuste,
-- como no card 9.2,7: a guarda de colunas e a auditoria não são o que se mede
-- aqui, e tudo volta no rollback.
-- ---------------------------------------------------------------------------
alter table public.aluno_material disable trigger user;

update public.aluno_material
   set data_entrega = pg_temp.m(-12) + 1
 where entregue;

update public.aluno_material am
   set data_entrega = s.data
  from (values
          ('Diego Alves',       'INTERATIVO', '01', pg_temp.m(0)  + 14),
          ('Ana Paula Ribeiro', 'INTERATIVO', '02', pg_temp.m(0)  + 14),
          ('Felipe Nunes',      'INGLES',     '01', pg_temp.m(0)  + 14),
          ('Bruno Carvalho',    'INTERATIVO', '01', pg_temp.m(1)  + 5),
          ('Ana Paula Ribeiro', 'INTERATIVO', '01', pg_temp.m(-2) + 10),
          ('João Pedro Martins','INTERATIVO', '04', pg_temp.m(-2) + 10)
       ) as s(aluno, metodo, material, data)
  join public.aluno    a  on a.nome = s.aluno
  join public.metodo   me on me.unidade_id = a.unidade_id and me.codigo = s.metodo
  join public.material m  on m.unidade_id = a.unidade_id and m.metodo_id = me.id
                          and m.codigo = s.material
 where am.aluno_id = a.id and am.material_id = m.id and am.entregue;

alter table public.aluno_material enable trigger user;

-- Premissa: as seis entregas fixadas existem nas DUAS escolas. Sem ela, um
-- nome trocado na fixture deixaria a suíte medindo menos do que diz.
select is((select count(*)::integer from public.aluno_material
            where entregue and data_entrega >= pg_temp.m(-2)),
  12, 'premissa: as seis entregas medidas, fixadas nas duas escolas');

delete from public.demanda_projetada_hist;

insert into public.demanda_projetada_hist (unidade_id, material_id, mes, quantidade, regra, snapshot_em)
values
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Essencial 1'), pg_temp.m(0), 1, 'RITMO_ALUNO',    pg_temp.m(-1)),
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Essencial 1'), pg_temp.m(0), 2, 'MEDIA_METODO',   pg_temp.m(-1)),
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Avançada 1'),  pg_temp.m(0), 2, 'PREVISAO_CURSO', pg_temp.m(-1)),
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Avançada 1'),  pg_temp.m(1), 4, 'PREVISAO_CURSO', pg_temp.m(-1)),
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Essencial 2'), pg_temp.m(0), 5, 'RITMO_ALUNO',    pg_temp.m(0)),
  -- o mês corrente medido (foto do mês passado) — e mesmo assim fora: não fechou
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Avançada 2'),
     pg_temp.m(4), 7, 'RITMO_ALUNO', pg_temp.m(3)),
  -- a Escola B, para a RLS
  (tests.unidade('ESCOLA_B'), pg_temp.mat('ESCOLA_B', 'Informática Essencial 1'), pg_temp.m(0), 9, 'MEDIA_METODO',   pg_temp.m(-1));

create temporary table t_a as select * from public.v_projecao_acuracia where false;
create temporary table t_b as select * from public.v_projecao_acuracia where false;
grant all on t_a, t_b to authenticated;

select tests.autenticar(tests.uid('direcao@escola-a.test'));
insert into t_a select * from public.v_projecao_acuracia;
reset role;
select set_config('request.jwt.claims', null, true);

select tests.autenticar(tests.uid('direcao@escola-b.test'));
insert into t_b select * from public.v_projecao_acuracia;
reset role;
select set_config('request.jwt.claims', null, true);

create function pg_temp.linhas(p_unidade text) returns text
language sql stable as $$
  select string_agg(format('%s %s %s/%s %s', to_char(v.mes, 'YYYY-MM'), m.nome, v.qtd_projetada,
                           v.qtd_realizada, coalesce(array_to_string(v.regras, '+'), '-')),
                    ' | ' order by v.mes, m.nome)
    from (select * from t_a where p_unidade = 'ESCOLA_A'
          union all select * from t_b where p_unidade = 'ESCOLA_B') v
    join t_mat m on m.id = v.material_id
$$;

-- ===========================================================================
-- 1. O retrato inteiro da Escola A
-- ===========================================================================
select is(pg_temp.linhas('ESCOLA_A'),
  format('%1$s English Book 1 0/1 - | %1$s Informática Avançada 1 2/0 PREVISAO_CURSO'
         || ' | %1$s Informática Essencial 1 3/1 MEDIA_METODO+RITMO_ALUNO'
         || ' | %1$s Informática Essencial 2 0/1 - | %2$s Informática Essencial 1 0/1 -',
         pg_temp.ym(0), pg_temp.ym(1)),
  'Escola A: previsto x realizado por material e mes fechado e medido');

-- ===========================================================================
-- 2. O full join — o que faltou aparece
-- ===========================================================================
select is((select format('%s/%s/%s', qtd_projetada, qtd_realizada, erro) from t_a
            where material_id = pg_temp.mat('ESCOLA_A', 'English Book 1') and mes = pg_temp.m(0)),
  '0/1/-1',
  'entregue SEM previsao aparece, com erro negativo: e o lado do erro que falta material (full join)');
select is((select format('%s/%s/%s', qtd_projetada, qtd_realizada, erro) from t_a
            where material_id = pg_temp.mat('ESCOLA_A', 'Informática Avançada 1') and mes = pg_temp.m(0)),
  '2/0/2', 'previsto e NAO entregue aparece, com erro positivo: o lado que sobra');

-- ===========================================================================
-- 3. Duas regras no mesmo material e mês: o realizado conta UMA vez
-- ===========================================================================
select is((select count(*)::integer from t_a
            where material_id = pg_temp.mat('ESCOLA_A', 'Informática Essencial 1') and mes = pg_temp.m(0)),
  1, 'material previsto por duas regras e UMA linha, nao duas');
select is((select sum(qtd_realizada)::integer from t_a where mes = pg_temp.m(0)),
  (select count(*)::integer from public.aluno_material
    where unidade_id = tests.unidade('ESCOLA_A') and entregue
      and data_entrega >= pg_temp.m(0) and data_entrega < pg_temp.m(1)),
  'o Sigma realizado do mes M e o das entregas do mes: o denominador do vies do §9.2(b) nao dobra');

-- ===========================================================================
-- 4. Só a foto de UM mês antes
-- ===========================================================================
select is((select qtd_projetada from t_a
            where material_id = pg_temp.mat('ESCOLA_A', 'Informática Essencial 2') and mes = pg_temp.m(0)),
  0, 'a foto do proprio mes (5) nao conta: responderia "acertamos o que ja estava acontecendo"');
select is((select count(*)::integer from t_a
            where material_id = pg_temp.mat('ESCOLA_A', 'Informática Avançada 1') and mes = pg_temp.m(1)),
  0, 'a foto de dois meses antes (4) nao conta: M+1 se mede com a foto de M');

-- ===========================================================================
-- 5. Só mês medido e fechado
-- ===========================================================================
select is((select count(*)::integer from t_a where mes = pg_temp.m(-2)),
  0, 'M-2 tem entregas e nenhuma foto de M-3: mes NAO medido nao vira "entregue sem previsao"');
select is((select count(*)::integer from t_a where mes >= date_trunc('month', public.fn_hoje())::date),
  0, 'o mes corrente, mesmo medido, fica fora: nao fechou');

-- ===========================================================================
-- 6. RLS na pele do perfil
-- ===========================================================================
select is(pg_temp.linhas('ESCOLA_B'),
  format('%1$s English Book 1 0/1 - | %1$s Informática Essencial 1 9/1 MEDIA_METODO'
         || ' | %1$s Informática Essencial 2 0/1 -', pg_temp.ym(0)),
  'a direcao da Escola B ve so a Escola B: security_invoker + RLS por unidade');

select tests.autenticar(tests.uid('direcao@escola-a.test'));
select is((select count(*)::integer from public.v_projecao_acuracia
            where unidade_id <> public.fn_unidade_atual()),
  0, 'e a direcao da Escola A nao ve linha de outra unidade');
reset role;
select set_config('request.jwt.claims', null, true);

select * from finish();
rollback;
