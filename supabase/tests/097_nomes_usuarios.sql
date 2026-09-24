-- =============================================================================
-- O nome de quem fez, para quem não é da Administração (card 9.2,74)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- A decisão de Irineu (24/09/2026), no formato aprovado e só nele: SÓ id e
-- nome dos usuários da MESMA unidade. O que se prova:
--
--   • fn_usuarios_nomes() devolve duas colunas, id e nome — a assinatura não
--     tem por onde vazar e-mail nem perfil;
--   • na pele da secretaria e do monitor: todos os nomes da Escola A, nenhum
--     da B; e a tabela `usuario` continua fechada para eles (e-mail incluso);
--   • a direção da B vê só a B; o anon não executa;
--   • v_material_movimento.criado_por_nome chega para a secretaria — antes,
--     nulo para quem não era admin.
--
-- Roda com begin/rollback.
-- =============================================================================

begin;
select plan(9);

-- ===========================================================================
-- 1. A assinatura: duas colunas, e só elas
-- ===========================================================================
select is(
  pg_get_function_result('public.fn_usuarios_nomes()'::regprocedure),
  'TABLE(id uuid, nome text)',
  'fn_usuarios_nomes devolve id e nome — e nada mais');

select ok(
  not has_function_privilege('anon', 'public.fn_usuarios_nomes()', 'EXECUTE'),
  'anon nao executa');

-- ===========================================================================
-- 2. Na pele de quem não é da Administração
-- ===========================================================================
select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
    'select 1 from public.fn_usuarios_nomes()'),
  (select count(*)::bigint from public.usuario where unidade_id = tests.unidade('ESCOLA_A')),
  'secretaria: todos os nomes da Escola A');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
    $sql$ select 1 from public.fn_usuarios_nomes()
           where id = '$sql$ || tests.uid('direcao@escola-b.test') || $sql$' $sql$),
  0::bigint,
  'monitor: nenhum nome da Escola B');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
    $sql$ select 1 from public.fn_usuarios_nomes()
           where nome is not null $sql$),
  (select count(*)::bigint from public.usuario where unidade_id = tests.unidade('ESCOLA_A')),
  'monitor: os nomes da A chegam preenchidos');

-- A tabela continua fechada: nenhuma política de `usuario` mudou.
select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
    $sql$ select 1 from public.usuario
           where id <> '$sql$ || tests.uid('secretaria@escola-a.test') || $sql$' $sql$),
  0::bigint,
  'secretaria continua sem ler a linha de usuario dos outros (e-mail e perfis ficam com admin.ler)');

-- Pela CONTAGEM, e não por um join em `usuario`: o join passaria pela RLS de
-- quem lê e esconderia exatamente o vazamento que se quer medir.
select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
    'select 1 from public.fn_usuarios_nomes()'),
  (select count(*)::bigint from public.usuario where unidade_id = tests.unidade('ESCOLA_B')),
  'direcao da Escola B: exatamente os nomes da B');

-- ===========================================================================
-- 3. O "por …" do estoque, para quem lê estoque
-- ===========================================================================
-- Um movimento com autor: a sessão da direção carimba criado_por (fn_auditoria).
select set_config('request.jwt.claims',
  json_build_object('sub', tests.uid('direcao@escola-a.test')::text,
                    'role', 'authenticated')::text, true);
insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade, observacao)
select tests.unidade('ESCOLA_A'), m.id, 'ENTRADA', 1, 'teste 097'
  from public.material m
 where m.unidade_id = tests.unidade('ESCOLA_A')
 order by m.codigo limit 1;
select set_config('request.jwt.claims', null, true);

select is(
  (select count(*)::bigint from public.movimento_estoque
    where observacao = 'teste 097' and criado_por = tests.uid('direcao@escola-a.test')),
  1::bigint,
  'premissa: o movimento tem a direcao como autora');

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
    $sql$ select 1 from public.v_material_movimento
           where observacao = 'teste 097' and criado_por_nome is not null $sql$),
  1::bigint,
  'secretaria le o NOME de quem lancou o movimento — antes, nulo para quem nao era admin');

select * from finish();
rollback;
