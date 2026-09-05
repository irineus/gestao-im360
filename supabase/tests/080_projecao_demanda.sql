-- =============================================================================
-- Projeção de demanda — card 8.1
-- (mapa suíte → card: docs/estrategia-testes.md §17; o arquivo nasce aqui)
--
-- Card de "Função/regra" com view, tabela e rotina dentro, então o §13 cobra
-- três linhas de uma vez: o comportamento da regra, a paridade de linhas das
-- views (§6.3) e as três propriedades de rotina do §8 — idempotência, isolamento
-- e contexto.
--
-- O §6.4 é específico sobre o que ESTE card tem de medir, e as cinco coisas
-- estão aqui:
--   • a DISJUNÇÃO (`where k >= 2`): nenhum aluno aparece na demanda imediata e
--     na projetada para o mesmo material. É a linha de que a fórmula do pedido
--     sugerido depende — sem ela todo aluno ativo pesa duas vezes na compra, e o
--     número continua parecendo plausível ao lado dos outros;
--   • um aluno-fixture POR DEGRAU, com a regra esperada, e a asserção de que um
--     mesmo aluno nunca tem duas regras (uma regra por ALUNO, nunca por item);
--   • os dois filtros do ritmo, que atacam falhas OPOSTAS: entrega em lote (o
--     caso da migração do card 9.1) não derruba o ritmo para perto de zero, e
--     volta de parada longa não empurra o aluno para fora do horizonte;
--   • a ORDEM da cascata, que nenhuma das anteriores enxerga: Bruno Carvalho tem
--     previsão de conclusão FUTURA **e** ritmo mensurável, e sai por
--     RITMO_ALUNO; Diego Alves tem previsão VENCIDA e sai por MEDIA_METODO, não
--     por PREVISAO_CURSO — previsão vencida daria passo negativo e despejaria a
--     trilha inteira no mês corrente;
--   • a âncora limitada a UM ritmo no passado, que é o que impede a projeção de
--     transformar atraso em pico de compra.
--
-- E duas que o §10 do documento pede e que só um teste de paridade pega:
--   • sem `materiais.ler` a projeção vem VAZIA, não errada — o `join` em
--     `metodo` é interno e obrigatório (a chave do parâmetro é
--     `ritmo_padrao_dias_<CODIGO>`). É a redução silenciosa do card 2.3 §3.4 na
--     view que decide o que a escola compra;
--   • `demanda_projetada` é escrita SÓ pela rotina: a direção, que tem todas as
--     50 permissões, é recusada no `insert` e no `delete`.
--
-- ⚠️ A SEÇÃO 10 É DO CARD 8.2, e não do 8.1: é onde a parcela projetada chega a
--    `v_pedido_sugerido`. Mora aqui, e não no 095, porque a asserção só existe
--    depois de `rt_projecao_demanda()` ter rodado — e quem a roda é este arquivo.
--    O 095 mede a mesma view com a projeção VAZIA, que é o outro caso, e diz isso
--    na §12.
--
-- ⚠️ AS DATAS SÃO TODAS RELATIVAS A `fn_hoje()`, e as asserções de data foram
--    escolhidas entre as que NÃO dependem do dia do mês: `hoje + 60`, `hoje + 30`
--    e `hoje + 36` valem em qualquer data. Quem depende do calendário é a janela
--    de meses da rotina, e por isso a seção 6 a mede por PARIDADE com
--    v_projecao_aluno, nunca por contagem literal — asserção de contagem ali
--    passaria onze meses por ano e reprovaria no décimo segundo.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(60);

-- Chaves naturais em um lugar só (card 2.8 §11: nunca `limit` sem ordem, nunca
-- UUID literal).
create temporary view t_ids as
  select tests.unidade('ESCOLA_A') as unidade,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Ana Paula Ribeiro')  as ana,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Bruno Carvalho')     as bruno,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Carla Menezes')      as carla,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Diego Alves')        as diego,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Eduarda Lima')       as eduarda,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza')     as gabriela,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'João Pedro Martins') as joao,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Lucas Ferreira')     as lucas,
         (select t.id from public.turma_modular t
           where t.unidade_id = tests.unidade('ESCOLA_A') and t.nome = 'Eletricista 2026.1') as turma,
         (select t.id from public.turma_modular t
           where t.unidade_id = tests.unidade('ESCOLA_A') and t.nome = 'Eletricista 2025.2') as turma_vazia;

-- ===========================================================================
-- 1. v_ritmo_aluno — a régua de que o degrau 2 depende
-- ===========================================================================
-- A fonte é `aluno_material.data_entrega`, e não `movimento_estoque`: o estorno
-- desmarca a trilha e zera a data, então a trilha já está limpa. Eduarda Lima é
-- a prova viva disso na fixture — a entrega dela foi estornada (seed §8.5), e
-- ela não tem entrega nenhuma aqui.
select is(
  (select string_agg(a.nome || '=' || coalesce(r.ritmo_dias::text, '-'), ' | ' order by a.nome)
     from public.v_ritmo_aluno r
     join public.aluno a on a.id = r.aluno_id
    where r.unidade_id = (select unidade from t_ids)),
  'Ana Paula Ribeiro=60 | Bruno Carvalho=60 | Diego Alves=- | Felipe Nunes=- | '
    || 'Henrique Dias=- | João Pedro Martins=77 | Lucas Ferreira=-',
  'o ritmo da fixture: 60 dias para quem tem dois intervalos, NULO para quem tem uma entrega so');

