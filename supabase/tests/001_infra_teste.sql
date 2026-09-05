-- =============================================================================
-- Suíte da infraestrutura de teste — card 3.4.5
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Testa o que TODOS os outros arquivos de teste passam a depender: os helpers
-- tests.* e a escola-fixture do card 2.8 §4.2. Um helper quebrado não reprova
-- uma suíte — ele a deixa VERDE testando outra coisa, que é o modo de falha que
-- o card 2.8 §4 descreve. Daí esta suíte existir.
--
-- A primeira asserção é o portão que impede a fixture de ficar para trás do
-- schema: se uma camada declarada em tests.fixture_camada já é devida (a tabela
-- que ela povoa passou a existir) e ninguém a escreveu, aqui fica vermelho.
--
-- Roda como `postgres`, com begin/rollback: nada do que este arquivo escrever
-- sobrevive para o próximo.
-- =============================================================================

begin;
select plan(30);

-- ===========================================================================
-- 1. O portão: a fixture está em dia com o schema?
-- ===========================================================================
select is(
  (select string_agg(camada || ' (card ' || card || ')', ', ' order by camada)
     from tests.fixture_camadas_devidas()),
  null,
  'nenhuma camada da fixture esta devida — se falhar, a mensagem diz qual camada e de que card');

select ok(
  (select count(*) from tests.fixture_camada) >= 7,
  'as camadas futuras continuam DECLARADAS: apagar a linha e o portao some junto');

-- ===========================================================================
-- 2. Camada `acesso` — o conteúdo que o card 2.8 §4.2 pede
-- ===========================================================================
-- Três unidades, e a terceira não é da fixture: MATRIZ vem da MIGRAÇÃO do card
-- 3.6 e existe em todo ambiente, inclusive neste. Asserir isso aqui é barato e
-- pega de graça o dia em que alguém acrescentar unidade ao seed de produção.
select is(
  (select string_agg(codigo, ',' order by codigo) from public.unidade),
  'ESCOLA_A,ESCOLA_B,MATRIZ',
  'duas unidades de fixture (a segunda prova isolamento) mais a unidade real do seed');

select is(
  (select count(*)::bigint from public.perfil where unidade_id = tests.unidade('ESCOLA_A')),
  5::bigint,
  'cinco perfis em A: os quatro do plano mais ARQUIVADO, desativado');

select is(
  (select count(*)::bigint from public.perfil
    where unidade_id = tests.unidade('ESCOLA_A') and not ativo),
  1::bigint,
  'exatamente um perfil desativado — e o que prova o filtro perfil.ativo');

-- A fixture NÃO tem catálogo próprio desde o card 3.6: as duas unidades chamam
-- public.fn_seed_acesso(), a mesma função da migração. Um catálogo escrito aqui
-- seria uma segunda fonte da verdade, e o teste de paridade do card 2.8 §6.3
-- compararia a tela real contra ela e passaria.
select is(
  (select count(*)::bigint from public.permissao where unidade_id = tests.unidade('ESCOLA_A')),
  50::bigint,
  'catalogo completo do card 2.4 §3 mais o 50º código do card 2.9');

select is(
  (select count(*)::bigint from public.permissao
    where unidade_id = tests.unidade('ESCOLA_B')),
  50::bigint,
  'a segunda unidade recebe o MESMO catalogo — isolamento comparavel, nao assimetrico');

-- Prova de fonte única: o conjunto de códigos da fixture é IDÊNTICO ao da
-- unidade real. Contagem igual com códigos diferentes passaria; esta não.
select is(
  (select string_agg(codigo, ',' order by codigo) from public.permissao
    where unidade_id = tests.unidade('ESCOLA_A')),
  (select string_agg(codigo, ',' order by codigo) from public.permissao
    where unidade_id = (select id from public.unidade where codigo = 'MATRIZ')),
  'fixture e unidade real tem exatamente os mesmos codigos — uma fonte so');

