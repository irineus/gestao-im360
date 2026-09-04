-- =============================================================================
-- Card 6.5 — Fluxo de pedidos de compra: criação, envio e recebimento
--            (total/parcial → ENTRADA), cancelamento e ajuste de estoque
--
-- Fonte: docs/regras-negocio-funcoes.md §7 (fn_ajustar_estoque), §7.1
--        (fn_pedido_receber e os dois triggers), §12 (catálogo de erros) e §13
--        (mapa função → card),
--        docs/modelagem-dados-ddl.md §10 (pedido_compra, pedido_item e
--        movimento_estoque),
--        docs/estrategia-testes.md §13 (obrigação de teste de função de
--        aplicação), §14 (decisões que precisam de teste) e §17 (a suíte é o
--        060_estoque_compras),
--        docs/views-leitura.md §6 (o que v_pedido_sugerido abate, e portanto o
--        que os status escritos aqui precisam manter verdadeiro),
--        docs/permissoes-matriz.md §3.5 (domínio `compras`) e §5.2 (o que ficou
--        só com a direção),
--        docs/wireframes.md §10.1 e §10.2 (a tela 7 do card 6.8, que é a
--        consumidora deste contrato).
--
-- Entrega:
--   • `fn_pedido_criar`, `fn_pedido_enviar`, `fn_pedido_cancelar` — o ciclo
--     RASCUNHO → ENVIADO → (PARCIAL) → RECEBIDO, mais CANCELADO;
--   • `fn_pedido_receber` (§7.1), com recebimento PARCIAL por padrão e a
--     exceção `compras.receber_excedente`;
--   • `fn_ajustar_estoque` (§7);
--   • `tg_movimento_valida_sinal` e `tg_movimento_resolve_pendencia`, os dois
--     triggers que o teste `050` §9 cobra desde o card 6.1;
--   • `tg_pedido_item_recebimento`, que substitui `pedido_item_recebido_ck`
--     (seção 1 — a decisão que este card tinha de tomar);
--   • dez códigos de erro novos, todos no fixture `test/fixtures/codigos_erro.txt`
--     e no catálogo Dart.
--
-- ⚠️ ESTRUTURA E MAIS NADA, como o 6.1, o 6.2 e o 6.3: nenhum pedido, nenhum
--    item e nenhum movimento de estoque entram aqui. Pedidos reais vêm pelo
--    importador do card 9.1, só em dev, e alcançam produção na virada do 9.7;
--    pedido e movimento de teste vivem na camada `trilha_estoque` de
--    supabase/seed.sql, que nunca sai do stack local. O portão do card 4.0,5
--    tem as cinco tabelas da fase 06 fora da lista permitida e segue as
--    chamadas transitivamente.
--
-- =============================================================================
-- A DECISÃO QUE ESTE CARD TINHA DE TOMAR — `check` não conhece permissão
-- =============================================================================
-- O card 6.1 escreveu `pedido_item_recebido_ck check (qtd_recebida <=
-- qtd_pedida)` chamando-o de "camada 1 do recebimento", e escreveu ao lado que
-- "a exceção é `compras.receber_excedente`, e é fn_pedido_receber quem a
-- aplica". As duas frases não cabem juntas: um `check` de tabela vale para todo
-- mundo, inclusive para a função — a direção com `compras.receber_excedente`
-- levaria um `23514` cru, e `RECEBIMENTO_EXCEDE_PEDIDO`, que está no contrato de
-- erros desde o card 2.2 §12, seria um código inalcançável.
--
-- Ou seja: mantido como estava, o card 6.5 entregaria a exceção do card 2.4 §5.2
-- QUEBRADA, com o sintoma sendo um erro de constraint numa tela que fala de
-- recebimento — exatamente o que o card 2.2 §1.2 proíbe chegar ao usuário.
--
-- A saída é a mesma dos cards 4.2 (coluna `status` de `aluno`), 5.1
-- (`bloco_aluno.tipo`) e 6.1 (`aluno_material.ordem`): a regra que DEPENDE DE
-- PERMISSÃO mora num trigger, não num `check`. `tg_pedido_item_recebimento`
-- recusa `qtd_recebida > qtd_pedida` para quem não tem
-- `compras.receber_excedente` — e recusa com o código do catálogo, não com um
-- `23514`. Três consequências que valem escrever:
--
--   (a) a barreira ficou MAIS forte, não mais fraca: um `check` alcança quem tem
--       BYPASSRLS, e este trigger também — a diferença é que agora ele sabe
--       distinguir a direção de todo o resto, e o `PATCH` direto pelo PostgREST
--       continua recusado para secretaria e monitor, que é o que o card 6.1
--       queria dizer com "receber a mais pelo PostgREST não passa aqui";
--   (b) `qtd_recebida >= 0` CONTINUA sendo `check`: ele não depende de permissão
--       nenhuma, e recebimento negativo não é decisão de ninguém;
--   (c) `pedido_item.qtd_recebida` passa a poder ser MAIOR que `qtd_pedida`, e é
--       o que se quer: a alternativa era grampear o número em `qtd_pedida` e
--       deixar o item dizendo "10 de 10" quando chegaram 12 — número errado com
--       cara de certo, e a parcela "já pedida" de `v_pedido_sugerido` ficaria
--       positiva para um pedido que já chegou inteiro.
--
-- ⚠️ O que ISTO obriga na view do card 6.4, e não é hipótese: `qtd_pedida −
--    qtd_recebida` fica NEGATIVO no item recebido com excedente. O
--    `greatest(…, 0)` de `v_pedido_sugerido` age sobre o total, não sobre a
--    parcela, então um item com excedente passaria a ABATER de outros materiais
--    do mesmo pedido. A soma da parcela ganha `greatest(…, 0)` por item nesta
--    migração (seção 8) — a view é do card 6.4, mas o defeito nasce aqui.
--
-- =============================================================================
-- O que este card NÃO traz, e onde está escrito que não é esquecimento:
--   • a TELA de Compras (pedido sugerido, criar, enviar, receber) é o card 6.8,
--     e a de Materiais e estoque — que é quem chama `fn_ajustar_estoque` e a
--     entrada manual — é o card 6.7 (docs/wireframes.md §9 e §10);
--   • `fn_certificado_abrir` e o checklist continuam sendo do card 8.3;
--   • `qtd_projetada` de `v_pedido_sugerido` continua sendo do card 8.2 — esta
--     migração toca a view SÓ na parcela pendente, e a coluna reservada segue
--     `0::integer` na posição definitiva.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. `pedido_item_recebido_ck` vira trigger (a decisão do cabeçalho)
-- -----------------------------------------------------------------------------
alter table public.pedido_item drop constraint pedido_item_recebido_ck;

