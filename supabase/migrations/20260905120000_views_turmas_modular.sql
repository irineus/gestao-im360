-- =============================================================================
-- Card 7.3 — a tela de Turmas Modular: as três views que ela lê
-- Fonte: docs/wireframes.md §8 (a tela 5, "Turmas Modular"),
--        docs/views-leitura.md §7.2 (SQL de `v_turma_modular_lotacao`),
--        §2 (princípios), §3 (as quatro armadilhas), §3.4 (a RLS que reduz em
--        silêncio), §12.1 (view de tela é do card da tela),
--        docs/permissoes-matriz.md §6 linha 5 (`turmas.ler` + `salas.ler` +
--        `materiais.ler` — todos os perfis) e §4 (a matriz por tabela),
--        docs/modelagem-dados-ddl.md §9 (as três tabelas do card 7.1),
--        docs/estrategia-testes.md §13 (obrigação de View e de Tela).
--
-- Entrega: TRÊS views de leitura (`security_invoker = on`, `unidade_id`,
--          colunas explícitas, `revoke`/`grant` do §2.5). Nenhuma função nova,
--          nenhum trigger novo: as cinco funções da regra são do card 7.2 e a
--          tela apenas as orquestra (card 2.6 decisão 2).
--
-- ⚠️ NENHUMA LINHA DE DADO. Migração é o que o CI empurra para produção sozinho
--    no merge em `main` (decisão de 02/09/2026): view é estrutura, e as três
--    tabelas do card 7.1 estão VAZIAS em produção até a virada do card 9.7 —
--    lá estas views devolvem zero linha, que é o estado correto.
--
-- =============================================================================
-- DIVERGÊNCIA REGISTRADA — `v_turma_modular_lotacao` NASCE AQUI, NÃO NO 7.4
-- =============================================================================
-- `docs/views-leitura.md` §7.2 e §12 atribuem a view aos cards **7.4 e 5.9**, e
-- o §8 do `wireframes.md` — que é o desenho DESTA tela — manda a tela 5 lê-la:
-- «Fonte: `v_turma_modular_lotacao` (cabeçalho e lotação)». As duas frases não
-- podem valer ao mesmo tempo com o 7.4 vindo DEPOIS do 7.3 na ordem do board.
--
-- Vence o §12.1 do próprio `views-leitura.md`, que é a regra geral e é literal:
-- **view de tela pertence ao card da tela**, e a primeira tela que a lê é esta.
-- Foi assim no `053` (card 6.6, `v_aluno_trilha`), no `061` (6.7,
-- `v_material_movimento`) e no `062` (6.8, `v_pedido_compra`/`v_pedido_item`) —
-- três precedentes, todos registrados. O card 7.4 (lotação por curso no
-- Dashboard) passa a **consumir** a view, e é o que já sobrou dele: a nota do
-- 7.4 diz, com todas as letras, que ele «é um card acrescentado a um dashboard
-- que os cards 5.9 e 8.7 já terão construído».
--
-- A alternativa — a tela 5 montar a lotação por conta própria — está proibida
-- por escrito duas vezes: o card 2.3 §4.1 (uma definição por número derivado) e
-- o §7.2, que fixa `modulo_atrasado` como coluna da view. Duas contas do módulo
-- corrente divergiriam na primeira vez que alguém mexesse numa só.
--
-- O SQL abaixo é **cópia palavra por palavra** do §7.2. Não há uma linha de
-- interpretação: se a expressão precisar mudar, muda no documento primeiro.
--
-- =============================================================================
-- AS OUTRAS DUAS VIEWS, QUE O §7.2 NÃO PREVIA
-- =============================================================================
-- O wireframe §8 desenha três regiões dentro do cartão da turma, e a view de
-- lotação só responde pela primeira:
--
--   • o cabeçalho e a lotação — `v_turma_modular_lotacao` (§7.2);
--   • «▤ Cronograma: 1 ✓ · 2 ✓ · 3 ► (01/08–20/09) · 4 · 5», que o §8 manda ler
--     de `turma_modular_modulo` — e ali a ORDEM e o NOME do módulo não existem:
--     vêm de `modulo`, por join, porque «o cronograma da turma herda a sequência
--     do catálogo» (card 2.2 §9, e o card 7.1 recusou a coluna de ordem por
--     isso). Ler a tabela crua pelo PostgREST obrigaria a tela a resolver a
--     ordem em Dart, que é a segunda fonte da verdade que o 7.1 evitou;
--   • «▤ Alunos (8) │ Ana … │ desde 01/06 │ [Remover]», que precisa de NOME e
--     status do aluno — `turma_modular_aluno` guarda só o `aluno_id`.
--
-- As duas nascem aqui pela mesma regra do §12.1 que traz a de lotação.
--
-- ⚠️ `v_turma_modular_aluno` junta `aluno` INTERNAMENTE, e a consequência é
--    deliberada: a rota da tela 5 é `turmas.ler` + `salas.ler` +
--    `materiais.ler` (permissoes-matriz §6, linha 5) e **não pede
--    `alunos.ler`**. Quem entrar sem `alunos.ler` vê o cartão, a lotação e o
--    cronograma, e a região de alunos vem VAZIA — a redução silenciosa do §3.4.
--
--    Das três saídas, a escolhida é a terceira:
--      (a) `left join` em `aluno`: a lista viria com N linhas SEM NOME. Uma
--          turma de oito alunos anônimos é pior que nenhuma, e é o mesmo
--          argumento do `v_pedido_item` (card 6.8);
--      (b) acrescentar `alunos.ler` ao conjunto da rota: aí a TELA INTEIRA
--          fecha para quem não tem a permissão, e some também o cronograma e o
--          avanço de módulo, que não dependem de aluno nenhum. Trocar uma
--          região vazia pela tela inteira fechada é piorar;
--      (c) join interno **e a região declara a permissão que lhe falta** — a
--          tela mostra ali o `EstadoSemAcesso` daquela região (design-system
--          §5.6, o texto por região de 04/09/2026), em vez de uma lista vazia
--          com cara de turma sem aluno. É o que o card 7.3 faz, e é o que torna
--          esta redução VISÍVEL em vez de silenciosa.
--    Com a matriz inicial (card 2.4 §5) os quatro perfis têm `alunos.ler`, então
--    o caso (c) só aparece em perfil montado à mão — e é exatamente aí que ele
--    precisa dizer o que houve.
--
-- `v_turma_modular_cronograma` faz o oposto: junta `modulo` internamente E a
-- rota já exige `materiais.ler`, então quem chega até aqui tem a permissão — é
-- o precedente do `v_pedido_item` (6.8) e do `v_aluno_trilha` (6.6), não o do
-- `v_material_movimento` (6.7).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. v_turma_modular_lotacao — cópia literal de docs/views-leitura.md §7.2
-- -----------------------------------------------------------------------------
-- O módulo corrente vem de `modulo.ordem` por join, não de coluna em
-- `turma_modular_modulo`. Turma com todos os módulos concluídos aparece com
-- `modulo_corrente_id` NULO — é o estado "turma terminou", e ela **não some** da
-- lotação (wireframe §8).
--
-- ⚠️ Armadilha §3.3 (`fn_hoje()`, nunca `current_date`): `modulo_atrasado`
--    compara a previsão com o hoje de São Paulo. O Postgres do Supabase roda em
--    UTC e das 21h à meia-noite `current_date` já é o dia seguinte — uma turma
--    que vence hoje apareceria atrasada três horas antes de estar. O teste C6 do
--    `011` varre o corpo das views desde o card 5.2 e reprova quem esquecer.
--
-- ⚠️ Armadilha §3.1 (soma/contagem de conjunto vazio): `count(*)` de subconsulta
--    sem linha é ZERO, não nulo — ao contrário de `sum()`. Turma sem aluno
--    nenhum (a `2025.2` da fixture) mostra `0/15`, e é isso que se quer.
--    `greatest(…, 0)` em `vagas_livres` porque turma ACIMA da capacidade é
--    estado real (o importador do card 9.1 pode trazer uma), e "−2 vagas livres"
--    não é frase de tela.
create view public.v_turma_modular_lotacao with (security_invoker = on) as
select t.unidade_id,
       t.id        as turma_id,
       t.nome      as turma_nome,
       t.curso_id,
       c.nome      as curso_nome,
       t.sala_id,
       s.nome      as sala_nome,
       t.capacidade,
       (select count(*) from public.turma_modular_aluno ta
         where ta.turma_id = t.id and ta.ativo)::integer as alocados,
       greatest(t.capacidade
                - (select count(*) from public.turma_modular_aluno ta
                    where ta.turma_id = t.id and ta.ativo), 0)::integer as vagas_livres,
       mc.modulo_id      as modulo_corrente_id,
       mo.nome           as modulo_corrente_nome,
       mo.ordem          as modulo_corrente_ordem,
       mc.data_inicio    as modulo_corrente_inicio,
       mc.prev_conclusao as modulo_corrente_prev_conclusao,
       (mc.prev_conclusao is not null and mc.prev_conclusao < public.fn_hoje()) as modulo_atrasado
  from public.turma_modular t
  join public.curso c on c.id = t.curso_id
  join public.sala  s on s.id = t.sala_id
  left join lateral (
         select tm.modulo_id, tm.data_inicio, tm.prev_conclusao
           from public.turma_modular_modulo tm
           join public.modulo m2 on m2.id = tm.modulo_id
          where tm.turma_id = t.id and not tm.concluido
          order by m2.ordem
          limit 1
       ) mc on true
  left join public.modulo mo on mo.id = mc.modulo_id
 where t.ativo;

