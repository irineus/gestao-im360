-- =============================================================================
-- Pedidos de compra, recebimento e ajuste de estoque — card 6.5
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Card de "Função/regra", então o §13 cobra quatro coisas: caminho feliz com
-- EFEITO conferido, um `throws_ok`/`codigo_do_erro` por código que as funções
-- podem levantar, um negativo de permissão e a camada 2 quando houver
-- trigger-garantia. As quatro estão aqui.
--
-- Fora da obrigação, o arquivo mede as decisões que sem ele são frase em
-- documento (docs/estrategia-testes.md §14):
--   • RASCUNHO não abate a parcela "já pedida"; ENVIADO e PARCIAL abatem;
--     RECEBIDO e CANCELADO não (card 2.3 §6 (d));
--   • a parcela é `qtd_pedida − qtd_recebida` DO ITEM, com piso zero por item —
--     sem o piso, um item recebido com excedente abateria a necessidade de OUTRO
--     material do mesmo pedido;
--   • `compras.receber_excedente` é EXCEÇÃO DE PERMISSÃO, e por isso a regra
--     mora num trigger e não num `check` (a decisão do cabeçalho da migração);
--   • a chegada da compra FECHA as pendências que a falta abriu — `ESTOQUE_ZERO`
--     por material e `COMPRA_SEM_ESTOQUE` por aluno —, e fecha só as certas;
--   • "sinal livre" no ajuste é sobre a direção, não sobre o saldo: saldo
--     negativo reprova o critério (4) do marco 6.9;
--   • o estorno espelha o movimento de origem (camada 2 de `movimento_estoque`).
--
-- ⚠️ A ORDEM DAS SEÇÕES IMPORTA, e não é estética. As pendências da seção 3 têm
--    de nascer ANTES de a seção 4 repor o estoque que as fecha — invertidas, o
--    trigger não teria o que fechar e as duas asserções passariam medindo nada.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(65);

-- Chaves naturais em um lugar só (card 2.8 §11: nunca `limit` sem ordem, nunca
-- UUID literal). ⚠️ Estas views só servem ao lado `postgres` do arquivo: dentro
-- de `tests.autenticar` o dono do objeto não muda e `alvo` chama `tests.unidade`,
-- num schema em que `authenticated` não tem USAGE. Nos blocos autenticados a
-- chave natural vai inteira na consulta, com `public.fn_unidade_atual()`.
create temporary view alvo as
  select tests.unidade('ESCOLA_A')                                  as unidade,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Diego Alves')   as diego,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Felipe Nunes')  as felipe;

create temporary view material_id (chave, id) as
  select me.codigo || ' ' || m.codigo, m.id
    from public.material m
    join public.metodo me on me.id = m.metodo_id
   where m.unidade_id = tests.unidade('ESCOLA_A');

create temporary view pedido_id (numero, id) as
  select p.numero, p.id from public.pedido_compra p
   where p.unidade_id = tests.unidade('ESCOLA_A');

-- Parcela "já pedida" de um material, lida da view do card 6.4 na pele de quem
-- tem as quatro permissões do §11 — é o número que a tela de Compras mostra.
create or replace function pg_temp.pendente(p_chave text)
returns integer
language plpgsql
as $$
declare
  v_role text := current_user;
  v_n    integer;
begin
  perform tests.autenticar(tests.uid('secretaria@escola-a.test'));
  select ps.qtd_pedida_pendente into v_n
    from public.v_pedido_sugerido ps
    join public.material m  on m.id = ps.material_id
    join public.metodo   me on me.id = m.metodo_id
   where me.codigo || ' ' || m.codigo = p_chave
     and ps.unidade_id = public.fn_unidade_atual();
  execute format('set local role %I', v_role);
  perform set_config('request.jwt.claims', null, true);
  return v_n;
end $$;

-- ===========================================================================
-- 1. fn_pedido_criar — o RASCUNHO que a tela do card 6.8 monta
-- ===========================================================================
-- Quem cria é a SECRETARIA: `compras.criar` está em {DIRECAO, SECRETARIA}
-- (card 2.4 §5), e é ela quem faz a compra no dia a dia.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

