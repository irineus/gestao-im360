-- =============================================================================
-- v_material_movimento — o painel de movimentações da tela 6 (card 6.7)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- ⚠️ O NÚMERO DO ARQUIVO É 061, e o §17 não previa arquivo nenhum para o 6.7 —
--    a linha do card não existe lá, porque a tela foi planejada sem objeto de
--    banco. Ela tem um: `v_material_movimento`, que `docs/views-leitura.md`
--    §12.1 sempre disse ser deste card. Card de View tem obrigação própria no
--    §13, e ela é cumprida aqui. Mora ao lado do `060_estoque_compras` (card
--    6.5), que é o arquivo do estoque, e não no `095` — mesmo critério que o
--    card 6.6 usou para pôr o `053` no bloco da trilha. Divergência registrada
--    no §17, não seguida em silêncio.
--
-- Obrigação de teste de um card de **View** (§13): paridade de linhas por perfil
-- + zero para quem não pode + isolamento de unidade (§6.3), mais as armadilhas
-- do card 2.3 §3 que se aplicam.
--
-- ⚠️ A PARIDADE AQUI É O CONTRÁRIO DA DO `053`, e é a razão de o arquivo existir.
--    Em `v_aluno_trilha` a asserção que vale é "sem `materiais.ler` vem VAZIA":
--    o `join` é interno de propósito. Nesta view TODO `join` de rótulo é
--    EXTERNO, e o que se prova é que **nenhum perfil com `estoque.ler` perde uma
--    linha** — o monitor, que não tem `compras.ler`, vê as mesmas linhas que a
--    direção, com o número do pedido em branco. Com `join` interno ele deixaria
--    de ver toda ENTRADA vinda de pedido, e a soma do painel não fecharia com o
--    saldo de `v_estoque_atual` — sem erro nenhum, que é o modo de falha que
--    este arquivo existe para impedir.
--
-- Três coisas que este arquivo prova e que nenhum catálogo enxerga:
--   • a soma das linhas do painel É o saldo de `v_estoque_atual`, material a
--     material. É a asserção que quebra no dia em que alguém trocar um `left
--     join` por `join`, e a única que enxerga uma linha desaparecida;
--   • `aluno_id` sem `aluno_nome` é um estado LEGÍTIMO e distinguível — é o que
--     permite à tela dizer "aluno não visível para o seu perfil" em vez do
--     traço que faria uma entrega parecer um ajuste sem dono;
--   • sem `estoque.ler` não vem linha nenhuma, e aqui isso é o certo: o
--     movimento é o assunto da view, não um rótulo dela.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(23);

-- ===========================================================================
-- 1. O contrato de forma
-- ===========================================================================
select has_view('public', 'v_material_movimento', 'v_material_movimento existe');

-- A ordem é contrato (card 2.3 §6.2): `create or replace view` não insere coluna
-- no meio nem troca tipo. Coluna nova entra no FIM.
select is(
  (select string_agg(a.attname, ',' order by a.attnum)
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'v_material_movimento'
      and a.attnum > 0),
  'unidade_id,movimento_id,material_id,tipo,quantidade,ocorrido_em,observacao,' ||
  'aluno_id,aluno_nome,aluno_codigo_sgf,pedido_item_id,pedido_numero,' ||
  'estorno_de_id,estorno_de_tipo,estorno_de_ocorrido_em,criado_por,' ||
  'criado_por_nome',
  'as 17 colunas na ordem definitiva — coluna nova entra no FIM (card 2.3 §6.2)');

-- ===========================================================================
-- 2. Uma linha por movimento, e os quatro tipos aparecem
-- ===========================================================================
-- Lida como `postgres` (BYPASSRLS): é a contagem de referência contra a qual as
-- contagens por perfil da seção 5 são comparadas.
select is(
  (select count(*) from public.v_material_movimento),
  (select count(*) from public.movimento_estoque),
  'uma linha por movimento: nenhum left join multiplica nem engole linha');

select is(
  (select count(distinct tipo) from public.v_material_movimento),
  4::bigint,
  'os quatro tipos estao na fixture — ENTRADA, SAIDA, AJUSTE e ESTORNO');

-- ===========================================================================
-- 3. Os rótulos externos, quando o leitor pode vê-los
-- ===========================================================================
select cmp_ok(
  (select count(*) from public.v_material_movimento
    where tipo = 'ENTRADA' and pedido_numero = '2026-001'),
  '>', 0::bigint,
  'a ENTRADA vinda do pedido carrega o NUMERO do pedido — o vinculo compra/estoque do card 6.1');

select cmp_ok(
  (select count(*) from public.v_material_movimento
    where tipo = 'SAIDA' and aluno_nome is not null),
  '>', 0::bigint,
  'a SAIDA de entrega carrega o nome do aluno');

select is(
  (select estorno_de_tipo from public.v_material_movimento where tipo = 'ESTORNO'
    order by ocorrido_em limit 1),
  'SAIDA',
  'o ESTORNO diz o que estornou: o tipo do movimento original vem resolvido');

select is_empty(
  $$ select movimento_id from public.v_material_movimento
      where tipo = 'ESTORNO' and estorno_de_ocorrido_em is null $$,
  'e a data do movimento original tambem — o painel escreve "(estorno de …)" sem segunda consulta');