-- Nulo, e não zero. Zero seria um ritmo instantâneo e traria a trilha inteira
-- para o mês corrente; nulo é o que faz o aluno DESCER um degrau da cascata.
select ok(
  (select r.ritmo_dias is null and r.intervalos_considerados = 0
     from public.v_ritmo_aluno r where r.aluno_id = (select lucas from t_ids)),
  'quem tem UMA entrega nao tem ritmo: nulo, com zero intervalos considerados');

-- A função é uma linha lendo a view, e é isso que garante que o número da ficha
-- do aluno (card 6.6) é o mesmo que entrou na compra.
select is(
  public.fn_ritmo_aluno((select ana from t_ids)),
  (select r.ritmo_dias from public.v_ritmo_aluno r where r.aluno_id = (select ana from t_ids)),
  'fn_ritmo_aluno devolve exatamente o que a view diz — nao e uma segunda implementacao');

-- ---------------------------------------------------------------------------
-- 1.1 O PISO de 7 dias: entrega em lote não é ritmo
-- ---------------------------------------------------------------------------
-- Duas apostilas entregues no MESMO dia (acerto de atraso, ou a carga da
-- migração do card 9.1, que traz várias entregas com a mesma data) dão intervalo
-- zero. Sem o piso, a média de João Pedro cairia de 77 para ~60 e, num aluno com
-- duas entregas, o ritmo iria a zero — ele passaria a "precisar" da trilha
-- inteira dentro do horizonte.
select tests.como_rotina((select unidade from t_ids));

update public.aluno_material am
   set data_entrega = (select x.data_entrega from public.aluno_material x
                        where x.aluno_id = am.aluno_id and x.ordem = 30)
 where am.aluno_id = (select joao from t_ids) and am.ordem = 40;

select is(
  (select r.ritmo_dias || '/' || r.intervalos_considerados
     from public.v_ritmo_aluno r where r.aluno_id = (select joao from t_ids)),
  '90/2',
  'entrega em lote e DESCARTADA pelo piso: o ritmo vira a media dos que sobraram, nao ~0');

-- ---------------------------------------------------------------------------
-- 1.2 O TETO de 120 dias: interrupção não é ritmo
-- ---------------------------------------------------------------------------
-- A falha oposta, e a defesa é a mesma: quem ficou meses parado e voltou tem um
-- intervalo enorme que, sozinho, empurraria o próximo livro para depois do
-- horizonte — o aluno sairia da compra justamente por ter voltado.
update public.aluno_material am
   set data_entrega = public.fn_hoje() - 30
 where am.aluno_id = (select joao from t_ids) and am.ordem = 40;

select is(
  (select r.ritmo_dias || '/' || r.intervalos_considerados
     from public.v_ritmo_aluno r where r.aluno_id = (select joao from t_ids)),
  '90/2',
  'intervalo de 170 dias e DESCARTADO pelo teto: interrupcao nao e ritmo');

-- ---------------------------------------------------------------------------
-- 1.3 A janela olha os intervalos MAIS RECENTES, e ela é parâmetro
-- ---------------------------------------------------------------------------
-- João Pedro é o único aluno da fixture com a janela cheia (três intervalos: 80,
-- 100 e 50 dias, do mais antigo ao mais recente). Estreitar a janela para UM
-- intervalo tem de devolver 50 — o mais recente. Se a ordenação de `recencia`
-- estivesse escrita `asc`, viria 80, e o aluno que mudou de ritmo levaria meses
-- para ser reconhecido.
update public.aluno_material am
   set data_entrega = public.fn_hoje() - 150
 where am.aluno_id = (select joao from t_ids) and am.ordem = 40;

update public.parametro set valor = '2'
 where unidade_id = (select unidade from t_ids) and chave = 'ritmo_janela_entregas';

select is(
  (select r.ritmo_dias || '/' || r.intervalos_considerados
     from public.v_ritmo_aluno r where r.aluno_id = (select joao from t_ids)),
  '50/1',
  'janela de 2 entregas = 1 intervalo, e ele e o MAIS RECENTE (50), nao o mais antigo (80)');

update public.parametro set valor = '4'
 where unidade_id = (select unidade from t_ids) and chave = 'ritmo_janela_entregas';

select is(
  (select r.ritmo_dias from public.v_ritmo_aluno r where r.aluno_id = (select joao from t_ids)),
  77,
  'e devolver o parametro devolve o ritmo: nenhum numero magico dentro da view');

select tests.encerrar_sessao();

-- ===========================================================================
-- 2. A cascata: um degrau por ALUNO, e a ordem entre eles
-- ===========================================================================
select is(
  (select string_agg(distinct p.regra, ',' order by p.regra)
     from public.v_projecao_aluno p where p.unidade_id = (select unidade from t_ids)),
  'MEDIA_METODO,MODULAR,PREVISAO_CURSO,RITMO_ALUNO',
  'os QUATRO degraus da cascata tem aluno na fixture — nenhum passa medindo conjunto vazio');

