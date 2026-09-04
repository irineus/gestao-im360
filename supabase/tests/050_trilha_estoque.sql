-- =============================================================================
-- Trilha do aluno e estoque — card 6.1
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Card de "Schema", então o §13 cobra duas listas: suíte de catálogo verde com
-- as tabelas novas (010 e 011 fazem sozinhas, derivando do catálogo do Postgres)
-- e um teste por check/unique que expresse regra de negócio.
--
-- Fora dessas duas, o arquivo prova as quatro coisas que este card decidiu e que
-- nenhum catálogo enxerga:
--   • a imutabilidade de `movimento_estoque` tem DUAS camadas independentes, e a
--     segunda existe porque a primeira não alcança quem tem BYPASSRLS — que no
--     Supabase é `postgres` e `service_role` (achado do card 3.3);
--   • o insert de `movimento_estoque` é POR TIPO, e não por um `estoque.criar`
--     genérico: o monitor grava SAIDA e não grava ENTRADA. Sem isso ele podia
--     inventar 500 exemplares pelo PostgREST (achado 9 do card 2.4 §7);
--   • o `or` da política de update de `aluno_material` existe para a ENTREGA do
--     monitor e vaza todas as outras colunas, porque RLS não é por coluna —
--     e aqui, ao contrário do card 5.1, o perfil que expõe a folga JÁ EXISTE na
--     matriz inicial;
--   • as duas guardas de exclusão da família do card 4.3: item de trilha já
--     entregue e item de pedido que saiu do rascunho.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(37);

-- ===========================================================================
-- 1. A fixture chegou (camada `trilha_estoque` do card 3.4.5)
-- ===========================================================================
-- O quadro do card 2.8 §4.2 pede seis materiais com saldos "0, 0, 1, n, n, n", e
-- os saldos são DERIVADOS: cada um é a soma dos movimentos que o produziram.
-- Asserir a soma, e não uma coluna, é o que faz este teste medir a decisão do
-- projeto (estoque atual nunca é coluna) em vez de medir o seed.
select is(
  (select string_agg(saldo::text, ',' order by metodo, codigo) from (
     select me.codigo as metodo, m.codigo,
            coalesce(sum(mv.quantidade), 0) as saldo
       from public.material m
       join public.metodo me on me.id = m.metodo_id
       left join public.movimento_estoque mv on mv.material_id = m.id
      where m.unidade_id = tests.unidade('ESCOLA_A')
      group by me.codigo, m.codigo) s),
  '10,0,20,0,1,10',
  'os seis materiais tem os saldos 0/0/1/n/n/n do card 2.8 §4.2, somados dos movimentos');

-- O saldo 1 só é o teste de concorrência do card 6.3 se o último exemplar for o
-- PRÓXIMO de mais de uma pessoa. Com um aluno só, as duas sessões da corrida
-- disputariam coisas diferentes e a suíte passaria sem nunca ter corrido.
select is(
  (select count(*)::bigint
     from public.aluno a
     join lateral (select am.material_id from public.aluno_material am
                    where am.aluno_id = a.id and not am.entregue
                    order by am.ordem limit 1) prox on true
     join public.material m on m.id = prox.material_id
     join public.metodo me on me.id = m.metodo_id
    where a.unidade_id = tests.unidade('ESCOLA_A')
      and me.codigo = 'INTERATIVO' and m.codigo = '03'),
  2::bigint,
  'o material de saldo 1 e o PROXIMO de dois alunos — o cenario da corrida do card 6.3');

-- O "1 em FIM" do quadro §4.2, que era a última marca sem casa: FIM é NENHUMA
-- linha pendente, e não uma coluna de status.
select is(
  (select count(*)::bigint from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A')
      and a.nome = 'João Pedro Martins' and not am.entregue),
  0::bigint,
  'Joao Pedro esta em FIM — nenhum item pendente na trilha');