comment on view public.v_turma_modular_lotacao is
  'Uma turma Modular ATIVA por linha, com lotação e módulo corrente — cabeçalho e lista da tela 5 (card 7.3, docs/wireframes.md §8) e cartão de lotação por curso do Dashboard (card 7.4). SQL copiado palavra por palavra de docs/views-leitura.md §7.2. O módulo corrente sai de modulo.ordem por join, e não de coluna em turma_modular_modulo: o cronograma da turma herda a sequência do catálogo (card 2.2 §9). Turma com todos os módulos concluídos vem com modulo_corrente_id NULO — é o estado "turma terminou", e ela não some da lista. Nasceu no 7.3 e não no 7.4 por views-leitura §12.1 (view de tela é do card da tela), como v_aluno_trilha (6.6), v_material_movimento (6.7) e v_pedido_compra (6.8).';

comment on column public.v_turma_modular_lotacao.capacidade is
  'Teto da turma, COLUNA de turma_modular e não conta derivada: a sala modular não tem PC, então não existe fn_capacidade_efetiva (card 5.2) que a produza. É a diferença de forma entre a turma Modular e o bloco de horário.';

comment on column public.v_turma_modular_lotacao.vagas_livres is
  'Piso ZERO: turma acima da capacidade é estado real — o importador do card 9.1 pode trazer uma —, e "−2 vagas livres" não é frase de tela. Quem recusa a admissão seguinte é tg_turma_modular_aluno_admissao (TURMA_LOTADA), não este número.';