-- O mapa aluno → degrau, que é onde a ORDEM da cascata fica visível:
--   • Ana Paula e Bruno têm ritmo mensurável → RITMO_ALUNO;
--   • Bruno tem TAMBÉM previsão de conclusão futura, e ainda assim sai por
--     ritmo: o degrau 2 vem antes do 3;
--   • Carla não tem entrega nenhuma (logo, não tem ritmo) e tem previsão futura
--     → PREVISAO_CURSO;
--   • Diego tem previsão VENCIDA e cai para MEDIA_METODO — data vencida é dado
--     errado, não previsão apertada, e o passo negativo despejaria a trilha
--     inteira no mês corrente;
--   • Eduarda é MODULAR com turma e cronograma → MODULAR, e não RITMO_ALUNO
--     (no Modular quem manda é o cronograma da turma, não a velocidade dela).
select is(
  (select string_agg(a.nome || '=' || p.regra, ' | ' order by a.nome)
     from (select distinct aluno_id, regra from public.v_projecao_aluno
            where unidade_id = (select unidade from t_ids)) p
     join public.aluno a on a.id = p.aluno_id
    where a.nome in ('Ana Paula Ribeiro','Bruno Carvalho','Carla Menezes',
                     'Diego Alves','Eduarda Lima','Lucas Ferreira')),
  'Ana Paula Ribeiro=RITMO_ALUNO | Bruno Carvalho=RITMO_ALUNO | Carla Menezes=PREVISAO_CURSO | '
    || 'Diego Alves=MEDIA_METODO | Eduarda Lima=MODULAR | Lucas Ferreira=MEDIA_METODO',
  'um aluno por degrau, e a ordem da cascata visivel em Bruno (ritmo vence previsao)');

-- A contraprova de Diego, que é o que separa "caiu no degrau certo" de "caiu no
-- degrau certo por acaso": a previsão dele EXISTE, e está no passado.
select ok(
  (select a.prev_conclusao_curso < public.fn_hoje()
     from public.aluno a where a.id = (select diego from t_ids)),
  'contraprova: Diego TEM previsao de conclusao, e ela esta vencida — por isso nao e o degrau 3');

select is_empty(
  $$ select p.aluno_id from public.v_projecao_aluno p
      group by p.aluno_id having count(distinct p.regra) > 1 $$,
  'nenhum aluno com DUAS regras: a cascata escolhe por aluno, nunca por item da trilha');

-- Só ATIVO e ACELERAR. Gabriela está em STANDBY com trilha inteira pendente: é a
-- contraprova de que a ausência dela é o filtro de status, e não falta de item.
select cmp_ok(
  (select count(*)::bigint from public.aluno_material am
    where am.aluno_id = (select gabriela from t_ids) and not am.entregue),
  '>=', 2::bigint,
  'contraprova: a aluna em STANDBY tem itens pendentes de sobra para ser projetada');

select is_empty(
  $$ select 1 from public.v_projecao_aluno p
      join public.aluno a on a.id = p.aluno_id
     where a.status not in ('ATIVO','ACELERAR') $$,
  'e mesmo assim nenhum aluno fora de ATIVO/ACELERAR e projetado: parado nao gera compra');

-- ===========================================================================
-- 3. A disjunção — a linha de que o pedido sugerido depende
-- ===========================================================================
-- É a asserção mais importante do arquivo. O primeiro item pendente de cada
-- aluno JÁ é `v_demanda_imediata`, e a fórmula `imediata + projetada + mínimo −
-- estoque − pedido pendente` só está certa com as duas parcelas disjuntas.
select is_empty(
  $$ select d.aluno_id from public.v_demanda_imediata_aluno d
      join public.v_projecao_aluno p
        on p.aluno_id = d.aluno_id and p.material_id = d.material_id $$,
  'imediata e projetada sao DISJUNTAS por aluno x material (docs/projecao-demanda.md §2.4)');

select is_empty(
  $$ select 1 from public.v_projecao_aluno where k < 2 $$,
  'e nenhuma linha com k = 1: o proximo livro nunca entra na projecao');

-- O outro lado da mesma moeda: quem tem UM item pendente só não aparece. Felipe
-- Nunes é esse caso na fixture, e é por isso que o `k >= 2` não pode ser lido
-- como "sobra sempre alguma coisa".
select is_empty(
  $$ select 1 from public.v_projecao_aluno p
      join public.aluno a on a.id = p.aluno_id
     where a.nome = 'Felipe Nunes' $$,
  'aluno com UM item pendente nao tem linha nenhuma: tudo o que ele precisa e demanda imediata');

-- ===========================================================================
-- 4. As datas de cada degrau
-- ===========================================================================
-- ÂNCORA LIMITADA A UM RITMO NO PASSADO. Ana Paula recebeu a última apostila há
-- 90 dias e anda a 60: sem o limite, o k = 2 dela cairia em `hoje − 90 + 120` =
-- `hoje + 30`, um mês antes — a projeção transformaria o atraso dela em pico de
-- compra. Com o limite, ela é tratada como quem recebe o próximo agora e segue
-- no ritmo dela, que é a leitura honesta: o sistema não sabe por que ela
-- atrasou.
select is(
  (select p.data_prevista from public.v_projecao_aluno p
    where p.aluno_id = (select ana from t_ids) and p.k = 2),
  public.fn_hoje() + 60,
  'RITMO_ALUNO: a ancora e limitada a UM ritmo no passado — hoje + 2 x 60, nao hoje + 30');

select is(
  (select p.data_prevista from public.v_projecao_aluno p
    where p.aluno_id = (select lucas from t_ids) and p.k = 2),
  public.fn_hoje() + 30,
  'MEDIA_METODO: ritmo_padrao_dias_INTERATIVO = 30, e a mesma ancora limitada');

-- PREVISAO_CURSO distribui os R itens pendentes uniformemente até a data
-- informada. Em k = R a data cai EXATAMENTE na previsão, que é o significado do
-- campo — e é a asserção que pega um `k − 1` ou um `pendentes + 1` na fórmula.
select is(
  (select string_agg((p.data_prevista - public.fn_hoje())::text, ',' order by p.k)
     from public.v_projecao_aluno p where p.aluno_id = (select carla from t_ids)),
  '60,90,120',
  'PREVISAO_CURSO: passo uniforme, e em k = R a data e a propria previsao de conclusao');