-- Karina não tem combo, então não tem trilha. É o caso que a pendência do card
-- 6.2 existe para acusar, e uma fixture em que todo aluno tem trilha o
-- esconderia.
select is(
  (select count(*)::bigint from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Karina Bastos'),
  0::bigint,
  'a aluna sem combo nao tem trilha — aluno ATIVO sem trilha e um caso, nao um esquecimento');

select is(
  (select string_agg(status, ',' order by numero) from public.pedido_compra
    where unidade_id = tests.unidade('ESCOLA_A')),
  'RECEBIDO,ENVIADO,RASCUNHO',
  'um pedido por estado que muda alguma conta: RECEBIDO, ENVIADO e RASCUNHO');

-- O vínculo compra ↔ estoque, que a planilha não tinha: lá a chegada do pedido e
-- a entrada em estoque eram duas anotações sem ligação nenhuma.
select is(
  (select count(*)::bigint from public.movimento_estoque mv
     join public.pedido_item pi on pi.id = mv.pedido_item_id
     join public.pedido_compra pc on pc.id = pi.pedido_id
    where mv.unidade_id = tests.unidade('ESCOLA_A') and pc.numero = '2026-001'),
  1::bigint,
  'a ENTRADA do pedido recebido aponta para o item que a originou');

-- Os quatro tipos: ENTRADA e SAIDA sozinhas deixariam movimento_sinal_ck,
-- movimento_estorno_ck e movimento_estorno_uk sem uma linha sequer para vigiar.
select is(
  (select string_agg(distinct tipo, ',' order by tipo) from public.movimento_estoque
    where unidade_id = tests.unidade('ESCOLA_A')),
  'AJUSTE,ENTRADA,ESTORNO,SAIDA',
  'os quatro tipos de movimento aparecem na fixture');

-- ===========================================================================
-- 2. Os checks e uniques que exprimem regra de negócio
-- ===========================================================================
-- Escreve como `postgres`, sem sessão: nenhum trigger BEFORE INSERT destas
-- tabelas exige permissão, então aqui a camada 1 é medida sozinha — o cuidado
-- que o card 5.3 obrigou a ter no teste 040 não se aplica a este arquivo, e vale
-- dizer por quê em vez de repetir o ritual.

-- `entregue` e `data_entrega` andam juntos: um dos dois sozinho é uma entrega
-- sem dia ou um dia sem entrega, e as duas metades mentem para a projeção do
-- card 8.1, que mede INTERVALO entre entregas.
select throws_ok(
  $$insert into public.aluno_material (unidade_id, aluno_id, material_id, ordem, entregue)
    select tests.unidade('ESCOLA_A'), a.id, m.id, 90, true
      from public.aluno a, public.material m, public.metodo me
     where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Carla Menezes'
       and me.unidade_id = tests.unidade('ESCOLA_A') and me.codigo = 'MODULAR'
       and m.unidade_id = tests.unidade('ESCOLA_A') and m.metodo_id = me.id
       and m.codigo = '01'$$,
  '23514', null,
  'entregue = true sem data_entrega e recusado pelo check');

-- A mesma apostila duas vezes na trilha do mesmo aluno seria contada duas vezes
-- pela demanda imediata do card 6.4 — e o pedido sugerido pediria o dobro.
select throws_ok(
  $$insert into public.aluno_material (unidade_id, aluno_id, material_id, ordem)
    select am.unidade_id, am.aluno_id, am.material_id, 91
      from public.aluno_material am
      join public.aluno a on a.id = am.aluno_id
     where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Carla Menezes'
     order by am.ordem limit 1$$,
  '23505', null,
  'a mesma apostila duas vezes na trilha do mesmo aluno e recusada');

-- ENTRADA com quantidade negativa passaria despercebida no saldo (a soma é
-- simples) e viraria uma "compra" que reduz o estoque.
select throws_ok(
  $$insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade)
    select tests.unidade('ESCOLA_A'), m.id, 'ENTRADA', -5
      from public.material m, public.metodo me
     where me.unidade_id = tests.unidade('ESCOLA_A') and me.codigo = 'INTERATIVO'
       and m.unidade_id = tests.unidade('ESCOLA_A') and m.metodo_id = me.id
       and m.codigo = '01'$$,
  '23514', null,
  'ENTRADA com quantidade negativa e recusada por movimento_sinal_ck');

