-- =============================================================================
-- Vigiar a rotina diária — rotina_execucao e fn_rotina_diaria_ultima_execucao
-- (card 9.2,66; mapa suíte → card: docs/estrategia-testes.md §17)
--
-- O achado: ninguém conferia que o pg_cron rodou. ROTINA_FALHOU cobre a falha
-- DENTRO da rotina, não a rotina que não roda. O que este arquivo prova:
--
--   • o anon lê a data e NADA MAIS: a função é a única aberta a ele, não tem
--     parâmetro, devolve um timestamptz, e a tabela continua fechada;
--   • só a execução COMPLETA carimba — a sob demanda da direção (9.2,65) não,
--     senão um clique diário esconderia um cron morto;
--   • só a unidade em que as cinco rt_* passaram carimba;
--   • a data devolvida é a da PIOR unidade, e NULL se alguma nunca rodou;
--   • a RLS da tabela, na pele: direção vê a linha da sua unidade, e só ela.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(14);

-- Lê como o vigia lê: com o papel anon, e volta ao postgres sem passar por
-- tests.* (anon não alcança o schema).
create temporary table t_leitura (quando timestamptz);
grant all on t_leitura to anon;

create or replace function pg_temp.como_vigia() returns timestamptz
language plpgsql as $$
declare v timestamptz;
begin
  set local role anon;
  v := public.fn_rotina_diaria_ultima_execucao();
  reset role;
  return v;
end $$;

-- ===========================================================================
-- 1. O que o anon alcança — a data, e só a data
-- ===========================================================================
select ok(
  has_function_privilege('anon', 'public.fn_rotina_diaria_ultima_execucao()', 'EXECUTE'),
  'anon executa fn_rotina_diaria_ultima_execucao — e o vigia so tem a chave publicavel');

select ok(
  not has_function_privilege('authenticated', 'public.fn_rotina_diaria_ultima_execucao()', 'EXECUTE'),
  'authenticated NAO: a funcao existe para o vigia, nao para o app');

select is(
  (select format('%s/%s/%s', p.pronargs, p.proretset, p.prorettype::regtype)
     from pg_proc p
    where p.oid = 'public.fn_rotina_diaria_ultima_execucao()'::regprocedure),
  '0/f/timestamp with time zone',
  'sem parametro, uma linha, um timestamptz: a assinatura nao tem por onde devolver mais que a data');

-- ===========================================================================
-- 2. A fixture nunca rodou a rotina completa
-- ===========================================================================
select is(pg_temp.como_vigia(), null::timestamptz,
  'fixture: nenhuma unidade carimbada -> NULL, e o vigia reprova "nunca rodou"');

-- ===========================================================================
-- 3. A execução sob demanda NÃO carimba
-- ===========================================================================
select public.rt_diaria(tests.unidade('ESCOLA_A'));
select is((select count(*)::bigint from public.rotina_execucao), 0::bigint,
  'rt_diaria(unidade) — a da direcao — nao carimba: um clique diario esconderia um cron morto');

-- ===========================================================================
-- 4. A execução completa carimba TODAS as unidades ativas
--    (as duas escolas da fixture e a MATRIZ da configuração)
-- ===========================================================================
select public.rt_diaria();
select is(
  (select count(*)::bigint from public.rotina_execucao where executada_em = now()),
  (select count(*)::bigint from public.unidade where ativo),
  'rt_diaria() — a do cron — carimba cada unidade ativa');
select is(pg_temp.como_vigia(), now(),
  'e o anon le a data da execucao');

-- ===========================================================================
-- 5. A pior unidade manda
-- ===========================================================================
update public.rotina_execucao
   set executada_em = now() - interval '3 days'
 where unidade_id = tests.unidade('ESCOLA_B');
select is(pg_temp.como_vigia(), now() - interval '3 days',
  'a data devolvida e a da unidade MAIS atrasada — "todas rodaram?" e a pergunta');

-- ===========================================================================
-- 6. A unidade em que uma rt_* falhou não carimba
-- ===========================================================================
-- Sabotagem só na Escola B, viva só dentro desta transação.
create or replace function public.rt_rep_avaliar()
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if current_setting('app.rotina_unidade', true) = tests.unidade('ESCOLA_B')::text then
    raise exception 'sabotagem do teste 093';
  end if;
end $$;

update public.rotina_execucao set executada_em = now() - interval '2 days';
select public.rt_diaria();

select is(
  (select string_agg(u.codigo || '=' || (r.executada_em = now())::text, ',' order by u.codigo)
     from public.rotina_execucao r join public.unidade u on u.id = r.unidade_id
    where u.codigo in ('ESCOLA_A', 'ESCOLA_B')),
  'ESCOLA_A=true,ESCOLA_B=false',
  'rt_rep_avaliar quebrou na Escola B: a A carimba, a B fica com a data velha');
select is(pg_temp.como_vigia(), now() - interval '2 days',
  'e o vigia ve a data velha da B — o e-mail sai mesmo que ninguem abra a central');

-- ===========================================================================
-- 7. A unidade ativa sem carimbo derruba a resposta para NULL
-- ===========================================================================
delete from public.rotina_execucao where unidade_id = tests.unidade('ESCOLA_B');
select is(pg_temp.como_vigia(), null::timestamptz,
  'uma unidade ativa sem carimbo -> NULL: "nunca rodou" nao se esconde atras da data de outra');

-- ===========================================================================
-- 8. A tabela continua fechada, e a RLS vale na pele
-- ===========================================================================
set local role anon;
insert into t_leitura select executada_em from public.rotina_execucao;
reset role;
select is((select count(*)::bigint from t_leitura), 0::bigint,
  'anon NAO le rotina_execucao: a unica coisa aberta e a data da funcao');

-- A Escola B foi apagada na seção 7; recarimba para a direção ter o que NÃO ver.
insert into public.rotina_execucao (unidade_id, executada_em)
values (tests.unidade('ESCOLA_B'), now());
select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.rotina_execucao'),
  1::bigint,
  'direcao (parametros.ler) ve UMA linha — a da Escola A, nunca a da B');

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
                   'select 1 from public.rotina_execucao'),
  0::bigint,
  'secretaria (sem parametros.ler) nao ve nenhuma linha');

select * from finish();
rollback;
