-- =============================================================================
-- Card 6.8 — a tela de Compras: as duas views que ela lê e a guarda que faltava
-- Fonte: docs/wireframes.md §10 (a tela 7, "Pedido sugerido" e "Pedidos"),
--        docs/views-leitura.md §2 (princípios), §3 (as quatro armadilhas),
--        §3.4 (a RLS que reduz em silêncio), §6 (`v_pedido_sugerido`, que já
--        existe e NÃO é tocada aqui) e §12.1 (view de tela é do card da tela),
--        docs/permissoes-matriz.md §3.5 (os seis códigos de `compras`) e §6
--        linha 7 (`materiais.ler` + `estoque.ler` + `alunos.ler` +
--        `compras.ler` — direção e secretaria),
--        docs/modelagem-dados-ddl.md §10 (as duas tabelas de compra),
--        docs/estrategia-testes.md §13 (obrigação de View e de Migração).
--
-- Entrega: DUAS views de listagem (`security_invoker = on`, `unidade_id`,
--          colunas explícitas, `revoke`/`grant` do §2.5) e UM trigger de
--          guarda em `pedido_item`.
--
-- ⚠️ NENHUMA LINHA DE DADO. Migração é o que o CI empurra para produção sozinho
--    no merge em `main` (decisão de 02/09/2026): view e trigger são estrutura, e
--    `pedido_compra`/`pedido_item` estão vazias em produção até a virada do
--    card 9.7 — lá estas views devolvem zero linha, que é o estado correto.
--
-- =============================================================================
-- A GUARDA QUE FALTAVA, E POR QUE ELA NASCE NESTE CARD
-- =============================================================================
-- O card 6.1 fechou a EXCLUSÃO de item com `tg_pedido_item_exclusao_valida`, e
-- escreveu por quê: item de pedido ENVIADO que some leva junto, em silêncio, a
-- parcela "já pedida" que `v_pedido_sugerido` abate — e o sistema passa a mandar
-- comprar de novo o que já está a caminho.
--
-- As outras duas metades da mesma porta ficaram abertas, e nada as fechava:
--
--   • `update pedido_item set qtd_pedida = …` num pedido ENVIADO. A política de
--     update autoriza quem tem `compras.editar` OU `compras.receber`, e nenhum
--     trigger olhava `qtd_pedida`. Baixar a quantidade de um item enviado tem
--     EXATAMENTE o efeito do delete que o 6.1 recusou, sem nem precisar apagar
--     a linha; subi-la faz o sistema parar de sugerir uma compra que ninguém
--     pediu ao fornecedor;
--   • `insert into pedido_item` apontando para um pedido ENVIADO — a política de
--     insert pede `compras.criar` ou `compras.editar` e não olha o status do
--     pai. O item nasce abatendo a parcela de um pedido que já foi feito, e o
--     fornecedor não sabe dele.
--
-- Os três são a MESMA regra do card 2.4 §3.5 ("editar itens do rascunho"), e o
-- que estava escrito só valia para um dos três caminhos. Este card fecha os
-- outros dois porque é ele que abre o caminho: a tela 7 é o primeiro lugar do
-- sistema onde alguém edita item de pedido.
--
-- ⚠️ O QUE O TRIGGER NÃO PODE QUEBRAR, e é a razão de ele olhar a COLUNA e não a
--    operação: `fn_pedido_receber` (card 6.5) faz `update pedido_item set
--    qtd_recebida = …` em pedido ENVIADO e PARCIAL — é o trabalho dela. Um
--    trigger que recusasse todo `update` fora do RASCUNHO derrubaria o
--    recebimento inteiro. Ele dispara `of qtd_pedida`, e no corpo confere
--    `is distinct from`: recebimento passa, edição de quantidade pedida não.
--
-- Reaproveita `PEDIDO_NAO_RASCUNHO` (card 6.1) em vez de criar código novo: é a
-- mesma regra e a mesma saída para quem está na tela — cancelar o pedido, ou
-- receber o que chegou. O texto do catálogo (`app/lib/erros/catalogo_erros.dart`)
-- deixou de falar só em "remover" neste card.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. tg_pedido_item_edicao — item só se cria e se muda enquanto o pedido é
--    RASCUNHO
-- -----------------------------------------------------------------------------
-- `security invoker` (o default), como `fn_pedido_item_exclusao_valida` (6.1),
-- `fn_pc_exclusao_valida` (4.3) e `fn_bloco_exclusao_valida` (5.1), e pela mesma
-- razão: só lê uma linha que o próprio chamador já pode ler — quem tem
-- `compras.criar`/`compras.editar` tem `compras.ler` na matriz do card 2.4 §5.
--
-- Status nulo é RECUSA e não "sem opinião" (a lição do card 5.3): nulo aqui
-- significa que a RLS escondeu o pedido, e um item validado contra o que não se
-- pode ler é um item não validado. `is distinct from 'RASCUNHO'` fecha os dois
-- casos com uma comparação só.
create or replace function public.fn_pedido_item_edicao_valida()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_status text;
begin
  -- Trocar o item de pedido é criar um item no destino: a checagem tem de valer
  -- para o pedido NOVO, senão bastaria mover a linha de um rascunho para um
  -- pedido enviado para furar a regra.
  select p.status into v_status
    from public.pedido_compra p where p.id = new.pedido_id;

  if v_status is distinct from 'RASCUNHO' then
    raise exception using
      errcode = 'PT409',
      message = 'Só dá para mexer nos itens de um pedido em rascunho. Cancele o pedido ou receba o que chegou.',
      detail  = json_build_object('codigo', 'PEDIDO_NAO_RASCUNHO',
                                  'pedido', new.pedido_id,
                                  'pedido_item', new.id,
                                  'status', v_status)::text;
  end if;

  return new;
