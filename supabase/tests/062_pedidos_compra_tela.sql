-- =============================================================================
-- v_pedido_compra, v_pedido_item e a guarda de edição de item — card 6.8
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- ⚠️ O §17 NÃO PREVIA ARQUIVO PARA O 6.8, e a divergência é a mesma do `053`
--    (card 6.6) e do `061` (card 6.7): a tela 7 foi planejada sem objeto de
--    banco e tem três — duas views de listagem e um trigger. `views-leitura.md`
--    §12.1 já dizia que view de tela pertence ao card da tela; card de View tem
--    obrigação própria no §13, e ela é cumprida aqui. Mora no bloco `06x`, ao
--    lado do `060_estoque_compras` (6.5) e do `061` (6.7), e não no `095`.
--    Registrada no §17, não seguida em silêncio.
--
-- Obrigação de **View** (§13): paridade de linhas por perfil + zero para quem
-- não pode + isolamento de unidade (§6.3), mais as armadilhas do card 2.3 §3 que
-- se aplicam. Obrigação de **migração de schema** (§13, camada 1): um teste por
-- regra que o trigger novo expressa.
--
-- Quatro coisas que este arquivo prova e que nenhum catálogo enxerga:
--
--   • **pedido SEM item conta 0, e não 1.** É a armadilha §3.2 (`count(*)` sobre
--     `left join` conta a linha nula) num caso REAL: o rascunho recém-criado, a
--     que ainda não se acrescentou nada, e cuja existência `PEDIDO_SEM_ITEM`
--     comprova. Com `left join` direto ele contaria um item que não existe, e a
--     soma viria `null` (§3.1). A contraprova está escrita ao lado;
--
--   • **`qtd_pendente` tem piso zero POR ITEM.** Recebido com excedente,
--     `qtd_pedida − qtd_recebida` fica negativo — é o que
--     `compras.receber_excedente` significa desde o 6.5 —, e "faltam −2" não é
--     frase de painel de conferência. A contraprova lê a subtração crua ao lado;
--
--   • **a guarda nova fecha as duas metades que o 6.1 deixou abertas** — criar
--     item e mudar `qtd_pedida` fora do RASCUNHO —, **sem tocar no recebimento**,
--     que escreve `qtd_recebida` em pedido ENVIADO e PARCIAL. As duas asserções
--     andam juntas de propósito: uma guarda mais larga passaria em todas as
--     recusas e derrubaria o recebimento inteiro;
--
--   • **as duas views reagem de forma OPOSTA à falta de `materiais.ler`**, e
--     isso é decisão, não acaso: `v_pedido_compra` vem cheia (não junta material
--     nenhum) e `v_pedido_item` vem VAZIA (join interno, o precedente do 6.6).
--     Um pedido "cheio de itens sem nome" seria uma lista de apostilas anônimas
--     para conferir contra a caixa que chegou.
--
-- ⚠️ A ORDEM DAS SEÇÕES IMPORTA. A seção 3 recebe com excedente e deixa o
--    `2026-002` em PARCIAL; a 4 exige que ele não seja RASCUNHO para as três
--    recusas e o fecha no fim. Invertidas, as recusas mediriam outro estado.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(35);

-- Chaves naturais em um lugar só (card 2.8 §11: nunca `limit` sem ordem, nunca
-- UUID literal). ⚠️ Como no `060`, estas views só servem ao lado `postgres` do
-- arquivo: elas chamam `tests.unidade`, e `authenticated` não tem USAGE no
-- schema `tests`. Os helpers abaixo resolvem os ids ANTES de trocar de papel.
create temporary view pedido_id (numero, id) as
  select p.numero, p.id from public.pedido_compra p
   where p.unidade_id = tests.unidade('ESCOLA_A');