-- "ESTORNO ⟺ estorno_de_id" é uma equivalência, e as duas direções importam: um
-- ESTORNO sem origem é um crédito de estoque sem causa.
select throws_ok(
  $$insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade)
    select tests.unidade('ESCOLA_A'), m.id, 'ESTORNO', 1
      from public.material m, public.metodo me
     where me.unidade_id = tests.unidade('ESCOLA_A') and me.codigo = 'INTERATIVO'
       and m.unidade_id = tests.unidade('ESCOLA_A') and m.metodo_id = me.id
       and m.codigo = '01'$$,
  '23514', null,
  'ESTORNO sem estorno_de_id e recusado por movimento_estorno_ck');

-- E a outra direção: movimento comum não pode carregar `estorno_de_id`.
select throws_ok(
  $$insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade, estorno_de_id)
    select mv.unidade_id, mv.material_id, 'AJUSTE', 1, mv.id
      from public.movimento_estoque mv
     where mv.unidade_id = tests.unidade('ESCOLA_A') and mv.tipo = 'SAIDA'
     order by mv.ocorrido_em limit 1$$,
  '23514', null,
  'e movimento que nao e ESTORNO nao pode apontar para um estornado');

-- Dois estornos do mesmo movimento devolveriam o dobro ao saldo, e cada um deles
-- pareceria certo sozinho — é o modo de falha que a unique parcial fecha.
select throws_ok(
  $$insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade,
                                          estorno_de_id)
    select mv.unidade_id, mv.material_id, 'ESTORNO', 1, mv.estorno_de_id
      from public.movimento_estoque mv
     where mv.unidade_id = tests.unidade('ESCOLA_A') and mv.tipo = 'ESTORNO'$$,
  '23505', null,
  'um movimento so se estorna UMA vez — a unique parcial de estorno_de_id');

-- ⚠️ Era um `23514` de `pedido_item_recebido_ck` até o card 6.5, e a mudança é
-- decisão registrada, não regressão: `check` não conhece permissão, então ele
-- valia igual para a direção e tornava `compras.receber_excedente` (card 2.4
-- §5.2) INALCANÇÁVEL — com `RECEBIMENTO_EXCEDE_PEDIDO`, que está no contrato de
-- erros desde o card 2.2 §12, sem nenhum caminho até a tela. A regra virou
-- `tg_pedido_item_recebimento`, que é MAIS forte (alcança BYPASSRLS igual, e
-- ainda distingue quem pode) e devolve o código do catálogo em vez do erro cru
-- que o card 2.2 §1.2 proíbe. Aqui a sessão é `postgres` sem auth.uid(), então
-- tem_permissao é falsa e a recusa acontece.
select throws_ok(
  $$update public.pedido_item set qtd_recebida = qtd_pedida + 1
     where unidade_id = tests.unidade('ESCOLA_A')
       and pedido_id = (select id from public.pedido_compra
                         where unidade_id = tests.unidade('ESCOLA_A')
                           and numero = '2026-002')
       and material_id = (select m.id from public.material m
                            join public.metodo me on me.id = m.metodo_id
                           where m.unidade_id = tests.unidade('ESCOLA_A')
                             and me.codigo = 'INTERATIVO' and m.codigo = '02')$$,
  'PT422', null,
  'receber mais do que foi pedido e recusado — e a excecao e PERMISSAO, medida no 060');