comment on column public.v_turma_modular_lotacao.modulo_atrasado is
  'Previsão do módulo corrente vencida, comparada com public.fn_hoje() e nunca com current_date (card 2.3 §10): o banco roda em UTC e das 21h à meia-noite a turma apareceria atrasada antes de estar. Nulo em prev_conclusao é AUSÊNCIA de previsão, não previsão vencida — a expressão devolve false, e é a tela que diz "sem previsão".';

revoke all   on public.v_turma_modular_lotacao from public;
revoke all   on public.v_turma_modular_lotacao from anon;
grant select on public.v_turma_modular_lotacao to authenticated;

-- -----------------------------------------------------------------------------
-- 2. v_turma_modular_cronograma — «1 ✓ · 2 ✓ · 3 ► (01/08–20/09) · 4 · 5»
-- -----------------------------------------------------------------------------
-- Uma linha por módulo JÁ NO CRONOGRAMA da turma, na ordem do catálogo. Os
-- módulos do curso que ainda não estão no cronograma **não aparecem aqui** — a
-- tela os descobre comparando com `modulo` (que ela já lê para o catálogo) e
-- oferece acrescentá-los.
--
-- ⚠️ `corrente` é DERIVADO aqui, e é a MESMA definição de
--    `fn_turma_modular_modulo_corrente` (card 7.2) e do `left join lateral` da
--    view acima: o primeiro não concluído por `modulo.ordem`. Três expressões
--    para o mesmo fato é o que o card 2.3 §4.1 proíbe — e a contraprova está no
--    teste `072` §3, que compara a coluna com a função linha a linha. Ela existe
--    como coluna porque a tela precisa marcar `►` na LINHA certa, e derivá-la em
--    Dart seria a quarta definição.
--
-- `row_number()` sobre a janela da turma, e não `min(ordem)`: com `filter` a
-- expressão precisaria de um segundo passe. A janela ordena por
-- `m.ordem, tm.modulo_id` — a MESMA ordem completa da função, e não só
-- `m.ordem`: `limit`/`row_number` sem ordem total é sorteio
-- (docs/estrategia-testes.md §11), e um empate faria a view marcar `►` numa
-- linha e a função avançar outra.
create view public.v_turma_modular_cronograma with (security_invoker = on) as
select tm.unidade_id,
       tm.id          as cronograma_id,
       tm.turma_id,
       tm.modulo_id,
       m.nome         as modulo_nome,
       m.ordem        as modulo_ordem,
       m.material_id,
       tm.data_inicio,
       tm.prev_conclusao,
       tm.concluido,
       (not tm.concluido
        and row_number() over (partition by tm.turma_id, tm.concluido
                                   order by m.ordem, tm.modulo_id) = 1) as corrente,
       (not tm.concluido
        and tm.prev_conclusao is not null
        and tm.prev_conclusao < public.fn_hoje())          as atrasado
  from public.turma_modular_modulo tm
  join public.modulo m on m.id = tm.modulo_id;