create temporary view item_id (chave, id) as
  select pc.numero || ' ' || me.codigo || ' ' || m.codigo, pi.id
    from public.pedido_item pi
    join public.pedido_compra pc on pc.id = pi.pedido_id
    join public.material m  on m.id = pi.material_id
    join public.metodo   me on me.id = m.metodo_id
   where pi.unidade_id = tests.unidade('ESCOLA_A');

-- Executa um comando na pele de alguém e volta ao papel do chamador — o mesmo
-- desenho de `tests.conta_como`, para o que não é contagem. Chamar sempre a
-- partir de `postgres`.
create or replace function pg_temp.como(p_email text, p_sql text)
returns void
language plpgsql
as $$
declare
  v_role text := current_user;
begin
  perform tests.autenticar(tests.uid(p_email));
  execute p_sql;
  execute format('set local role %I', v_role);
  perform set_config('request.jwt.claims', null, true);
end $$;

-- Recebimento por chave natural. Os ids são resolvidos ANTES de `autenticar`,
-- porque as views temporárias acima chamam `tests.unidade`.
create or replace function pg_temp.receber(
  p_numero text, p_chave text, p_qtd integer, p_email text)
returns integer
language plpgsql
as $$
declare
  v_role   text := current_user;
  v_pedido uuid;
  v_item   uuid;
  v_n      integer;
begin
  select id into v_pedido from pedido_id where numero = p_numero;
  select id into v_item   from item_id   where chave  = p_chave;
  perform tests.autenticar(tests.uid(p_email));
  v_n := public.fn_pedido_receber(
           v_pedido,
           jsonb_build_array(jsonb_build_object('pedido_item_id', v_item,
                                                'quantidade', p_qtd)));
  execute format('set local role %I', v_role);
  perform set_config('request.jwt.claims', null, true);
  return v_n;
end $$;

-- ===========================================================================
-- 1. O contrato de forma
-- ===========================================================================
select has_view('public', 'v_pedido_compra', 'v_pedido_compra existe');
select has_view('public', 'v_pedido_item',   'v_pedido_item existe');

-- A ordem é contrato (card 2.3 §6.2): `create or replace view` não insere coluna
-- no meio nem troca tipo. Coluna nova entra no FIM.
select is(
  (select string_agg(a.attname, ',' order by a.attnum)
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'v_pedido_compra'
      and a.attnum > 0),
  'unidade_id,pedido_id,numero,status,data_envio,fornecedor,observacao,' ||
  'criado_em,data_referencia,qtd_itens,qtd_pedida_total,qtd_recebida_total',
  'as 12 colunas de v_pedido_compra na ordem definitiva — coluna nova entra no FIM');

select is(
  (select string_agg(a.attname, ',' order by a.attnum)
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'v_pedido_item'
      and a.attnum > 0),
  'unidade_id,pedido_item_id,pedido_id,material_id,metodo_id,codigo,nome,' ||
  'categoria,qtd_pedida,qtd_recebida,qtd_pendente',
  'as 11 colunas de v_pedido_item na ordem definitiva');

-- ===========================================================================
-- 2. Os agregados da aba Pedidos, e as duas armadilhas do §3
-- ===========================================================================
-- Lido como `postgres` (BYPASSRLS): é a contagem de referência da seção 5.
select is(
  (select string_agg(v.numero || '=' || v.qtd_itens || ' itens ' ||
                     v.qtd_recebida_total || '/' || v.qtd_pedida_total,
                     '; ' order by v.numero)
     from public.v_pedido_compra v
    where v.unidade_id = tests.unidade('ESCOLA_A')),
  '2026-001=1 itens 26/26; 2026-002=2 itens 0/15; 2026-003=1 itens 0/5',
  'os tres pedidos da fixture com itens, recebido e pedido — o "10 de 15" sai daqui');

