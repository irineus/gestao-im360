-- =============================================================================
-- Catálogo curricular — card 4.1
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Obrigação do §13 para card de "Migração de schema": a suíte de catálogo (010 e
-- 011) verde com as tabelas novas incluídas — o que elas fazem sozinhas, porque
-- derivam a lista do catálogo do Postgres — MAIS um teste por `check`/`unique`
-- que expresse regra de negócio. Este arquivo é a segunda metade.
--
-- As três regras que moram em constraint e que, quebradas, só apareceriam meses
-- depois:
--   * `material_codigo_uk (unidade_id, metodo_id, codigo)` — código de material é
--     único POR MÉTODO. Escrita por engano como (unidade_id, codigo), a unique
--     passa em qualquer teste de caminho feliz e só falha na importação do card
--     9.1, com erro de chave duplicada que ninguém liga a uma decisão de
--     modelagem.
--   * `curso_material_ordem_uk … deferrable initially deferred` — reordenar é UM
--     update que troca as ordens entre si. Sem o deferrable a mesma tela precisa
--     de duas escritas e de um estado inválido no meio.
--   * `metodo.codigo in (…)` — os três métodos são enumeração fixa do produto, e
--     os parâmetros `ritmo_padrao_dias_<METODO>` do seed do card 3.6 são escritos
--     sobre eles.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(27);

-- ===========================================================================
-- 1. Os três métodos — configuração, não catálogo de planilha
-- ===========================================================================
-- A migração do card 4.1 grava `metodo` e mais nada: material, curso, módulo e
-- combo nascem VAZIOS em produção e só recebem dado pelo importador do card 9.1
-- (decisão de 02/09/2026). Quem impede o contrário é o portão do card 4.0,5;
-- aqui se assere o lado positivo — as três linhas EXISTEM na unidade real.
select is(
  (select string_agg(codigo, ',' order by codigo) from public.metodo
    where unidade_id = (select id from public.unidade where codigo = 'MATRIZ')),
  'INGLES,INTERATIVO,MODULAR',
  'a unidade real tem exatamente os tres metodos do produto');

-- Mesma prova de fonte única que o teste 001 faz para as permissões: fixture e
-- unidade real chamam `public.fn_seed_metodos()`, então os conjuntos são
-- idênticos. Um método declarado à parte no seed.sql seria uma segunda
-- enumeração, livre para divergir sem que nada acuse.
select is(
  (select string_agg(codigo, ',' order by codigo) from public.metodo
    where unidade_id = tests.unidade('ESCOLA_A')),
  (select string_agg(codigo, ',' order by codigo) from public.metodo
    where unidade_id = (select id from public.unidade where codigo = 'MATRIZ')),
  'fixture e unidade real tem os mesmos metodos — uma fonte so');

-- Idempotência: a migração pode rodar de novo (e roda, em todo `db reset`).
select is(
  public.fn_seed_metodos((select id from public.unidade where codigo = 'MATRIZ')),
  0,
  'fn_seed_metodos chamada de novo nao grava nada');

-- `do nothing`, e não `do update`: a matriz do card 2.4 dá `materiais.editar`
-- sobre `metodo`, então o nome é editável na tela do card 4.4. Com `do update`,
-- a correção feita lá voltaria ao valor da migração no deploy seguinte — sem
-- erro e sem log, que é a falha que o card 3.6 corrigiu no contrato do seed.
update public.metodo set nome = 'Interativo (nome corrigido na tela)'
 where unidade_id = (select id from public.unidade where codigo = 'MATRIZ')
   and codigo = 'INTERATIVO';

select public.fn_seed_metodos((select id from public.unidade where codigo = 'MATRIZ'));

select is(
  (select nome from public.metodo
    where unidade_id = (select id from public.unidade where codigo = 'MATRIZ')
      and codigo = 'INTERATIVO'),
  'Interativo (nome corrigido na tela)',
  'reexecutar o seed NAO desfaz o nome editado na tela');

-- O `check` é o que impede um quarto método de nascer pela tela de Materiais.
select throws_ok(
  $$insert into public.metodo (unidade_id, codigo, nome)
    select id, 'PRESENCIAL', 'Presencial' from public.unidade where codigo = 'MATRIZ'$$,
  '23514',
  null,
  'metodo.codigo fora dos tres do produto e recusado pelo check');

