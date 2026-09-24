-- =============================================================================
-- v_projecao_acuracia — previsto × realizado (card 11.1,5; spec: projecao-demanda §9.3)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- A fixture tem entregas com DATA FIXA (Escola A e B iguais). Esta suíte
-- escreve as fotos mensais à mão (como dono, na transação — a tabela só aceita
-- a rotina) e confere a view linha a linha:
--
--   foto 2026-05 → mês 2026-06:  Informática Essencial 1 = 1 (RITMO_ALUNO)
--                                                       + 2 (MEDIA_METODO)
--                                Informática Avançada 1  = 2 (PREVISAO_CURSO)
--   foto 2026-05 → mês 2026-07:  Informática Avançada 1  = 4  (dois meses antes:
--                                                              NÃO conta)
--   foto 2026-06 → mês 2026-06:  Informática Essencial 2 = 5  (a foto do próprio
--                                                              mês: NÃO conta)
--   entregas 2026-06: IE1 ×1, IE2 ×1, English Book 1 ×1 · 2026-07: IE1 ×1
--   entregas 2026-04: IE1, IA2 — sem foto de 2026-03: mês NÃO medido
--
-- Tudo na pele do perfil (tests.autenticar), nunca em contexto de rotina.
-- =============================================================================

begin;
select plan(11);

create temporary table t_mat as
  select u.codigo as unidade, m.nome, m.id
    from public.material m join public.unidade u on u.id = m.unidade_id;
grant select on t_mat to authenticated;

create function pg_temp.mat(p_unidade text, p_nome text) returns uuid
language sql stable as $$ select id from t_mat where unidade = p_unidade and nome = p_nome $$;

delete from public.demanda_projetada_hist;

insert into public.demanda_projetada_hist (unidade_id, material_id, mes, quantidade, regra, snapshot_em)
values
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Essencial 1'), '2026-06-01', 1, 'RITMO_ALUNO',    '2026-05-01'),
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Essencial 1'), '2026-06-01', 2, 'MEDIA_METODO',   '2026-05-01'),
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Avançada 1'),  '2026-06-01', 2, 'PREVISAO_CURSO', '2026-05-01'),
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Avançada 1'),  '2026-07-01', 4, 'PREVISAO_CURSO', '2026-05-01'),
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Essencial 2'), '2026-06-01', 5, 'RITMO_ALUNO',    '2026-06-01'),
  -- o mês corrente medido (foto do mês passado) — e mesmo assim fora: não fechou
  (tests.unidade('ESCOLA_A'), pg_temp.mat('ESCOLA_A', 'Informática Avançada 2'),
     date_trunc('month', public.fn_hoje())::date, 7, 'RITMO_ALUNO',
     (date_trunc('month', public.fn_hoje()) - interval '1 month')::date),
  -- a Escola B, para a RLS
  (tests.unidade('ESCOLA_B'), pg_temp.mat('ESCOLA_B', 'Informática Essencial 1'), '2026-06-01', 9, 'MEDIA_METODO',   '2026-05-01');

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
  '2026-06 English Book 1 0/1 - | 2026-06 Informática Avançada 1 2/0 PREVISAO_CURSO'
  || ' | 2026-06 Informática Essencial 1 3/1 MEDIA_METODO+RITMO_ALUNO'
  || ' | 2026-06 Informática Essencial 2 0/1 - | 2026-07 Informática Essencial 1 0/1 -',
  'Escola A: previsto x realizado por material e mes fechado e medido');

-- ===========================================================================
-- 2. O full join — o que faltou aparece
-- ===========================================================================
select is((select format('%s/%s/%s', qtd_projetada, qtd_realizada, erro) from t_a
            where material_id = pg_temp.mat('ESCOLA_A', 'English Book 1') and mes = '2026-06-01'),
  '0/1/-1',
  'entregue SEM previsao aparece, com erro negativo: e o lado do erro que falta material (full join)');
select is((select format('%s/%s/%s', qtd_projetada, qtd_realizada, erro) from t_a
            where material_id = pg_temp.mat('ESCOLA_A', 'Informática Avançada 1') and mes = '2026-06-01'),
  '2/0/2', 'previsto e NAO entregue aparece, com erro positivo: o lado que sobra');

-- ===========================================================================
-- 3. Duas regras no mesmo material e mês: o realizado conta UMA vez
-- ===========================================================================
select is((select count(*)::integer from t_a
            where material_id = pg_temp.mat('ESCOLA_A', 'Informática Essencial 1') and mes = '2026-06-01'),
  1, 'material previsto por duas regras e UMA linha, nao duas');
select is((select sum(qtd_realizada)::integer from t_a where mes = '2026-06-01'),
  (select count(*)::integer from public.aluno_material
    where unidade_id = tests.unidade('ESCOLA_A') and entregue
      and data_entrega >= '2026-06-01' and data_entrega < '2026-07-01'),
  'o Sigma realizado de 2026-06 e o das entregas do mes: o denominador do vies do §9.2(b) nao dobra');

-- ===========================================================================
-- 4. Só a foto de UM mês antes
-- ===========================================================================
select is((select qtd_projetada from t_a
            where material_id = pg_temp.mat('ESCOLA_A', 'Informática Essencial 2') and mes = '2026-06-01'),
  0, 'a foto do proprio mes (5) nao conta: responderia "acertamos o que ja estava acontecendo"');
select is((select count(*)::integer from t_a
            where material_id = pg_temp.mat('ESCOLA_A', 'Informática Avançada 1') and mes = '2026-07-01'),
  0, 'a foto de dois meses antes (4) nao conta: julho se mede com a foto de junho');

-- ===========================================================================
-- 5. Só mês medido e fechado
-- ===========================================================================
select is((select count(*)::integer from t_a where mes = '2026-04-01'),
  0, 'abril tem entregas e nenhuma foto de marco: mes NAO medido nao vira "entregue sem previsao"');
select is((select count(*)::integer from t_a where mes >= date_trunc('month', public.fn_hoje())::date),
  0, 'o mes corrente, mesmo medido, fica fora: nao fechou');

-- ===========================================================================
-- 6. RLS na pele do perfil
-- ===========================================================================
select is(pg_temp.linhas('ESCOLA_B'),
  '2026-06 English Book 1 0/1 - | 2026-06 Informática Essencial 1 9/1 MEDIA_METODO'
  || ' | 2026-06 Informática Essencial 2 0/1 -',
  'a direcao da Escola B ve so a Escola B: security_invoker + RLS por unidade');

select tests.autenticar(tests.uid('direcao@escola-a.test'));
select is((select count(*)::integer from public.v_projecao_acuracia
            where unidade_id <> public.fn_unidade_atual()),
  0, 'e a direcao da Escola A nao ve linha de outra unidade');
reset role;
select set_config('request.jwt.claims', null, true);

select * from finish();
rollback;
