-- =============================================================================
-- v_aluno_trilha — a view da aba Trilha (card 6.6)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- ⚠️ O NÚMERO DO ARQUIVO É 053, e o §17 não o previa: o mapa atribui ao card 6.6
--    só o `dialogo_resultado_test` do Flutter, porque a tela foi planejada sem
--    objeto de banco. Ela tem um — `v_aluno_trilha`, que o `views-leitura.md`
--    §12.1 sempre disse ser deste card —, e card de View tem obrigação própria
--    no §13. As views do 6.4 moram no `095` porque nasceram junto com a grade;
--    esta fica no bloco `05x` da trilha, ao lado das três suítes que a produzem
--    (050 tabelas, 051 geração, 052 entrega), que é onde alguém vai procurá-la.
--    Divergência registrada no §17, não seguida em silêncio.
--
-- Obrigação de teste de um card de **View** (§13): paridade de linhas por perfil
-- + zero para quem não pode + isolamento de unidade (§6.3), mais as armadilhas
-- do card 2.3 §3 que se aplicam — aqui as duas da RLS silenciosa, e elas tomam
-- formas OPOSTAS que a seção 5 mede lado a lado.
--
-- Três coisas que este arquivo prova e que nenhum catálogo enxerga:
--   • `proximo` é o MESMO item que `fn_trilha_proximo_material` devolve, aluno a
--     aluno, para os doze da fixture. É a asserção que impede a janela da view e
--     a função do card 6.2 de divergirem no dia em que alguém mexer numa só —
--     e divergir aqui significa a tela oferecer "Registrar entrega" na apostila
--     errada, enquanto a função entrega a certa;
--   • `posicao` é 1..n contínua e na ordem de `ordem` — o número que a coluna `#`
--     da aba mostra. Sem ele a tela exibiria `ordem` crua (10, 20, 25, 30), que
--     é o que a inserção do card 6.2 §5.1 produz de propósito;
--   • aluno SEM trilha e aluno em FIM são estados DIFERENTES aqui: o primeiro
--     não tem linha nenhuma, o segundo tem todas as linhas e nenhuma `proximo`.
--     `fn_trilha_em_fim` devolve `true` para os dois (card 6.2), e é justamente
--     por isso que a tela pergunta à view, não à função.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(23);

-- Chaves naturais em um lugar só (card 2.8 §11: nunca `limit` sem ordem, nunca
-- UUID literal).
create temporary view alvo as
  select tests.unidade('ESCOLA_A')                                  as unidade,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Ana Paula Ribeiro')  as ana,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Karina Bastos')      as karina,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Felipe Nunes')       as felipe;

-- ===========================================================================
-- 1. O contrato de forma: a view existe, é `invoker` e tem as 16 colunas na
--    ordem em que nasceram
-- ===========================================================================
-- A ordem é contrato (card 2.3 §6.2): `create or replace view` não insere coluna
-- no meio nem troca tipo. Quem acrescentar coluna nova acrescenta no FIM, e esta
-- asserção é o aviso de que mexer no meio exige `drop view`.
select has_view('public', 'v_aluno_trilha', 'v_aluno_trilha existe');

select is(
  (select string_agg(a.attname, ',' order by a.attnum)
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'v_aluno_trilha' and a.attnum > 0),
  'unidade_id,aluno_id,item_id,material_id,ordem,posicao,origem,entregue,' ||
  'data_entrega,movimento_estoque_id,metodo_id,material_codigo,material_nome,' ||
  'material_categoria,proximo,saldo',
  'as 16 colunas na ordem definitiva — coluna nova entra no FIM (card 2.3 §6.2)');

-- ===========================================================================
-- 2. `proximo` é fn_trilha_proximo_material, aluno a aluno
-- ===========================================================================
-- A contraprova vem antes: sem alunos com item pendente, a asserção seguinte
-- compararia dois conjuntos vazios e passaria sempre.
select cmp_ok(
  (select count(*) from public.v_aluno_trilha where proximo),
  '>', 0::bigint,
  'ha aluno com proximo na fixture — senao a paridade abaixo passaria de graca');

select is_empty(
  $$ select a.id
       from public.aluno a
      where public.fn_trilha_proximo_material(a.id) is distinct from
            (select v.material_id from public.v_aluno_trilha v
              where v.aluno_id = a.id and v.proximo) $$,
  'a view e a funcao do card 6.2 concordam sobre o proximo em TODO aluno');

select is(
  (select count(*) from (
     select v.aluno_id from public.v_aluno_trilha v
      where v.proximo group by v.aluno_id having count(*) > 1) t),
  0::bigint,
  'no maximo UM proximo por aluno: a janela usa min(ordem), nao um filtro por linha');

-- O item pulado por falta de estoque continua pendente e volta a ser o próximo
-- (card 2.2 (b)): a `ordem` do próximo é sempre a menor pendente, entregue ou
-- não o item seguinte.
select is_empty(
  $$ select v.item_id
       from public.v_aluno_trilha v
      where v.proximo and v.entregue $$,
  'nenhum item ENTREGUE e marcado como proximo');

-- ===========================================================================
-- 3. `posicao` é 1..n, contínua, na ordem de `ordem`
-- ===========================================================================
select is_empty(
  $$ select v.aluno_id
       from public.v_aluno_trilha v
      group by v.aluno_id
     having min(v.posicao) <> 1 or max(v.posicao) <> count(*) $$,
  'posicao vai de 1 a n sem buraco, por aluno');