select is(
  (select a.prev_conclusao_curso from public.aluno a where a.id = (select carla from t_ids)),
  (select max(p.data_prevista) from public.v_projecao_aluno p
    where p.aluno_id = (select carla from t_ids)),
  'e o ultimo item cai no MESMO dia da previsao informada, nao um dia antes nem depois');

-- ---------------------------------------------------------------------------
-- 4.1 O fator de aceleração vale SÓ em MEDIA_METODO
-- ---------------------------------------------------------------------------
-- Aplicá-lo nos quatro degraus contaria a aceleração duas vezes: em RITMO_ALUNO
-- ela já está medida, em PREVISAO_CURSO a data foi declarada por uma pessoa que
-- sabe se o aluno acelerou, e em MODULAR quem manda é a turma. As duas metades
-- estão aqui, com a MESMA aluna, e é isso que faz a asserção significar algo.
select tests.como_rotina((select unidade from t_ids));

update public.aluno set status = 'ACELERAR', status_desde = public.fn_hoje()
 where id = (select carla from t_ids);

select is(
  (select p.data_prevista from public.v_projecao_aluno p
    where p.aluno_id = (select carla from t_ids) and p.k = 2),
  public.fn_hoje() + 60,
  'ACELERAR em PREVISAO_CURSO nao muda nada: a data foi declarada por quem sabia');

update public.aluno set prev_conclusao_curso = null where id = (select carla from t_ids);

select is(
  (select p.regra || '/' || (p.data_prevista - public.fn_hoje())::text
     from public.v_projecao_aluno p
    where p.aluno_id = (select carla from t_ids) and p.k = 2),
  'MEDIA_METODO/20',
  'ACELERAR em MEDIA_METODO anda a 50% do ritmo do metodo: 15 dias por livro, nao 30');

select tests.encerrar_sessao();

-- ===========================================================================
-- 5. MODULAR: a data sai do CRONOGRAMA da turma, e ela se completa sozinha
-- ===========================================================================
-- O livro do aluno Modular é necessário quando a turma entra no PRIMEIRO módulo
-- daquele livro. Na fixture o módulo 3 (o do segundo livro) não tem data de
-- início: ela vem da regra 2 do §5.4 — `prev_conclusao` do módulo anterior + 1.
select is(
  (select p.data_prevista from public.v_projecao_aluno p
    where p.aluno_id = (select eduarda from t_ids)),
  public.fn_hoje() + 36,
  'MODULAR: modulo sem data_inicio herda prev_conclusao do anterior + 1 dia (regra 2 do §5.4)');

select is(
  (select p.k::text || '/' || p.pendentes::text from public.v_projecao_aluno p
    where p.aluno_id = (select eduarda from t_ids)),
  '2/2',
  'e e o SEGUNDO livro dela: o primeiro, estornado e de volta a pendente, e demanda imediata');

