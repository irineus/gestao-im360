-- =============================================================================
-- v_certificado_fila — card 8.6 (a tela 9)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- ⚠️ O §17 NÃO PREVIA ARQUIVO PARA O 8.6, e a divergência é a sexta da mesma
--    família: `053` (6.6), `061` (6.7), `062` (6.8), `072` (7.3) e `082` (8.5).
--    Tela planejada sem objeto de banco que acaba precisando de view própria —
--    `views-leitura.md` §12.1 já diz que view de listagem pertence ao card da
--    tela, e card com View tem obrigação própria no §13. Mora no bloco `08x`, ao
--    lado do `081_certificado_checklist` (8.3), que é o arquivo da tabela.
--    Registrada no §17, não seguida em silêncio.
--
-- Obrigação de **View** (§13): paridade de linhas por perfil + zero para quem
-- não pode + isolamento de unidade (§6.3), mais as armadilhas do card 2.3 §3.
--
-- Três coisas que este arquivo prova e que nenhum catálogo enxerga:
--
--   • **ALUNO SEM TRILHA NÃO É FORMANDO.** `fn_trilha_em_fim` e a coluna
--     `em_fim` do dashboard devolvem `true` para quem nunca teve trilha, e o
--     comentário do card 6.2 manda quem precisar distinguir "acabou" de "nunca
--     começou" perguntar pela trilha. Esta view é quem precisa: sem o `exists`,
--     a fixture entrega Karina Bastos e Aluno Modular 01 como prontos para o
--     certificado, e na escola real seria todo aluno recém-matriculado;
--
--   • **AS DUAS SITUAÇÕES EXISTEM E SÃO DISTINTAS** (divergência 2 do §17 de
--     wireframes.md): ULTIMO_LIVRO é um item pendente — o aluno ainda tem aula
--     pela frente, e é por isso que dá tempo de pedir o certificado — e FIM é
--     nenhum. A fixture nasce só com o primeiro caso, e a transação deste
--     arquivo produz o segundo entregando o último livro de Felipe;
--
--   • **NULO NÃO É `false`.** As cinco colunas do checklist vêm nulas para quem
--     ainda não tem checklist e `false`/`NAO_PEDIDO` logo depois de abri-lo. É
--     a diferença entre "ninguém abriu isto ainda" e "o pedagógico ainda não
--     assinou", e é ela que decide se a tela mostra um traço ou uma caixa.
--
-- CONTRAPROVAS VISTAS VERMELHAS EM 06/09/2026, cada uma sabotando uma regra:
-- remover o `exists` da trilha (reprova as seções 2 e 1), trocar o `left join`
-- por `join` (reprova a seção 4, a fila perde metade), abrir `status` para
-- FORMADO (reprova a seção 3) e trocar `pend.qtd <= 1` por `< 1` (reprova a 1).
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(20);

-- Chaves naturais em um lugar só (card 2.8 §11: nunca `limit` sem ordem, nunca
-- UUID literal).
--
-- ⚠️ TABELA temporária, e não view, pelo motivo do `081`: a seção 4 chama
--    `fn_certificado_abrir` já em `authenticated`, e nesse papel o schema
--    `tests` não é alcançável — uma view materializaria `tests.unidade()` na
--    hora do `select` e morreria em «permission denied for function unidade».
--    Colhida como `postgres`, antes de qualquer autenticação.
create temporary table t_ids as
  select tests.unidade('ESCOLA_A') as unidade_a,
         tests.unidade('ESCOLA_B') as unidade_b,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Felipe Nunes')       as felipe,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Karina Bastos')      as karina,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Aluno Modular 01')   as modular_01,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'João Pedro Martins') as joao,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza')     as gabriela,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Henrique Dias')      as henrique;

grant select on t_ids to authenticated;

-- ===========================================================================
-- 1. O panorama: quem está na fila, e com que situação
-- ===========================================================================
-- Uma linha só, e é a asserção mais barata que existe contra escopo errado: um
-- `where` frouxo em qualquer das três condições (status, pendentes, trilha)
-- muda esta string inteira. Felipe Nunes tem DOIS itens na trilha e UM pendente
-- (`INGLES 02`, o saldo zero do caso BLOQUEADA_SEM_ESTOQUE, camada
-- `trilha_estoque`): é o único ULTIMO_LIVRO da fixture.
select is(
  (select string_agg(f.aluno_nome || '=' || f.situacao, ' | ' order by f.aluno_nome)
     from public.v_certificado_fila f
    where f.unidade_id = (select unidade_a from t_ids)),
  'Felipe Nunes=ULTIMO_LIVRO',
  'a fila da fixture e Felipe Nunes, em ULTIMO_LIVRO — um item pendente, com aula pela frente');

select is(
  (select f.itens_pendentes from public.v_certificado_fila f
    where f.aluno_id = (select felipe from t_ids)),
  (select count(*)::integer from public.aluno_material am
    where am.aluno_id = (select felipe from t_ids) and not am.entregue),
  'itens_pendentes e a contagem real da trilha, nao um numero copiado');

