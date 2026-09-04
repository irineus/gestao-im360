-- =============================================================================
-- Card 6.4 — Views: estoque atual, demanda imediata e pedido sugerido
--            (v_estoque_atual, v_demanda_imediata_aluno, v_demanda_imediata,
--             v_pedido_sugerido)
-- Fonte: docs/views-leitura.md §4.1 (estoque), §5.1 e §5.2 (demanda), §6 e §6.2
--        (pedido sugerido), §2 (princípios), §3 (as quatro armadilhas) e §11
--        (permissões de leitura por view),
--        docs/modelagem-dados-ddl.md §10 (estoque e compras),
--        docs/estrategia-testes.md §13 (obrigação de teste de card de View).
--
-- Entrega: as quatro views da fase 06, todas `security_invoker = on`, todas com
--          `unidade_id` e colunas explícitas, todas com `revoke`/`grant` do §2.5.
--
-- ⚠️ NENHUMA LINHA DE DADO. Migração é o que o CI empurra para produção sozinho
--    no merge em `main` (decisão de 02/09/2026): view é estrutura, e estas
--    quatro nascem sobre tabelas que estão vazias em produção até a virada do
--    card 9.7. Elas devolvem zero linha lá, o que é o estado correto.
--
-- O que este card NÃO traz, e onde está escrito que não é esquecimento:
--   • `demanda_projetada` e `v_demanda_projetada` são do card 8.1
--     (docs/views-leitura.md §5.3, que fixa o CONTRATO agora);
--   • a parcela projetada de `v_pedido_sugerido` é do card 8.2 — aqui ela nasce
--     como o literal `0::integer` NA POSIÇÃO DEFINITIVA (seção 4 abaixo);
--   • `v_material_movimento` (histórico por material) é do card 6.7 e
--     `v_aluno_trilha` do 6.6 (§12.1): são views de LISTAGEM, sem número
--     derivado, e pertencem aos cards das telas;
--   • `fn_pedido_receber` e `fn_ajustar_estoque` são do card 6.5 — view não
--     escreve, e o `qtd_recebida` que a seção 4 lê é escrito por lá.
--
-- ⚠️ AJUSTE 12 DO §7 DE docs/permissoes-matriz.md, ATRIBUÍDO A ESTE CARD:
--    `v_demanda_imediata_aluno`/`v_demanda_imediata` declaravam `materiais.ler`
--    no conjunto mínimo do §11 e **não leem tabela de material nenhuma** — só
--    `aluno_material` e `aluno`, as duas com política de `select` por
--    `alunos.ler`. O conjunto correto é `alunos.ler`, e só. Quem precisa do NOME
--    do material é a tela; a view devolve `material_id`. Corrigido no documento
--    e asserido no teste 095 (seção 12), com contraprova: um perfil que tem
--    `alunos.ler` e NÃO tem `materiais.ler` vê a demanda INTEIRA.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. v_estoque_atual — docs/views-leitura.md §4.1
-- -----------------------------------------------------------------------------
-- Saldo é `sum(quantidade)` de `movimento_estoque`, COM SINAL, como o card 2.1
-- fechou: nunca coluna, nunca cache, e nunca um `case` por tipo — com `case`, o
-- tipo novo que alguém acrescentar ao `check` entra na tabela e some da conta.
--
-- Duas das quatro armadilhas do §3 moram nesta view, e as duas produzem o mesmo
-- desfecho: o material MAIS urgente de comprar desaparece da lista de compras.
--   • §3.1 — `sum()` de conjunto vazio é `null`, não zero, e `null <
--     estoque_minimo` é `null`, não `true`. Daí `left join` (nunca `join`) e
--     `coalesce(sum(…), 0)`: material recém-cadastrado, sem movimento nenhum,
--     aparece com saldo 0 e `abaixo_minimo` verdadeiro.
--   • §3.2 — `count(*)` sobre `left join` conta a LINHA NULA e devolveria 1 para
--     esse mesmo material. A contagem é `count(mov.id)`, sobre uma coluna que
--     não pode ser nula do lado certo do join.
--
-- Material INATIVO continua aqui, de propósito (§2.3): apostila aposentada com
-- saldo é estoque que a escola tem. Quem restringe a `ativo` é a seção 4, que
-- fala de COMPRAR — e essa é a exceção declarada.
create view public.v_estoque_atual with (security_invoker = on) as
select m.unidade_id,
       m.id             as material_id,
       m.metodo_id,
       m.codigo,
       m.nome,
       m.categoria,
       m.ativo,
       m.estoque_minimo,
       coalesce(sum(mov.quantidade), 0)::integer             as saldo,
       (coalesce(sum(mov.quantidade), 0) < m.estoque_minimo) as abaixo_minimo,
       count(mov.id)::integer                                as qtd_movimentos,
       max(mov.ocorrido_em)                                  as ultimo_movimento_em
  from public.material m
  left join public.movimento_estoque mov
         on mov.material_id = m.id
        and mov.unidade_id  = m.unidade_id
 group by m.unidade_id, m.id, m.metodo_id, m.codigo, m.nome,
          m.categoria, m.ativo, m.estoque_minimo;