-- ⚠️ A armadilha §3.2 num caso REAL. `fn_pedido_enviar` recusa pedido sem item
--    com `PEDIDO_SEM_ITEM` justamente porque esse estado existe: é o rascunho a
--    que ainda não se acrescentou nada, e a aba Pedidos precisa mostrá-lo.
select pg_temp.como('secretaria@escola-a.test',
  $i$insert into public.pedido_compra (unidade_id, numero, status, fornecedor)
     values (public.fn_unidade_atual(), '2026-900', 'RASCUNHO', 'Fornecedor do teste 062')$i$);

select is(
  (select v.qtd_itens from public.v_pedido_compra v
    where v.numero = '2026-900' and v.unidade_id = tests.unidade('ESCOLA_A')),
  0,
  'pedido SEM item conta ZERO itens — count(*) sobre left join contaria 1 (card 2.3 §3.2)');

select is(
  (select v.qtd_pedida_total || '/' || v.qtd_recebida_total
     from public.v_pedido_compra v
    where v.numero = '2026-900' and v.unidade_id = tests.unidade('ESCOLA_A')),
  '0/0',
  'e os totais vem ZERO, nao nulo: sum() de conjunto vazio e null (card 2.3 §3.1)');

-- Contraprova das duas acima: com o agregado no `left join` direto e sem
-- `coalesce`, este mesmo pedido devolve 1 item e soma nula.
select is(
  (select count(*)::text || ' / ' || coalesce(sum(pi.qtd_pedida)::text, 'null')
     from public.pedido_compra p
     left join public.pedido_item pi on pi.pedido_id = p.id
    where p.numero = '2026-900' and p.unidade_id = tests.unidade('ESCOLA_A')
    group by p.id),
  '1 / null',
  'contraprova: a forma ingenua conta 1 item inexistente e soma null — e o que a view evita');

-- A data que a linha mostra (wireframe §10.2: "#24 RASCUNHO 01/09").
select is(
  (select v.data_referencia from public.v_pedido_compra v
    where v.numero = '2026-900' and v.unidade_id = tests.unidade('ESCOLA_A')),
  public.fn_hoje(),
  'rascunho mostra a data de CRIACAO no fuso da escola — nao criado_em::date em UTC');

select is(
  (select v.data_referencia from public.v_pedido_compra v
    where v.numero = '2026-002' and v.unidade_id = tests.unidade('ESCOLA_A')),
  (select p.data_envio from public.pedido_compra p
    where p.numero = '2026-002' and p.unidade_id = tests.unidade('ESCOLA_A')),
  'pedido enviado mostra a data do ENVIO');

-- ===========================================================================
-- 3. v_pedido_item — o material resolvido e o piso zero por item
-- ===========================================================================
select is(
  (select string_agg(me.codigo || ' ' || v.codigo || '=' || v.qtd_pedida || '/' ||
                     v.qtd_recebida || ' faltam ' || v.qtd_pendente,
                     '; ' order by me.codigo)
     from public.v_pedido_item v
     join public.pedido_compra p on p.id = v.pedido_id
     join public.metodo me on me.id = v.metodo_id
    where p.numero = '2026-002' and p.unidade_id = tests.unidade('ESCOLA_A')),
  'INGLES 02=5/0 faltam 5; INTERATIVO 02=10/0 faltam 10',
  'os itens do pedido enviado, com codigo e metodo vindos do join em material');

select is_empty(
  $$ select pedido_item_id from public.v_pedido_item where nome is null $$,
  'nenhum item vem sem NOME: o join em material e interno, e nao ha meio-termo');

-- O excedente do card 6.5, que só a direção pode: 12 de 10 num item.
select is(
  pg_temp.receber('2026-002', '2026-002 INTERATIVO 02', 12, 'direcao@escola-a.test'),
  1,
  'a direcao recebe 12 de 10 — compras.receber_excedente e excecao de PERMISSAO (card 6.5)');

select is(
  (select v.qtd_pendente from public.v_pedido_item v
    where v.pedido_item_id = (select id from item_id where chave = '2026-002 INTERATIVO 02')),
  0,
  'item recebido com excedente falta ZERO — piso por item, o mesmo de v_pedido_sugerido');