-- ===========================================================================
-- 2. Código de material é único POR MÉTODO
-- ===========================================================================
-- A regra vem da planilha: os três catálogos reaproveitam a mesma numeração. A
-- fixture repete '01' nos três métodos de propósito — é o que faz esta asserção
-- reprovar se a unique for escrita em (unidade_id, codigo).
select is(
  (select count(*)::bigint from public.material
    where unidade_id = tests.unidade('ESCOLA_A') and codigo = '01'),
  3::bigint,
  'o mesmo codigo de material coexiste nos tres metodos');

select throws_ok(
  $$insert into public.material (unidade_id, metodo_id, codigo, nome, categoria)
    select m.unidade_id, m.id, '01', 'Duplicata no mesmo metodo', 'APOSTILA'
      from public.metodo m
     where m.unidade_id = (select id from public.unidade where codigo = 'ESCOLA_A')
       and m.codigo = 'INTERATIVO'$$,
  '23505',
  null,
  'codigo repetido DENTRO do mesmo metodo continua recusado');

-- ===========================================================================
-- 3. A cadeia combo → curso → material (entrada do card 6.2)
-- ===========================================================================
-- É esta consulta que o card 6.2 usa para gerar a trilha na matrícula. Com o
-- combo de dois cursos da fixture, ela também prova que `combo_curso.ordem`
-- ordena os cursos e `curso_material.ordem` ordena dentro de cada um.
select is(
  (select string_agg(mt.codigo, ',' order by cc.ordem, cm.ordem)
     from public.combo          cb
     join public.combo_curso    cc on cc.combo_id = cb.id
     join public.curso_material cm on cm.curso_id = cc.curso_id
     join public.material       mt on mt.id       = cm.material_id
    where cb.unidade_id = tests.unidade('ESCOLA_A')
      and cb.nome = 'Informática Completo'),
  '01,02,03',
  'o combo devolve a trilha na ordem: curso 1 inteiro, depois curso 2');

-- No Modular o livro é único e o que avança é o módulo (card 7.2). Uma fixture
-- com um módulo por material não exercitaria isso.
select is(
  (select count(distinct mo.material_id)::bigint
     from public.modulo mo where mo.unidade_id = tests.unidade('ESCOLA_A')),
  1::bigint,
  'os tres modulos do Modular apontam para o MESMO livro');

-- ===========================================================================
-- 4. `deferrable initially deferred` — reordenar em UM update
-- ===========================================================================
-- ⚠️ MEDIDO AQUI, e derruba a primeira versão deste teste: `set constraints …
-- IMMEDIATE` numa constraint DEFERRABLE **não** volta à checagem linha a linha —
-- ela passa a valer no fim do COMANDO. Ou seja, a troca em um único update
-- sobrevive nos dois modos, e uma contraprova escrita com `immediate` mostraria
-- "não lançou exceção" e não provaria nada. O que separa o mundo do card 2.1 do
-- mundo sem ele é DEFERRABLE × NOT DEFERRABLE, e é esse o contraste abaixo: a
-- mesma troca, na mesma forma de tabela, com a unique NOT DEFERRABLE.
create temporary table t_ordem_estrita (
  curso_id integer not null,
  ordem    integer not null,
  constraint t_ordem_estrita_uk unique (curso_id, ordem)   -- NOT DEFERRABLE
);
insert into t_ordem_estrita values (1, 1), (1, 2);

select throws_ok(
  $$update t_ordem_estrita set ordem = 3 - ordem where curso_id = 1$$,
  '23505',
  null,
  'a MESMA troca, com a unique NOT DEFERRABLE, morre no meio do update');

-- É a decisão (e) do card 2.1, e é o contraste com a asserção acima que lhe dá
-- sentido. O que torna a checagem adiada verificável é o `set constraints …
-- immediate` logo abaixo: dentro de begin/rollback o COMMIT nunca acontece,
-- então ela só é exercitada se alguém a forçar.
select lives_ok(
  $$update public.curso_material set ordem = 3 - ordem
     where curso_id = (select c.id from public.curso c
                        where c.unidade_id = (select id from public.unidade where codigo = 'ESCOLA_A')
                          and c.nome = 'Informática Essencial')$$,
  'reordenar a sequencia do curso e UM update, sem valor temporario');

-- O que o `initially deferred` compra ALÉM do `deferrable`: a tabela pode ficar
-- inválida ENTRE comandos da mesma transação. É o que permite à tela do card 4.4
-- gravar uma reordenação em etapas sem inventar ordem temporária.
select lives_ok(
  $$update public.curso_material set ordem = 1
     where material_id = (select mt.id from public.material mt
                            join public.metodo me on me.id = mt.metodo_id
                           where mt.unidade_id = (select id from public.unidade where codigo = 'ESCOLA_A')
                             and me.codigo = 'INTERATIVO' and mt.codigo = '01')$$,
  'a primeira metade de uma reordenacao em etapas deixa duas linhas na ordem 1, e a transacao segue');