-- ===========================================================================
-- 3. `deferrable initially deferred` — reordenar em UM update
-- ===========================================================================
-- Mesma decisão (e) do card 2.1 que o teste 023 já mede em `curso_material`, e o
-- que a torna necessária aqui é o reordenamento por falta de estoque do card 6.3:
-- ele troca posições dentro da transação da entrega. Sem o adiamento, a troca
-- precisaria de um valor temporário — e um valor temporário numa coluna com
-- unique é um estado inválido que sobrevive a qualquer falha no meio.
--
-- ⚠️ A troca roda como a SECRETARIA e não como `postgres`, e não é detalhe: o
--    trigger da seção 9 da migração exige `alunos.editar_trilha` para mexer em
--    `ordem`, então esta asserção é também a contraprova positiva da guarda —
--    quem tem a permissão continua reordenando.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

--
-- ⚠️ As ordens são 10 e 20, e não 1 e 2, desde o card 6.2: a trilha da fixture
--    passou a nascer de `fn_trilha_gerar`, que numera de 10 em 10 (§5.1, passo 4)
--    para deixar espaço à inserção manual.
select lives_ok(
  $$update public.aluno_material set ordem = 30 - ordem
     where aluno_id = (select id from public.aluno
                        where nome = 'Carla Menezes'
                          and unidade_id = public.fn_unidade_atual())
       and ordem in (10, 20)$$,
  'trocar duas posicoes da trilha e UM update, sem valor temporario');

reset role;

-- ===========================================================================
-- 4. Imutabilidade de movimento_estoque, nas DUAS camadas
-- ===========================================================================
-- Camada 1 — ausência de política. O `update` não dá erro: ele simplesmente não
-- encontra linha nenhuma para atualizar, porque sem política de UPDATE o USING
-- não deixa passar nada. É o "sem política, sem acesso" do card 2.1, e o
-- silêncio dele é a razão de a camada 2 existir.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

update public.movimento_estoque set quantidade = -999
 where unidade_id = public.fn_unidade_atual() and tipo = 'ENTRADA';

reset role;

select is(
  (select count(*)::bigint from public.movimento_estoque
    where unidade_id = tests.unidade('ESCOLA_A') and quantidade = -999),
  0::bigint,
  'sem politica de update, o UPDATE do monitor nao muda nada — e nao levanta erro');

-- Camada 2 — o trigger, e é ele quem alcança quem a camada 1 não alcança.
-- Aqui a sessão é `postgres`, que TEM BYPASSRLS (achado do card 3.3): sem o
-- trigger, este update passaria. É também o papel do `service_role`, isto é, de
-- toda Edge Function e de todo script de manutenção.
select throws_ok(
  $$update public.movimento_estoque set quantidade = -999
     where unidade_id = tests.unidade('ESCOLA_A') and tipo = 'ENTRADA'$$,
  'PT409', null,
  'o trigger recusa o UPDATE ate para quem tem BYPASSRLS — a camada que a RLS nao cobre');

select throws_ok(
  $$delete from public.movimento_estoque
     where unidade_id = tests.unidade('ESCOLA_A') and tipo = 'ENTRADA'$$,
  'PT409', null,
  'e recusa o DELETE pela mesma razao: correcao de estoque e por estorno');

-- ===========================================================================
-- 5. O insert POR TIPO (achado 9 do card 2.4 §7)
-- ===========================================================================
-- É a política mais incomum do projeto — a única condicionada ao VALOR de uma
-- coluna —, e o par negativo/positivo é o que lhe dá sentido: um insert que
-- falha para todo mundo passaria no throws_ok sozinho.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select lives_ok(
  $$insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade, aluno_id)
    select public.fn_unidade_atual(), m.id, 'SAIDA', -1, a.id
      from public.material m
      join public.metodo me on me.id = m.metodo_id
      join public.aluno a on a.unidade_id = public.fn_unidade_atual()
                         and a.nome = 'Carla Menezes'
     where m.unidade_id = public.fn_unidade_atual()
       and me.codigo = 'INTERATIVO' and m.codigo = '01'$$,
  'o monitor grava SAIDA — e a jornada dele, e estoque.lancar_saida a autoriza');