create temporary table pedido_a as
  select public.fn_pedido_criar(
    (select jsonb_agg(jsonb_build_object('material_id', m.id, 'qtd_pedida', q.qtd))
       from (values ('INTERATIVO', '02', 8), ('INGLES', '02', 4)) as q(metodo, codigo, qtd)
       join public.metodo me on me.unidade_id = public.fn_unidade_atual()
                            and me.codigo = q.metodo
       join public.material m on m.unidade_id = public.fn_unidade_atual()
                             and m.metodo_id = me.id and m.codigo = q.codigo),
    'Editora Interativa', 'reposicao do teste 060') as id;

create temporary table pedido_b as
  select public.fn_pedido_criar(
    (select jsonb_build_array(jsonb_build_object('material_id', m.id, 'qtd_pedida', 5))
       from public.metodo me
       join public.material m on m.unidade_id = public.fn_unidade_atual()
                             and m.metodo_id = me.id and m.codigo = '01'
      where me.unidade_id = public.fn_unidade_atual() and me.codigo = 'INTERATIVO'),
    null, null) as id;

reset role;

select matches(
  (select p.numero from public.pedido_compra p where p.id = (select id from pedido_a)),
  '^[0-9]{4}-[0-9]{3}$',
  'o numero nasce no formato AAAA-NNN, derivado e nao digitado');

select is(
  (select p.status from public.pedido_compra p where p.id = (select id from pedido_a)),
  'RASCUNHO',
  'e o pedido nasce em RASCUNHO — enviar e um ato separado');

-- A sequência é POR UNIDADE, e o segundo pedido do dia prova que ela anda: um
-- `max` lido sob RLS por quem não pode ler devolveria zero e repetiria o número,
-- que é por que a função exige `compras.ler` além de `compras.criar`.
select is(
  (select (split_part(b.numero, '-', 2))::integer - (split_part(a.numero, '-', 2))::integer
     from public.pedido_compra a, public.pedido_compra b
    where a.id = (select id from pedido_a) and b.id = (select id from pedido_b)),
  1,
  'o segundo pedido leva o numero seguinte — a sequencia e por unidade e por ano');

select is(
  (select string_agg(me.codigo || ' ' || m.codigo || '=' || pi.qtd_pedida
                     || '/' || pi.qtd_recebida, '; ' order by me.codigo, m.codigo)
     from public.pedido_item pi
     join public.material m  on m.id = pi.material_id
     join public.metodo   me on me.id = m.metodo_id
    where pi.pedido_id = (select id from pedido_a)),
  'INGLES 02=4/0; INTERATIVO 02=8/0',
  'os dois itens entraram com a quantidade pedida e NADA recebido');

select is(
  (select p.criado_por from public.pedido_compra p where p.id = (select id from pedido_a)),
  tests.uid('secretaria@escola-a.test'),
  'a autoria nao e coluna propria: veio de criado_por, preenchido por fn_auditoria');

select is(
  (select p.unidade_id from public.pedido_compra p where p.id = (select id from pedido_a)),
  (select unidade from alvo),
  'e a unidade e a do contexto, nunca um parametro que o cliente escolhe');

-- ===========================================================================
-- 2. RASCUNHO não abate; ENVIADO abate (card 2.3 §6 (d))
-- ===========================================================================
-- Pedido em rascunho não foi feito a ninguém: contá-lo faria o sistema parar de
-- sugerir uma compra que nunca vai chegar.
select is(pg_temp.pendente('INTERATIVO 02'), 10,
  'com o rascunho de 8 unidades no ar, a parcela ja pedida continua sendo so a do 2026-002');

select tests.autenticar(tests.uid('secretaria@escola-a.test'));
select public.fn_pedido_enviar((select id from pedido_a));
reset role;

select is(
  (select p.status || '/' || (p.data_envio = public.fn_hoje())::text
     from public.pedido_compra p where p.id = (select id from pedido_a)),
  'ENVIADO/true',
  'enviar grava ENVIADO com a data no fuso da escola (fn_hoje, card 2.3 §3.3)');

select is(pg_temp.pendente('INTERATIVO 02'), 18,
  'e AGORA o pedido abate: 10 do 2026-002 mais 8 do que acabou de sair');

-- ===========================================================================
-- 3. As pendências que a falta abriu (pré-condição da seção 4)
-- ===========================================================================
-- Quem as abre é a entrega, do card 6.3 — este arquivo não as semeia à mão, pelo
-- mesmo argumento da fixture do card 5.4: pendência semeada prova que alguém sabe
-- escrever linha; pendência GERADA prova que o caminho por evento dispara.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