-- ===========================================================================
-- 2. A armadilha: aluno sem trilha NÃO é fim de curso
-- ===========================================================================
-- Karina Bastos e Aluno Modular 01 são ATIVOS sem uma linha de `aluno_material`
-- (camadas `alunos` e `modular`). "Nenhum item pendente" é verdade para os dois,
-- e é por isso que a view pergunta pela TRILHA e não só pela contagem.
select is(
  (select count(*)::bigint from public.v_certificado_fila f
    where f.aluno_id in ((select karina from t_ids), (select modular_01 from t_ids))),
  0::bigint,
  'aluno ATIVO sem trilha nenhuma fica FORA da fila — nao terminou nada, nunca comecou');

-- E o outro lado da mesma moeda, para a asserção acima não ser confundida com
-- "a fila é pequena": a função do card 6.2 diz `true` para ela, de propósito.
select ok(
  (select public.fn_trilha_em_fim((select karina from t_ids))),
  'e fn_trilha_em_fim diz TRUE para ela — e por isso que a fila nao pode perguntar so a ela');

-- ===========================================================================
-- 3. Quem já saiu da fila
-- ===========================================================================
-- João Pedro é o único aluno em FIM da fixture, tem checklist ENTREGUE e está
-- FORMADO. Mantê-lo na fila deixaria todo formando da história na tela para
-- sempre; o checklist dele continua na aba Certificado da ficha.
select is(
  (select count(*)::bigint from public.v_certificado_fila f
    where f.aluno_id = (select joao from t_ids)),
  0::bigint,
  'aluno FORMADO com certificado ENTREGUE sai da fila — o trabalho dele acabou');

-- STANDBY e TRANCADO não estão chegando ao fim de nada (e os dois têm itens
-- pendentes de sobra, então esta asserção mede o filtro de status).
select is(
  (select count(*)::bigint from public.v_certificado_fila f
    where f.aluno_id in ((select gabriela from t_ids), (select henrique from t_ids))),
  0::bigint,
  'STANDBY e TRANCADO ficam fora: a fila e de quem esta em curso');

-- ===========================================================================
-- 4. As cinco colunas do checklist — e o nulo que não é `false`
-- ===========================================================================
select is(
  (select format('%s/%s/%s/%s/%s',
                 f.checklist_id is null, f.data_fim_curso is null,
                 f.pedagogico_ok is null, f.formatura is null,
                 f.certificado_status is null)
     from public.v_certificado_fila f
    where f.aluno_id = (select felipe from t_ids)),
  't/t/t/t/t',
  'quem esta em ULTIMO_LIVRO ainda NAO tem checklist — as cinco colunas vem NULAS, nao falsas');

-- O caminho que a tela oferece: abrir o checklist à mão antes do fim do curso, é
-- para isso que `fn_certificado_abrir` é idempotente e resolve a data sozinha
-- (card 8.3). A secretaria tem `certificados.criar`.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));
select public.fn_certificado_abrir((select felipe from t_ids));
reset role;

select is(
  (select format('%s/%s/%s/%s',
                 f.pedagogico_ok, f.financeiro_ok, f.formatura, f.certificado_status)
     from public.v_certificado_fila f
    where f.aluno_id = (select felipe from t_ids)),
  'f/f/f/NAO_PEDIDO',
  'aberto o checklist, as colunas passam a FALSO e NAO_PEDIDO — o traco vira caixa vazia');

-- Felipe TEM entrega na trilha, então o `coalesce` de fn_certificado_abrir cai
-- na data da última — não em fn_hoje(). É a metade do default que o `081`
-- exercita pelo outro lado, com Carla, que não tem entrega nenhuma.
select is(
  (select f.data_fim_curso from public.v_certificado_fila f
    where f.aluno_id = (select felipe from t_ids)),
  (select max(am.data_entrega) from public.aluno_material am
    where am.aluno_id = (select felipe from t_ids) and am.entregue),
  'data_fim_curso e a data da ultima entrega da trilha, e a fila ordena por ela');

-- Sem cópia: o resumo que a fila mostra é o da tabela, linha por linha. Uma view
-- que recalculasse qualquer um dos quatro estados poderia divergir da tela de
-- detalhe, que lê a tabela direto.
select is(
  (select count(*)::bigint
     from public.v_certificado_fila f
     join public.certificado_checklist cc on cc.aluno_id = f.aluno_id
    where f.pedagogico_ok is distinct from cc.pedagogico_ok
       or f.financeiro_ok is distinct from cc.financeiro_ok
       or f.formatura     is distinct from cc.formatura
       or f.certificado_status is distinct from cc.certificado_status
       or f.checklist_id  is distinct from cc.id
       or f.data_fim_curso is distinct from cc.data_fim_curso),
  0::bigint,
  'as cinco colunas sao as da tabela, sem copia nem recalculo');