comment on column public.pedido_item.qtd_recebida is
  'Recebido acumulado. Pode passar de qtd_pedida SOMENTE com compras.receber_excedente (card 2.4 §5.2), e quem faz valer isso é tg_pedido_item_recebimento (card 6.5) — era um `check`, que não conhece permissão e tornava a exceção inalcançável. `qtd_recebida >= 0` continua `check`: não depende de permissão nenhuma.';

create or replace function public.fn_pedido_item_recebimento_valido()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- Camada 2 do recebimento (card 2.2 §1.1): a função de aplicação recusa antes
  -- de escrever, e este trigger alcança QUALQUER caminho até a coluna —
  -- inclusive o `PATCH` direto pelo PostgREST, que a política de update de
  -- `pedido_item` autoriza para quem tem `compras.editar` ou `compras.receber`.
  if new.qtd_recebida > new.qtd_pedida
     and not public.tem_permissao('compras.receber_excedente') then
    raise exception using
      errcode = 'PT422',
      message = 'Quantidade acima do pedido: o recebimento com excedente requer a direção.',
      detail  = json_build_object('codigo', 'RECEBIMENTO_EXCEDE_PEDIDO',
                                  'pedido_item', new.id,
                                  'qtd_pedida', new.qtd_pedida,
                                  'qtd_recebida', new.qtd_recebida)::text;
  end if;

  return new;
end $$;

comment on function public.fn_pedido_item_recebimento_valido() is
  'Trigger BEFORE INSERT OR UPDATE em pedido_item: qtd_recebida só passa de qtd_pedida com compras.receber_excedente (PT422 / RECEBIMENTO_EXCEDE_PEDIDO). Substitui pedido_item_recebido_ck, que valia para todo mundo e tornava a exceção do card 2.4 §5.2 inalcançável.';

revoke execute on function public.fn_pedido_item_recebimento_valido() from public;
revoke execute on function public.fn_pedido_item_recebimento_valido() from anon;

create trigger tg_pedido_item_recebimento
  before insert or update on public.pedido_item
  for each row execute function public.fn_pedido_item_recebimento_valido();

-- -----------------------------------------------------------------------------
-- 2. tg_movimento_valida_sinal (§7.1) — o estorno espelha o movimento de origem
-- -----------------------------------------------------------------------------
-- O que já é `check` no DDL do card 2.1 NÃO se repete aqui: ENTRADA > 0,
-- SAIDA < 0, `quantidade <> 0` e "ESTORNO ⟺ estorno_de_id" são
-- `movimento_sinal_ck` e `movimento_estorno_ck`. Este trigger cobre só o que
-- depende da OUTRA linha, que é o que um `check` não alcança.
--
-- Sem ele, um ESTORNO de magnitude qualquer devolveria ao estoque mais do que
-- saiu — e apontando para outro material devolveria a um material que nunca
-- perdeu nada, com o saldo dos dois errado e nenhuma linha denunciando.
-- `fn_estornar_entrega` (card 6.3) já grava `-v_quantidade`; o trigger é a
-- garantia contra a escrita direta, que a política `insert` POR TIPO permite a
-- quem tem `estoque.estornar`.
--
-- `security invoker`, e a escolha é a de `fn_pc_exclusao_valida` (card 4.3): ele
-- só lê uma linha que o próprio chamador já pode ler, e a falha por RLS é
-- FECHADA — origem invisível vira `MOVIMENTO_INEXISTENTE`, nunca um "passou".
create or replace function public.fn_movimento_valida_sinal()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_qtd      integer;
  v_material uuid;
  v_unidade  uuid;
  v_achou    boolean;
begin
  select mv.quantidade, mv.material_id, mv.unidade_id, true
    into v_qtd, v_material, v_unidade, v_achou
    from public.movimento_estoque mv
   where mv.id = new.estorno_de_id;

  -- Nulo é ERRO e não "sem opinião" (lição do card 5.3): a FK garante que a
  -- linha existe, então não achar aqui significa que a RLS a escondeu — e um
  -- estorno validado contra o que não se pode ler é um estorno não validado.
  if v_achou is not true then
    raise exception using
      errcode = 'PT404',
      message = 'Este movimento de estoque não foi encontrado.',
      detail  = json_build_object('codigo', 'MOVIMENTO_INEXISTENTE',
                                  'movimento', new.estorno_de_id)::text;
  end if;

  if new.quantidade <> -v_qtd
     or new.material_id is distinct from v_material
     or new.unidade_id  is distinct from v_unidade then
    raise exception using
      errcode = 'PT422',
      message = 'O estorno tem de devolver exatamente o que o movimento original movimentou.',
      detail  = json_build_object('codigo', 'ESTORNO_SINAL_INVALIDO',
                                  'movimento', new.estorno_de_id,
                                  'quantidade_esperada', -v_qtd,
                                  'quantidade_informada', new.quantidade)::text;
  end if;

  return new;