comment on view public.v_turma_modular_cronograma is
  'O cronograma de uma turma Modular com o módulo resolvido, para a faixa "1 ✓ · 2 ✓ · 3 ► (01/08–20/09) · 4 · 5" da tela 5 (card 7.3, docs/wireframes.md §8). A ordem e o nome vêm de modulo por join INTERNO: turma_modular_modulo não tem coluna de ordem de propósito (card 7.1 — o cronograma herda a sequência do catálogo, card 2.2 §9), e a rota da tela já exige materiais.ler, que é o precedente de v_aluno_trilha (6.6) e v_pedido_item (6.8). Só lista o que JÁ está no cronograma; módulo do curso ainda não incluído a tela descobre comparando com o catálogo.';

comment on column public.v_turma_modular_cronograma.corrente is
  'O primeiro módulo NÃO concluído por modulo.ordem — a mesma definição de fn_turma_modular_modulo_corrente (card 7.2) e do left join lateral de v_turma_modular_lotacao, e o teste 072 §3 compara as três linha a linha. Existe como coluna porque a tela marca o ► numa linha, e derivá-la em Dart seria uma quarta definição do mesmo fato (card 2.3 §4.1). Turma inteira concluída não tem nenhuma linha com corrente = true, que é o estado "turma terminou".';

comment on column public.v_turma_modular_cronograma.atrasado is
  'Módulo não concluído com previsão vencida, por public.fn_hoje() e nunca current_date (card 2.3 §10). Módulo JÁ CONCLUÍDO nunca é atrasado, mesmo com prev_conclusao no passado: fn_turma_modular_avancar grava ali a data REAL da conclusão (card 7.2 §5), e sem esta condição toda turma em dia apareceria com metade do cronograma em vermelho.';

revoke all   on public.v_turma_modular_cronograma from public;
revoke all   on public.v_turma_modular_cronograma from anon;
grant select on public.v_turma_modular_cronograma to authenticated;

-- -----------------------------------------------------------------------------
-- 3. v_turma_modular_aluno — «▤ Alunos (8) │ Ana … │ desde 01/06 │ [Remover]»
-- -----------------------------------------------------------------------------
-- Traz os INATIVOS também (`ativo` é coluna, não filtro), pela mesma decisão que
-- `bloco_ativo` em `v_bloco_alunos` (card 5.7): quem sai da turma deixa
-- `motivo_saida` escrito, e essa é a única leitura do sistema que responde «por
-- que fulano não está mais aqui». Quem ocupa vaga é só o ativo — e é
-- `v_turma_modular_lotacao.alocados` quem conta, com o mesmo predicado.
--
-- ⚠️ `join` INTERNO em `aluno`: ver o bloco de decisão no cabeçalho. A rota da
--    tela 5 não pede `alunos.ler`, então a região pode vir vazia — e a tela
--    declara a permissão que falta em vez de mostrar uma turma sem ninguém.
create view public.v_turma_modular_aluno with (security_invoker = on) as
select ta.unidade_id,
       ta.id        as alocacao_id,
       ta.turma_id,
       ta.aluno_id,
       a.nome       as aluno_nome,
       a.codigo_sgf,
       a.status     as aluno_status,
       a.metodo_id,
       ta.data_entrada,
       ta.ativo,
       ta.motivo_saida
  from public.turma_modular_aluno ta
  join public.aluno a on a.id = ta.aluno_id;

comment on view public.v_turma_modular_aluno is
  'Os alunos de uma turma Modular com o cadastro resolvido, para a região "Alunos (n)" da tela 5 (card 7.3, docs/wireframes.md §8). Traz os INATIVOS também — ativo é COLUNA e não filtro, como bloco_ativo em v_bloco_alunos (card 5.7) —, porque motivo_saida é a única leitura que responde por que alguém não está mais na turma; quem ocupa vaga é só o ativo, e quem conta é v_turma_modular_lotacao.alocados. O join em aluno é INTERNO: a rota da tela NÃO exige alunos.ler, então sem ela a região vem vazia, e é a TELA que declara a permissão faltante (design-system §5.6) em vez de mostrar uma turma sem ninguém.';

comment on column public.v_turma_modular_aluno.ativo is
  'Falso quando o aluno saiu da turma — inclusive SEM ATOR, por tg_aluno_status_desaloca (card 7.1 §8), quando ele deixa de ser ATIVO/ACELERAR. A tela lista os inativos separados e sem ação, para que a saída tenha onde ser lida.';

revoke all   on public.v_turma_modular_aluno from public;
revoke all   on public.v_turma_modular_aluno from anon;
grant select on public.v_turma_modular_aluno to authenticated;