comment on view public.v_estoque_atual is
  'Saldo por material = soma COM SINAL de movimento_estoque (card 2.3 §4.1). Inclui material sem movimento (saldo 0, qtd_movimentos 0) e material INATIVO. Leitura exige materiais.ler E estoque.ler: sem a segunda, a RLS esconde os movimentos e todo saldo vem 0 sem erro nenhum.';

comment on column public.v_estoque_atual.saldo is
  'NÃO deveria ser negativo — fn_registrar_entrega bloqueia ou pula por falta de estoque, e o advisory lock do card 2.2 impede a corrida do último exemplar. Negativo é sintoma de AJUSTE errado, e a tela do card 6.7 DESTACA, não esconde.';

revoke all   on public.v_estoque_atual from public;
revoke all   on public.v_estoque_atual from anon;
grant select on public.v_estoque_atual to authenticated;

-- -----------------------------------------------------------------------------
-- 2. v_demanda_imediata_aluno — docs/views-leitura.md §5.1
-- -----------------------------------------------------------------------------
-- Detalhe primeiro, agregado depois (seção 3 é escrita em cima desta): duas
-- consultas independentes para o total e para o detalhe é como o total e o
-- detalhe passam a divergir, e a tela de projeção (card 8.5) pede o drill-down.
--
-- `distinct on (am.aluno_id) … order by am.aluno_id, am.ordem` é o "próximo
-- livro" do card 2.2 §5.2 — menor `ordem` com `entregue = false` — escrito uma
-- vez para todos os alunos, e derivado, nunca coluna.
--
-- Só ATIVO e ACELERAR: aluno em STANDBY, TRANCADO, CANCELADO ou FORMADO não
-- gera compra. Aluno sem trilha (o sem combo) não tem linha, e aluno em FIM
-- também não — nenhuma das duas é ausência de dado, é ausência de demanda.
create view public.v_demanda_imediata_aluno with (security_invoker = on) as
select distinct on (am.aluno_id)
       am.unidade_id,
       am.aluno_id,
       a.nome        as aluno_nome,
       a.codigo_sgf,
       a.status      as aluno_status,
       a.metodo_id,
       am.material_id,
       am.id         as aluno_material_id,
       am.ordem,
       (select count(*) from public.aluno_material p
         where p.aluno_id = am.aluno_id and not p.entregue)::integer as itens_pendentes
  from public.aluno_material am
  join public.aluno a on a.id = am.aluno_id
 where not am.entregue
   and a.status in ('ATIVO','ACELERAR')
 order by am.aluno_id, am.ordem;

comment on view public.v_demanda_imediata_aluno is
  'Próximo livro de cada aluno ATIVO/ACELERAR — o drill-down por aluno da coluna DEMANDA da planilha (card 2.3 §5.1). Leitura exige alunos.ler, e SÓ: a view não lê tabela de material nenhuma, e o materiais.ler que o §11 declarava era o ajuste 12 do §7 do card 2.4, fechado pelo card 6.4.';

revoke all   on public.v_demanda_imediata_aluno from public;
revoke all   on public.v_demanda_imediata_aluno from anon;
grant select on public.v_demanda_imediata_aluno to authenticated;

