-- =============================================================================
-- fn_ritmo_metodo_observado — a mediana do ritmo por método (card 9.2,69)
-- (mapa suíte → card: docs/estrategia-testes.md §17; spec: projecao-demanda §9.1)
--
-- A fixture tem, na Escola A, cinco intervalos de INTERATIVO entre entregas
-- consecutivas do mesmo aluno: {50, 60, 60, 80, 100}. MEDIANA 60, MÉDIA 70 — a
-- cauda longa que a especificação manda não seguir já está nela, e é o que faz
-- a contraprova média × mediana reprovar (sem a cauda, as duas coincidiriam e
-- a sabotagem passaria verde). Inglês tem UMA entrega datada (nenhum
-- intervalo) e Modular nenhuma: os dois são "sem base".
--
-- Tudo na pele do perfil (tests.autenticar / conta_como / codigo_do_erro),
-- nunca em contexto de rotina. Roda com begin/rollback.
-- =============================================================================

begin;
select plan(10);

create temporary table t_metodo as
  select u.codigo as unidade, m.codigo as metodo, m.id
    from public.metodo m join public.unidade u on u.id = m.unidade_id;
grant select on t_metodo to authenticated;

create temporary table t_r (caso text primary key, ritmo integer, n integer);
grant all on t_r to authenticated;

-- Janela larga (3650 dias) nos casos de valor: o resultado não pode depender
-- do dia em que a suíte roda. A janela padrão tem a sua própria asserção.
select tests.autenticar(tests.uid('direcao@escola-a.test'));
insert into t_r select 'A_INTERATIVO', * from public.fn_ritmo_metodo_observado(
  (select id from t_metodo where unidade = 'ESCOLA_A' and metodo = 'INTERATIVO'), 3650);
insert into t_r select 'A_INGLES', * from public.fn_ritmo_metodo_observado(
  (select id from t_metodo where unidade = 'ESCOLA_A' and metodo = 'INGLES'), 3650);
insert into t_r select 'A_MODULAR', * from public.fn_ritmo_metodo_observado(
  (select id from t_metodo where unidade = 'ESCOLA_A' and metodo = 'MODULAR'), 3650);
insert into t_r select 'A_PADRAO', * from public.fn_ritmo_metodo_observado(
  (select id from t_metodo where unidade = 'ESCOLA_A' and metodo = 'INTERATIVO'));
reset role;
select set_config('request.jwt.claims', null, true);

-- ===========================================================================
-- 1. A mediana, e não a média
-- ===========================================================================
select is((select format('%s/%s', ritmo, n) from t_r where caso = 'A_INTERATIVO'), '60/5',
  'INTERATIVO na Escola A: mediana 60 de 5 intervalos — a media (70) compraria tarde demais');

-- ===========================================================================
-- 2. Sem base é NULO, nunca zero
-- ===========================================================================
select is((select format('%s/%s', coalesce(ritmo::text, 'NULO'), n) from t_r where caso = 'A_INGLES'),
  'NULO/0', 'INGLES (uma entrega datada, nenhum intervalo): sem base — nulo e 0, nao zero');
select is((select format('%s/%s', coalesce(ritmo::text, 'NULO'), n) from t_r where caso = 'A_MODULAR'),
  'NULO/0', 'MODULAR (nenhuma entrega datada): sem base');

-- ===========================================================================
-- 3. A janela padrão sai de ritmo_calibracao_dias — paridade com a conta à mão
-- ===========================================================================
select is(
  (select n from t_r where caso = 'A_PADRAO'),
  (with i as (
     select am.data_entrega,
            am.data_entrega - lag(am.data_entrega) over (partition by am.aluno_id
                                                          order by am.data_entrega, am.ordem) as dias
       from public.aluno_material am join public.aluno a on a.id = am.aluno_id
      where am.entregue and am.data_entrega is not null
        and a.metodo_id = (select id from t_metodo where unidade = 'ESCOLA_A' and metodo = 'INTERATIVO'))
   select count(*)::integer from i
    where i.dias between 7 and 120
      and i.data_entrega >= public.fn_hoje()
          - (select valor::integer from public.parametro
              where unidade_id = tests.unidade('ESCOLA_A') and chave = 'ritmo_calibracao_dias')),
  'sem p_dias, a janela e a de ritmo_calibracao_dias (paridade com a conta a mao)');