end $$;

comment on function public.fn_movimento_valida_sinal() is
  'Trigger BEFORE INSERT em movimento_estoque, só para ESTORNO (card 2.2 §7.1): exige sinal oposto, mesma magnitude, mesmo material e mesma unidade do movimento em estorno_de_id. O que não depende da outra linha já é check no DDL do card 2.1.';

revoke execute on function public.fn_movimento_valida_sinal() from public;
revoke execute on function public.fn_movimento_valida_sinal() from anon;

-- ⚠️ O `when` exige `estorno_de_id not null` além do tipo, e não é redundância
--    com `movimento_estorno_ck`: sem essa metade, um ESTORNO sem origem entraria
--    NESTE trigger (que roda BEFORE, antes de qualquer `check`) e sairia com
--    `MOVIMENTO_INEXISTENTE` — trocando a mensagem certa ("estorno sem origem")
--    por uma que manda procurar um movimento que o autor nunca informou. Camada
--    1 primeiro; o trigger só cobre o que ela não alcança.
create trigger tg_movimento_valida_sinal
  before insert on public.movimento_estoque
  for each row when (new.tipo = 'ESTORNO' and new.estorno_de_id is not null)
  execute function public.fn_movimento_valida_sinal();

-- -----------------------------------------------------------------------------
-- 3. tg_movimento_resolve_pendencia (§7.1) — a chegada fecha o ciclo do §6.2
-- -----------------------------------------------------------------------------
-- A apostila que faltou gerou pendência (`ESTOQUE_ZERO` por material,
-- `COMPRA_SEM_ESTOQUE` por aluno, card 6.3); a chegada do pedido as resolve
-- sozinha. Sem isto, a central do card 5.8 continuaria pedindo a compra de um
-- material que já está na prateleira — e pendência que ninguém fecha é a central
-- inteira perdendo credibilidade.
--
-- ⚠️ DIVERGÊNCIA REGISTRADA em relação ao §7.1, e é ampliação, não corte: o
--    documento condiciona o disparo a "ENTRADA/AJUSTE positivo". A condição que
--    de fato importa é a que ele mesmo escreve na coluna ao lado — "se o saldo
--    do material voltou a ser > 0" —, e o ESTORNO de uma SAIDA devolve exemplar
--    à prateleira exatamente como uma ENTRADA. Deixá-lo de fora manteria a
--    pendência aberta com o material disponível, que é o mal que este trigger
--    existe para impedir. O gatilho, então, é `quantidade > 0`, qualquer que
--    seja o tipo — e AJUSTE negativo continua de fora, porque ele não repõe nada.
--
-- ⚠️ `security definer`, e a razão é a mesma de `fn_revalidar_blocos_sala`
--    (card 5.4) e de `fn_pendencia_abrir`/`fn_pendencia_resolver` (card 5.5):
--    como `invoker`, ele leria `pendencia` sob `pendencias.ler` e
--    `aluno_material` sob `alunos.ler`. Quem recebe compra tem `compras.receber`
--    e pode não ter nenhuma das duas — e a RLS NEGA LINHA em vez de devolver
--    erro, então a pendência simplesmente não fecharia, sem nada denunciando.
--    Com a matriz INICIAL isso não aparece (direção e secretaria têm as três), e
--    o card 4.2 já deixou escrito que isso não é argumento. O filtro de unidade
--    está no corpo, e vem da LINHA que o trigger recebe (`new.unidade_id`), como
--    manda a correção do card 2.3 e faz `fn_perfil_permissao_historico`.
create or replace function public.fn_movimento_resolve_pendencia()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r record;
begin
  -- O saldo é a conta de sempre, e de propósito não é reescrita aqui: uma
  -- terceira implementação da mesma soma divergiria no dia em que uma mudasse
  -- (card 6.3 §2). `material_id` pertence a uma unidade só, então a soma não
  -- cruza unidade nenhuma.
  if public.fn_saldo_material(new.material_id) <= 0 then
    return null;
  end if;

  -- Só chama o fechamento quando há o que fechar. Não é economia: como
  -- `fn_pendencia_resolver` exige unidade no contexto e levanta exceção sem ela,
  -- uma chamada incondicional derrubaria toda escrita de movimento feita fora de
  -- sessão autenticada — a começar pela camada `trilha_estoque` do seed, que
  -- roda como `postgres` e faria o `db reset` inteiro morrer.
  for r in
    select p.chave_dedup
      from public.pendencia p
     where p.unidade_id = new.unidade_id
       and p.resolvida_em is null
       and (
         (p.tipo = 'ESTOQUE_ZERO' and p.material_id = new.material_id)
         or
         -- `COMPRA_SEM_ESTOQUE` é por ALUNO, não por material (card 6.3): o
         -- aluno bloqueado é desbloqueado quando chega alguma apostila que ele
         -- ainda deve receber. Sem o vínculo pela trilha, uma entrada de INGLES
         -- fecharia a pendência de um aluno de INTERATIVO — pendência fechada
         -- sem o problema ter sumido é pior do que pendência aberta.
         (p.tipo = 'COMPRA_SEM_ESTOQUE'
          and exists (select 1 from public.aluno_material am
                       where am.aluno_id = p.aluno_id
                         and am.material_id = new.material_id
                         and not am.entregue))
       )
  loop
    perform public.fn_pendencia_resolver(r.chave_dedup);
  end loop;

  return null;