-- A sessão continua sendo a do monitor: `throws_ok` não recebe usuário, e trocar
-- de papel entre as três asserções faria a negativa medir a permissão errada.
select throws_ok(
  $$insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade)
    select public.fn_unidade_atual(), m.id, 'ENTRADA', 500
      from public.material m
      join public.metodo me on me.id = m.metodo_id
     where m.unidade_id = public.fn_unidade_atual()
       and me.codigo = 'INTERATIVO' and m.codigo = '01'$$,
  '42501', null,
  'mas NAO grava ENTRADA: sem a politica por tipo ele inventaria 500 exemplares pelo PostgREST');

select throws_ok(
  $$insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade)
    select public.fn_unidade_atual(), m.id, 'AJUSTE', -3
      from public.material m
      join public.metodo me on me.id = m.metodo_id
     where m.unidade_id = public.fn_unidade_atual()
       and me.codigo = 'INTERATIVO' and m.codigo = '01'$$,
  '42501', null,
  'nem AJUSTE, que e o outro caminho para mexer no saldo sem entrega nenhuma');

reset role;
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade)
    select public.fn_unidade_atual(), m.id, 'ENTRADA', 500
      from public.material m
      join public.metodo me on me.id = m.metodo_id
     where m.unidade_id = public.fn_unidade_atual()
       and me.codigo = 'INTERATIVO' and m.codigo = '01'$$,
  'a secretaria, que tem compras.receber, grava a ENTRADA — a contraprova do negativo');

reset role;