-- ===========================================================================
-- 5. A segunda situação: a entrega do último livro leva a FIM
-- ===========================================================================
-- A fixture nasce sem nenhum aluno em FIM na fila (o único está FORMADO), e sem
-- este passo o rótulo `FIM` nunca seria medido. As três colunas mexidas são as
-- que a guarda do card 6.1 §9 deixa livres — é o mesmo `update` que a camada
-- `trilha_estoque` do seed usa.
update public.aluno_material am
   set entregue = true, data_entrega = public.fn_hoje() - 2
 where am.aluno_id = (select felipe from t_ids) and not am.entregue;

select is(
  (select format('%s/%s', f.situacao, f.itens_pendentes)
     from public.v_certificado_fila f
    where f.aluno_id = (select felipe from t_ids)),
  'FIM/0',
  'entregue o ultimo livro, o mesmo aluno passa a FIM — os dois rotulos do card 2.3 §8.1 existem');

select is(
  (select count(distinct f.checklist_id)::bigint from public.v_certificado_fila f
    where f.aluno_id = (select felipe from t_ids)),
  1::bigint,
  'e continua o MESMO checklist: mudar de situacao nao abre um segundo');

-- ===========================================================================
-- 6. Paridade de linhas, silêncio e isolamento (card 2.8 §6.3)
-- ===========================================================================
-- "O perfil X lê a view sem erro" é asserção quase vazia: a RLS não devolve
-- erro, ela REDUZ LINHAS em silêncio. O teste correto é paridade, com a
-- contagem da direção garantidamente > 0.
--
-- ⚠️ `tests.encerrar_sessao()` primeiro, pela mesma razão do `082` §4: a seção 4
--    autenticou a secretaria, e `tests.conta_como` sobre uma sessão já montada
--    mediria a permissão errada.
select tests.encerrar_sessao();

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_certificado_fila'),
  '>', 0::bigint,
  'a direcao ve linhas na fila (a contagem de referencia da paridade e > 0)');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select 1 from public.v_certificado_fila') as n
       from (values ('direcao@escola-a.test'), ('secretaria@escola-a.test'),
                    ('pedagogico@escola-a.test'), ('monitor@escola-a.test')) v(e)) x),
  1::bigint,
  'os quatro perfis veem a MESMA fila — o monitor marca o financeiro na lista do celular');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_certificado_fila'),
  0::bigint,
  'quem nao tem perfil ve ZERO linha — e a rota e barrada antes, pelo guarda do card 3.7');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_certificado_fila f
                     where f.unidade_id = ''' || (select unidade_a from t_ids) || ''''),
  0::bigint,
  'a ESCOLA_B nao ve uma linha da fila da ESCOLA_A, e as duas tem a mesma fixture');

-- ---------------------------------------------------------------------------
-- 6.1 As três reduções silenciosas, e a terceira é a que MENTE
-- ---------------------------------------------------------------------------
-- Sem `materiais.ler` a fila vem vazia (join interno em `metodo`); sem
-- `alunos.ler`, idem. Sem `certificados.ler` as LINHAS CONTINUAM e o checklist
-- inteiro vira nulo — a fila diria "ninguém abriu checklist para ninguém" com os
-- checklists abertos ali. É o §3.4 do card 2.3 na sua forma pior, e é por isso
-- que `certificados.ler` está no conjunto da rota.
delete from public.perfil_permissao pp
 using public.perfil pe, public.permissao pm
 where pp.perfil_id = pe.id and pp.permissao_id = pm.id
   and pe.unidade_id = (select unidade_a from t_ids) and pe.nome = 'Monitor'
   and pm.codigo = 'materiais.ler';

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_certificado_fila'),
  0::bigint,
  'sem materiais.ler a fila vem VAZIA, nao errada — o join em metodo e interno');

delete from public.perfil_permissao pp
 using public.perfil pe, public.permissao pm
 where pp.perfil_id = pe.id and pp.permissao_id = pm.id
   and pe.unidade_id = (select unidade_a from t_ids) and pe.nome = 'Pedagógico'
   and pm.codigo = 'alunos.ler';

select is(
  tests.conta_como(tests.uid('pedagogico@escola-a.test'),
                   'select 1 from public.v_certificado_fila'),
  0::bigint,
  'sem alunos.ler tambem: a lista de nomes exige a permissao de quem tem nome');

delete from public.perfil_permissao pp
 using public.perfil pe, public.permissao pm
 where pp.perfil_id = pe.id and pp.permissao_id = pm.id
   and pe.unidade_id = (select unidade_a from t_ids) and pe.nome = 'Secretaria'
   and pm.codigo = 'certificados.ler';

select cmp_ok(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
                   'select 1 from public.v_certificado_fila'),
  '>', 0::bigint,
  'sem certificados.ler as LINHAS continuam — o left join nao some com o aluno');

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
                   'select 1 from public.v_certificado_fila f where f.checklist_id is not null'),
  0::bigint,
  'mas o checklist inteiro vira NULO: a fila mentiria "ninguem abriu" com os checklists abertos');

select * from finish();
rollback;
