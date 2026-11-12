-- =============================================================================
-- O próximo livro do aluno Modular segue os módulos dele — card 9.2,886, item 1
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- O cenário é a turma `Eletricista 2026.1` da escola-fixture — M1 concluído;
-- M2 corrente; M3 sem data — com dois livros: o `01` cobre M1 e M2, o `02`
-- cobre M3 (o mesmo arranjo do teste 107).
--
--   Novo (9101)  entra para começar no M3. A trilha dele está na ORDEM DO CURSO
--                — 01, depois 02 —, que é como ela nasce do combo. A sequência
--                dele é M3 → M1 → M2: o livro de que ele precisa primeiro é o 02.
--
-- ⚠️ Vermelho antes deste card: os quatro lugares que dizem "próximo livro"
--    apontavam o 01 — a entrega sem material escolhido entregaria o livro
--    errado, a aba Trilha marcaria o errado, e a compra imediata e a projeção
--    contariam o livro trocado.
--
-- E o outro lado, que importa tanto quanto: o aluno que NÃO está em turma
-- Modular continua com o próximo pela `ordem`, como sempre.
--
-- Roda com begin/rollback.
-- =============================================================================

begin;
select plan(12);

create temporary table t_ids as
select tests.unidade('ESCOLA_A') as unidade,
       (select id from public.turma_modular
         where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eletricista 2026.1') as turma,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.codigo_sgf = '9101') as novo;
grant select on t_ids to authenticated;

create temporary table t_mod as
select m.ordem, m.id, m.material_id, mt.codigo
  from public.modulo m
  join public.material mt on mt.id = m.material_id
  join public.turma_modular t on t.curso_id = m.curso_id
 where t.id = (select turma from t_ids);
grant select on t_mod to authenticated;

-- A pré-condição do cenário: dois livros, e o M3 num livro diferente do M1.
select isnt(
  (select material_id from t_mod where ordem = 3),
  (select material_id from t_mod where ordem = 1),
  'o cenario tem dois livros: o M3 usa um livro diferente do M1');

-- A trilha do aluno novo, na ordem do CURSO (01 = M1/M2, 02 = M3), como nasce do
-- combo. Estoque dos dois, para a entrega do §3 não cair em REORDENADA.
select tests.como_rotina((select unidade from t_ids));

insert into public.aluno_material (unidade_id, aluno_id, material_id, ordem, origem)
select (select unidade from t_ids), (select novo from t_ids), x.material_id, x.ordem, 'MANUAL'
  from (select (select material_id from t_mod where ordem = 1) as material_id, 10 as ordem
        union all
        select (select material_id from t_mod where ordem = 3), 20) x;

insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade, observacao)
select (select unidade from t_ids), material_id, 'ENTRADA', 5, 'teste 109'
  from (select distinct material_id from t_mod) x;

select tests.encerrar_sessao();

-- ===========================================================================
-- 1. Fora da turma: o próximo é a `ordem`, como sempre
-- ===========================================================================
select is(
  public.fn_trilha_proximo_material((select novo from t_ids)),
  (select material_id from t_mod where ordem = 1),
  'sem turma Modular, o proximo livro e o primeiro da trilha, pela ordem — nada mudou');

-- ===========================================================================
-- 2. Na turma, entrando pelo M3: o próximo é o livro do M3
-- ===========================================================================
select tests.autenticar(tests.uid('secretaria@escola-a.test'));
select public.fn_turma_modular_admitir((select turma from t_ids), (select novo from t_ids),
                                       (select id from t_mod where ordem = 3));

select is(
  public.fn_trilha_proximo_material((select novo from t_ids)),
  (select material_id from t_mod where ordem = 3),
  'entrou pelo M3: o proximo livro e o do M3, e nao o primeiro da trilha');

select is(
  (select string_agg(s.seq || ':' || t.codigo, ' ' order by s.seq)
     from public.v_aluno_material_sequencia s
     join t_mod t on t.material_id = s.material_id and t.ordem in (1, 3)
    where s.aluno_id = (select novo from t_ids)),
  format('1:%s 2:%s', (select codigo from t_mod where ordem = 3),
                      (select codigo from t_mod where ordem = 1)),
  'a sequencia efetiva dele: o livro do M3, depois o do M1');

select is(
  (select t.codigo from public.v_aluno_trilha v
     join t_mod t on t.material_id = v.material_id and t.ordem in (1, 3)
    where v.aluno_id = (select novo from t_ids) and v.proximo),
  (select codigo from t_mod where ordem = 3),
  'a aba Trilha marca como proxima o livro do M3');

select is(
  (select count(*)::integer from public.v_aluno_trilha v
    where v.aluno_id = (select novo from t_ids) and v.proximo),
  1,
  'e so ele — um proximo por aluno');

-- A `ordem` gravada NÃO mudou: a correção é derivada, não reordena a trilha.
select is(
  (select string_agg(t.codigo || '=' || am.ordem, ' ' order by am.ordem)
     from public.aluno_material am
     join t_mod t on t.material_id = am.material_id and t.ordem in (1, 3)
    where am.aluno_id = (select novo from t_ids)),
  format('%s=10 %s=20', (select codigo from t_mod where ordem = 1),
                        (select codigo from t_mod where ordem = 3)),
  'a ordem gravada da trilha continua a do curso — nada foi reordenado');

-- ===========================================================================
-- 3. Demanda imediata e projeção: o livro certo, e sem contar duas vezes
-- ===========================================================================
select is(
  (select t.codigo from public.v_demanda_imediata_aluno d
     join t_mod t on t.material_id = d.material_id and t.ordem in (1, 3)
    where d.aluno_id = (select novo from t_ids)),
  (select codigo from t_mod where ordem = 3),
  'a compra imediata conta o livro do M3 para ele');

select is(
  (select string_agg(t.codigo || ':k' || p.k, ' ')
     from public.v_projecao_aluno p
     join t_mod t on t.material_id = p.material_id and t.ordem in (1, 3)
    where p.aluno_id = (select novo from t_ids)),
  (select codigo from t_mod where ordem = 1) || ':k2',
  'a projecao conta so o livro do M1, como k = 2 — o do M3 e demanda imediata');

-- A disjunção, para todos os alunos: nenhum livro na imediata E na projetada.
select is(
  (select count(*)::integer
     from public.v_demanda_imediata_aluno d
     join public.v_projecao_aluno p on p.aluno_id = d.aluno_id
                                   and p.material_id = d.material_id),
  0,
  'nenhum aluno tem o mesmo livro na demanda imediata e na projetada');

-- ===========================================================================
-- 4. A entrega sem material escolhido entrega o livro certo
-- ===========================================================================
reset role;
select tests.autenticar(tests.uid('monitor@escola-a.test'));

create temporary table t_entrega as
with e as (select * from public.fn_registrar_entrega((select novo from t_ids)))
select e.status, e.material_id, e.proximo_material_id from e;

reset role;
select is(
  (select status || ':' || (select codigo from t_mod t where t.material_id = te.material_id limit 1)
     from t_entrega te),
  'ENTREGUE:' || (select codigo from t_mod where ordem = 3),
  'o monitor entrega sem escolher o livro, e sai o do M3');

select is(
  (select proximo_material_id from t_entrega),
  (select material_id from t_mod where ordem = 1),
  'e o proximo passa a ser o do M1');

select * from finish();
rollback;