create temporary table r_felipe as
  select * from public.fn_registrar_entrega(
    (select a.id from public.aluno a
      where a.unidade_id = public.fn_unidade_atual() and a.nome = 'Felipe Nunes'));

create temporary table r_diego as
  select * from public.fn_registrar_entrega(
    (select a.id from public.aluno a
      where a.unidade_id = public.fn_unidade_atual() and a.nome = 'Diego Alves'));

reset role;

select is(
  (select r.status from r_felipe r) || '/' || (select r.status from r_diego r),
  'BLOQUEADA_SEM_ESTOQUE/REORDENADA',
  'pre-condicao: Felipe ficou bloqueado (INGLES 02 zerado) e Diego reordenou (INTERATIVO 02 zerado)');

select is(
  (select count(*)::bigint from public.pendencia p
    where p.unidade_id = (select unidade from alvo)
      and p.resolvida_em is null
      and p.chave_dedup in (
        'COMPRA_SEM_ESTOQUE:' || (select felipe from alvo)::text,
        'ESTOQUE_ZERO:' || (select id from material_id where chave = 'INTERATIVO 02')::text)),
  2::bigint,
  'as duas pendencias do catalogo do card 2.2 §10.1 estao ABERTAS antes de a compra chegar');

-- ===========================================================================
-- 4. Recebimento PARCIAL — a ENTRADA nasce vinculada ao item
-- ===========================================================================
-- É o ato que a planilha não tinha: lá, a chegada do pedido e a entrada em
-- estoque eram duas anotações sem ligação nenhuma.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

create temporary table r_parcial as
  select public.fn_pedido_receber(
    (select id from pedido_a),
    (select jsonb_build_array(jsonb_build_object('pedido_item_id', pi.id, 'quantidade', 4))
       from public.pedido_item pi
       join public.material m  on m.id = pi.material_id
       join public.metodo   me on me.id = m.metodo_id
      where pi.pedido_id = (select id from pedido_a)
        and me.codigo = 'INTERATIVO' and m.codigo = '02')) as n;

reset role;

select is((select n from r_parcial), 1,
  'o retorno e o numero de ENTRADAs criadas — uma, porque um item foi recebido');

select is(
  (select p.status from public.pedido_compra p where p.id = (select id from pedido_a)),
  'PARCIAL',
  'com um item incompleto, o pedido fica PARCIAL — o status sai dos ITENS, nao de um contador');

select is(
  (select pi.qtd_recebida from public.pedido_item pi
     join public.material m  on m.id = pi.material_id
     join public.metodo   me on me.id = m.metodo_id
    where pi.pedido_id = (select id from pedido_a)
      and me.codigo = 'INTERATIVO' and m.codigo = '02'),
  4,
  'e qtd_recebida do item subiu exatamente o que chegou');

select is(
  (select public.fn_saldo_material((select id from material_id where chave = 'INTERATIVO 02'))),
  4,
  'o saldo, que era zero, e agora quatro — sum(quantidade), nunca uma coluna');

select is(
  (select mv.tipo || '/' || mv.quantidade::text || '/' || (mv.pedido_item_id = pi.id)::text
     from public.movimento_estoque mv
     join public.pedido_item pi on pi.id = mv.pedido_item_id
    where pi.pedido_id = (select id from pedido_a)),
  'ENTRADA/4/true',
  'a ENTRADA e positiva e carrega pedido_item_id: e o vinculo compra <-> estoque');

select is(
  (select mv.criado_por from public.movimento_estoque mv
     join public.pedido_item pi on pi.id = mv.pedido_item_id
    where pi.pedido_id = (select id from pedido_a)),
  tests.uid('secretaria@escola-a.test'),
  'com a autoria de quem recebeu, vinda de criado_por');

-- O ciclo que o §6.2 abriu, fechado pelo §7.1: a apostila que faltou gerou
-- pendência, e a chegada do pedido a resolve sozinha.
select is(
  (select p.resolucao || '/' || (p.resolvida_por is null)::text
     from public.pendencia p
    where p.unidade_id = (select unidade from alvo)
      and p.chave_dedup = 'ESTOQUE_ZERO:'
                          || (select id from material_id where chave = 'INTERATIVO 02')::text),
  'RESOLVIDA/true',
  'ESTOQUE_ZERO fechou sozinha, com resolvida_por NULO — foi o sistema, nao uma pessoa');

