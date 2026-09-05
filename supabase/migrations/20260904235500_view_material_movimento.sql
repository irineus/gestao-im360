-- =============================================================================
-- Card 6.7 — v_material_movimento: o histórico de um material como a tela lê
-- Fonte: docs/wireframes.md §9 (a tela 6, e o painel "Movimentações INT-04"),
--        docs/views-leitura.md §12.1 (a view é deste card) e §2 (princípios),
--        §3 (as quatro armadilhas), §3.4 (a RLS que reduz em silêncio),
--        docs/permissoes-matriz.md §6 linha 6 (`materiais.ler` + `estoque.ler`,
--        e mais nada — nem `alunos.ler`, nem `compras.ler`, nem `admin.ler`),
--        docs/design-system.md §7.2 (o estado vazio deste painel),
--        docs/estrategia-testes.md §13 (obrigação de teste de card de View).
--
-- Entrega: UMA view de listagem, `security_invoker = on`, com `unidade_id`,
--          colunas explícitas e o `revoke`/`grant` do §2.5.
--
-- ⚠️ NENHUMA LINHA DE DADO. Migração é o que o CI empurra para produção sozinho
--    no merge em `main` (decisão de 02/09/2026): view é estrutura, e
--    `movimento_estoque` está vazia em produção até a virada do card 9.7 — lá
--    esta view devolve zero linha, que é o estado correto.
--
-- =============================================================================
-- A DECISÃO DESTE ARQUIVO — TODO `join` É EXTERNO, E É O CONTRÁRIO DO 6.6
-- =============================================================================
-- `v_aluno_trilha` (card 6.6) tem o `join` em `material` INTERNO de propósito:
-- sem `materiais.ler` a trilha vem VAZIA, porque uma trilha com o nome em branco
-- pareceria uma trilha curta e a pessoa entregaria a apostila errada. Aqui a
-- escolha é a oposta, e pelo mesmo método — perguntar o que cada forma de errar
-- custa:
--
--   • esta view é a CONFERÊNCIA do saldo. O painel existe para explicar por que
--     `v_estoque_atual` diz 7, e a soma das quantidades exibidas tem de fechar
--     com esse 7. Uma linha que some por causa de um RÓTULO ilegível quebra a
--     conta na tela **sem erro nenhum**: o saldo diria 7 e o histórico somaria 9,
--     e a pessoa concluiria que o sistema perdeu movimento;
--
--   • os quatro rótulos que esta view resolve moram atrás de permissões que a
--     rota da tela 6 **não exige** (docs/permissoes-matriz.md §6): o nome do
--     aluno pede `alunos.ler`, o número do pedido pede `compras.ler`, e o nome
--     de quem lançou pede `admin.ler` (ou ser a própria pessoa — card 3.4). Com
--     `join` interno, o monitor — que não tem `compras.ler` — deixaria de ver
--     **toda ENTRADA vinda de pedido**, que é a maioria das entradas do sistema.
--
-- Por isso: `left join` em `aluno`, `pedido_item`/`pedido_compra`, `usuario` e no
-- próprio `movimento_estoque` (o estornado). A contagem de linhas desta view é
-- **igual para todos os perfis que têm `estoque.ler`**, e o teste `061` assere
-- isso perfil a perfil, com a contraprova de que o rótulo de fato some.
--
-- ⚠️ O QUE ISSO OBRIGA NA TELA, e sem isso a decisão vira defeito: `aluno_id`,
--    `pedido_item_id` e `criado_por` vão na view AO LADO dos nomes justamente
--    para a tela distinguir "não tem aluno" de "tem aluno e você não pode
--    vê-lo". Mostrar "—" nos dois casos seria a mentira que o card 4.6 recusou
--    na ficha do aluno (pendência 9.13): lá a saída foi OMITIR o nome, e aqui é
--    dizer que ele existe e não está visível. Um traço no lugar de um aluno faria
--    uma SAIDA de entrega parecer um ajuste sem dono.
--
-- ⚠️ NÃO HÁ `join` EM `material`, e isso não é esquecimento: o painel é de UM
--    material, escolhido na lista de cima, e a lista já veio de `v_estoque_atual`
--    com código e nome. Trazê-los de novo acrescentaria a única redução
--    silenciosa que ainda faltava — sem `materiais.ler` o painel viria vazio,
--    numa tela cuja rota já exige `materiais.ler` para abrir. Cada `join` interno
--    a mais é mais um modo de a view vir vazia por permissão que a tela não pede
--    (card 5.7).
--
-- ⚠️ SEM `estoque.ler` NÃO VEM LINHA NENHUMA, e aqui isso é o comportamento
--    CERTO, não a redução silenciosa do §3.4: `movimento_estoque` é o assunto da
--    view, não um rótulo dela. A rota da tela exige `estoque.ler` (§6 linha 6),
--    então quem chega ao painel já passou por essa guarda.
--
-- =============================================================================
-- O que este card NÃO traz, e onde está escrito que não é esquecimento:
--   • `saldo_apos` (o saldo linha a linha) NÃO existe: §12.1 diz que as views de
--     tela são "de listagem, sem número derivado", e um saldo acumulado por
--     linha seria a TERCEIRA implementação da soma que o card 2.3 §4.1 proíbe —
--     e erraria para quem não tivesse `estoque.ler`, que já não vê linha nenhuma;
--   • o ESTORNO de uma SAIDA continua sendo feito na aba Trilha do aluno
--     (wireframe §9, última linha), onde há contexto; aqui a listagem é
--     conferência e não tem botão de estorno;
--   • a ENTRADA por recebimento de pedido é da tela 7 (card 6.8).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. v_material_movimento
-- -----------------------------------------------------------------------------
-- A ordem das colunas é contrato (card 2.3 §6.2): `create or replace view` não
-- insere coluna no meio nem troca tipo. Colunas novas entram no FIM.
create view public.v_material_movimento with (security_invoker = on) as
select mov.unidade_id,
       mov.id                                       as movimento_id,
       mov.material_id,
       mov.tipo,
       -- COM SINAL, como a coluna (card 6.1): a tela mostra "−1" e "+10", e a
       -- soma da lista fecha com o saldo de `v_estoque_atual`. Um valor absoluto
       -- com o sinal derivado do `tipo` recriaria em Dart o `case` por tipo que
       -- o card 2.1 tirou do banco de propósito.
       mov.quantidade,
       mov.ocorrido_em,
       mov.observacao,
       -- --- os quatro rótulos externos, todos `left join` ---------------------
       mov.aluno_id,
       a.nome                                       as aluno_nome,
       a.codigo_sgf                                 as aluno_codigo_sgf,
       mov.pedido_item_id,
       pc.numero                                    as pedido_numero,
       mov.estorno_de_id,
       orig.tipo                                    as estorno_de_tipo,
       orig.ocorrido_em                             as estorno_de_ocorrido_em,
       mov.criado_por,
       u.nome                                       as criado_por_nome
  from public.movimento_estoque mov
  left join public.aluno a
         on a.id = mov.aluno_id
  left join public.pedido_item pi
         on pi.id = mov.pedido_item_id
  left join public.pedido_compra pc
         on pc.id = pi.pedido_id
  -- O movimento estornado é da MESMA tabela e da mesma política (`estoque.ler`):
  -- este `left join` não abre nem fecha nada que a linha de cima já não decida.
  -- Continua externo porque `estorno_de_id` é nulo em três dos quatro tipos.
  left join public.movimento_estoque orig
         on orig.id = mov.estorno_de_id
  left join public.usuario u
         on u.id = mov.criado_por;

