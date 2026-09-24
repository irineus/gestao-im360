-- =============================================================================
-- Importação: a validação chamada direto, a trava da aplicação e
-- v_importacao_ocorrencia (card 9.2,68; mapa suíte → card: estrategia-testes §17)
--
-- Três achados da varredura de 24/09/2026, nenhum visto em uso porque a tela
-- chama as funções na ordem certa:
--
--   • fn_importacao_validar, chamada de novo pelo PostgREST, DUPLICAVA as
--     ocorrências — inclusive em lote APLICADO. Agora recusa com
--     IMPORTACAO_JA_VALIDADA, e quem não pode importar ouve SEM_PERMISSAO;
--   • fn_importacao_aplicar não travava o lote. A corrida de duas sessões mora
--     em supabase/tests_concorrencia/importacao_aplicar_dupla.sh; aqui fica o
--     guarda-chuva barato de que o `for update` não sumiu (como o C13 do 071);
--   • v_importacao_ocorrencia não tinha teste nenhum: paridade de linhas com a
--     tabela e a RLS na pele de quem não pode importar.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(10);

create temporary table t_lote (id uuid);
grant all on t_lote to authenticated;

-- Um arquivo com um aviso de propósito (aluno ativo fora de bloco): ocorrência
-- existe, e é ela que a segunda validação duplicaria.
select tests.autenticar(tests.uid('direcao@escola-a.test'));
insert into t_lote
  select public.fn_importacao_registrar('guardas.json', '2026-08-29'::date, $json$
{
  "professor": [{"nome": "Prof. Guardas"}],
  "aluno": [{"codigo": "GUA-1", "nome": "Aluno Guardas", "metodo": "INTERATIVO"}]
}
$json$::jsonb);
reset role;
select set_config('request.jwt.claims', null, true);

create temporary view t_contagem as
  select count(*)::bigint as n from public.importacao_ocorrencia o
   where o.importacao_id = (select id from t_lote);

select cmp_ok((select n from t_contagem), '>', 0::bigint,
  'premissa: o lote nasceu com ocorrencia — sem ela, a duplicacao nao teria o que duplicar');

-- ===========================================================================
-- 1. A validação chamada de novo
-- ===========================================================================
create temporary table t_antes as select n from t_contagem;

select is(
  tests.codigo_do_erro(
    format($sql$ select public.fn_importacao_validar(%L::uuid) $sql$, (select id from t_lote)),
    tests.uid('direcao@escola-a.test')),
  'IMPORTACAO_JA_VALIDADA',
  'validar de novo um lote ja validado e recusado com codigo do catalogo');

select is((select n from t_contagem), (select n from t_antes),
  'e as ocorrencias NAO dobraram');

select is(
  tests.codigo_do_erro(
    format($sql$ select public.fn_importacao_validar(%L::uuid) $sql$, (select id from t_lote)),
    tests.uid('secretaria@escola-a.test')),
  'SEM_PERMISSAO',
  'secretaria (fora do conjunto da rota 13): SEM_PERMISSAO, e nao "nao encontrada"');

-- Aplicado, o lote continua recusando a validação.
select tests.autenticar(tests.uid('direcao@escola-a.test'));
select public.fn_importacao_aplicar((select id from t_lote), false);
reset role;
select set_config('request.jwt.claims', null, true);

select is(
  (select i.status from public.importacao i where i.id = (select id from t_lote)),
  'APLICADA',
  'premissa: o lote foi aplicado');

select is(
  tests.codigo_do_erro(
    format($sql$ select public.fn_importacao_validar(%L::uuid) $sql$, (select id from t_lote)),
    tests.uid('direcao@escola-a.test')),
  'IMPORTACAO_JA_VALIDADA',
  'lote APLICADO tambem recusa a validacao — era o caso que duplicava o relatorio de um lote ja em producao');

-- ===========================================================================
-- 2. A trava da aplicação (guarda-chuva; a prova é a suíte de concorrência)
-- ===========================================================================
select ok(
  (select pg_get_functiondef('public.fn_importacao_aplicar(uuid, boolean)'::regprocedure)
          ~* 'where i\.id = p_importacao_id\s+for update'),
  'fn_importacao_aplicar le o lote com FOR UPDATE — sem ele, duas aplicacoes simultaneas correm juntas');

-- ===========================================================================
-- 3. v_importacao_ocorrencia: paridade com a tabela e RLS na pele
-- ===========================================================================
select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
    format($sql$ select 1 from public.v_importacao_ocorrencia where importacao_id = %L $sql$,
           (select id from t_lote))),
  (select n from t_contagem),
  'paridade: a direcao ve pela view exatamente as ocorrencias que a tabela tem para o lote');

select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
    'select 1 from public.v_importacao_ocorrencia v
      where not exists (select 1 from public.importacao i where i.id = v.importacao_id)'),
  0::bigint,
  'e nenhuma ocorrencia de lote que ela nao ve (a view nao atravessa a RLS de importacao)');

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
    'select 1 from public.v_importacao_ocorrencia')
  + tests.conta_como(tests.uid('monitor@escola-a.test'),
    'select 1 from public.v_importacao_ocorrencia')
  + tests.conta_como(tests.uid('direcao@escola-b.test'),
    'select 1 from public.v_importacao_ocorrencia'),
  0::bigint,
  'secretaria, monitor e a direcao da OUTRA unidade nao veem ocorrencia nenhuma');

select * from finish();
rollback;