select is(
  (select v.qtd_pedida - v.qtd_recebida from public.v_pedido_item v
    where v.pedido_item_id = (select id from item_id where chave = '2026-002 INTERATIVO 02')),
  -2,
  'contraprova: a subtracao crua e -2, e "faltam -2" e o que o piso existe para nao escrever');

select is(
  (select v.status from public.v_pedido_compra v
    where v.numero = '2026-002' and v.unidade_id = tests.unidade('ESCOLA_A')),
  'PARCIAL',
  'e o pedido virou PARCIAL: o outro item ainda nao chegou');

select is(
  (select v.qtd_recebida_total || '/' || v.qtd_pedida_total
     from public.v_pedido_compra v
    where v.numero = '2026-002' and v.unidade_id = tests.unidade('ESCOLA_A')),
  '12/15',
  'o total recebido nao e grampeado no pedido: "15 de 15" com 17 na caixa seria mentira');

-- ===========================================================================
-- 4. tg_pedido_item_edicao — a guarda que o card 6.1 deixou pela metade
-- ===========================================================================
select has_trigger('public', 'pedido_item', 'tg_pedido_item_edicao',
  'o trigger de INSERT existe');
select has_trigger('public', 'pedido_item', 'tg_pedido_item_edicao_upd',
  'o trigger de UPDATE de qtd_pedida existe');