comment on view public.v_material_movimento is
  'Movimentações de um material para o painel da tela 6 (card 6.7, docs/wireframes.md §9): uma linha por movimento_estoque, com aluno, pedido, estorno e autor resolvidos. TODOS os joins de rótulo são EXTERNOS, ao contrário do de v_aluno_trilha: a rota da tela exige só materiais.ler + estoque.ler, e uma linha que sumisse por causa de um rótulo ilegível faria a soma do histórico não fechar com o saldo de v_estoque_atual — sem erro nenhum. Quem não tem estoque.ler não vê linha nenhuma, e isso é o certo: o movimento é o assunto da view, não um rótulo dela.';

comment on column public.v_material_movimento.quantidade is
  'COM SINAL, igual à coluna (card 6.1): a soma das linhas do painel fecha com o saldo de v_estoque_atual. A tela NÃO deriva o sinal do tipo — seria recriar em Dart o `case` por tipo que o card 2.1 tirou do banco.';

comment on column public.v_material_movimento.aluno_id is
  'Vai ao lado de aluno_nome de propósito: com alunos.ler ausente o nome vem nulo e o id não, e é assim que a tela distingue "movimento sem aluno" de "tem aluno e você não pode vê-lo". Um traço nos dois casos faria uma SAIDA de entrega parecer um ajuste sem dono (a mesma armadilha da pendência 9.13, card 4.6).';

comment on column public.v_material_movimento.pedido_numero is
  'Nulo quando o movimento não veio de pedido OU quando o leitor não tem compras.ler — que é o caso do MONITOR (card 2.3). O par com pedido_item_id desfaz a ambiguidade; com join interno, o monitor deixaria de ver toda ENTRADA vinda de pedido.';

comment on column public.v_material_movimento.criado_por_nome is
  'Nulo para quem não tem admin.ler e não é a própria pessoa (card 3.4: a política de select de usuario é admin.ler OR id = auth.uid()). A tela OMITE o "por …" nesse caso, em vez de escrever "por —" (decisão do card 4.6, pendência 9.13).';

revoke all   on public.v_material_movimento from public;
revoke all   on public.v_material_movimento from anon;
grant select on public.v_material_movimento to authenticated;