-- ===========================================================================
-- 6. RLS não é por coluna — a folga do `or` no update de aluno_material
-- ===========================================================================
-- ⚠️ A diferença para o card 5.1: lá o perfil que expunha a folga precisava ser
--    MONTADO dentro da transação, porque nenhum da matriz inicial era assim.
--    Aqui ele já existe — o MONITOR tem `estoque.lancar_saida` e não tem
--    `alunos.editar_trilha` (card 2.4 §5). A folga é real desde o primeiro dia.
select is(
  tests.codigo_do_erro(
    $$update public.aluno_material set ordem = ordem + 50
       where aluno_id = (select id from public.aluno
                          where nome = 'Ana Paula Ribeiro'
                            and unidade_id = public.fn_unidade_atual())$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor NAO reordena a trilha — reordenar sem passar pelo card 6.2 nao escreveria historico');

select is(
  tests.codigo_do_erro(
    $$update public.aluno_material set material_id =
        (select m.id from public.material m
           join public.metodo me on me.id = m.metodo_id
          where m.unidade_id = public.fn_unidade_atual()
            and me.codigo = 'INGLES' and m.codigo = '01')
       where aluno_id = (select id from public.aluno
                          where nome = 'Carla Menezes'
                            and unidade_id = public.fn_unidade_atual())
         and ordem = 30$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'nem troca a apostila devida por outra, inclusive de outro metodo');

select is(
  tests.codigo_do_erro(
    $$update public.aluno_material set origem = 'MANUAL'
       where aluno_id = (select id from public.aluno
                          where nome = 'Carla Menezes'
                            and unidade_id = public.fn_unidade_atual())$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'nem tira a linha do alcance da regeneracao da trilha, mudando origem para MANUAL');

-- Contraprova: o mesmo monitor continua fazendo a ÚNICA escrita que o `or`
-- existe para permitir. Sem ela, os três negativos acima passariam mesmo que a
-- guarda estivesse barrando tudo — e a entrega do card 6.3 nasceria quebrada.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select lives_ok(
  $$update public.aluno_material
       set entregue = true, data_entrega = public.fn_hoje(),
           -- A SAIDA mais RECENTE é a que o próprio monitor gravou na seção 5;
           -- `order by` é obrigatório aqui pela lição do card 5.2 (§11 da
           -- estratégia de testes): `limit 1` sem ordem é o teste que passa hoje
           -- e morre no primeiro stack local em que o sorteio cair em outra linha.
           movimento_estoque_id = (select mv.id from public.movimento_estoque mv
                                    where mv.unidade_id = public.fn_unidade_atual()
                                      and mv.tipo = 'SAIDA'
                                    order by mv.ocorrido_em desc, mv.id limit 1)
     where aluno_id = (select id from public.aluno
                        where nome = 'Carla Menezes'
                          and unidade_id = public.fn_unidade_atual())
       and ordem = 30$$,
  'e continua registrando a ENTREGA — que e o que o `or` da politica existe para permitir');

reset role;

-- ===========================================================================
-- 7. As duas guardas de exclusão (a família do card 4.3)
-- ===========================================================================
-- 7.1 Item de trilha já entregue.
select is(
  tests.codigo_do_erro(
    $$delete from public.aluno_material
       where unidade_id = public.fn_unidade_atual() and entregue
         and aluno_id = (select id from public.aluno
                          where nome = 'Ana Paula Ribeiro'
                            and unidade_id = public.fn_unidade_atual())$$,
    tests.uid('secretaria@escola-a.test')),
  'ITEM_JA_ENTREGUE',
  'apostila entregue nao sai da trilha — o caminho e estornar a entrega (card 6.3)');

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$delete from public.aluno_material
     where unidade_id = public.fn_unidade_atual() and not entregue
       and aluno_id = (select id from public.aluno
                        where nome = 'Gabriela Souza'
                          and unidade_id = public.fn_unidade_atual())$$,
  'item PENDENTE continua removivel — a guarda nao esvazia o "remover" de alunos.editar_trilha');

reset role;

-- CONTRAPROVA: o mundo sem a guarda. O trigger cai dentro desta transação e
-- volta no rollback. Sem ele o delete passa em silêncio — a SAIDA continua lá
-- (o saldo não muda) e a trilha passa a discordar dela: a apostila some como se
-- nunca tivesse sido devida, e pode ser incluída de novo e entregue outra vez.
-- Guarda que nunca foi vista fazendo diferença é decoração.
drop trigger tg_aluno_material_exclusao_valida on public.aluno_material;

select lives_ok(
  $$delete from public.aluno_material
     where unidade_id = tests.unidade('ESCOLA_A') and entregue
       and aluno_id = (select id from public.aluno
                        where nome = 'Ana Paula Ribeiro'
                          and unidade_id = tests.unidade('ESCOLA_A'))$$,
  'sem a guarda, o item entregue some e a trilha passa a discordar do estoque');

-- 7.2 Item de pedido que saiu do rascunho.
select is(
  tests.codigo_do_erro(
    $$delete from public.pedido_item pi
       using public.pedido_compra pc
       where pc.id = pi.pedido_id and pi.unidade_id = public.fn_unidade_atual()
         and pc.numero = '2026-002'$$,
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_NAO_RASCUNHO',
  'item de pedido ENVIADO nao se remove — sumiria a parcela ja pedida do card 2.3 §6, em silencio');

select is(
  tests.codigo_do_erro(
    $$delete from public.pedido_item pi
       using public.pedido_compra pc
       where pc.id = pi.pedido_id and pi.unidade_id = public.fn_unidade_atual()
         and pc.numero = '2026-001'$$,
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_NAO_RASCUNHO',
  'nem item ja recebido, que sem a guarda morreria num 23503 cru da FK do movimento');

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$delete from public.pedido_item pi
     using public.pedido_compra pc
     where pc.id = pi.pedido_id and pi.unidade_id = public.fn_unidade_atual()
       and pc.numero = '2026-003'$$,
  'item de pedido em RASCUNHO continua removivel — o "em RASCUNHO" do card 2.4 §3.5 vira estrutura');

reset role;

-- ===========================================================================
-- 8. Isolamento entre unidades
-- ===========================================================================
-- As duas unidades receberam a MESMA trilha e o mesmo estoque, e é isso que faz
-- a asserção significar alguma coisa: uma fixture com a unidade B vazia passaria
-- mesmo com a RLS escrita sem o filtro de unidade. Daí a primeira asserção, que
-- parece óbvia e é o que impede as outras duas de serem vácuo.
--
-- E a forma é a do card 2.8 §6.3: PARIDADE de linhas, e não "não deu erro" — a
-- RLS reduz em silêncio, e a tela vazia mente.
select cmp_ok(
  (select count(*)::bigint from public.movimento_estoque
    where unidade_id = tests.unidade('ESCOLA_B')),
  '>', 0::bigint,
  'a unidade B tem movimentos — sem isso as duas asercoes seguintes passariam de graca');

select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
    $$select 1 from public.movimento_estoque$$),
  (select count(*)::bigint from public.movimento_estoque
    where unidade_id = tests.unidade('ESCOLA_A')),
  'a direcao de A ve EXATAMENTE os movimentos de A — nenhum a menos, nenhum de B');

select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
    $$select 1 from public.aluno_material$$),
  (select count(*)::bigint from public.aluno_material
    where unidade_id = tests.unidade('ESCOLA_A')),
  'e a trilha inteira da unidade A, sem nenhuma linha da unidade B');