-- E fechou SÓ a certa: Felipe é aluno de INGLÊS e continua sem a apostila dele.
-- Pendência fechada sem o problema ter sumido é pior do que pendência aberta.
select ok(
  (select p.resolvida_em is null from public.pendencia p
    where p.unidade_id = (select unidade from alvo)
      and p.chave_dedup = 'COMPRA_SEM_ESTOQUE:' || (select felipe from alvo)::text),
  'e a de Felipe CONTINUA aberta: entrada de INTERATIVO nao desbloqueia aluno de INGLES');

select is(pg_temp.pendente('INTERATIVO 02'), 14,
  'a parcela ja pedida caiu para 14: o recebido sai da conta, o resto do item fica');

-- ===========================================================================
-- 5. Recebimento TOTAL — e o desbloqueio do aluno certo
-- ===========================================================================
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

create temporary table r_total as
  select public.fn_pedido_receber(
    (select id from pedido_a),
    (select jsonb_agg(jsonb_build_object('pedido_item_id', pi.id,
                                         'quantidade', pi.qtd_pedida - pi.qtd_recebida))
       from public.pedido_item pi
      where pi.pedido_id = (select id from pedido_a))) as n;

reset role;

select is((select n from r_total), 2,
  'os dois itens restantes viraram duas ENTRADAs');

select is(
  (select p.status from public.pedido_compra p where p.id = (select id from pedido_a)),
  'RECEBIDO',
  'com todos os itens completos, o pedido vira RECEBIDO');

select is(
  (select p.resolucao from public.pendencia p
    where p.unidade_id = (select unidade from alvo)
      and p.chave_dedup = 'COMPRA_SEM_ESTOQUE:' || (select felipe from alvo)::text),
  'RESOLVIDA',
  'e AGORA Felipe e desbloqueado — chegou a apostila que ELE ainda deve receber');

select is(pg_temp.pendente('INTERATIVO 02'), 10,
  'RECEBIDO nao abate (ja esta no saldo): sobra so a parcela do 2026-002');

-- ===========================================================================
-- 6. O excedente é EXCEÇÃO DE PERMISSÃO — a decisão do cabeçalho da migração
-- ===========================================================================
-- `pedido_item_recebido_ck` valia para todo mundo e tornava
-- `compras.receber_excedente` (card 2.4 §5.2) inalcançável. A regra virou
-- trigger, e é aqui que a diferença entre os dois mundos aparece.
select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_receber(%L::uuid,
             (select jsonb_build_array(jsonb_build_object('pedido_item_id', pi.id, 'quantidade', 11))
                from public.pedido_item pi
                join public.material m  on m.id = pi.material_id
                join public.metodo   me on me.id = m.metodo_id
               where pi.pedido_id = %L::uuid and me.codigo = 'INTERATIVO' and m.codigo = '02'))$$,
           (select id from pedido_id where numero = '2026-002'),
           (select id from pedido_id where numero = '2026-002')),
    tests.uid('secretaria@escola-a.test')),
  'RECEBIMENTO_EXCEDE_PEDIDO',
  'a secretaria NAO recebe acima do pedido — e o codigo e do catalogo, nao um 23514 cru');

select tests.autenticar(tests.uid('direcao@escola-a.test'));

create temporary table r_excedente as
  select public.fn_pedido_receber(
    (select id from public.pedido_compra
      where unidade_id = public.fn_unidade_atual() and numero = '2026-002'),
    (select jsonb_build_array(jsonb_build_object('pedido_item_id', pi.id, 'quantidade', 11))
       from public.pedido_item pi
       join public.material m  on m.id = pi.material_id
       join public.metodo   me on me.id = m.metodo_id
       join public.pedido_compra pc on pc.id = pi.pedido_id
      where pc.unidade_id = public.fn_unidade_atual() and pc.numero = '2026-002'
        and me.codigo = 'INTERATIVO' and m.codigo = '02')) as n;

reset role;

select is((select n from r_excedente), 1,
  'a DIRECAO recebe: compras.receber_excedente e dela, e so dela (card 2.4 §5.2)');

select is(
  (select pi.qtd_recebida || ' de ' || pi.qtd_pedida
     from public.pedido_item pi
     join public.material m  on m.id = pi.material_id
     join public.metodo   me on me.id = m.metodo_id
    where pi.pedido_id = (select id from pedido_id where numero = '2026-002')
      and me.codigo = 'INTERATIVO' and m.codigo = '02'),
  '11 de 10',
  'e qtd_recebida guarda o que CHEGOU: grampear em 10 seria numero errado com cara de certo');