select is(
  (select count(*)::bigint from public.perfil_permissao pp
     join public.perfil pe on pe.id = pp.perfil_id
    where pe.unidade_id = tests.unidade('ESCOLA_A') and pe.codigo = 'DIRECAO'),
  50::bigint,
  'direcao de A tem os 50 codigos (matriz de docs/permissoes-matriz.md §5)');

select is(
  (select count(*)::bigint from public.perfil_permissao pp
     join public.perfil pe on pe.id = pp.perfil_id
    where pe.unidade_id = tests.unidade('ESCOLA_A') and pe.codigo = 'MONITOR'),
  14::bigint,
  'monitor tem os 13 codigos do card 2.4 §5 mais salas.acessar_credencial (card 2.9)');

select is(
  (select count(*)::bigint from public.usuario where unidade_id = tests.unidade('ESCOLA_A')),
  7::bigint,
  'sete usuarios em A: um por perfil, um sem perfil, um desativado, um de perfil arquivado');

select is(
  (select count(*)::bigint from public.usuario where unidade_id = tests.unidade('ESCOLA_B')),
  1::bigint,
  'um usuario na unidade B');

select is(
  (select count(*)::bigint from public.usuario_perfil
    where usuario_id = tests.uid('semperfil@escola-a.test')),
  0::bigint,
  'o usuario sem perfil nao tem perfil nenhum — e o teste de "sem politica, sem acesso"');

select ok(
  not (select ativo from public.usuario where id = tests.uid('desativado@escola-a.test')),
  'o usuario desativado esta desativado, com o perfil de direcao intacto');

-- ===========================================================================
-- 3. Helpers de identidade
-- ===========================================================================
select isnt(tests.uid('direcao@escola-a.test'), null::uuid,
  'tests.uid resolve o usuario pela chave natural (e-mail)');

select isnt(tests.unidade('ESCOLA_A'), null::uuid,
  'tests.unidade resolve a unidade pelo codigo — nenhum UUID literal em teste nenhum');

select tests.autenticar(tests.uid('monitor@escola-a.test'));

select is(current_user::text, 'authenticated',
  'tests.autenticar deixa a sessao no papel authenticated DEPOIS de retornar');

-- Daqui até o `reset role` a sessão é o monitor, e `tests.*` está fora de
-- alcance de propósito — por isso a comparação é feita com SQL puro. Ela vale
-- dobrado: só existe resposta porque a política de `select` de `usuario` ganhou
-- `or id = auth.uid()` no card 3.4.
select is(auth.uid(), (select id from public.usuario where email = 'monitor@escola-a.test'),
  'as claims sao as do usuario pedido — e isso que o PostgREST monta');

-- `(select id from public.unidade)` devolve uma linha só porque a sessão está
-- autenticada e a RLS já reduziu as três unidades à do monitor. Rodar isto como
-- `postgres` daria "more than one row" — e seria o teste avisando que a
-- comparação perdeu o sentido.
select is(public.fn_unidade_atual(), (select id from public.unidade),
  'fn_unidade_atual enxerga a unidade do usuario autenticado pelo helper');

-- Trocar de usuário exige voltar a postgres: `authenticated` não tem USAGE no
-- schema tests, de propósito. Esquecer esta linha dá "permission denied for
-- schema tests" — erro alto, não silêncio.
reset role;

select is(current_user::text, 'postgres',
  'reset role devolve a sessao ao papel que monta a fixture');

select tests.como_anonimo();

select is((select count(*)::bigint from public.unidade), 0::bigint,
  'tests.como_anonimo nao le nada — toda politica e `to authenticated`');

reset role;
select tests.encerrar_sessao();

select is(auth.uid(), null::uuid,
  'tests.encerrar_sessao limpa as claims — nenhuma identidade vaza para o proximo teste');