-- EXTRAPOLAÇÃO (regra 3 do §5.4). Sem `prev_conclusao` no módulo 2, o módulo 3
-- fica sem data conhecida e passa a herdar a última conhecida mais o passo médio
-- planejado da turma — 36 dias, do único módulo que ainda tem as duas datas.
-- Sem ela, ou se perde a demanda dos livros seguintes em silêncio (a pior das
-- opções), ou o aluno inteiro cai de degrau por causa de um módulo sem data.
--
-- ⚠️ AS DUAS MUTAÇÕES DESTA SEÇÃO VIVEM DENTRO DE UM SAVEPOINT, e não é
--    preciosismo: sem ele a turma de Eduarda chega SEM CRONOGRAMA na seção 7, e
--    a contraprova de lá ("com cronograma nas três turmas, a rotina não abre
--    pendência nenhuma") passaria a medir uma pendência que ESTE arquivo criou.
--    Medido: ela reprovou exatamente assim antes do savepoint entrar.
select tests.como_rotina((select unidade from t_ids));
savepoint cronograma_original;

update public.turma_modular_modulo tmm set prev_conclusao = null
 where tmm.turma_id = (select turma from t_ids)
   and tmm.modulo_id = (select m.id from public.modulo m
                         join public.turma_modular t on t.curso_id = m.curso_id
                        where t.id = (select turma from t_ids) and m.ordem = 2);

select is(
  (select p.data_prevista from public.v_projecao_aluno p
    where p.aluno_id = (select eduarda from t_ids)),
  public.fn_hoje() + 11,
  'MODULAR: sem data adiante, extrapola pela duracao media planejada da turma (regra 3 do §5.4)');

-- Turma SEM cronograma nenhum degrada a projeção: o aluno cai de degrau. É o
-- caso que a pendência da seção 7 existe para não deixar acontecer em silêncio.
delete from public.turma_modular_modulo where turma_id = (select turma from t_ids);

select is(
  (select distinct p.regra from public.v_projecao_aluno p
    where p.aluno_id = (select eduarda from t_ids)),
  'MEDIA_METODO',
  'turma Modular sem cronograma nenhum: a aluna cai para a media do metodo');

rollback to savepoint cronograma_original;
select tests.encerrar_sessao();

-- ===========================================================================
-- 6. rt_projecao_demanda — contexto, janela, paridade com o detalhe
-- ===========================================================================
-- CONTEXTO (card 2.2 §2.2): sem a GUC não há unidade, e a rotina falha FECHADO.
-- Tratar unidade nula como "não faz nada" seria um contorno permanente em
-- produção escrito para acomodar quem a chamou errado.
select throws_ok(
  $$ select public.rt_projecao_demanda() $$,
  'P0001',
  null,
  'sem contexto de rotina a projecao falha FECHADO — nao escreve nada em silencio');

select is_empty(
  $$ select 1 from public.demanda_projetada $$,
  'e a tabela continua vazia: nenhuma unidade recebeu linha nenhuma');

select tests.como_rotina((select unidade from t_ids));
select public.rt_projecao_demanda();

select cmp_ok(
  (select count(*)::bigint from public.demanda_projetada
    where unidade_id = (select unidade from t_ids)),
  '>', 0::bigint,
  'com contexto, a rotina grava — e a contagem de referencia das asercoes abaixo e > 0');

-- A rotina grava SÓ a janela [mês corrente, mês de hoje + horizonte].
select is_empty(
  $$ select 1 from public.demanda_projetada
      where mes < date_trunc('month', public.fn_hoje())::date
         or mes > date_trunc('month', public.fn_hoje()
                             + public.fn_param_int('projecao_horizonte_dias'))::date $$,
  'nenhum mes fora da janela: guardar fora dela e guardar linha que nenhuma tela le');

-- E o TOTAL é o DETALHE agregado, nos dois sentidos. É o princípio do §2.3
-- transformado em asserção: ter duas expressões independentes para o total e
-- para o detalhe é como o total e o detalhe passam a divergir — e a tela do card
-- 8.5 mostra os dois lado a lado.
select is_empty(
  $$ select * from (
       select material_id, mes, regra, quantidade
         from public.demanda_projetada
        where unidade_id = (select tests.unidade('ESCOLA_A'))
       except
       select p.material_id,
              date_trunc('month', p.data_prevista)::date,
              p.regra,
              count(*)::integer
         from public.v_projecao_aluno p
        where p.unidade_id = (select tests.unidade('ESCOLA_A'))
          and date_trunc('month', p.data_prevista)::date
              between date_trunc('month', public.fn_hoje())::date
                  and date_trunc('month', public.fn_hoje()
                                 + public.fn_param_int('projecao_horizonte_dias'))::date
        group by 1, 2, 3
     ) x $$,
  'nenhuma linha na tabela que o detalhe nao produza — o total e o detalhe agregado');

select is_empty(
  $$ select * from (
       select p.material_id,
              date_trunc('month', p.data_prevista)::date as mes,
              p.regra,
              count(*)::integer as quantidade
         from public.v_projecao_aluno p
        where p.unidade_id = (select tests.unidade('ESCOLA_A'))
          and date_trunc('month', p.data_prevista)::date
              between date_trunc('month', public.fn_hoje())::date
                  and date_trunc('month', public.fn_hoje()
                                 + public.fn_param_int('projecao_horizonte_dias'))::date
        group by 1, 2, 3
       except
       select material_id, mes, regra, quantidade
         from public.demanda_projetada
        where unidade_id = (select tests.unidade('ESCOLA_A'))
     ) x $$,
  'nem o contrario: nenhuma linha do detalhe dentro da janela ficou de fora da tabela');

-- ISOLAMENTO (card 2.2 §2.2): a rotina opera na unidade do contexto, e não itera
-- unidades por conta própria — quem itera é rt_diaria.
select is_empty(
  $$ select 1 from public.demanda_projetada
      where unidade_id = (select tests.unidade('ESCOLA_B')) $$,
  'a rotina rodou na ESCOLA_A e a ESCOLA_B continua sem projecao nenhuma');

-- IDEMPOTÊNCIA (§8): rodar de novo produz o MESMO conjunto. `delete` + `insert`
-- na mesma transação não abre janela de tabela vazia — pelo MVCC, quem consultar
-- durante a execução continua vendo o conjunto anterior até o commit.
create temporary table antes as
  select material_id, mes, regra, quantidade from public.demanda_projetada
   where unidade_id = tests.unidade('ESCOLA_A');

select public.rt_projecao_demanda();

select is_empty(
  $$ select * from (
       (select material_id, mes, regra, quantidade from antes
        except
        select material_id, mes, regra, quantidade from public.demanda_projetada
         where unidade_id = (select tests.unidade('ESCOLA_A')))
       union all
       (select material_id, mes, regra, quantidade from public.demanda_projetada
         where unidade_id = (select tests.unidade('ESCOLA_A'))
        except
        select material_id, mes, regra, quantidade from antes)
     ) x $$,
  'rodar duas vezes seguidas produz o MESMO conjunto — a rotina e idempotente');

-- ---------------------------------------------------------------------------
-- 6.1 A foto mensal, tirada UMA vez por mês
-- ---------------------------------------------------------------------------
-- Sem ela, em janeiro não há como responder "o que a gente previu em novembro
-- para dezembro?" e a recalibração do card 11.2 fica reduzida a opinião.
select is(
  (select count(distinct snapshot_em)::bigint from public.demanda_projetada_hist
    where unidade_id = (select unidade from t_ids)),
  1::bigint,
  'a foto mensal tem UM snapshot_em, mesmo depois de duas execucoes no mesmo mes');

select is(
  (select count(*)::bigint from public.demanda_projetada_hist
    where unidade_id = (select unidade from t_ids)),
  (select count(*)::bigint from antes),
  'e ela fotografou exatamente as linhas da primeira execucao do mes');

select is(
  (select distinct snapshot_em from public.demanda_projetada_hist
    where unidade_id = (select unidade from t_ids)),
  date_trunc('month', public.fn_hoje())::date,
  'com snapshot_em no dia 1 do mes corrente — o par com `mes` e que responde ao card 11.2');

select tests.encerrar_sessao();

-- ===========================================================================
-- 7. A pendência de cronograma: abre E fecha
-- ===========================================================================
-- Cronograma vazio degrada a projeção sem quebrar nada — exatamente o tipo de
-- falha que precisa de alguém avisado. A turma usada aqui é a VAZIA de propósito
-- (`Eletricista 2025.2`): a de Eduarda carrega o outro assunto da seção 5.
--
-- ⚠️ O `check` de `pendencia.tipo` só aceita TURMA_MODULAR_SEM_CRONOGRAMA desde
--    o card 7.2. Três documentos davam esse ajuste como feito e ele não estava —
--    e o sintoma teria sido uma ROTINA_FALHOU às 03:10, com a projeção inteira
--    desaparecendo da tela de Compras e o erro aparecendo longe da causa.
select tests.como_rotina((select unidade from t_ids));

select is_empty(
  $$ select 1 from public.pendencia
      where tipo = 'TURMA_MODULAR_SEM_CRONOGRAMA' and resolvida_em is null $$,
  'contraprova: com cronograma nas tres turmas, a rotina nao abre pendencia nenhuma');

delete from public.turma_modular_modulo where turma_id = (select turma_vazia from t_ids);
select public.rt_projecao_demanda();

select is(
  (select p.severidade from public.pendencia p
    where p.unidade_id = (select unidade from t_ids)
      and p.chave_dedup = 'CRONOGRAMA:' || (select turma_vazia from t_ids)::text
      and p.resolvida_em is null),
  'BAIXA',
  'turma ativa sem nenhum modulo datado abre TURMA_MODULAR_SEM_CRONOGRAMA (severidade BAIXA)');

select public.rt_projecao_demanda();

select is(
  (select count(*)::bigint from public.pendencia p
    where p.chave_dedup = 'CRONOGRAMA:' || (select turma_vazia from t_ids)::text
      and p.resolvida_em is null),
  1::bigint,
  'e rodar de novo NAO duplica: a dedup por chave e o que impede a central de virar ruido');

insert into public.turma_modular_modulo (unidade_id, turma_id, modulo_id, data_inicio)
select (select unidade from t_ids), (select turma_vazia from t_ids), m.id, public.fn_hoje()
  from public.modulo m
  join public.turma_modular t on t.curso_id = m.curso_id
 where t.id = (select turma_vazia from t_ids) and m.ordem = 1;

select public.rt_projecao_demanda();

select is_empty(
  $$ select 1 from public.pendencia p
      where p.chave_dedup = 'CRONOGRAMA:' || (select t.id from public.turma_modular t
                                               where t.unidade_id = (select tests.unidade('ESCOLA_A'))
                                                 and t.nome = 'Eletricista 2025.2')::text
        and p.resolvida_em is null $$,
  'datado o cronograma, a rotina FECHA a pendencia — pendencia que so abre vira lista morta');

select tests.encerrar_sessao();

-- ===========================================================================
-- 8. Quem escreve em demanda_projetada é a rotina, e mais ninguém
-- ===========================================================================
-- Decisão (g) do card de Ordem 5, e ela não é o padrão de quatro políticas: as
-- políticas de `insert` e `delete` exigem `fn_contexto_rotina()`, não permissão
-- de domínio. Com uma política por permissão, a tela de Compras poderia GRAVAR
-- projeção pelo PostgREST — e o número apareceria na compra sem ninguém saber de
-- onde veio.
--
-- ⚠️ AS DUAS METADES DESTA SEÇÃO SÃO DIFERENTES DE PROPÓSITO, e a diferença é a
--    própria natureza da RLS. No `insert` a política com `with check` VIOLADA
--    devolve 42501 — erro de verdade. No `update` e no `delete` não há erro
--    nenhum: sem política para o comando, a RLS simplesmente não encontra linha
--    e o comando afeta ZERO. Escrever `throws_ok` nos quatro seria escrever dois
--    testes que nunca poderiam passar — e, pior, esconderia a metade que
--    interessa: a asserção certa aqui é sobre o EFEITO, e não sobre a exceção.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select throws_ok(
  $$ insert into public.demanda_projetada
            (unidade_id, material_id, mes, quantidade, regra)
     select public.fn_unidade_atual(), m.id,
            date_trunc('month', public.fn_hoje())::date, 99, 'MEDIA_METODO'
       from public.material m
      where m.unidade_id = public.fn_unidade_atual()
      order by m.codigo, m.id limit 1 $$,
  '42501',
  null,
  'a DIRECAO, com as 50 permissoes, e recusada no insert: escrita e so da rotina');

select throws_ok(
  $$ insert into public.demanda_projetada_hist
            (unidade_id, material_id, mes, quantidade, regra, snapshot_em)
     select public.fn_unidade_atual(), m.id,
            date_trunc('month', public.fn_hoje())::date, 99, 'MEDIA_METODO',
            date_trunc('month', public.fn_hoje())::date
       from public.material m
      where m.unidade_id = public.fn_unidade_atual()
      order by m.codigo, m.id limit 1 $$,
  '42501',
  null,
  'a foto mensal e imutavel pela mesma porta: nem a direcao insere linha nela');

delete from public.demanda_projetada;
update public.demanda_projetada set quantidade = 1;

-- ⚠️ `reset role` ANTES de `tests.encerrar_sessao()`, e a ordem não é estilo: de
--    dentro de `authenticated` o schema `tests` é inalcançável (o papel não tem
--    USAGE), e a chamada morre com "permission denied for schema tests",
--    derrubando o arquivo inteiro no meio. É a mesma pedra que o card 3.4
--    encontrou em `tests.conta_como`, e ela mordeu aqui em 05/09/2026.
reset role;
select tests.encerrar_sessao();

select is_empty(
  $$ select * from (
       (select material_id, mes, regra, quantidade from antes
        except
        select material_id, mes, regra, quantidade from public.demanda_projetada
         where unidade_id = (select tests.unidade('ESCOLA_A')))
       union all
       (select material_id, mes, regra, quantidade from public.demanda_projetada
         where unidade_id = (select tests.unidade('ESCOLA_A'))
        except
        select material_id, mes, regra, quantidade from antes)
     ) x $$,
  'o delete e o update da direcao afetaram ZERO linha — sem erro, e e esse o ponto');

-- ===========================================================================
-- 9. Paridade de linhas, silêncio e isolamento (card 2.8 §6.3)
-- ===========================================================================
-- "O perfil X consegue ler a view sem erro" é asserção quase vazia: a RLS não
-- devolve erro, ela REDUZ LINHAS em silêncio. O teste correto é paridade, com a
-- contagem da direção garantidamente > 0.
select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_projecao_aluno'),
  '>', 0::bigint,
  'a direcao ve linhas em v_projecao_aluno (a contagem de referencia da paridade e > 0)');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select 1 from public.v_projecao_aluno') as n
       from (values ('direcao@escola-a.test'), ('secretaria@escola-a.test'),
                    ('pedagogico@escola-a.test'), ('monitor@escola-a.test')) v(e)) x),
  1::bigint,
  'os quatro perfis veem o MESMO numero de linhas da projecao: a tela nao mente para ninguem');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select 1 from public.v_ritmo_aluno') as n
       from (values ('direcao@escola-a.test'), ('secretaria@escola-a.test'),
                    ('pedagogico@escola-a.test'), ('monitor@escola-a.test')) v(e)) x),
  1::bigint,
  'e o mesmo em v_ritmo_aluno — o ritmo da ficha do aluno e igual para os quatro');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select 1 from public.v_demanda_projetada') as n
       from (values ('direcao@escola-a.test'), ('secretaria@escola-a.test'),
                    ('pedagogico@escola-a.test'), ('monitor@escola-a.test')) v(e)) x),
  1::bigint,
  'e em v_demanda_projetada: os quatro tem estoque.ler, entao os quatro veem a projeta inteira');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_projecao_aluno'),
  0::bigint,
  'quem nao tem perfil ve ZERO linha — e a rota e barrada antes, pelo guarda do card 3.7');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_demanda_projetada'),
  0::bigint,
  'idem na projecao materializada');