select is(
  (select p.status from public.pedido_compra p
    where p.id = (select id from pedido_id where numero = '2026-002')),
  'PARCIAL',
  'o pedido segue PARCIAL: o outro item dele (INGLES 02) nao chegou');

select is(pg_temp.pendente('INTERATIVO 02'), 0,
  'e a parcela ja pedida e ZERO, nao -1: o greatest por item impede que um excedente abata outro material');

-- ===========================================================================
-- 7. Camada 2 — o `PATCH` direto pelo PostgREST encontra a mesma regra
-- ===========================================================================
-- A política de update de `pedido_item` aceita `compras.editar` e
-- `compras.receber`, e RLS não é por coluna: sem o trigger, a secretaria
-- escreveria `qtd_recebida` acima do pedido sem passar pela função.
select is(
  tests.codigo_do_erro(
    $$update public.pedido_item pi set qtd_recebida = pi.qtd_pedida + 1
       from public.pedido_compra pc
      where pc.id = pi.pedido_id and pc.numero = '2026-003'
        and pc.unidade_id = public.fn_unidade_atual()$$,
    tests.uid('secretaria@escola-a.test')),
  'RECEBIMENTO_EXCEDE_PEDIDO',
  'camada 2: o update direto e recusado pelo trigger, com o mesmo codigo da funcao');

select tests.autenticar(tests.uid('direcao@escola-a.test'));

update public.pedido_item pi set qtd_recebida = pi.qtd_pedida + 1
  from public.pedido_compra pc
 where pc.id = pi.pedido_id and pc.numero = '2026-003'
   and pc.unidade_id = public.fn_unidade_atual();

reset role;

select is(
  (select pi.qtd_recebida - pi.qtd_pedida from public.pedido_item pi
    where pi.pedido_id = (select id from pedido_id where numero = '2026-003')),
  1,
  'e passa para a direcao — a barreira distingue quem pode, que e o que o `check` nao fazia');

-- ===========================================================================
-- 8. fn_ajustar_estoque — a conferência de prateleira
-- ===========================================================================
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

create temporary table aj as
  select public.fn_ajustar_estoque(
    (select m.id from public.material m
       join public.metodo me on me.id = m.metodo_id
      where m.unidade_id = public.fn_unidade_atual()
        and me.codigo = 'MODULAR' and m.codigo = '01'),
    -3, 'conferencia de prateleira: tres a menos') as id;

reset role;

select is(
  (select mv.tipo || '/' || mv.quantidade::text || '/' || mv.observacao
     from public.movimento_estoque mv where mv.id = (select id from aj)),
  'AJUSTE/-3/conferencia de prateleira: tres a menos',
  'o ajuste e um movimento AJUSTE com sinal livre, e o motivo vai na observacao');

select is(
  (select public.fn_saldo_material((select id from material_id where chave = 'MODULAR 01'))),
  7,
  'e o saldo caiu exatamente tres — a fixture tinha dez (10 de entrada, uma saida estornada)');

-- "Sinal livre" é sobre a DIREÇÃO do ajuste, não sobre o saldo: saldo negativo
-- reprova o critério (4) do marco 6.9 e é um número que ninguém explica.
select is(
  tests.codigo_do_erro(
    format($$select public.fn_ajustar_estoque(%L::uuid, -1000, 'sumiu tudo')$$,
           (select id from material_id where chave = 'MODULAR 01')),
    tests.uid('secretaria@escola-a.test')),
  'SALDO_INSUFICIENTE',
  'ajuste que deixaria o estoque negativo e recusado — sinal livre nao e saldo livre');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_ajustar_estoque(%L::uuid, 5, '   ')$$,
           (select id from material_id where chave = 'MODULAR 01')),
    tests.uid('secretaria@escola-a.test')),
  'MOTIVO_OBRIGATORIO',
  'ajuste sem motivo nao passa: ajustar e decisao, e decisao sem porque se perde');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_ajustar_estoque(%L::uuid, 0, 'nada')$$,
           (select id from material_id where chave = 'MODULAR 01')),
    tests.uid('secretaria@escola-a.test')),
  'QUANTIDADE_INVALIDA',
  'zero e recusado antes de chegar ao check (quantidade <> 0), que chegaria cru a tela');