-- Movimento sem aluno é legítimo (entrada, ajuste) e não é o mesmo caso de
-- "aluno ilegível": a seção 5 mede a diferença.
select cmp_ok(
  (select count(*) from public.v_material_movimento
    where aluno_id is null and tipo in ('ENTRADA','AJUSTE')),
  '>', 0::bigint,
  'entrada e ajuste nao tem aluno, e isso e um estado normal da coluna');

-- ===========================================================================
-- 4. A CONFERÊNCIA: a soma do painel é o saldo de v_estoque_atual
-- ===========================================================================
-- É a asserção que este arquivo existe para ter. Ela quebra no dia em que
-- alguém trocar um `left join` por `join` — e é a única capaz de enxergar uma
-- linha que sumiu, porque uma linha a menos não levanta erro nenhum.
select cmp_ok(
  (select count(*) from public.v_estoque_atual where saldo <> 0),
  '>', 0::bigint,
  'ha material com saldo diferente de zero — senao a paridade abaixo comparava zero com zero');

select is_empty(
  $$ select e.material_id
       from public.v_estoque_atual e
       left join (select unidade_id, material_id, sum(quantidade) as total
                    from public.v_material_movimento
                   group by unidade_id, material_id) v
              on v.unidade_id = e.unidade_id and v.material_id = e.material_id
      where coalesce(v.total, 0) <> e.saldo $$,
  'a soma das linhas do painel E o saldo de v_estoque_atual, material a material');

-- ===========================================================================
-- 5. Paridade por perfil — nenhum rótulo ilegível derruba linha
-- ===========================================================================
select tests.encerrar_sessao();

-- Um perfil que só lê estoque: nem `alunos.ler`, nem `compras.ler`, nem
-- `admin.ler`. É o mínimo que a rota da tela 6 exige do lado do estoque, e o
-- pior caso para uma view cheia de `join` de rótulo.
insert into public.perfil (unidade_id, codigo, nome)
values (tests.unidade('ESCOLA_A'), 'MOV_SEST', 'So estoque.ler (teste 061)');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select tests.unidade('ESCOLA_A'), pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A')
   and pm.unidade_id = tests.unidade('ESCOLA_A')
   and pe.codigo = 'MOV_SEST'
   and pm.codigo in ('materiais.ler', 'estoque.ler');

select tests.criar_usuario('movsoestoque@escola-a.test', 'MOV_SEST');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_material_movimento'),
  '>', 0::bigint,
  'a direcao ve movimento: sem isso toda paridade abaixo comparava zero com zero');

-- O monitor não tem `compras.ler` (card 2.3): é o perfil real em que o `join`
-- interno em `pedido_compra` teria custado toda ENTRADA vinda de pedido.
select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_material_movimento'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_material_movimento'),
  'o monitor ve as MESMAS linhas que a direcao, sem compras.ler — o join do pedido e externo');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_material_movimento where pedido_numero is not null'),
  0::bigint,
  'e sem o NUMERO do pedido: o rotulo some, a linha fica');

select cmp_ok(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_material_movimento where pedido_item_id is not null'),
  '>', 0::bigint,
  'com pedido_item_id preenchido ao lado: e assim que a tela diz "pedido de compra" em vez de nada');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_material_movimento where pedido_numero is not null'),
  '>', 0::bigint,
  'contraprova: com compras.ler o numero VEM — senao a assercao acima passaria de graca');

select is(
  tests.conta_como(tests.uid('movsoestoque@escola-a.test'),
                   'select 1 from public.v_material_movimento'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_material_movimento'),
  'quem so tem estoque.ler ve as MESMAS linhas: nenhum rotulo ilegivel derruba movimento');

select is(
  tests.conta_como(tests.uid('movsoestoque@escola-a.test'),
                   'select 1 from public.v_material_movimento where aluno_nome is not null'),
  0::bigint,
  'sem alunos.ler o NOME do aluno vem nulo');

select cmp_ok(
  tests.conta_como(tests.uid('movsoestoque@escola-a.test'),
                   'select 1 from public.v_material_movimento where aluno_id is not null'),
  '>', 0::bigint,
  'e o ID nao: "tem aluno e voce nao pode ve-lo" e distinguivel de "nao tem aluno"');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_material_movimento where aluno_nome is not null'),
  '>', 0::bigint,
  'contraprova: com alunos.ler o nome VEM — senao a assercao acima passaria de graca');

-- ===========================================================================
-- 6. Zero para quem não pode, e isolamento de unidade
-- ===========================================================================
-- Sem `estoque.ler` não vem linha nenhuma — e aqui isso NÃO é a redução
-- silenciosa do card 2.3 §3.4: o movimento é o assunto da view. A rota da tela 6
-- exige `estoque.ler` (card 2.4 §6), então quem chega ao painel já passou.
select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_material_movimento'),
  0::bigint,
  'sem perfil nenhum o painel e vazio — e vazio por RLS, que a view nao pode esconder');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_material_movimento where unidade_id = ' ||
                   quote_literal(tests.unidade('ESCOLA_A')::text) || '::uuid'),
  0::bigint,
  'a direcao da Escola B nao ve movimento da Escola A: security_invoker + RLS por unidade');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_material_movimento'),
  '>', 0::bigint,
  'contraprova: ela ve o movimento da PROPRIA unidade, e o isolamento nao e "view quebrada"');

select * from finish();
rollback;