-- ===========================================================================
-- 4. Os filtros são os do ritmo individual — lidos do parâmetro
-- ===========================================================================
update public.parametro set valor = '90'
 where unidade_id = tests.unidade('ESCOLA_A') and chave = 'ritmo_intervalo_max_dias';
select tests.autenticar(tests.uid('direcao@escola-a.test'));
insert into t_r select 'A_MAX90', * from public.fn_ritmo_metodo_observado(
  (select id from t_metodo where unidade = 'ESCOLA_A' and metodo = 'INTERATIVO'), 3650);
reset role;
select set_config('request.jwt.claims', null, true);
select is((select format('%s/%s', ritmo, n) from t_r where caso = 'A_MAX90'), '60/4',
  'com ritmo_intervalo_max_dias = 90 o intervalo de 100 sai: 4 intervalos');

-- Sem o parâmetro, erro alto — nenhum default escondido no código (card 8.4).
delete from public.parametro
 where unidade_id = tests.unidade('ESCOLA_A') and chave = 'ritmo_calibracao_dias';
select is(
  tests.codigo_do_erro(
    format($sql$ select * from public.fn_ritmo_metodo_observado(%L::uuid) $sql$,
           (select id from t_metodo where unidade = 'ESCOLA_A' and metodo = 'INTERATIVO')),
    tests.uid('direcao@escola-a.test')),
  'PARAMETRO_AUSENTE',
  'sem ritmo_calibracao_dias e sem p_dias: PARAMETRO_AUSENTE, e nao uma janela inventada');

-- ===========================================================================
-- 5. Unidade e permissão
-- ===========================================================================
-- A direção da Escola B pedindo pelo método da A: nada da A vaza (o filtro de
-- unidade está no corpo, e a função é definer).
select tests.autenticar(tests.uid('direcao@escola-b.test'));
insert into t_r select 'B_COM_METODO_DA_A', * from public.fn_ritmo_metodo_observado(
  (select id from t_metodo where unidade = 'ESCOLA_A' and metodo = 'INTERATIVO'), 3650);
insert into t_r select 'B_INTERATIVO', * from public.fn_ritmo_metodo_observado(
  (select id from t_metodo where unidade = 'ESCOLA_B' and metodo = 'INTERATIVO'), 3650);
reset role;
select set_config('request.jwt.claims', null, true);

select is((select format('%s/%s', coalesce(ritmo::text, 'NULO'), n) from t_r where caso = 'B_COM_METODO_DA_A'),
  'NULO/0', 'direcao B com o metodo da A: nada da Escola A atravessa');
select is((select format('%s/%s', ritmo, n) from t_r where caso = 'B_INTERATIVO'), '60/5',
  'e a Escola B tem a mediana DELA (o parametro alterado na A nao a alcanca)');

select is(
  tests.codigo_do_erro(
    format($sql$ select * from public.fn_ritmo_metodo_observado(%L::uuid, 3650) $sql$,
           (select id from t_metodo where unidade = 'ESCOLA_A' and metodo = 'INTERATIVO')),
    tests.uid('secretaria@escola-a.test')),
  'SEM_PERMISSAO', 'secretaria (sem parametros.ler): SEM_PERMISSAO');
select is(
  tests.codigo_do_erro(
    format($sql$ select * from public.fn_ritmo_metodo_observado(%L::uuid, 3650) $sql$,
           (select id from t_metodo where unidade = 'ESCOLA_A' and metodo = 'INTERATIVO')),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO', 'monitor: SEM_PERMISSAO');

select * from finish();
rollback;