select is(
  tests.codigo_do_erro(
    $$select public.fn_ajustar_estoque('00000000-0000-0000-0000-000000000009'::uuid, 5, 'x')$$,
    tests.uid('secretaria@escola-a.test')),
  'MATERIAL_INEXISTENTE',
  'material inexistente e PT404 — e vale igual para material de outra unidade');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_ajustar_estoque(%L::uuid, 5, 'x')$$,
           (select id from material_id where chave = 'MODULAR 01')),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor lanca saida mas nao ajusta: estoque.ajustar nao esta no perfil dele');

-- ===========================================================================
-- 9. Os erros das funções de pedido (§13: um por codigo)
-- ===========================================================================
select tests.encerrar_sessao();

select throws_ok(
  format($$select public.fn_pedido_enviar(%L::uuid)$$, (select id from pedido_b)),
  'PT403', null,
  'sem permissao o SQLSTATE e PT403 (o texto nunca e contrato — card 2.8 §6.2)');

select is(
  tests.codigo_do_erro(
    $$select public.fn_pedido_criar('[]'::jsonb)$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor nao cria pedido: compras.criar e da direcao e da secretaria');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_receber(%L::uuid, '[]'::jsonb)$$, (select id from pedido_a)),
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'e o pedagogico nem enxerga compras: ele nao tem compras.receber');

select is(
  tests.codigo_do_erro(
    $$select public.fn_pedido_receber('00000000-0000-0000-0000-000000000003'::uuid, '[]'::jsonb)$$,
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_INEXISTENTE',
  'pedido que nao existe e PT404 / PEDIDO_INEXISTENTE (familia do PC_INEXISTENTE)');

-- Isolamento de unidade pela mesma porta: a leitura é `invoker`, então pedido de
-- OUTRA unidade e pedido inexistente respondem a mesma coisa.
select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_cancelar(%L::uuid, 'motivo')$$,
           (select p.id from public.pedido_compra p
             where p.unidade_id = tests.unidade('ESCOLA_B') and p.numero = '2026-002')),
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_INEXISTENTE',
  'e pedido da ESCOLA_B responde o MESMO para a secretaria da ESCOLA_A');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_receber(%L::uuid, '[]'::jsonb)$$,
           (select id from pedido_id where numero = '2026-003')),
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_NAO_RECEBIVEL',
  'rascunho nao se recebe: ele nem foi feito a ninguem');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_enviar(%L::uuid)$$, (select id from pedido_a)),
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_NAO_ENVIAVEL',
  'so rascunho se envia — e a frase e outra, por isso o codigo tambem e');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_cancelar(%L::uuid, 'desisti')$$, (select id from pedido_a)),
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_NAO_CANCELAVEL',
  'pedido RECEBIDO nao se cancela: as ENTRADAs ja estao no estoque e sao imutaveis');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_cancelar(%L::uuid, '   ')$$, (select id from pedido_b)),
    tests.uid('secretaria@escola-a.test')),
  'MOTIVO_OBRIGATORIO',
  'cancelar sem motivo nao passa: e o precedente dos cards 4.2, 6.2 e 6.3');

select is(
  tests.codigo_do_erro(
    $$select public.fn_pedido_criar('[]'::jsonb)$$,
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_SEM_ITEM',
  'pedido sem item nao se cria');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_receber(%L::uuid, '[]'::jsonb)$$,
           (select id from pedido_id where numero = '2026-002')),
    tests.uid('secretaria@escola-a.test')),
  'PEDIDO_SEM_ITEM',
  'e recebimento sem item tambem nao — o mesmo codigo, porque a frase e a mesma');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_criar(
       jsonb_build_array(jsonb_build_object('material_id', %L::uuid, 'qtd_pedida', 2),
                         jsonb_build_object('material_id', %L::uuid, 'qtd_pedida', 3)))$$,
           (select id from material_id where chave = 'INTERATIVO 01'),
           (select id from material_id where chave = 'INTERATIVO 01')),
    tests.uid('secretaria@escola-a.test')),
  'MATERIAL_JA_NO_PEDIDO',
  'o mesmo material duas vezes viraria um 23505 da pedido_item_uk — o remedio e somar, nao repetir');