-- -----------------------------------------------------------------------------
-- 3. v_demanda_imediata — docs/views-leitura.md §5.2
-- -----------------------------------------------------------------------------
-- `security_invoker` DE NOVO, e não por descuido: a opção é por view e NÃO é
-- herdada (§2.1). Sem ela aqui, esta agregação rodaria como o dono e devolveria
-- a demanda das duas unidades a quem só pode ver uma — com a view de baixo
-- respeitando a RLS e a de cima não, que é o pior dos dois mundos.
--
-- Material sem demanda NÃO tem linha aqui. Quem precisa da lista completa é a
-- seção 4, que faz `left join` e `coalesce` — de novo o §3.1.
create view public.v_demanda_imediata with (security_invoker = on) as
select unidade_id,
       material_id,
       count(*)::integer as qtd_alunos
  from public.v_demanda_imediata_aluno
 group by unidade_id, material_id;

comment on view public.v_demanda_imediata is
  'Quantos alunos ATIVO/ACELERAR têm este material como PRÓXIMO livro (card 2.3 §5.2) — a coluna DEMANDA da planilha. Material sem demanda não aparece; quem precisa da lista inteira é v_pedido_sugerido. Leitura exige alunos.ler.';

revoke all   on public.v_demanda_imediata from public;
revoke all   on public.v_demanda_imediata from anon;
grant select on public.v_demanda_imediata to authenticated;

-- -----------------------------------------------------------------------------
-- 4. v_pedido_sugerido — docs/views-leitura.md §6, completada no card 8.2
-- -----------------------------------------------------------------------------
--   sugerido = imediata + projetada(H) + estoque_mínimo − estoque − não recebido
--
-- ⚠️ `qtd_projetada` NASCE COMO `0::integer` NA POSIÇÃO DEFINITIVA (§6.2), e o
--    zero é reserva documentada, não esquecimento. `create or replace view` não
--    insere coluna no meio, não renomeia e não troca tipo — só acrescenta no
--    fim. Se a coluna aparecesse só na Fase 8, o card 8.2 teria de `drop view`,
--    derrubando em cascata tudo o que dependesse dela, ou pendurar a projeção
--    fora de ordem. Reservada aqui, o 8.2 vira um `create or replace` que troca
--    DUAS EXPRESSÕES: o literal desta coluna e a parcela do `greatest`.
--
-- Quatro escolhas do §6 que a migração não pode simplificar:
--   (a) `RASCUNHO` NÃO abate. Pedido em rascunho não foi feito a ninguém, e
--       contá-lo faria o sistema parar de sugerir uma compra que nunca vai
--       chegar. `RECEBIDO` também não abate (já está no saldo) e `CANCELADO`
--       tampouco (não virá). Abatem só `ENVIADO` e `PARCIAL`.
--   (b) a quantidade pendente é `qtd_pedida − qtd_recebida` DO ITEM, nunca do
--       pedido: recebimento parcial é a regra, não a exceção, e pelo pedido um
--       pedido meio recebido abateria duas vezes.
--   (c) `greatest(…, 0)`: "se ≤ 0, não sugere" é ZERAR, não esconder — a linha
--       continua, com as parcelas ao lado (§2.3), porque view que já entrega o
--       resultado filtrado esconde o material que acabou de zerar.
--   (d) `where e.ativo` é a ÚNICA exceção declarada do §2.3: não se sugere
--       comprar apostila aposentada. `v_estoque_atual` não restringe.
--
-- ⚠️ §3.4 — a RLS reduz em silêncio, e é AQUI que isso dói: sem `compras.ler`, a
--    subconsulta `pp` não enxerga `pedido_item`, `qtd_pedida_pendente` vem 0 e o
--    sistema manda comprar de novo o que já está a caminho, com a cara de um
--    número correto. É por isso que a rota da tela de Compras (card 6.8) é
--    guardada pelo conjunto INTEIRO do §11 — materiais.ler, estoque.ler,
--    alunos.ler e compras.ler — e não pela permissão óbvia. O teste 095 mede as
--    quatro reduções, uma a uma.
create view public.v_pedido_sugerido with (security_invoker = on) as
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
                sum(pi.qtd_pedida - pi.qtd_recebida)::integer as qtd_pendente
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
  'qtd_pedida − qtd_recebida somada por ITEM, só de pedidos ENVIADO e PARCIAL. RASCUNHO não abate (nunca foi feito a ninguém), RECEBIDO já está no saldo e CANCELADO não virá.';

revoke all   on public.v_pedido_sugerido from public;
revoke all   on public.v_pedido_sugerido from anon;
grant select on public.v_pedido_sugerido to authenticated;