end $$;

comment on function public.fn_pedido_item_edicao_valida() is
  'Trigger BEFORE INSERT OR UPDATE OF qtd_pedida, pedido_id em pedido_item (card 6.8): recusa (PT409 / PEDIDO_NAO_RASCUNHO) criar item, mudar qtd_pedida ou mover o item quando o pedido não é RASCUNHO. Completa tg_pedido_item_exclusao_valida (card 6.1), que fechava só a exclusão — baixar qtd_pedida num pedido ENVIADO tem o mesmo efeito de apagar a linha sobre a parcela "já pedida" de v_pedido_sugerido, e sem apagar nada. NÃO alcança qtd_recebida: fn_pedido_receber escreve nessa coluna em pedido ENVIADO e PARCIAL, e é o trabalho dela.';

revoke execute on function public.fn_pedido_item_edicao_valida() from public;
revoke execute on function public.fn_pedido_item_edicao_valida() from anon;
grant  execute on function public.fn_pedido_item_edicao_valida() to authenticated;

-- `of qtd_pedida, pedido_id` no UPDATE, e nenhuma coluna no INSERT: é o que
-- deixa o recebimento (que só toca `qtd_recebida`) passar sem nem chamar a
-- função. O `is distinct from` do corpo cobre o resto — um `update` que
-- reescreve `qtd_pedida` com o MESMO valor dispara o trigger e é recusado num
-- pedido enviado, e isso é o certo: a linha é a mesma, mas a intenção de quem
-- escreveu não era receber.
create trigger tg_pedido_item_edicao
  before insert on public.pedido_item
  for each row execute function public.fn_pedido_item_edicao_valida();

create trigger tg_pedido_item_edicao_upd
  before update of qtd_pedida, pedido_id on public.pedido_item
  for each row execute function public.fn_pedido_item_edicao_valida();

-- -----------------------------------------------------------------------------
-- 2. v_pedido_compra — a lista da aba "Pedidos" (wireframe §10.2)
-- -----------------------------------------------------------------------------
-- "#24 RASCUNHO 01/09 3 itens" e "#23 PARCIAL 28/08 10 de 15 receb." são TRÊS
-- agregados que a tela não pode recalcular: contar itens em Dart obrigaria a
-- carregar os itens de todos os pedidos para escrever o número de um, que é o
-- desperdício que o card 4.6 já recusou na ficha do aluno.
--
-- ⚠️ AS DUAS PRIMEIRAS ARMADILHAS DO §3, e as duas mordem aqui:
--
--   §3.1 `sum()` de conjunto vazio é NULL, não zero. Pedido sem item é um estado
--        REAL — é o rascunho recém-criado a que ainda não se acrescentou nada, e
--        o `PEDIDO_SEM_ITEM` de `fn_pedido_enviar` existe justamente porque ele
--        acontece. Sem `coalesce`, a tela mostraria "null itens" para ele;
--
--   §3.2 `count(*)` sobre `left join` conta a linha nula. Com o `left join`
--        direto em `pedido_item` e `count(*)` no `group by`, o pedido sem item
--        contaria **1** — um item que não existe, com cara de item. Daí o
--        agregado morar numa SUBCONSULTA que já vem agrupada, e o `left join`
--        ser sobre o resultado dela.
--
-- Sem `join` em `usuario`, `unidade` ou `material`: cada `join` interno a mais é
-- mais um modo de a lista vir vazia por uma permissão que a rota da tela não
-- pede (§3.4 e a decisão do card 5.7). O que a lista precisa mostrar já está em
-- `pedido_compra`.
create view public.v_pedido_compra with (security_invoker = on) as
select p.unidade_id,
       p.id                                        as pedido_id,
       p.numero,
       p.status,
       p.data_envio,
       p.fornecedor,
       p.observacao,
       p.criado_em,
       -- A data que a linha mostra: a do envio quando houve envio, a da criação
       -- enquanto o pedido é rascunho. No fuso da escola, e não `criado_em::date`
       -- puro (card 2.3 §3.3): o Postgres do Supabase roda em UTC, e das 21h à
       -- meia-noite um rascunho criado hoje apareceria datado de amanhã.
       coalesce(p.data_envio,
                (p.criado_em at time zone 'America/Sao_Paulo')::date)
                                                   as data_referencia,
       coalesce(i.qtd_itens, 0)::integer           as qtd_itens,
       coalesce(i.qtd_pedida_total, 0)::integer    as qtd_pedida_total,
       coalesce(i.qtd_recebida_total, 0)::integer  as qtd_recebida_total
  from public.pedido_compra p
  left join (
        select pi.pedido_id,
               count(*)                      as qtd_itens,
               sum(pi.qtd_pedida)            as qtd_pedida_total,
               sum(pi.qtd_recebida)          as qtd_recebida_total
          from public.pedido_item pi
         group by pi.pedido_id
       ) i on i.pedido_id = p.id;

