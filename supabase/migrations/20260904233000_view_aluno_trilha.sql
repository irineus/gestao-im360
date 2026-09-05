-- =============================================================================
-- Card 6.6 — v_aluno_trilha: a trilha do aluno como a aba Trilha a lê
-- Fonte: docs/wireframes.md §6.3 (a tabela da aba, coluna a coluna),
--        docs/views-leitura.md §12.1 (a view é deste card) e §2 (princípios),
--        §3 (as quatro armadilhas), docs/permissoes-matriz.md §6 linha 3b
--        (`alunos.ler` + `materiais.ler` + `estoque.ler`),
--        docs/estrategia-testes.md §13 (obrigação de teste de card de View).
--
-- Entrega: UMA view de listagem, `security_invoker = on`, com `unidade_id`,
--          colunas explícitas e o `revoke`/`grant` do §2.5.
--
-- ⚠️ NENHUMA LINHA DE DADO. Migração é o que o CI empurra para produção sozinho
--    no merge em `main` (decisão de 02/09/2026): view é estrutura, e `aluno_material`
--    está vazia em produção até a virada do card 9.7 — lá esta view devolve zero
--    linha, que é o estado correto.
--
-- Por que a tela precisa de uma view, e não de um `select` no PostgREST: o
-- wireframe §6.3 pede QUATRO coisas que a tabela sozinha não dá — a posição na
-- lista (1, 2, 3…, que não é `ordem`, porque `ordem` anda de 10 em 10 e ganha
-- frestas), a marca do PRÓXIMO, o saldo do material e o nome dele. Montar isso
-- em Dart custaria dois `select` e uma junção em memória, e a marca do próximo
-- viraria a terceira implementação de "menor ordem não entregue" — a mesma
-- proibição que o card 2.3 §4.1 faz à soma do saldo.
--
-- ⚠️ AS TRÊS DERIVAÇÕES DESTA VIEW TÊM DONO EM OUTRO LUGAR, e é de propósito:
--    • `proximo` repete o critério de `fn_trilha_proximo_material` (card 6.2) —
--      menor `ordem` com `entregue = false`. Aqui ele é uma janela porque a view
--      responde por TODOS os itens de uma vez e a função responde por um aluno;
--      chamá-la por linha seria n execuções para saber n vezes a mesma coisa. O
--      teste `053` §2 asserta que as duas concordam aluno a aluno, que é o que
--      impede as duas de divergirem no dia em que alguém mexer numa só;
--    • `saldo` é `fn_saldo_material` (card 6.3), chamada e não recopiada: a
--      SEGUNDA implementação da soma já existe e é aquela; uma terceira, aqui,
--      é exatamente o que o card 2.3 §4.1 proíbe;
--    • `posicao` é `row_number()` e não existe em lugar nenhum além daqui — é
--      número de TELA ("apostila 4 de 14"), não de banco, e a `ordem` continua
--      sendo a coluna que ordena.
--
-- ⚠️ O `join` em `material` é INTERNO, e a consequência está medida: sem
--    `materiais.ler` a trilha vem VAZIA, e não "cheia sem o nome". É a redução
--    silenciosa do card 2.3 §3.4, e aqui ela é a forma MENOS pior — uma trilha
--    com o nome em branco pareceria uma trilha curta, e a pessoa registraria
--    entrega da apostila errada. Vazia, a aba diz o que falta (a tela do card 6.6
--    checa o conjunto do §6 linha 3b antes de consultar). Asserido no `053` §5.
--
-- ⚠️ SEM `estoque.ler` O SALDO VEM 0 EM TODA LINHA, sem erro nenhum — a mesma
--    mentira que `v_estoque_atual` conta no card 6.4, pela mesma razão (a função
--    é `invoker`, a RLS de `movimento_estoque` esconde as linhas e a soma de
--    conjunto vazio vira 0 pelo `coalesce`). É por isso que a aba Trilha exige
--    `estoque.ler` na rota, e não só `alunos.ler` + `materiais.ler`: com saldo 0
--    em tudo, `fn_registrar_entrega` bloquearia toda entrega por falta de um
--    estoque que existe. Asserido no `053` §5.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. v_aluno_trilha
-- -----------------------------------------------------------------------------
-- A ordem das colunas é contrato (card 2.3 §6.2): `create or replace view` não
-- insere coluna no meio nem troca tipo. Colunas novas entram no FIM — é assim
-- que o card 8.1 acrescentará a data prevista de entrega sem `drop view`.
create view public.v_aluno_trilha with (security_invoker = on) as
select am.unidade_id,
       am.aluno_id,
       am.id                                        as item_id,
       am.material_id,
       am.ordem,
       -- Posição na lista, 1..n. NÃO é `ordem`: `ordem` nasce de 10 em 10 (card
       -- 6.2 §5.1) para a inserção caber entre dois itens sem renumerar, então
       -- mostrá-la ao usuário exibiria "10, 20, 25, 30" na coluna `#`.
       row_number() over (partition by am.aluno_id order by am.ordem)::integer
                                                    as posicao,
       am.origem,
       am.entregue,
       am.data_entrega,
       am.movimento_estoque_id,
       m.metodo_id,
       m.codigo                                     as material_codigo,
       m.nome                                       as material_nome,
       m.categoria                                  as material_categoria,
       -- O "► próxima" da aba (wireframe §6.3): o item pendente de menor `ordem`.
       -- `filter (where not entregue)` e não um `case` por fora — com `case`, o
       -- mínimo seria o da trilha INTEIRA e o "próximo" apontaria para o primeiro
       -- livro, já entregue, em toda ficha com histórico.
       (not am.entregue
        and am.ordem = min(am.ordem) filter (where not am.entregue)
                           over (partition by am.aluno_id))
                                                    as proximo,
       public.fn_saldo_material(am.material_id)     as saldo
  from public.aluno_material am
  join public.material m on m.id = am.material_id;

comment on view public.v_aluno_trilha is
  'Trilha do aluno para a aba Trilha da ficha (card 6.6, docs/wireframes.md §6.3): um item por linha, com posição de tela, marca do próximo e saldo do material. Leitura exige alunos.ler E materiais.ler E estoque.ler — sem a segunda a view vem VAZIA (join interno), sem a terceira vem CHEIA com saldo 0 em tudo, e é a segunda forma que faria a entrega ser recusada por falta de estoque que existe.';

comment on column public.v_aluno_trilha.posicao is
  'Posição de TELA (1..n), derivada por row_number sobre `ordem`. `ordem` anda de 10 em 10 e ganha frestas na inserção (card 6.2 §5.1): mostrá-la ao usuário exibiria "10, 20, 25" na coluna #.';

comment on column public.v_aluno_trilha.proximo is
  'Verdadeiro no item pendente de menor `ordem` — o mesmo critério de fn_trilha_proximo_material (card 6.2), aqui como janela porque a view responde por todos os itens de uma vez. Aluno em FIM não tem nenhuma linha verdadeira, e é assim que a tela distingue "acabou" de "nunca começou": a trilha existe e nenhum item é o próximo.';

comment on column public.v_aluno_trilha.saldo is
  'fn_saldo_material do material (card 6.3), NÃO uma terceira soma. É informativo: a tela não pré-verifica saldo (card 2.6 decisão 2) — quem decide, na transação, é fn_registrar_entrega. Sem estoque.ler vem 0 sem erro nenhum (card 2.3 §3.4).';

revoke all   on public.v_aluno_trilha from public;
revoke all   on public.v_aluno_trilha from anon;
grant select on public.v_aluno_trilha to authenticated;