select lives_ok(
  $$update public.curso_material set ordem = 2
     where material_id = (select mt.id from public.material mt
                            join public.metodo me on me.id = mt.metodo_id
                           where mt.unidade_id = (select id from public.unidade where codigo = 'ESCOLA_A')
                             and me.codigo = 'INTERATIVO' and mt.codigo = '02')$$,
  'a segunda metade repara o estado');

select lives_ok(
  $$set constraints curso_material_ordem_uk immediate$$,
  'e o estado final e valido — a checagem adiada roda e aprova');

-- Com a constraint agora imediata, o par (curso, ordem) volta a ser recusado na
-- hora: o deferrable adia a checagem, não a dispensa.
select throws_ok(
  $$update public.curso_material set ordem = 1
     where curso_id = (select c.id from public.curso c
                        where c.unidade_id = (select id from public.unidade where codigo = 'ESCOLA_A')
                          and c.nome = 'Informática Essencial')$$,
  '23505',
  null,
  'duas apostilas na mesma ordem do mesmo curso continuam recusadas');

select throws_ok(
  $$insert into public.curso_material (unidade_id, curso_id, material_id, ordem)
    select c.unidade_id, c.id, mt.id, 0
      from public.curso c
      join public.metodo   me on me.unidade_id = c.unidade_id and me.codigo = 'INTERATIVO'
      join public.material mt on mt.unidade_id = c.unidade_id and mt.metodo_id = me.id
                             and mt.codigo = '03'
     where c.unidade_id = (select id from public.unidade where codigo = 'ESCOLA_A')
       and c.nome = 'Informática Essencial'$$,
  '23514',
  null,
  'ordem zero e recusada pelo check (a sequencia comeca em 1)');

-- ===========================================================================
-- 5. RLS — paridade, silêncio e isolamento (card 2.8 §6.3)
-- ===========================================================================
-- `materiais.ler` é permissão dos QUATRO perfis, e não por generosidade: cinco
-- das dez views do card 2.3 fazem join INTERNO em metodo/curso/modulo e, com
-- `security_invoker`, quem não lê o catálogo recebe zero linhas — a grade
-- semanal e o dashboard aparecem VAZIOS, não errados.
select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'), 'select id from public.material'),
  6::bigint,
  'direcao le os seis materiais (a contagem de referencia da paridade e > 0)');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select id from public.material') as n
       from (values ('direcao@escola-a.test'), ('pedagogico@escola-a.test'),
                    ('secretaria@escola-a.test'), ('monitor@escola-a.test')) as u(e)
   ) t)::bigint,
  1::bigint,
  'paridade: os quatro perfis com materiais.ler leem a MESMA contagem');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'), 'select id from public.material'),
  0::bigint,
  'quem nao tem materiais.ler le zero — a RLS reduz em silencio, nao acusa');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   format('select id from public.material where unidade_id = %L',
                          tests.unidade('ESCOLA_A'))),
  0::bigint,
  'a unidade B nao ve material nenhum da unidade A');

-- ===========================================================================
-- 6. Escrita: quem pode e quem não pode
-- ===========================================================================
-- O par negativo/positivo é o que dá sentido ao negativo: um insert que falha
-- para todo mundo (por FK errada, por coluna faltando) passaria no throws_ok
-- sozinho e provaria coisa nenhuma.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select is(
  (select count(*)::bigint from public.metodo),
  3::bigint,
  'o monitor enxerga os tres metodos — materiais.ler e de todos os perfis');

select throws_ok(
  $$insert into public.material (unidade_id, metodo_id, codigo, nome, categoria)
    select public.fn_unidade_atual(), m.id, 'ZZ', 'Nao deve entrar', 'APOSTILA'
      from public.metodo m
     where m.unidade_id = public.fn_unidade_atual() and m.codigo = 'INTERATIVO'$$,
  '42501',
  null,
  'o monitor nao tem materiais.criar: o insert e barrado pela politica');