-- Isolamento de unidade. A ESCOLA_B tem a MESMA fixture, então ela também tem
-- projeção — o que não pode acontecer é uma ver a linha da outra.
select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_projecao_aluno'),
  '>', 0::bigint,
  'a ESCOLA_B tem projecao propria (senao o isolamento seria zero contra zero)');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_projecao_aluno p
                     join public.aluno a on a.id = p.aluno_id
                    where a.codigo_sgf = ''3001'''),
  1::bigint,
  'e ela ve UM Ana Paula, o dela: os codigos SGF se repetem entre unidades de proposito');

-- ---------------------------------------------------------------------------
-- 9.1 A redução silenciosa que decide o que a escola compra
-- ---------------------------------------------------------------------------
-- O `join` em `metodo` é INTERNO e obrigatório — a chave do parâmetro é
-- `ritmo_padrao_dias_' || metodo.codigo`. Sem `materiais.ler`, a projeção não vem
-- ERRADA: vem VAZIA, com cara de escola que não precisa comprar nada. É o achado
-- #12 do card 2.4 na sua forma perigosa, e o motivo de o §10 declarar
-- `materiais.ler` no conjunto desta view.
delete from public.perfil_permissao pp
 using public.perfil pe, public.permissao pm
 where pp.perfil_id = pe.id and pp.permissao_id = pm.id
   and pe.unidade_id = (select unidade from t_ids) and pe.nome = 'Monitor'
   and pm.codigo = 'materiais.ler';

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_projecao_aluno'),
  0::bigint,
  'sem materiais.ler a projecao vem VAZIA, nao errada — e ninguem recebe erro nenhum');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_projecao_aluno'),
  '>', 0::bigint,
  'contraprova na mesma transacao: para a direcao ela continua cheia');

-- ===========================================================================
-- 10. A parcela projetada CHEGA ao pedido sugerido — card 8.2
-- ===========================================================================
-- O card 8.2 troca duas expressoes de `v_pedido_sugerido` (docs/views-leitura.md
-- §6.2): o literal `0::integer` da coluna `qtd_projetada` e o `+ 0` de dentro do
-- `greatest`. Sao duas, e as asercoes abaixo sao construidas para que MEXER EM
-- UMA SO ja fique vermelho:
--   • trocar so a coluna (e esquecer o `greatest`) reprova em 10.3, porque o
--     total deixa de fechar com as parcelas que a propria linha exibe;
--   • trocar so o `greatest` (e esquecer a coluna) reprova no MESMO 10.3, pelo
--     lado oposto — o total cresce sem que a parcela apareca ao lado dele;
--   • nao trocar nenhuma das duas reprova em 10.1.
-- Vista vermelha em 05/09/2026 revertendo a view para o `0::integer` do card 6.4.
--
-- Roda como `postgres`, que tem BYPASSRLS (card 3.3): o filtro por `unidade_id`
-- e o que restringe o resultado a ESCOLA_A, e nao a RLS. Quem mede a RLS desta
-- view e o 095 §14 — misturar as duas coisas produz o teste que passa sem testar
-- nada (card 2.8 §6.3). A projecao aqui e a que a secao 7 deixou gravada.
--
-- ⚠️ MAS PRECISA DE CONTEXTO DE UNIDADE, e isso e novo: desde o 8.2 a view chama
--    `fn_param_int('projecao_horizonte_dias')` para montar a janela, e o
--    parametro e POR UNIDADE. Sem contexto, `fn_unidade_atual()` e nula, nenhuma
--    linha de `parametro` casa e a leitura morre com PARAMETRO_AUSENTE — medido
--    em 05/09/2026, quando esta secao rodava sem contexto nenhum. Usa-se
--    `como_rotina`, que da a unidade pela GUC SEM trocar de papel: trocar para
--    `authenticated` tornaria o schema `tests` inalcancavel daqui para a frente
--    (a mesma pedra da secao 8).
select tests.como_rotina((select unidade from t_ids));

-- 10.1 — a parcela existe. Sem ela as tres asercoes seguintes comparariam zero
-- com zero e passariam com a view do card 6.4 intacta.
select cmp_ok(
  (select count(*)::bigint from public.v_pedido_sugerido v
    where v.unidade_id = (select unidade from t_ids) and v.qtd_projetada > 0),
  '>', 0::bigint,
  'algum material do pedido sugerido tem parcela projetada > 0 — a coluna deixou de ser reserva');

-- 10.2 — e ela e EXATAMENTE a soma de v_demanda_projetada na janela, material a
-- material. Somando sobre TODAS as regras: um aluno produz UMA linha por
-- material (a regra e unica por aluno), entao somar os quatro degraus e somar
-- alunos distintos, nao contar o mesmo aluno quatro vezes.
select is_empty(
  $$ select 1 from public.v_pedido_sugerido v
      where v.unidade_id = (select tests.unidade('ESCOLA_A'))
        and v.qtd_projetada <> coalesce((
              select sum(d.quantidade)::integer from public.v_demanda_projetada d
               where d.unidade_id = v.unidade_id and d.material_id = v.material_id
                 and d.mes between date_trunc('month', public.fn_hoje())::date
                               and date_trunc('month', public.fn_hoje()
                                     + public.fn_param_int('projecao_horizonte_dias'))::date), 0) $$,
  'a parcela projetada e a soma de v_demanda_projetada na janela, material a material');

-- 10.3 — e a formula inteira fecha COM ela: imediata + projetada + minimo −
-- saldo − pendente, com piso zero. A conta e feita sobre as colunas que a
-- PROPRIA LINHA exibe, que e o que o card 2.3 §2.3 promete a quem olha a tela.
select is_empty(
  $$ select 1 from public.v_pedido_sugerido v
      where v.unidade_id = (select tests.unidade('ESCOLA_A'))
        and v.qtd_sugerida <> greatest(v.qtd_imediata + v.qtd_projetada
                                       + v.estoque_minimo - v.saldo
                                       - v.qtd_pedida_pendente, 0) $$,
  'o total fecha com as cinco parcelas ao lado dele, e a projetada e uma delas');

select is_empty(
  $$ select 1 from public.v_pedido_sugerido where qtd_sugerida < 0 $$,
  'e o piso zero sobreviveu a parcela nova: nenhuma sugestao negativa');

-- 10.4 — a JANELA e de mes inteiro e ela CORTA. Duas linhas de projecao para o
-- mesmo material, uma no mes anterior ao corrente e outra no mes seguinte ao do
-- horizonte: nenhuma das duas pode mexer na parcela. Sem o `where` da janela, a
-- view somaria tudo o que houvesse na tabela e a compra de setembro carregaria a
-- demanda de dezembro.
create temporary table sugerido_antes as
  select v.material_id, v.qtd_projetada, v.qtd_sugerida
    from public.v_pedido_sugerido v
   where v.unidade_id = tests.unidade('ESCOLA_A');

insert into public.demanda_projetada (unidade_id, material_id, mes, quantidade, regra)
select (select unidade from t_ids), a.material_id, m.mes, 99, 'MEDIA_METODO'
  from (select material_id from sugerido_antes order by material_id limit 1) a
  cross join (values
    ((date_trunc('month', public.fn_hoje()) - interval '1 month')::date),
    ((date_trunc('month', public.fn_hoje()
       + public.fn_param_int('projecao_horizonte_dias')) + interval '1 month')::date)
  ) m(mes);

select is_empty(
  $$ select 1 from public.v_pedido_sugerido v
       join sugerido_antes a on a.material_id = v.material_id
      where v.unidade_id = (select tests.unidade('ESCOLA_A'))
        and (v.qtd_projetada <> a.qtd_projetada or v.qtd_sugerida <> a.qtd_sugerida) $$,
  'mes fora da janela nao entra na compra: 99 antes e 99 depois do horizonte mudam ZERO');

-- 10.5 — e o `left join` e `left` de proposito: material sem projecao nenhuma
-- CONTINUA na lista, com a parcela zero. Sumir dali seria o oposto do §2.3 — e o
-- material sem demanda alguma e justamente o que entra com a sugestao igual ao
-- minimo, que e o que a planilha perdia.
select cmp_ok(
  (select count(*)::bigint from public.v_pedido_sugerido v
    where v.unidade_id = (select unidade from t_ids) and v.qtd_projetada = 0),
  '>', 0::bigint,
  'material sem projecao continua na lista com a parcela zero — o join e left');

select tests.encerrar_sessao();

select * from finish();
rollback;