-- ===========================================================================
-- 9. Portão dos dois triggers de movimento_estoque — DISPARADO no card 6.5
-- ===========================================================================
-- `tg_movimento_valida_sinal` (o estorno com sinal oposto e mesma magnitude do
-- movimento de origem) e `tg_movimento_resolve_pendencia` (a chegada do pedido
-- fechando ESTOQUE_ZERO e COMPRA_SEM_ESTOQUE) eram do card 6.5, e não podiam
-- nascer aqui: o primeiro dependia de fn_estornar_entrega para ter um chamador
-- real e o segundo dos dois tipos de pendência, que só o card 6.3 passa a abrir.
--
-- ✅ O card 6.5 fechou os dois em 04/09/2026, e o portão MUDOU DE LADO: até
--    aqui ele vigiava a ausência da função; agora vigia a ausência dos triggers,
--    que é o que continua podendo desaparecer numa refatoração — e a razão de o
--    portão continuar existindo é que esquecê-los não daria erro nenhum. Daria
--    um estorno de magnitude qualquer (devolvendo ao estoque mais do que saiu) e
--    uma central de pendências que continua pedindo a compra de um material que
--    já chegou: as duas com cara de sistema funcionando.
create temporary view portao_estoque (gatilho, card) as values
  ('tg_movimento_valida_sinal',      '6.5'),
  ('tg_movimento_resolve_pendencia', '6.5');

-- A condição casa pelo NOME e ignora a assinatura: um portão preso a
-- `(uuid, jsonb)` deixaria de disparar em silêncio no dia em que a função
-- mudasse de parâmetros — que é o pior desfecho possível para um portão, pior do
-- que não existir.
create temporary view portao_estoque_devido as
  select coalesce(string_agg(format('fn_pedido_receber existe (card %s) e %s nao', p.card, p.gatilho),
                             '; ' order by p.gatilho), '') as devido
    from portao_estoque p
   where exists (select 1 from pg_proc pr
                  where pr.pronamespace = 'public'::regnamespace
                    and pr.proname = 'fn_pedido_receber')
     and not exists (select 1 from pg_trigger t
                      where t.tgname = p.gatilho and not t.tgisinternal);

select is((select devido from portao_estoque_devido), '',
  'portao em dia: fn_pedido_receber existe (card 6.5) e os dois triggers dela tambem');

-- Prova por construção, dentro da transação: portão que nunca foi visto vermelho
-- é decoração. O `rollback` do fim devolve o trigger.
drop trigger tg_movimento_resolve_pendencia on public.movimento_estoque;

select is((select devido from portao_estoque_devido),
  'fn_pedido_receber existe (card 6.5) e tg_movimento_resolve_pendencia nao',
  'retirado o trigger, o portao o nomeia — e nomeia o card de quem o deve');

select * from finish();
rollback;