reset role;
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$insert into public.material (unidade_id, metodo_id, codigo, nome, categoria)
    select public.fn_unidade_atual(), m.id, 'ZZ', 'Cadastrada pela secretaria', 'APOSTILA'
      from public.metodo m
     where m.unidade_id = public.fn_unidade_atual() and m.codigo = 'INTERATIVO'$$,
  'a secretaria tem materiais.criar e cadastra material — a contraprova do negativo acima');

reset role;
select tests.encerrar_sessao();

-- ===========================================================================
-- 7. Coerência de método na composição (pendência 9.11, fechada no card 6.1)
-- ===========================================================================
-- ⚠️ Esta seção nasceu em 04/09/2026, com o card **6.1**, e a nota daquele card
--    a manda para cá de propósito: as três tabelas são deste arquivo, e o
--    trigger é que veio depois.
--
-- O buraco que ela fecha: nada no banco impedia `curso_material`, `modulo` e
-- `combo_curso` de CRUZAREM métodos. A tela do card 4.4 filtra os candidatos
-- pelo método do pai, mas **tela não é regra** (card 2.6, decisão 2) e um `POST`
-- direto no PostgREST passava. O resultado não seria um erro: seria uma trilha
-- coerente para o banco e absurda para a escola — o aluno de Informática com
-- English Book 2 como próximo livro, `METODO_INCOMPATIVEL` nunca disparando
-- (ele compara o método do ALUNO com o da TURMA) e a projeção do card 8.1
-- pedindo a compra da apostila errada, cada peça funcionando como escrita.
select is(
  tests.codigo_do_erro(
    $$insert into public.curso_material (unidade_id, curso_id, material_id, ordem)
      select public.fn_unidade_atual(), c.id, m.id, 9
        from public.curso c, public.material m, public.metodo mi
       where c.unidade_id = public.fn_unidade_atual() and c.nome = 'Informática Essencial'
         and mi.unidade_id = public.fn_unidade_atual() and mi.codigo = 'INGLES'
         and m.unidade_id = public.fn_unidade_atual() and m.metodo_id = mi.id
         and m.codigo = '02'$$,
    tests.uid('direcao@escola-a.test')),
  'COMPOSICAO_METODO_DIVERGENTE',
  'apostila de Ingles na sequencia de um curso Interativo e recusada');

select is(
  tests.codigo_do_erro(
    $$insert into public.modulo (unidade_id, curso_id, material_id, nome, ordem)
      select public.fn_unidade_atual(), c.id, m.id, 'Modulo fora do metodo', 9
        from public.curso c, public.material m, public.metodo mi
       where c.unidade_id = public.fn_unidade_atual() and c.nome = 'Informática Essencial'
         and mi.unidade_id = public.fn_unidade_atual() and mi.codigo = 'MODULAR'
         and m.unidade_id = public.fn_unidade_atual() and m.metodo_id = mi.id
         and m.codigo = '01'$$,
    tests.uid('direcao@escola-a.test')),
  'COMPOSICAO_METODO_DIVERGENTE',
  'modulo apontando para material de outro metodo tambem e recusado');

select is(
  tests.codigo_do_erro(
    $$insert into public.combo_curso (unidade_id, combo_id, curso_id, ordem)
      select public.fn_unidade_atual(), cb.id, c.id, 9
        from public.combo cb, public.curso c
       where cb.unidade_id = public.fn_unidade_atual() and cb.nome = 'Informática Completo'
         and c.unidade_id = public.fn_unidade_atual() and c.nome = 'Inglês Kids'$$,
    tests.uid('direcao@escola-a.test')),
  'COMPOSICAO_METODO_DIVERGENTE',
  'curso de Ingles dentro de um combo Interativo e recusado');

-- CONTRAPROVA, e sem ela as três acima passariam com um trigger que recusa
-- TUDO: a composição coerente continua entrando. É a mesma exigência que o §13
-- faz a todo negativo — um insert que falha para todo mundo prova coisa nenhuma.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select lives_ok(
  $$insert into public.curso_material (unidade_id, curso_id, material_id, ordem)
    select public.fn_unidade_atual(), c.id, m.id, 9
      from public.curso c, public.material m, public.metodo mi
     where c.unidade_id = public.fn_unidade_atual() and c.nome = 'Informática Avançada'
       and mi.unidade_id = public.fn_unidade_atual() and mi.codigo = 'INTERATIVO'
       and m.unidade_id = public.fn_unidade_atual() and m.metodo_id = mi.id
       and m.codigo = '01'$$,
  'a composicao do MESMO metodo continua entrando — a guarda nao fecha a porta inteira');

reset role;
select tests.encerrar_sessao();

select * from finish();
rollback;
