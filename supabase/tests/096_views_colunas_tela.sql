-- =============================================================================
-- Views do card 9.2,7: o fuso de dias_aberta e as colunas das telas 5 e 8
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
--   (1) v_pendencias_abertas.dias_aberta no fuso da ESCOLA — a pendência aberta
--       ontem às 22h de São Paulo (01h de hoje em UTC) tem 1 dia, não 0;
--   (2) v_projecao_material_mes.metodo_codigo/metodo_nome = o método do material;
--   (3) v_turma_modular_lotacao.data_inicio = a coluna da turma;
--   (4) v_projecao_aluno_detalhe.modular_sem_cronograma — o aluno Modular que
--       cai para outro degrau aparece marcado; o que segue o cronograma, não.
--
-- Leituras na pele de quem abre a tela (conta_como). Roda com begin/rollback.
-- =============================================================================

begin;
select plan(8);

-- O banco do Supabase roda em UTC; o teste fixa isso para o defeito existir.
set local timezone = 'UTC';

-- ===========================================================================
-- 1. dias_aberta no fuso da escola
-- ===========================================================================
create temporary table t_pend as
  select p.id from public.pendencia p
   where p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null
   limit 1;
grant select on t_pend to authenticated;

-- fn_auditoria preserva criado_em no update (é o que o protege em produção);
-- para fabricar o caso, os triggers de usuário saem só em volta deste ajuste.
alter table public.pendencia disable trigger user;
update public.pendencia
   set criado_em = ((public.fn_hoje() - 1)::timestamp + time '22:00')
                   at time zone 'America/Sao_Paulo'
 where id = (select id from t_pend);
alter table public.pendencia enable trigger user;

select is(
  (select (criado_em::date = public.fn_hoje())::text from public.pendencia
    where id = (select id from t_pend)),
  'true',
  'premissa: ontem 22h em Sao Paulo ja e HOJE em UTC — o caso do defeito');

select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
    'select 1 from public.v_pendencias_abertas
      where pendencia_id = (select id from t_pend) and dias_aberta = 1'),
  1::bigint,
  'dias_aberta = 1: aberta ONTEM no fuso da escola, e nao 0 como o cast em UTC dizia');

-- ===========================================================================
-- 2. O método na grade da projeção
-- ===========================================================================
select public.rt_diaria(tests.unidade('ESCOLA_A'));

create temporary table t_grade (metodo_id uuid, metodo_codigo text, metodo_nome text);
grant all on t_grade to authenticated;
select tests.autenticar(tests.uid('direcao@escola-a.test'));
insert into t_grade select metodo_id, metodo_codigo, metodo_nome from public.v_projecao_material_mes;
reset role;
select set_config('request.jwt.claims', null, true);

select cmp_ok((select count(*) from t_grade), '>', 0::bigint,
  'premissa: a grade da Escola A tem linhas depois da rotina');

select is(
  (select count(*) from t_grade g join public.metodo m on m.id = g.metodo_id
    where g.metodo_codigo is distinct from m.codigo or g.metodo_nome is distinct from m.nome),
  0::bigint,
  'metodo_codigo e metodo_nome sao os do metodo do material, em toda linha');

-- ===========================================================================
-- 3. O início da turma Modular
-- ===========================================================================
select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
    'select 1 from public.v_turma_modular_lotacao v
       join public.turma_modular t on t.id = v.turma_id
      where v.data_inicio is distinct from t.data_inicio'),
  0::bigint,
  'data_inicio da lotacao e a coluna da turma');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
    'select 1 from public.v_turma_modular_lotacao where data_inicio is not null'),
  '>', 0::bigint,
  'e ela chega preenchida — a tela 5 tem o que mostrar');

-- ===========================================================================
-- 4. O aluno Modular que caiu de degrau
-- ===========================================================================
create temporary view t_modular as
  select d.aluno_id, d.regra, d.modular_sem_cronograma
    from public.v_projecao_aluno_detalhe d
    join public.material m on m.id = d.material_id
    join public.metodo  me on me.id = m.metodo_id
   where me.codigo = 'MODULAR' and d.unidade_id = tests.unidade('ESCOLA_A');

select is(
  (select string_agg(regra || '=' || modular_sem_cronograma, ',') from t_modular),
  'MODULAR=false',
  'fixture: o aluno Modular segue o cronograma da turma, e nao esta marcado');

-- Sem turma, ele cai para a previsão de curso ou a média do método.
select tests.como_rotina(tests.unidade('ESCOLA_A'));
update public.turma_modular_aluno set ativo = false
 where aluno_id in (select aluno_id from t_modular);
select tests.encerrar_sessao();

select is(
  (select bool_and(modular_sem_cronograma and regra <> 'MODULAR') from t_modular),
  true,
  'fora do cronograma, o aluno Modular aparece marcado — o drill-down diz QUAIS estao na media');

select * from finish();
rollback;
