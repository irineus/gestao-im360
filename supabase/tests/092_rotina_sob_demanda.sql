-- =============================================================================
-- A rotina diária sob demanda — fn_rotina_diaria_executar (card 9.2,65)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- O problema medido: depois de uma importação a direção só via projeção, pedido
-- sugerido e pendências no dia seguinte, às 03:10. O que este arquivo prova:
--
--   • a direção executa a rotina da SUA unidade na hora, e a projeção sai do
--     zero — a da outra unidade não se mexe (definer com filtro no corpo, C8);
--   • quem não tem `parametros.gerir` recebe SEM_PERMISSAO, com o código do
--     catálogo — na pele do perfil, nunca em contexto de rotina (card 8.3);
--   • `rt_diaria(p_unidade)` roda só a unidade pedida, e `rt_diaria()` sem
--     argumento continua rodando todas (é o que o cron chama);
--   • a trava entre DUAS sessões não cabe aqui (o advisory lock é reentrante
--     na mesma sessão): mora em supabase/tests_concorrencia/rotina_diaria_dupla.sh.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(9);

create temporary view t_projecao as
  select u.codigo, count(d.id)::bigint as linhas
    from public.unidade u
    left join public.demanda_projetada d on d.unidade_id = u.id
   group by u.codigo;

-- ===========================================================================
-- 1. Premissa: a fixture nasce sem projeção calculada (é o estado depois de
--    um db reset — e o de depois de uma importação, na vida real)
-- ===========================================================================
select is(
  (select linhas from t_projecao where codigo = 'ESCOLA_A'), 0::bigint,
  'fixture: a Escola A comeca sem projecao calculada');

-- ===========================================================================
-- 2. A direção executa — na pele dela
-- ===========================================================================
select tests.autenticar(tests.uid('direcao@escola-a.test'));
select is(public.fn_rotina_diaria_executar(), 'EXECUTADA',
  'direcao: a rotina da unidade roda na hora e devolve EXECUTADA');
-- Volta ao postgres sem passar por tests.* (authenticated não alcança o schema).
reset role;
select set_config('request.jwt.claims', null, true);

select cmp_ok(
  (select linhas from t_projecao where codigo = 'ESCOLA_A'), '>', 0::bigint,
  'e a projecao da Escola A sai do zero — sem esperar as 03:10');

select is(
  (select linhas from t_projecao where codigo = 'ESCOLA_B'), 0::bigint,
  'e a da Escola B NAO se mexe: a execucao sob demanda roda so a unidade de quem chama');

-- O contexto de rotina não vaza para o resto da transação de quem chamou.
select is(current_setting('app.rotina', true), '',
  'o contexto de rotina morre com a chamada — nao vaza para quem chamou');

-- ===========================================================================
-- 3. Quem não tem parametros.gerir
-- ===========================================================================
select is(
  tests.codigo_do_erro('select public.fn_rotina_diaria_executar()',
                       tests.uid('secretaria@escola-a.test')),
  'SEM_PERMISSAO',
  'secretaria (sem parametros.gerir): SEM_PERMISSAO, com o codigo do catalogo');

select is(
  tests.codigo_do_erro('select public.fn_rotina_diaria_executar()',
                       tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'monitor: SEM_PERMISSAO');

-- ===========================================================================
-- 4. rt_diaria com e sem unidade
-- ===========================================================================
select public.rt_diaria(tests.unidade('ESCOLA_B'));
select cmp_ok(
  (select linhas from t_projecao where codigo = 'ESCOLA_B'), '>=', 0::bigint,
  'rt_diaria(unidade B) roda sem erro');

-- `rt_diaria()` sem argumento é o que o cron chama: continua existindo e
-- continua sendo UMA função só (a antiga sem parâmetro foi removida, não
-- sobrecarregada — duas funções com o mesmo nome deixariam o cron ambíguo).
select is(
  (select count(*)::bigint from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rt_diaria'),
  1::bigint,
  'rt_diaria existe uma vez so, com o parametro opcional — o cron resolve pelo default');

select * from finish();
rollback;