comment on view public.v_pedido_compra is
  'Um pedido de compra por linha, com os agregados que a aba Pedidos da tela 7 mostra (card 6.8, docs/wireframes.md §10.2): quantos itens, quanto foi pedido e quanto já chegou. O agregado vem de SUBCONSULTA agrupada, e não de left join com count(*): sobre o left join, o pedido SEM item contaria 1 (card 2.3 §3.2), e sum() de conjunto vazio devolveria null (§3.1) — pedido sem item é o rascunho recém-criado, e é estado real. Sem join de rótulo nenhum: a rota da tela já exige compras.ler, e cada join interno a mais é um modo de a lista vir vazia por permissão que a tela não pede.';

comment on column public.v_pedido_compra.data_referencia is
  'A data que a linha mostra: data_envio quando o pedido saiu, a data de criação enquanto ele é rascunho. Convertida para America/Sao_Paulo, nunca criado_em::date puro (card 2.3 §3.3) — o banco roda em UTC e um rascunho criado às 22h apareceria datado do dia seguinte.';

comment on column public.v_pedido_compra.qtd_recebida_total is
  'Soma de qtd_recebida dos itens. PODE PASSAR de qtd_pedida_total: o recebimento com excedente é permitido à direção (compras.receber_excedente, card 6.5), e grampear o número aqui faria o pedido dizer "15 de 15" quando chegaram 17.';

revoke all   on public.v_pedido_compra from public;
revoke all   on public.v_pedido_compra from anon;
grant select on public.v_pedido_compra to authenticated;

-- -----------------------------------------------------------------------------
-- 3. v_pedido_item — os itens de um pedido, com o material resolvido
-- -----------------------------------------------------------------------------
-- É a lista do painel de recebimento (wireframe §10.2: "INT-04 | pedido 10 |
-- recebido 10 | [__] receber") e a do rascunho em edição.
--
-- ⚠️ O `join` em `material` é INTERNO de propósito, e aqui é o precedente do
--    card 6.6 (`v_aluno_trilha`) que vale, não o do 6.7 (`v_material_movimento`).
--    A diferença é qual permissão está em jogo: a rota da tela 7 EXIGE
--    `materiais.ler` (docs/permissoes-matriz.md §6, linha 7), então quem chega
--    aqui sem ela já viu a tela "sem acesso" com o diagnóstico. Das duas reduções
--    silenciosas do §3.4, a menos pior é a lista VAZIA: um pedido "cheio de itens
--    sem nome" seria uma lista de apostilas anônimas para conferir contra uma
--    caixa que chegou — e conferir apostila pelo id é como se recebe a errada.
--    Em `v_material_movimento` a escolha foi a oposta porque lá a rota NÃO exige
--    `compras.ler` e a soma exibida tem de fechar com o saldo; aqui não há soma
--    que precise fechar com nada fora da própria lista.
--
-- `qtd_pendente` com o mesmo `greatest(…, 0)` POR ITEM de `v_pedido_sugerido`
-- (card 6.5, views-leitura §6): item recebido com excedente tem
-- `qtd_pedida − qtd_recebida` NEGATIVO, e "faltam −1" não é frase que alguém
-- leia num painel de conferência. O que falta chegar é zero.
create view public.v_pedido_item with (security_invoker = on) as
select pi.unidade_id,
       pi.id            as pedido_item_id,
       pi.pedido_id,
       pi.material_id,
       m.metodo_id,
       m.codigo,
       m.nome,
       m.categoria,
       pi.qtd_pedida,
       pi.qtd_recebida,
       greatest(pi.qtd_pedida - pi.qtd_recebida, 0)::integer as qtd_pendente
  from public.pedido_item pi
  join public.material m on m.id = pi.material_id;

comment on view public.v_pedido_item is
  'Itens de um pedido de compra com o material resolvido, para o painel de recebimento e o rascunho em edição da tela 7 (card 6.8, docs/wireframes.md §10.2). O join em material é INTERNO, como o de v_aluno_trilha (card 6.6) e ao contrário do de v_material_movimento (6.7): a rota da tela 7 já exige materiais.ler, e um item com o nome em branco viraria uma apostila anônima para conferir contra a caixa que chegou.';

comment on column public.v_pedido_item.qtd_pendente is
  'O que falta chegar, com piso ZERO por item (card 6.5): recebimento com excedente deixa qtd_pedida − qtd_recebida negativo, e "faltam −1" não é frase de painel de conferência. É o mesmo greatest(…,0) que v_pedido_sugerido aplica na parcela já pedida, pela mesma razão.';

revoke all   on public.v_pedido_item from public;
revoke all   on public.v_pedido_item from anon;
grant select on public.v_pedido_item to authenticated;