select is(
  tests.codigo_do_erro(
    $i$update public.pedido_item pi set qtd_pedida = 1
        from public.pedido_compra pc
       where pc.id = pi.pedido_id and pc.numero = '2026-002'
         and pc.unidade_id = public.fn_unidade_atual()$i$,
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_NAO_RASCUNHO',
  'baixar qtd_pedida de pedido ja enviado e recusado — some a parcela "ja pedida" sem apagar linha');

select is(
  tests.codigo_do_erro(
    $i$insert into public.pedido_item (unidade_id, pedido_id, material_id, qtd_pedida)
       select public.fn_unidade_atual(), pc.id, m.id, 3
         from public.pedido_compra pc, public.material m
         join public.metodo me on me.id = m.metodo_id
        where pc.numero = '2026-002' and pc.unidade_id = public.fn_unidade_atual()
          and m.unidade_id = public.fn_unidade_atual()
          and me.codigo = 'MODULAR' and m.codigo = '01'$i$,
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_NAO_RASCUNHO',
  'e acrescentar item a pedido ja enviado tambem: o fornecedor nao sabe dele');

select is(
  tests.codigo_do_erro(
    $i$update public.pedido_item pi
          set pedido_id = (select p.id from public.pedido_compra p
                            where p.numero = '2026-002'
                              and p.unidade_id = public.fn_unidade_atual())
        from public.pedido_compra pc
       where pc.id = pi.pedido_id and pc.numero = '2026-003'
         and pc.unidade_id = public.fn_unidade_atual()$i$,
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_NAO_RASCUNHO',
  'mover item do rascunho para o enviado e criar item no enviado — a guarda olha o pedido NOVO');

-- Caminho feliz: no RASCUNHO a edição passa, que é o que a tela 7 faz.
select lives_ok(
  $q$select pg_temp.como('secretaria@escola-a.test',
       $i$update public.pedido_item pi set qtd_pedida = 9
           from public.pedido_compra pc
          where pc.id = pi.pedido_id and pc.numero = '2026-003'
            and pc.unidade_id = public.fn_unidade_atual()$i$)$q$,
  'em RASCUNHO a quantidade se edita — e a edicao do rascunho da tela 7');

select lives_ok(
  $q$select pg_temp.como('secretaria@escola-a.test',
       $i$insert into public.pedido_item (unidade_id, pedido_id, material_id, qtd_pedida)
          select public.fn_unidade_atual(), pc.id, m.id, 4
            from public.pedido_compra pc, public.material m
            join public.metodo me on me.id = m.metodo_id
           where pc.numero = '2026-003' and pc.unidade_id = public.fn_unidade_atual()
             and m.unidade_id = public.fn_unidade_atual()
             and me.codigo = 'MODULAR' and m.codigo = '01'$i$)$q$,
  'e item novo entra no rascunho — sem isso o "criar pedido" nao teria como crescer');

-- ⚠️ A ASSERÇÃO QUE IMPEDE A GUARDA DE FICAR LARGA DEMAIS. `fn_pedido_receber`
--    escreve `qtd_recebida` em pedido ENVIADO e PARCIAL; um trigger sem o
--    `of qtd_pedida` derrubaria o recebimento inteiro, e as três recusas acima
--    passariam do mesmo jeito.
select is(
  pg_temp.receber('2026-002', '2026-002 INGLES 02', 5, 'direcao@escola-a.test'),
  1,
  'o recebimento continua escrevendo qtd_recebida em pedido PARCIAL — a guarda e por COLUNA');

select is(
  (select v.status from public.v_pedido_compra v
    where v.numero = '2026-002' and v.unidade_id = tests.unidade('ESCOLA_A')),
  'RECEBIDO',
  'e o pedido fechou: os dois itens chegaram');

-- ===========================================================================
-- 5. Paridade por perfil, zero para quem não pode e isolamento de unidade
-- ===========================================================================
-- Um perfil com `compras.ler` e SEM `materiais.ler`: é o que separa as duas
-- views, e o único jeito de provar que a escolha do `join` é escolha.
insert into public.perfil (unidade_id, codigo, nome)
values (tests.unidade('ESCOLA_A'), 'COMP_SMAT', 'So compras.ler (teste 062)');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select tests.unidade('ESCOLA_A'), pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A')
   and pm.unidade_id = tests.unidade('ESCOLA_A')
   and pe.codigo = 'COMP_SMAT'
   and pm.codigo = 'compras.ler';

select tests.criar_usuario('compsmat@escola-a.test', 'COMP_SMAT');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_pedido_compra'),
  '>', 0::bigint,
  'a direcao ve pedido: sem isso toda paridade abaixo comparava zero com zero');

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
                   'select 1 from public.v_pedido_compra'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_pedido_compra'),
  'a secretaria ve os MESMOS pedidos que a direcao — os dois perfis da rota da tela 7');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_pedido_compra'),
  0::bigint,
  'o monitor nao tem compras.ler e nao ve pedido nenhum — a tela 7 nao abre para ele');

-- As duas views reagindo de forma OPOSTA à mesma falta de permissão.
select cmp_ok(
  tests.conta_como(tests.uid('compsmat@escola-a.test'),
                   'select 1 from public.v_pedido_compra'),
  '>', 0::bigint,
  'sem materiais.ler a LISTA de pedidos vem cheia: ela nao junta material nenhum');

select is(
  tests.conta_como(tests.uid('compsmat@escola-a.test'),
                   'select 1 from public.v_pedido_item'),
  0::bigint,
  'e a lista de ITENS vem VAZIA: o join em material e interno, como o de v_aluno_trilha');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_pedido_item'),
  '>', 0::bigint,
  'contraprova: com materiais.ler os itens VEM — senao a assercao acima passaria de graca');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_pedido_compra'),
  0::bigint,
  'sem perfil nenhum a aba Pedidos e vazia — e vazia por RLS, que a view nao pode esconder');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_pedido_compra where unidade_id = ' ||
                   quote_literal(tests.unidade('ESCOLA_A')::text) || '::uuid'),
  0::bigint,
  'a direcao da Escola B nao ve pedido da Escola A: security_invoker + RLS por unidade');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_pedido_compra'),
  '>', 0::bigint,
  'contraprova: ela ve os pedidos da PROPRIA unidade, e o isolamento nao e "view quebrada"');

select * from finish();
rollback;