select is(
  tests.codigo_do_erro(
    $$select public.fn_pedido_criar(
       jsonb_build_array(jsonb_build_object(
         'material_id', '00000000-0000-0000-0000-000000000009'::uuid, 'qtd_pedida', 2)))$$,
    tests.uid('secretaria@escola-a.test')),
  'MATERIAL_INEXISTENTE',
  'material que nao existe nao entra em pedido nenhum');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_criar(
       jsonb_build_array(jsonb_build_object('material_id', %L::uuid, 'qtd_pedida', 0)))$$,
           (select id from material_id where chave = 'INTERATIVO 01')),
    tests.uid('secretaria@escola-a.test')),
  'QUANTIDADE_INVALIDA',
  'e quantidade zero tambem nao: o check (qtd_pedida > 0) chegaria cru a tela');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_receber(%L::uuid,
             (select jsonb_build_array(jsonb_build_object('pedido_item_id', pi.id, 'quantidade', 0))
                from public.pedido_item pi where pi.pedido_id = %L::uuid limit 1))$$,
           (select id from pedido_id where numero = '2026-002'),
           (select id from pedido_id where numero = '2026-002')),
    tests.uid('secretaria@escola-a.test')),
  'QUANTIDADE_INVALIDA',
  'receber zero unidades nao e recebimento — e uma linha que nao devia ter sido enviada');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_pedido_receber(%L::uuid,
             (select jsonb_build_array(jsonb_build_object('pedido_item_id', pi.id, 'quantidade', 1))
                from public.pedido_item pi where pi.pedido_id = %L::uuid
                order by pi.id limit 1))$$,
           (select id from pedido_id where numero = '2026-002'),
           (select id from pedido_a)),
    tests.uid('secretaria@escola-a.test')),
  'ITEM_FORA_DO_PEDIDO',
  'item de OUTRO pedido e recusado: sem isso, o recebimento somaria na linha errada');

-- Camada 2 de `movimento_estoque`: o estorno espelha a origem. Quem escreve
-- direto é quem tem `estoque.estornar` — a secretaria (card 2.4 §5).
select is(
  tests.codigo_do_erro(
    $$insert into public.movimento_estoque
        (unidade_id, material_id, tipo, quantidade, estorno_de_id)
      select mv.unidade_id, mv.material_id, 'ESTORNO', 5, mv.id
        from public.movimento_estoque mv
       where mv.unidade_id = public.fn_unidade_atual() and mv.tipo = 'SAIDA'
         and mv.estorno_de_id is null
         and not exists (select 1 from public.movimento_estoque e where e.estorno_de_id = mv.id)
       order by mv.ocorrido_em, mv.id limit 1$$,
    tests.uid('secretaria@escola-a.test')),
  'ESTORNO_SINAL_INVALIDO',
  'estorno de magnitude diferente da origem e recusado — senao devolveria mais do que saiu');

-- ===========================================================================
-- 10. Cancelamento — o pedido sai da conta sem sair da história
-- ===========================================================================
select tests.autenticar(tests.uid('secretaria@escola-a.test'));
select public.fn_pedido_enviar((select id from pedido_b));
reset role;

select is(pg_temp.pendente('INTERATIVO 01'), 5,
  'enviado, o pedido B abate cinco unidades de INTERATIVO 01');

select tests.autenticar(tests.uid('secretaria@escola-a.test'));
select public.fn_pedido_cancelar((select id from pedido_b), 'fornecedor sem previsao');
reset role;

select is(
  (select p.status from public.pedido_compra p where p.id = (select id from pedido_b)),
  'CANCELADO',
  'cancelar nao apaga: pedido_compra nao tem politica de delete (card 2.4 §3.5)');

select matches(
  (select p.observacao from public.pedido_compra p where p.id = (select id from pedido_b)),
  'CANCELADO em .*: fornecedor sem previsao',
  'e o motivo fica registrado na observacao — cancelamento sem porque nao se explica depois');

select is(pg_temp.pendente('INTERATIVO 01'), 0,
  'CANCELADO nao abate: o material voltou a ser sugerido, que e o unico desfecho seguro');