-- ===========================================================================
-- 4. tests.conta_como — a base do teste de paridade (card 2.8 §6.3)
-- ===========================================================================
-- Paridade: os quatro perfis autorizados leem A MESMA contagem, e a da direção
-- é garantidamente > 0. Paridade de zero contra zero passa sempre e não prova
-- nada — daí a asserção separada de que a contagem da direção não é zero.
select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'), 'select id from public.unidade'),
  1::bigint,
  'direcao le a propria unidade (e a contagem de referencia da paridade e > 0)');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select id from public.unidade') as n
       from (values ('direcao@escola-a.test'), ('pedagogico@escola-a.test'),
                    ('secretaria@escola-a.test'), ('monitor@escola-a.test')) as u(e)
   ) t)::bigint,
  1::bigint,
  'paridade: os quatro perfis com unidades.ler leem a MESMA contagem');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'), 'select id from public.unidade'),
  0::bigint,
  'quem nao tem unidades.ler le zero — a RLS reduz em silencio, nao acusa');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select id from public.unidade where codigo = ''ESCOLA_A'''),
  0::bigint,
  'a segunda unidade nao ve nada da primeira');

-- ===========================================================================
-- 5. tests.como_rotina e tests.codigo_do_erro
-- ===========================================================================
select tests.como_rotina(tests.unidade('ESCOLA_A'));

select ok(public.tem_permissao('codigo.que_nao_existe'),
  'em contexto de rotina tem_permissao e sempre verdadeira (card 2.2 §2.2)');

select tests.encerrar_sessao();

select is(
  tests.codigo_do_erro($$ select public.fn_param_int('chave_inexistente') $$,
                       tests.uid('monitor@escola-a.test')),
  'PARAMETRO_AUSENTE',
  'tests.codigo_do_erro devolve o codigo estavel do DETAIL, na pele do usuario pedido');

-- ===========================================================================
-- 6. tests.criar_usuario é idempotente
-- ===========================================================================
-- Reexecutar o seed não pode duplicar usuário: `usuario.email` é unique, então
-- um helper não idempotente derrubaria o `db reset` de quem rodasse duas vezes.
select is(
  tests.criar_usuario('direcao@escola-a.test', 'DIRECAO'),
  tests.uid('direcao@escola-a.test'),
  'tests.criar_usuario chamado de novo devolve o mesmo id, sem duplicar');

-- ===========================================================================
-- 7. O portão reprova mesmo? (prova por construção)
-- ===========================================================================
-- Portão que nunca foi visto vermelho é decoração — é a crítica que o card 2.8
-- faz à suíte que existe e não reprova nada. Aqui a tabela que torna a próxima
-- camada devida é criada dentro da própria transação, e some no rollback junto
-- com o resto.
--
-- A sentinela era `public.material` até o card 4.1, `public.aluno` até o 4.2,
-- `public.pc` até o 4.3, `public.bloco_aluno` até o 5.1, `public.movimento_estoque`
-- até o 6.1 e `public.turma_modular_aluno` até o **7.1**; de lá em diante essas
-- tabelas EXISTEM, o `create table` morreria com "already exists" e a asserção
-- deixaria de dizer o que promete. A sentinela acompanha a fronteira: agora é
-- `public.certificado_checklist`, a tabela da camada `certificados` (card 8.3),
-- que é a última declarada.
--
-- ⚠️ E cada troca seguiu à risca a instrução que este comentário já trazia —
--    «quando ela for aplicada, esta asserção precisa de uma camada NOVA para
--    vigiar, e não de uma sentinela nova». O card 6.1 aplicou `trilha_estoque` e
--    declarou `modular` no mesmo commit; o **7.1** aplicou `modular` e declarou
--    `certificados` no mesmo commit. Sem a camada nova, o portão ficaria sem
--    sentinela e esta prova por construção viraria decoração — que é a crítica
--    que o card 2.8 faz à suíte que existe e não reprova nada.
create table public.certificado_checklist (id uuid primary key);

select is(
  (select string_agg(camada, ',' order by camada) from tests.fixture_camadas_devidas()),
  'certificados',
  'criada a tabela que a camada povoa, o portao acusa a camada que ficou para tras');

drop table public.certificado_checklist;

select * from finish();
rollback;