select is_empty(
  $$ select v.item_id
       from public.v_aluno_trilha v
       join public.v_aluno_trilha w
         on w.aluno_id = v.aluno_id and w.ordem < v.ordem and w.posicao > v.posicao $$,
  'posicao respeita a ordem: item de `ordem` menor nunca tem posicao maior');

-- A contraprova de que `posicao` não é `ordem` disfarçada — se fosse, a coluna `#`
-- da aba mostraria 10, 20, 30 (card 6.2 §5.1 numera de 10 em 10).
select cmp_ok(
  (select count(*) from public.v_aluno_trilha where posicao <> ordem),
  '>', 0::bigint,
  'posicao DIFERE de ordem na fixture: a numeracao de 10 em 10 nao chega a tela');

-- ===========================================================================
-- 4. `saldo` é fn_saldo_material, e não uma terceira soma
-- ===========================================================================
select is_empty(
  $$ select v.item_id
       from public.v_aluno_trilha v
       join public.v_estoque_atual e on e.material_id = v.material_id
      where e.saldo is distinct from v.saldo $$,
  'o saldo da trilha e o mesmo de v_estoque_atual — duas leituras, um numero');

-- Aluno sem trilha × aluno em FIM: os dois estados que `fn_trilha_em_fim`
-- confunde de propósito (card 6.2) e que a tela precisa separar.
select is(
  (select count(*) from public.v_aluno_trilha v, alvo where v.aluno_id = alvo.karina),
  0::bigint,
  'Karina, a aluna SEM combo, nao tem linha nenhuma — "nunca comecou"');

select is(
  (select public.fn_trilha_em_fim(alvo.karina) from alvo),
  true,
  'e fn_trilha_em_fim diz true para ela: e por isso que a tela pergunta a VIEW');

-- ===========================================================================
-- 5. As duas reduções silenciosas, em formas OPOSTAS (card 2.3 §3.4)
-- ===========================================================================
select tests.encerrar_sessao();

insert into public.perfil (unidade_id, codigo, nome)
values (tests.unidade('ESCOLA_A'), 'TRI_SMAT', 'Trilha sem materiais.ler (teste 053)'),
       (tests.unidade('ESCOLA_A'), 'TRI_SEST', 'Trilha sem estoque.ler (teste 053)');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select tests.unidade('ESCOLA_A'), pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A')
   and pm.unidade_id = tests.unidade('ESCOLA_A')
   and ((pe.codigo = 'TRI_SMAT' and pm.codigo in ('alunos.ler', 'estoque.ler'))
        or (pe.codigo = 'TRI_SEST' and pm.codigo in ('alunos.ler', 'materiais.ler')));

select tests.criar_usuario('trilhasemmaterial@escola-a.test', 'TRI_SMAT');
select tests.criar_usuario('trilhasemestoque@escola-a.test',  'TRI_SEST');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_aluno_trilha'),
  '>', 0::bigint,
  'a direcao ve a trilha: sem isso toda paridade abaixo comparava zero com zero');

select is(
  tests.conta_como(tests.uid('trilhasemmaterial@escola-a.test'),
                   'select 1 from public.v_aluno_trilha'),
  0::bigint,
  'sem materiais.ler a trilha vem VAZIA — o join em material e interno, de proposito');

select is(
  tests.conta_como(tests.uid('trilhasemestoque@escola-a.test'),
                   'select 1 from public.v_aluno_trilha'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_aluno_trilha'),
  'sem estoque.ler a trilha vem CHEIA: a forma oposta da mesma reducao');

select is(
  tests.conta_como(tests.uid('trilhasemestoque@escola-a.test'),
                   'select 1 from public.v_aluno_trilha where saldo <> 0'),
  0::bigint,
  'e com saldo 0 em TUDO: nao quebra, MENTE — o motivo de a rota 3b exigir estoque.ler');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_aluno_trilha where saldo <> 0'),
  '>', 0::bigint,
  'contraprova: com estoque.ler o saldo VEM — senao a assercao acima passaria de graca');

-- ===========================================================================
-- 6. Paridade por perfil, zero para quem não pode, isolamento de unidade
-- ===========================================================================
select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_aluno_trilha'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_aluno_trilha'),
  'o monitor ve a MESMA trilha que a direcao — a aba Trilha e a jornada dele');

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
                   'select 1 from public.v_aluno_trilha'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_aluno_trilha'),
  'a secretaria ve a MESMA trilha que a direcao');

select is(
  tests.conta_como(tests.uid('pedagogico@escola-a.test'),
                   'select 1 from public.v_aluno_trilha'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_aluno_trilha'),
  'o pedagogico ve a MESMA trilha que a direcao');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_aluno_trilha'),
  0::bigint,
  'sem perfil nenhum a trilha e vazia — e vazia por RLS, que a view nao pode esconder');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_aluno_trilha where unidade_id = ' ||
                   quote_literal(tests.unidade('ESCOLA_A')::text) || '::uuid'),
  0::bigint,
  'a direcao da Escola B nao ve a trilha da Escola A: security_invoker + RLS por unidade');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_aluno_trilha'),
  '>', 0::bigint,
  'contraprova: ela ve a trilha da PROPRIA unidade, e o isolamento nao e "view quebrada"');

select * from finish();
rollback;