-- ===========================================================================
-- 11. A ampliação registrada: ESTORNO positivo também fecha a pendência
-- ===========================================================================
-- ⚠️ O §7.1 condiciona o trigger a "ENTRADA/AJUSTE positivo". A condição que de
--    fato importa é a que ele mesmo escreve ao lado — "se o saldo voltou a ser
--    > 0" —, e o ESTORNO de uma SAIDA devolve exemplar à prateleira exatamente
--    como uma ENTRADA. A divergência está registrada na migração; aqui ela é
--    MEDIDA, senão continuaria sendo um comentário.
--
-- ⚠️ Esta pendência é ABERTA À MÃO, ao contrário das da seção 3, e a diferença é
--    de propósito: o estado que ela exige — pendência aberta de um material que
--    ainda tem uma SAIDA estornável — não existe na fixture nem se produz por
--    uma sequência curta de entregas. O que se mede aqui é o TRIGGER, não quem
--    abriu a pendência; e ela é aberta pela função do card 5.5, não por `insert`
--    direto, que é a regra que vale para todo o projeto.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select public.fn_pendencia_abrir(
  'ESTOQUE_ZERO',
  'ESTOQUE_ZERO:' || (select m.id from public.material m
                        join public.metodo me on me.id = m.metodo_id
                       where m.unidade_id = public.fn_unidade_atual()
                         and me.codigo = 'INGLES' and m.codigo = '01')::text,
  'pendencia do teste 060, para medir o fechamento pelo ESTORNO',
  'MEDIA',
  p_material_id => (select m.id from public.material m
                      join public.metodo me on me.id = m.metodo_id
                     where m.unidade_id = public.fn_unidade_atual()
                       and me.codigo = 'INGLES' and m.codigo = '01'));

reset role;

select ok(
  (select p.resolvida_em is null from public.pendencia p
    where p.unidade_id = (select unidade from alvo)
      and p.chave_dedup = 'ESTOQUE_ZERO:'
                          || (select id from material_id where chave = 'INGLES 01')::text),
  'pre-condicao: a pendencia de INGLES 01 esta aberta');

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select public.fn_estornar_entrega(
  (select mv.id from public.movimento_estoque mv
     join public.material m  on m.id = mv.material_id
     join public.metodo   me on me.id = m.metodo_id
    where mv.unidade_id = public.fn_unidade_atual() and mv.tipo = 'SAIDA'
      and me.codigo = 'INGLES' and m.codigo = '01'
      and not exists (select 1 from public.movimento_estoque e where e.estorno_de_id = mv.id)
    order by mv.ocorrido_em, mv.id limit 1),
  'livro devolvido pelo aluno');

reset role;

select is(
  (select p.resolucao from public.pendencia p
    where p.unidade_id = (select unidade from alvo)
      and p.chave_dedup = 'ESTOQUE_ZERO:'
                          || (select id from material_id where chave = 'INGLES 01')::text),
  'RESOLVIDA',
  'o ESTORNO positivo fechou a pendencia: deixa-lo de fora manteria o alerta com o livro na prateleira');

-- ===========================================================================
-- 12. Estrutural — os locks e a lista fechada de definer
-- ===========================================================================
create temporary view corpo_projeto as
  select p.proname,
         regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as fonte
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f';

-- C13 (docs/estrategia-testes.md §5.1). Guarda-chuva barato: aqui a corrida não
-- existe, porque tudo acontece numa conexão só. Quem prova de fato é
-- supabase/tests_concorrencia/.
select is(
  (select coalesce(string_agg(proname, ',' order by proname), '')
     from corpo_projeto
    where proname in ('fn_pedido_receber', 'fn_ajustar_estoque', 'fn_pedido_criar')
      and fonte ~ 'pg_advisory_xact_lock'),
  'fn_ajustar_estoque,fn_pedido_criar,fn_pedido_receber',
  'C13: recebimento, ajuste e numeracao serializam com pg_advisory_xact_lock');

-- Definer tiraria as funções de aplicação da política `insert` POR TIPO de
-- movimento_estoque — a única coisa que impede uma ENTRADA inventada (achado 9
-- do card 2.4 §7). É a mesma decisão que o card 6.3 tomou para a entrega.
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
     from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('fn_pedido_criar', 'fn_pedido_enviar', 'fn_pedido_cancelar',
                        'fn_pedido_receber', 'fn_ajustar_estoque')
      and p.prosecdef),
  '',
  'nenhuma das cinco funcoes de aplicacao e definer: elas continuam sujeitas as politicas');

select ok(
  (select p.prosecdef from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'fn_movimento_resolve_pendencia'),
  'o trigger que fecha pendencia E definer: quem recebe compra pode nao ter pendencias.ler');

select ok(
  (select fonte ~ 'new\.unidade_id' from corpo_projeto
    where proname = 'fn_movimento_resolve_pendencia'),
  'e filtra a unidade NO CORPO, pela linha que o trigger recebe (correcao do card 2.3)');

select * from finish();
rollback;