end $$;

comment on function public.fn_movimento_resolve_pendencia() is
  'Trigger AFTER INSERT em movimento_estoque, para todo movimento POSITIVO (card 2.2 §7.1, ampliado para ESTORNO): com o saldo do material de volta acima de zero, fecha ESTOQUE_ZERO daquele material e COMPRA_SEM_ESTOQUE de cada aluno que ainda deve receber essa apostila. SECURITY DEFINER porque quem recebe compra pode não ter pendencias.ler nem alunos.ler, e a RLS nega linha em silêncio.';

revoke execute on function public.fn_movimento_resolve_pendencia() from public;
revoke execute on function public.fn_movimento_resolve_pendencia() from anon;

create trigger tg_movimento_resolve_pendencia
  after insert on public.movimento_estoque
  for each row when (new.quantidade > 0)
  execute function public.fn_movimento_resolve_pendencia();

-- -----------------------------------------------------------------------------
-- 4. fn_pedido_criar — o RASCUNHO que a tela do card 6.8 monta
-- -----------------------------------------------------------------------------
-- ⚠️ Exige `compras.criar` E `compras.ler`, e o segundo não é zelo: o número do
--    pedido é DERIVADO da leitura dos pedidos da unidade, e sob RLS quem não lê
--    conta zero e produz um número já usado — a redução silenciosa do card 2.3
--    §3.4 chegando à tela como um `23505` cru. Pedir a permissão explicitamente
--    troca isso por `PT403 / SEM_PERMISSAO`, que é uma frase que se entende. Na
--    matriz inicial ninguém tem `compras.criar` sem `compras.ler`, e é por isso
--    que a exigência não muda nada na prática — muda o modo de falha.
--
-- Sem parâmetro de número, de propósito: um número informado de fora colidiria
-- com `pedido_compra_numero_uk` e chegaria à tela como `23505` cru, e o único
-- consumidor que precisaria dele é o importador do card 9.1 — que escreve nas
-- tabelas direto, sem passar por aqui.
create or replace function public.fn_pedido_criar(
  p_itens      jsonb,
  p_fornecedor text default null,
  p_observacao text default null
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade   uuid;
  v_ano       text;
  v_seq       integer;
  v_numero    text;
  v_pedido    uuid;
  v_itens     integer;
  v_distintos integer;
  r           record;
begin
  perform public.fn_exige_permissao('compras.criar');
  perform public.fn_exige_permissao('compras.ler');

  v_unidade := public.fn_unidade_atual();

  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception using
      errcode = 'PT422',
      message = 'Informe ao menos um item para o pedido.',
      detail  = json_build_object('codigo', 'PEDIDO_SEM_ITEM')::text;
  end if;

  -- O mesmo material duas vezes na carga violaria `pedido_item_uk` e chegaria à
  -- tela como `23505` — e o remédio certo não é "tente de novo", é somar as duas
  -- linhas antes de enviar. Por isso o código é próprio, no molde do
  -- MATERIAL_JA_NA_TRILHA do card 6.2.
  select count(*), count(distinct e->>'material_id')
    into v_itens, v_distintos
    from jsonb_array_elements(p_itens) e;

  if v_itens <> v_distintos then
    raise exception using
      errcode = 'PT409',
      message = 'O mesmo material aparece mais de uma vez no pedido. Some as quantidades numa linha só.',
      detail  = json_build_object('codigo', 'MATERIAL_JA_NO_PEDIDO')::text;
  end if;

  -- Serializa a numeração por unidade e ano. Sem o lock, dois pedidos criados no
  -- mesmo instante leem o mesmo `max` e o segundo morre na unique — a mesma
  -- família de corrida da admissão (card 2.2 §4.5) e da entrega (card 6.3).
  v_ano := to_char(public.fn_hoje(), 'YYYY');
  perform pg_advisory_xact_lock(hashtextextended(v_unidade::text || ':' || v_ano, 0));

  select coalesce(max(nullif(split_part(p.numero, '-', 2), '')::integer), 0) + 1
    into v_seq
    from public.pedido_compra p
   where p.unidade_id = v_unidade
     and p.numero ~ ('^' || v_ano || '-[0-9]+$');

  v_numero := v_ano || '-' || lpad(v_seq::text, 3, '0');

  insert into public.pedido_compra (unidade_id, numero, status, fornecedor, observacao)
  values (v_unidade, v_numero, 'RASCUNHO', p_fornecedor, p_observacao)
  returning id into v_pedido;

  for r in
    select (e->>'material_id')::uuid as material_id,
           (e->>'qtd_pedida')::integer as qtd_pedida
      from jsonb_array_elements(p_itens) e
  loop
    if r.qtd_pedida is null or r.qtd_pedida <= 0 then
      raise exception using
        errcode = 'PT422',
        message = 'A quantidade tem de ser maior que zero.',
        detail  = json_build_object('codigo', 'QUANTIDADE_INVALIDA',
                                    'material', r.material_id,
                                    'quantidade', r.qtd_pedida)::text;
    end if;

    -- Material de outra unidade e material inexistente respondem a mesma coisa,
    -- pelo precedente de PC_INEXISTENTE (card 2.9) e ALUNO_INEXISTENTE (4.2):
    -- quem não pode ver não descobre que existe.
    if not exists (select 1 from public.material m where m.id = r.material_id) then
      raise exception using
        errcode = 'PT404',
        message = 'Esta apostila não foi encontrada.',
        detail  = json_build_object('codigo', 'MATERIAL_INEXISTENTE',
                                    'material', r.material_id)::text;
    end if;

    insert into public.pedido_item (unidade_id, pedido_id, material_id, qtd_pedida)
    values (v_unidade, v_pedido, r.material_id, r.qtd_pedida);
  end loop;

  return v_pedido;
end $$;

comment on function public.fn_pedido_criar(jsonb, text, text) is
  'Cria um pedido de compra em RASCUNHO com os itens informados ([{"material_id":…,"qtd_pedida":…}]). Exige compras.criar E compras.ler (o número é derivado da leitura dos pedidos da unidade). Numeração AAAA-NNN por unidade, serializada com pg_advisory_xact_lock. RASCUNHO não abate a parcela "já pedida" de v_pedido_sugerido (card 2.3 §6 (d)).';

revoke execute on function public.fn_pedido_criar(jsonb, text, text) from public;
revoke execute on function public.fn_pedido_criar(jsonb, text, text) from anon;
grant  execute on function public.fn_pedido_criar(jsonb, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. fn_pedido_enviar — o RASCUNHO passa a abater no pedido sugerido
-- -----------------------------------------------------------------------------
-- Enviar não é uma mudança de rótulo: é o instante em que o pedido passa a
-- contar na parcela "já pedida" de `v_pedido_sugerido` (card 2.3 §6 (d)). Um
-- pedido enviado sem item nenhum abateria zero e ficaria para sempre em ENVIADO,
-- porque `fn_pedido_receber` recalcula o status a partir dos itens — daí
-- `PEDIDO_SEM_ITEM` ser recusa, e não aviso.
create or replace function public.fn_pedido_enviar(
  p_pedido_id  uuid,
  p_data_envio date default null
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_status text;
begin
  perform public.fn_exige_permissao('compras.editar');

  select p.status into v_status
    from public.pedido_compra p where p.id = p_pedido_id;

  if v_status is null then
    raise exception using
      errcode = 'PT404',
      message = 'Este pedido de compra não foi encontrado.',
      detail  = json_build_object('codigo', 'PEDIDO_INEXISTENTE',
                                  'pedido', p_pedido_id)::text;
  end if;

  if v_status <> 'RASCUNHO' then
    raise exception using
      errcode = 'PT409',
      message = 'Só pedido em rascunho pode ser enviado.',
      detail  = json_build_object('codigo', 'PEDIDO_NAO_ENVIAVEL',
                                  'pedido', p_pedido_id,
                                  'status', v_status)::text;
  end if;

  if not exists (select 1 from public.pedido_item pi where pi.pedido_id = p_pedido_id) then
    raise exception using
      errcode = 'PT422',
      message = 'Informe ao menos um item para o pedido.',
      detail  = json_build_object('codigo', 'PEDIDO_SEM_ITEM',
                                  'pedido', p_pedido_id)::text;
  end if;

  -- `fn_hoje()` e nunca a data do servidor (card 2.3 §3.3): o Postgres do
  -- Supabase roda em UTC, e das 21h à meia-noite um pedido enviado hoje ficaria
  -- registrado como enviado amanhã.
  update public.pedido_compra p
     set status     = 'ENVIADO',
         data_envio = coalesce(p_data_envio, public.fn_hoje())
   where p.id = p_pedido_id;
end $$;

comment on function public.fn_pedido_enviar(uuid, date) is
  'RASCUNHO → ENVIADO, com data_envio (fn_hoje() por omissão). Exige compras.editar. Pedido sem item é recusado: enviado, ele passa a abater a parcela "já pedida" de v_pedido_sugerido e nunca sairia de ENVIADO, porque o status é recalculado a partir dos itens.';

revoke execute on function public.fn_pedido_enviar(uuid, date) from public;
revoke execute on function public.fn_pedido_enviar(uuid, date) from anon;
grant  execute on function public.fn_pedido_enviar(uuid, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. fn_pedido_cancelar — pedido não se apaga, vira CANCELADO
-- -----------------------------------------------------------------------------
-- `pedido_compra` não tem política de DELETE (card 2.4 §3.5): o histórico de
-- compra é o que explica um saldo três meses depois. Cancelar tira o pedido da
-- parcela "já pedida" sem tirá-lo da história.
--
-- RECEBIDO não se cancela, e a razão é física: o material já entrou no estoque
-- por movimentos que são IMUTÁVEIS. Cancelar deixaria um pedido "que não veio"
-- com ENTRADAs vinculadas aos itens dele — o desfazer certo é o estorno das
-- entradas, não a reescrita do pedido.
create or replace function public.fn_pedido_cancelar(
  p_pedido_id uuid,
  p_motivo    text
)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_status text;
begin
  perform public.fn_exige_permissao('compras.editar');

  -- Motivo obrigatório, pelo precedente de fn_aluno_alterar_status (4.2),
  -- fn_trilha_remover (6.2) e fn_estornar_entrega (6.3): cancelar é decisão, e
  -- decisão sem porquê é decisão perdida.
  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception using
      errcode = 'PT422',
      message = 'Informe o motivo do cancelamento.',
      detail  = json_build_object('codigo', 'MOTIVO_OBRIGATORIO',
                                  'pedido', p_pedido_id)::text;
  end if;

  select p.status into v_status
    from public.pedido_compra p where p.id = p_pedido_id;

  if v_status is null then
    raise exception using
      errcode = 'PT404',
      message = 'Este pedido de compra não foi encontrado.',
      detail  = json_build_object('codigo', 'PEDIDO_INEXISTENTE',
                                  'pedido', p_pedido_id)::text;
  end if;

  if v_status in ('RECEBIDO', 'CANCELADO') then
    raise exception using
      errcode = 'PT409',
      message = 'Este pedido não pode ser cancelado.',
      detail  = json_build_object('codigo', 'PEDIDO_NAO_CANCELAVEL',
                                  'pedido', p_pedido_id,
                                  'status', v_status)::text;
  end if;

  -- O motivo vai para `observacao` porque `pedido_compra` não tem histórico
  -- próprio, e um cancelamento sem porquê registrado é indistinguível de um
  -- pedido que nunca foi feito. Concatena em vez de sobrescrever: o que a
  -- secretaria escreveu ao criar continua lá.
  update public.pedido_compra p
     set status     = 'CANCELADO',
         observacao = coalesce(p.observacao || E'\n', '')
                      || 'CANCELADO em ' || to_char(public.fn_hoje(), 'DD/MM/YYYY')
                      || ': ' || btrim(p_motivo)
   where p.id = p_pedido_id;
end $$;

comment on function public.fn_pedido_cancelar(uuid, text) is
  'Cancela um pedido (qualquer status menos RECEBIDO e CANCELADO), exigindo compras.editar e motivo. Pedido não se apaga — não há política de delete (card 2.4 §3.5) —, e o motivo é acrescentado a observacao. RECEBIDO não se cancela: as ENTRADAs já estão no estoque e são imutáveis; o desfazer certo é o estorno.';

revoke execute on function public.fn_pedido_cancelar(uuid, text) from public;
revoke execute on function public.fn_pedido_cancelar(uuid, text) from anon;
grant  execute on function public.fn_pedido_cancelar(uuid, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. fn_pedido_receber (§7.1) — o vínculo entre a compra e o estoque
-- -----------------------------------------------------------------------------
-- É o ato que a planilha não tinha: lá, a chegada de um pedido e a entrada em
-- estoque eram duas anotações sem ligação nenhuma. Aqui a ENTRADA nasce com
-- `pedido_item_id` preenchido, na mesma transação em que `qtd_recebida` sobe e o
-- status do pedido é recalculado.
--
-- ⚠️ O advisory lock por PEDIDO é da mesma família do da entrega (card 6.3) e do
--    da admissão (card 2.2 §4.5): dois recebimentos parciais simultâneos do
--    mesmo item leem `qtd_recebida` antes de a outra transação escrever, e o
--    total ultrapassa `qtd_pedida` sem que nenhuma das duas tenha visto o
--    excedente. NENHUMA constraint pega isso: é regra de AGREGADO, como o saldo.
--    O trigger da seção 1 fecharia o buraco por sorte de ordenação; o lock o
--    fecha por construção.
create or replace function public.fn_pedido_receber(
  p_pedido_id uuid,
  p_itens     jsonb
)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade  uuid;
  v_numero   text;
  v_status   text;
  v_entradas integer := 0;
  v_completo boolean;
  r          record;
  v_item     record;
begin
  perform public.fn_exige_permissao('compras.receber');

  perform pg_advisory_xact_lock(hashtextextended(p_pedido_id::text, 0));

  select p.unidade_id, p.numero, p.status
    into v_unidade, v_numero, v_status
    from public.pedido_compra p where p.id = p_pedido_id;

  if v_status is null then
    raise exception using
      errcode = 'PT404',
      message = 'Este pedido de compra não foi encontrado.',
      detail  = json_build_object('codigo', 'PEDIDO_INEXISTENTE',
                                  'pedido', p_pedido_id)::text;
  end if;

  -- RASCUNHO não foi feito a ninguém, RECEBIDO já entrou inteiro e CANCELADO não
  -- vem: os três recusam com o mesmo código, porque a frase que o usuário precisa
  -- ler é a mesma.
  if v_status not in ('ENVIADO', 'PARCIAL') then
    raise exception using
      errcode = 'PT409',
      message = 'Este pedido não está aguardando recebimento.',
      detail  = json_build_object('codigo', 'PEDIDO_NAO_RECEBIVEL',
                                  'pedido', p_pedido_id,
                                  'status', v_status)::text;
  end if;

  if jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception using
      errcode = 'PT422',
      message = 'Informe ao menos um item para o pedido.',
      detail  = json_build_object('codigo', 'PEDIDO_SEM_ITEM',
                                  'pedido', p_pedido_id)::text;
  end if;

  for r in
    select (e->>'pedido_item_id')::uuid as item_id,
           (e->>'quantidade')::integer  as quantidade
      from jsonb_array_elements(p_itens) e
  loop
    if r.quantidade is null or r.quantidade <= 0 then
      raise exception using
        errcode = 'PT422',
        message = 'A quantidade tem de ser maior que zero.',
        detail  = json_build_object('codigo', 'QUANTIDADE_INVALIDA',
                                    'pedido_item', r.item_id,
                                    'quantidade', r.quantidade)::text;
    end if;

    select pi.id, pi.material_id, pi.qtd_pedida, pi.qtd_recebida
      into v_item
      from public.pedido_item pi
     where pi.id = r.item_id and pi.pedido_id = p_pedido_id;

    -- Item de OUTRO pedido e item inexistente respondem a mesma coisa: o que
    -- interessa a quem está na tela é que aquela linha não é deste recebimento.
    if v_item.id is null then
      raise exception using
        errcode = 'PT422',
        message = 'Este item não pertence ao pedido que está sendo recebido.',
        detail  = json_build_object('codigo', 'ITEM_FORA_DO_PEDIDO',
                                    'pedido', p_pedido_id,
                                    'pedido_item', r.item_id)::text;
    end if;

    -- Camada 1 do §7.1 passo 2. O trigger da seção 1 diz a MESMA coisa e é a
    -- garantia contra a escrita direta; aqui a recusa vem antes de qualquer
    -- movimento ser gravado, que é o que separa "recusou" de "recusou pela
    -- metade".
    if v_item.qtd_recebida + r.quantidade > v_item.qtd_pedida
       and not public.tem_permissao('compras.receber_excedente') then
      raise exception using
        errcode = 'PT422',
        message = 'Quantidade acima do pedido: o recebimento com excedente requer a direção.',
        detail  = json_build_object('codigo', 'RECEBIMENTO_EXCEDE_PEDIDO',
                                    'pedido_item', v_item.id,
                                    'qtd_pedida', v_item.qtd_pedida,
                                    'qtd_recebida', v_item.qtd_recebida,
                                    'quantidade', r.quantidade)::text;
    end if;

    -- Quantidade COM SINAL (card 2.1): `movimento_sinal_ck` já exige ENTRADA > 0.
    -- O `pedido_item_id` é o vínculo compra ↔ estoque, e é ele que permite
    -- responder "de que pedido veio este exemplar?" três meses depois.
    insert into public.movimento_estoque
      (unidade_id, material_id, tipo, quantidade, pedido_item_id, ocorrido_em, observacao)
    values (v_unidade, v_item.material_id, 'ENTRADA', r.quantidade, v_item.id, now(),
            'recebimento do pedido ' || v_numero);

    update public.pedido_item pi
       set qtd_recebida = pi.qtd_recebida + r.quantidade
     where pi.id = v_item.id;

    v_entradas := v_entradas + 1;
  end loop;

  -- Passo 4: o status sai do que os ITENS dizem, nunca de um contador próprio —
  -- contador de pedido divergiria dos itens na primeira escrita direta, e a
  -- parcela "já pedida" de v_pedido_sugerido é lida dos itens.
  select bool_and(pi.qtd_recebida >= pi.qtd_pedida) into v_completo
    from public.pedido_item pi where pi.pedido_id = p_pedido_id;

  update public.pedido_compra p
     set status = case when v_completo then 'RECEBIDO' else 'PARCIAL' end
   where p.id = p_pedido_id;

  return v_entradas;
end $$;

comment on function public.fn_pedido_receber(uuid, jsonb) is
  'Recebimento de pedido (card 2.2 §7.1), parcial por padrão: por item de [{"pedido_item_id":…,"quantidade":…}] grava uma ENTRADA com pedido_item_id preenchido, soma qtd_recebida e recalcula o status do pedido (RECEBIDO se todos completos, senão PARCIAL). Exige compras.receber; acima do pedido só com compras.receber_excedente. Devolve quantas ENTRADAs criou. Serializa o pedido com pg_advisory_xact_lock.';

revoke execute on function public.fn_pedido_receber(uuid, jsonb) from public;
revoke execute on function public.fn_pedido_receber(uuid, jsonb) from anon;
grant  execute on function public.fn_pedido_receber(uuid, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- 8. fn_ajustar_estoque (§7) — a conferência de prateleira
-- -----------------------------------------------------------------------------
-- "Sinal livre" (§7) quer dizer que o ajuste vale nos dois sentidos, e não que
-- ele possa levar o saldo a NEGATIVO: saldo negativo reprova o critério (4) do
-- marco 6.9 e é um número que ninguém consegue explicar. O ajuste que faltar é
-- uma conferência errada; o remédio é conferir de novo, não deixar o sistema
-- afirmar que existem −3 apostilas na prateleira.
create or replace function public.fn_ajustar_estoque(
  p_material_id uuid,
  p_quantidade  integer,
  p_motivo      text
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_mov     uuid;
begin
  perform public.fn_exige_permissao('estoque.ajustar');

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception using
      errcode = 'PT422',
      message = 'Informe o motivo do ajuste.',
      detail  = json_build_object('codigo', 'MOTIVO_OBRIGATORIO',
                                  'material', p_material_id)::text;
  end if;

  -- Zero é recusado antes de chegar ao `check (quantidade <> 0)`: o erro cru de
  -- constraint é o que o card 2.2 §1.2 proíbe chegar à tela.
  if p_quantidade is null or p_quantidade = 0 then
    raise exception using
      errcode = 'PT422',
      message = 'A quantidade do ajuste não pode ser zero.',
      detail  = json_build_object('codigo', 'QUANTIDADE_INVALIDA',
                                  'material', p_material_id,
                                  'quantidade', p_quantidade)::text;
  end if;

  select m.unidade_id into v_unidade
    from public.material m where m.id = p_material_id;

  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Esta apostila não foi encontrada.',
      detail  = json_build_object('codigo', 'MATERIAL_INEXISTENTE',
                                  'material', p_material_id)::text;
  end if;

  -- O mesmo lock por material da entrega (card 6.3): sem ele, dois ajustes
  -- negativos simultâneos leem o mesmo saldo e a soma fecha abaixo de zero, cada
  -- um deles parecendo certo sozinho.
  perform pg_advisory_xact_lock(hashtextextended(p_material_id::text, 0));

  if public.fn_saldo_material(p_material_id) + p_quantidade < 0 then
    raise exception using
      errcode = 'PT409',
      message = 'O ajuste deixaria o estoque negativo. Confira a contagem.',
      detail  = json_build_object('codigo', 'SALDO_INSUFICIENTE',
                                  'material', p_material_id,
                                  'saldo', public.fn_saldo_material(p_material_id),
                                  'quantidade', p_quantidade)::text;
  end if;

  insert into public.movimento_estoque
    (unidade_id, material_id, tipo, quantidade, ocorrido_em, observacao)
  values (v_unidade, p_material_id, 'AJUSTE', p_quantidade, now(), btrim(p_motivo))
  returning id into v_mov;

  return v_mov;
end $$;

comment on function public.fn_ajustar_estoque(uuid, integer, text) is
  'Ajuste manual de estoque (card 2.2 §7): movimento AJUSTE com sinal livre, motivo OBRIGATÓRIO, exigindo estoque.ajustar. Recusa ajuste que deixaria o saldo negativo (PT409 / SALDO_INSUFICIENTE) — "sinal livre" é sobre a direção do ajuste, não sobre o saldo, e saldo negativo reprova o critério (4) do marco 6.9. Serializa o material com pg_advisory_xact_lock.';

revoke execute on function public.fn_ajustar_estoque(uuid, integer, text) from public;
revoke execute on function public.fn_ajustar_estoque(uuid, integer, text) from anon;
grant  execute on function public.fn_ajustar_estoque(uuid, integer, text) to authenticated;

-- -----------------------------------------------------------------------------
-- 9. v_pedido_sugerido — a parcela pendente não pode ficar negativa
-- -----------------------------------------------------------------------------
-- Consequência direta da decisão do cabeçalho, e o único ponto em que este card
-- toca uma view do card 6.4. Com o excedente permitido, `qtd_pedida −
-- qtd_recebida` fica NEGATIVO no item que recebeu a mais; a soma por material
-- levaria esse negativo para `qtd_pedida_pendente`, e o `greatest(…, 0)` do
-- total não o alcança — ele age sobre a soma, não sobre a parcela. O efeito
-- seria um item recebido com excedente MANDANDO COMPRAR outro material do mesmo
-- pedido, com todas as parcelas parecendo plausíveis ao lado.
--
-- ⚠️ Muda UMA expressão: `sum(...)` vira `sum(greatest(..., 0))`. `qtd_projetada`
--    continua `0::integer` na posição definitiva, reservada para o card 8.2, e
--    a ordem das colunas é a mesma — é o que o teste 095 assere por `attnum`.
create or replace view public.v_pedido_sugerido with (security_invoker = on) as
select e.unidade_id,
       e.material_id,
       e.metodo_id,
       e.codigo,
       e.nome,
       e.categoria,
       e.saldo,
       e.estoque_minimo,
       coalesce(di.qtd_alunos, 0)::integer         as qtd_imediata,
       0::integer                                  as qtd_projetada,   -- card 8.2 substitui (§6.2)
       coalesce(pp.qtd_pendente, 0)::integer       as qtd_pedida_pendente,
       greatest(
         coalesce(di.qtd_alunos, 0)
         + 0                                                            -- idem
         + e.estoque_minimo
         - e.saldo
         - coalesce(pp.qtd_pendente, 0),
         0)::integer                               as qtd_sugerida
  from public.v_estoque_atual e
  left join public.v_demanda_imediata di
         on di.unidade_id = e.unidade_id and di.material_id = e.material_id
  left join (
         select pi.unidade_id, pi.material_id,
                -- `greatest(…, 0)` POR ITEM (card 6.5): item recebido com
                -- excedente tem pendente negativo, e um negativo aqui abateria a
                -- necessidade de OUTRO material do mesmo pedido.
                sum(greatest(pi.qtd_pedida - pi.qtd_recebida, 0))::integer as qtd_pendente
           from public.pedido_item pi
           join public.pedido_compra pc on pc.id = pi.pedido_id
          where pc.status in ('ENVIADO','PARCIAL')
          group by pi.unidade_id, pi.material_id
       ) pp on pp.unidade_id = e.unidade_id and pp.material_id = e.material_id
 where e.ativo;

comment on view public.v_pedido_sugerido is
  'Pedido sugerido v1 (card 2.3 §6): imediata + projetada + mínimo − saldo − pendente, com greatest(…,0). Devolve TODO material ativo, inclusive com qtd_sugerida = 0 — quem filtra é a tela. Leitura exige materiais.ler, estoque.ler, alunos.ler E compras.ler: qualquer uma que falte devolve número menor sem erro nenhum.';

comment on column public.v_pedido_sugerido.qtd_projetada is
  'RESERVA do card 8.2, na posição definitiva (card 2.3 §6.2). Zero até a projeção existir, porque create or replace view não insere coluna no meio nem troca tipo — o 8.2 troca esta expressão e a parcela correspondente do greatest, e nada mais.';

comment on column public.v_pedido_sugerido.qtd_pedida_pendente is
  'qtd_pedida − qtd_recebida somada por ITEM, com piso zero por item (card 6.5), só de pedidos ENVIADO e PARCIAL. RASCUNHO não abate (nunca foi feito a ninguém), RECEBIDO já está no saldo e CANCELADO não virá.';

-- `create or replace view` preserva os privilégios, mas repeti-los aqui é o que
-- mantém o arquivo legível sozinho — e o que garante o estado certo se um dia
-- alguém trocar o `replace` por `drop`/`create`.
revoke all   on public.v_pedido_sugerido from public;
revoke all   on public.v_pedido_sugerido from anon;
grant select on public.v_pedido_sugerido to authenticated;
