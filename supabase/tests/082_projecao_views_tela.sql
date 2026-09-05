-- =============================================================================
-- v_projecao_aluno.ritmo_dias, v_projecao_material_mes e
-- v_projecao_aluno_detalhe — card 8.5 (a tela 8)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- ⚠️ O §17 NÃO PREVIA ARQUIVO PARA O 8.5, e a divergência é a quinta da mesma
--    família: `053` (card 6.6), `061` (6.7), `062` (6.8) e `072` (7.3). Tela
--    planejada sem objeto de banco que acaba precisando de views próprias —
--    `views-leitura.md` §12.1 já diz que view de tela pertence ao card da tela,
--    e card com View tem obrigação própria no §13. Mora no bloco `08x`, ao lado
--    do `080_projecao_demanda` (8.1) e do `081_certificado_checklist` (8.3), e
--    não no `095`. Registrada no §17, não seguida em silêncio.
--
-- Obrigação de **View** (§13): paridade de linhas por perfil + zero para quem
-- não pode + isolamento de unidade (§6.3), mais as armadilhas do card 2.3 §3.
--
-- Quatro coisas que este arquivo prova e que nenhum catálogo enxerga:
--
--   • **O TOTAL E O DETALHE FECHAM, célula por célula.** É a razão de a tela 8
--     existir com drill-down (card 2.3 §5.1, "detalhe primeiro, agregado
--     depois") e a única propriedade que uma segunda implementação quebraria em
--     silêncio: os números continuariam plausíveis lado a lado. A asserção
--     compara `sum(quantidade)` da grade com `count(*)` do detalhe **dentro da
--     janela**, por (material, mês) e por (material, mês, regra) — e a seção 3.4
--     mostra que fora da janela eles divergem DE PROPÓSITO, senão a paridade
--     estaria medindo duas listas idênticas por construção;
--
--   • **`ritmo_dias` é o ritmo que gerou a data, e não um ritmo parecido.** A
--     contraprova é o passo: dois itens consecutivos da trilha do mesmo aluno
--     distam exatamente `ritmo_dias` dias. Uma recomposição de fora (v_ritmo_
--     aluno para um degrau, `fn_param_int` para outro) passaria nas asserções de
--     igualdade e reprovaria nesta, porque erraria o fator de aceleração;
--
--   • **NULO em PREVISAO_CURSO e MODULAR**, onde a data não vem de ritmo nenhum.
--     Preencher com o ritmo do método daria à tela um número que não participou
--     da conta — e o `—` da coluna é o que diz isso a quem revisa a compra;
--
--   • **as duas views reagem de forma DIFERENTE à falta de permissão**: sem
--     `materiais.ler` as duas vêm vazias (join interno em `material`), e sem
--     `alunos.ler` o detalhe vem vazio enquanto a grade continua CHEIA. É a
--     redução silenciosa do card 2.3 §3.4 na tela que decide o que a escola
--     compra, e é por isso que a rota exige os quatro códigos.
--
-- CONTRAPROVAS VISTAS VERMELHAS EM 05/09/2026, cada uma sabotando uma regra:
-- `coalesce(ritmo_dias, 30)` no detalhe (reprova a asserção do nulo), `mes`
-- deslocado em um mês (reprova a definição E a paridade), `where m.ativo` na
-- grade (reprova a exceção declarada) e a remoção do `encerrar_sessao` da §4
-- (reprova as sete de RLS, e essa foi vista **verde** primeiro — ver o aviso lá).
--
-- ⚠️ A PRIMEIRA TENTATIVA DE CONTRAPROVA DO `mes` PASSOU VERDE, e a razão não é
--    fraqueza da asserção: era `data_prevista + 15`, e **toda** data prevista da
--    fixture cai antes do dia 16 (a mais tardia é 14/12). Somar 15 dias não muda
--    o bucket de nenhuma linha — a view sabotada era, sobre estes dados,
--    idêntica à correta, e teste nenhum detecta mudança que não muda nada. Quem
--    for escrever contraprova de agrupamento por mês aqui: desloque um MÊS
--    inteiro, não alguns dias.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(26);

-- Chaves naturais em um lugar só (card 2.8 §11: nunca `limit` sem ordem, nunca
-- UUID literal).
create temporary view t_ids as
  select tests.unidade('ESCOLA_A') as unidade_a,
         tests.unidade('ESCOLA_B') as unidade_b,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Diego Alves')  as diego,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Ana Paula Ribeiro') as ana,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Carla Menezes') as carla,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Eduarda Lima')  as eduarda;

-- A projeção materializada das DUAS unidades. A ESCOLA_B tem a mesma fixture, e
-- é isso que faz o isolamento da seção 4 comparar algo com algo em vez de zero
-- com zero.
select tests.como_rotina((select unidade_b from t_ids));
select public.rt_projecao_demanda();
select tests.como_rotina((select unidade_a from t_ids));
select public.rt_projecao_demanda();

-- ===========================================================================
-- 1. v_projecao_aluno.ritmo_dias — a coluna nova
-- ===========================================================================
-- O panorama primeiro: qual ritmo cada degrau produz na fixture. Uma
-- implementação que aplicasse o fator de aceleração aos quatro degraus, ou que
-- preenchesse os dois de baixo, muda esta linha inteira.
select is(
  (select string_agg(distinct pa.regra || '=' || coalesce(pa.ritmo_dias::text, '-'), ' | ' order by pa.regra || '=' || coalesce(pa.ritmo_dias::text, '-'))
     from public.v_projecao_aluno pa
    where pa.unidade_id = (select unidade_a from t_ids)),
  'MEDIA_METODO=30 | MODULAR=- | PREVISAO_CURSO=- | RITMO_ALUNO=60',
  'ritmo_dias por degrau: o do metodo em MEDIA_METODO, o do aluno em RITMO_ALUNO, NULO nos outros dois');

-- RITMO_ALUNO: é o ritmo do PRÓPRIO aluno, o mesmo que a ficha dele mostra
-- (card 6.6). Se aqui saísse o do método, a tela explicaria a data com o número
-- errado — e ninguém perceberia, porque os dois são plausíveis.
select is(
  (select pa.ritmo_dias from public.v_projecao_aluno pa
    where pa.aluno_id = (select ana from t_ids) order by pa.k limit 1),
  (select r.ritmo_dias from public.v_ritmo_aluno r
    where r.aluno_id = (select ana from t_ids)),
  'em RITMO_ALUNO a coluna e o ritmo do proprio aluno, identico ao de v_ritmo_aluno');

-- MEDIA_METODO: é o parâmetro do método do aluno, resolvido pela chave
-- `ritmo_padrao_dias_<CODIGO>`. Diego Alves tem previsão VENCIDA e cai neste
-- degrau (card 8.1) — é o aluno certo para medir o fallback.
select is(
  (select pa.ritmo_dias from public.v_projecao_aluno pa
    where pa.aluno_id = (select diego from t_ids) order by pa.k limit 1),
  (select public.fn_param_int('ritmo_padrao_dias_' || me.codigo, 30)
     from public.aluno a join public.metodo me on me.id = a.metodo_id
    where a.id = (select diego from t_ids)),
  'em MEDIA_METODO a coluna e o parametro do metodo do aluno, pela chave ritmo_padrao_dias_<CODIGO>');

-- Os dois degraus em que a data NÃO vem de ritmo: a previsão foi declarada por
-- uma pessoa, e o cronograma da turma é quem manda.
select ok(
  (select bool_and(pa.ritmo_dias is null)
     from public.v_projecao_aluno pa
    where pa.aluno_id in ((select carla from t_ids), (select eduarda from t_ids))),
  'PREVISAO_CURSO e MODULAR tem ritmo_dias NULO — a data deles nao sai de ritmo nenhum');

-- ---------------------------------------------------------------------------
-- 1.1 A contraprova do ritmo: o PASSO entre itens consecutivos
-- ---------------------------------------------------------------------------
-- Esta é a asserção que separa "a coluna diz um número parecido" de "a coluna
-- diz o número que gerou a data". `data_prevista` de k e de k+1 distam
-- exatamente `ritmo_dias`, porque a fórmula é `ancora + k * ritmo`. Recompor o
-- ritmo fora da view passaria nas igualdades acima e erraria aqui no dia em que
-- o fator de aceleração de MEDIA_METODO mudasse.
select is(
  (select count(*) from (
     select pa.aluno_id,
            pa.data_prevista - lag(pa.data_prevista) over (partition by pa.aluno_id order by pa.k) as passo,
            pa.ritmo_dias
       from public.v_projecao_aluno pa
      where pa.unidade_id = (select unidade_a from t_ids)
        and pa.ritmo_dias is not null) x
    where x.passo is not null and x.passo <> x.ritmo_dias),
  0::bigint,
  'entre dois itens consecutivos a data avanca EXATAMENTE ritmo_dias — a coluna e a que gerou a data');

-- ===========================================================================
-- 2. v_projecao_material_mes — a grade da tela
-- ===========================================================================
-- O `join` em `material` é interno: não pode perder linha nem duplicar. É a
-- armadilha do card 2.3 §3.2 na direção que importa aqui — a grade some com um
-- material e a soma da tela deixa de fechar com o pedido sugerido.
select is(
  (select count(*) from public.v_projecao_material_mes g
    where g.unidade_id = (select unidade_a from t_ids)),
  (select count(*) from public.v_demanda_projetada d
    where d.unidade_id = (select unidade_a from t_ids)),
  'a grade tem UMA linha por linha de v_demanda_projetada: o join em material nao perde nem duplica');

select is(
  (select coalesce(sum(g.quantidade), 0) from public.v_projecao_material_mes g
    where g.unidade_id = (select unidade_a from t_ids)),
  (select coalesce(sum(d.quantidade), 0) from public.v_demanda_projetada d
    where d.unidade_id = (select unidade_a from t_ids)),
  'e a soma e a mesma — a grade e rotulo por cima do contrato, nunca uma segunda conta');

select is(
  (select count(*) from public.v_projecao_material_mes g
     join public.material m on m.id = g.material_id
    where g.unidade_id = (select unidade_a from t_ids)
      and (g.codigo <> m.codigo or g.nome <> m.nome
           or g.categoria <> m.categoria or g.metodo_id <> m.metodo_id)),
  0::bigint,
  'codigo, nome, categoria e metodo da grade sao os do material, sem copia envelhecida');

-- O carimbo é da PROJEÇÃO INTEIRA, não de um material (card 8.2): a rotina
-- apaga e regrava a unidade a cada execução. É o que autoriza a tela a ler o
-- maior e chamá-lo de "calculada em".
select is(
  (select count(distinct g.calculado_em) from public.v_projecao_material_mes g
    where g.unidade_id = (select unidade_a from t_ids)),
  1::bigint,
  'calculado_em e o MESMO em toda a grade da unidade — e o carimbo da rodada, nao do material');

-- ---------------------------------------------------------------------------
-- 2.1 A grade NÃO filtra `material.ativo`, e é decisão
-- ---------------------------------------------------------------------------
-- Apostila aposentada que ainda está na trilha de um aluno ATIVO vai ser
-- precisa. Escondê-la aqui esconderia a demanda exatamente do caso mais fácil de
-- esquecer; quem filtra ativo é o pedido sugerido (§2.3), que fala de compra.
-- A contraprova é direta: desativa-se um material projetado e ele continua.
update public.material m
   set ativo = false
 where m.id = (select g.material_id from public.v_projecao_material_mes g
                where g.unidade_id = (select unidade_a from t_ids)
                order by g.codigo, g.mes, g.regra limit 1);

select cmp_ok(
  (select count(*) from public.v_projecao_material_mes g
     join public.material m on m.id = g.material_id
    where g.unidade_id = (select unidade_a from t_ids) and not m.ativo),
  '>', 0::bigint,
  'material INATIVO continua na grade: demanda nao e compra, e a apostila aposentada ainda esta em trilha');

update public.material m set ativo = true where not m.ativo;

-- ===========================================================================
-- 3. v_projecao_aluno_detalhe — o drill-down
-- ===========================================================================
-- `mes` é `date_trunc('month', data_prevista)`, letra por letra a expressão do
-- `group by` de rt_projecao_demanda. Sem isso o drill-down de uma célula
-- devolveria "quase" os alunos daquela célula.
select is(
  (select count(*) from public.v_projecao_aluno_detalhe d
    where d.unidade_id = (select unidade_a from t_ids)
      and d.mes <> date_trunc('month', d.data_prevista)::date),
  0::bigint,
  'mes e sempre o dia 1 do mes de data_prevista — a mesma expressao que a rotina agrupa');

-- ---------------------------------------------------------------------------
-- 3.1 A PARIDADE: total e detalhe fecham célula por célula
-- ---------------------------------------------------------------------------
-- A janela é a que a rotina gravou. Comparar fora dela seria comparar o que a
-- grade nem tenta ter (ver 3.3).
select is(
  (select count(*) from (
     select g.material_id, g.mes, sum(g.quantidade)::bigint as total
       from public.v_projecao_material_mes g
      where g.unidade_id = (select unidade_a from t_ids)
      group by g.material_id, g.mes) t
     full join (
     select d.material_id, d.mes, count(*)::bigint as detalhe
       from public.v_projecao_aluno_detalhe d
      where d.unidade_id = (select unidade_a from t_ids)
        and d.mes between (select min(g.mes) from public.v_projecao_material_mes g
                            where g.unidade_id = (select unidade_a from t_ids))
                      and (select max(g.mes) from public.v_projecao_material_mes g
                            where g.unidade_id = (select unidade_a from t_ids))
      group by d.material_id, d.mes) x
       on x.material_id = t.material_id and x.mes = t.mes
    where t.total is distinct from x.detalhe),
  0::bigint,
  'celula por celula, o total da grade e a CONTAGEM de alunos do detalhe — nenhuma divergencia');

select is(
  (select count(*) from (
     select g.material_id, g.mes, g.regra, sum(g.quantidade)::bigint as total
       from public.v_projecao_material_mes g
      where g.unidade_id = (select unidade_a from t_ids)
      group by g.material_id, g.mes, g.regra) t
     full join (
     select d.material_id, d.mes, d.regra, count(*)::bigint as detalhe
       from public.v_projecao_aluno_detalhe d
      where d.unidade_id = (select unidade_a from t_ids)
        and d.mes between (select min(g.mes) from public.v_projecao_material_mes g
                            where g.unidade_id = (select unidade_a from t_ids))
                      and (select max(g.mes) from public.v_projecao_material_mes g
                            where g.unidade_id = (select unidade_a from t_ids))
      group by d.material_id, d.mes, d.regra) x
       on x.material_id = t.material_id and x.mes = t.mes and x.regra = t.regra
    where t.total is distinct from x.detalhe),
  0::bigint,
  'e fecha tambem por REGRA: a proveniencia do total e a mesma que o drill-down mostra');

-- ---------------------------------------------------------------------------
-- 3.2 A fixture tem célula de DUAS regras — senão 3.1 mediria menos do que diz
-- ---------------------------------------------------------------------------
-- Material atendido por um só degrau faria a paridade por regra ser a mesma
-- asserção da anterior escrita duas vezes.
select cmp_ok(
  (select count(*) from (
     select g.material_id, g.mes from public.v_projecao_material_mes g
      where g.unidade_id = (select unidade_a from t_ids)
      group by g.material_id, g.mes having count(distinct g.regra) > 1) x),
  '>', 0::bigint,
  'ha celula com mais de uma regra na fixture — e o caso "Varias" da coluna Regra da tela');

-- ---------------------------------------------------------------------------
-- 3.3 O detalhe passa da janela, a grade não — e essa divergência é a certa
-- ---------------------------------------------------------------------------
-- A rotina grava só [mês corrente, mês de hoje + horizonte]; a view do detalhe
-- não recorta nada, porque é a expressão inteira. Sem esta asserção, a paridade
-- de 3.1 poderia estar comparando duas listas idênticas por construção.
select cmp_ok(
  (select count(*) from public.v_projecao_aluno_detalhe d
    where d.unidade_id = (select unidade_a from t_ids)
      and d.mes > (select max(g.mes) from public.v_projecao_material_mes g
                    where g.unidade_id = (select unidade_a from t_ids))),
  '>', 0::bigint,
  'o detalhe tem meses ALEM da janela da rotina: a grade e recortada de proposito, o detalhe nao');

select is(
  (select count(*) from public.v_projecao_aluno_detalhe d
     join public.aluno a    on a.id = d.aluno_id
     join public.material m on m.id = d.material_id
    where d.unidade_id = (select unidade_a from t_ids)
      and (d.aluno_nome <> a.nome or d.codigo_sgf <> a.codigo_sgf
           or d.aluno_status <> a.status
           or d.codigo <> m.codigo or d.material_nome <> m.nome)),
  0::bigint,
  'nome, codigo SGF e status do aluno e o rotulo do material sao os das tabelas, sem copia');

-- ===========================================================================
-- 4. Paridade de linhas, silêncio e isolamento (card 2.8 §6.3)
-- ===========================================================================
-- "O perfil X lê a view sem erro" é asserção quase vazia: a RLS não devolve
-- erro, ela REDUZ LINHAS em silêncio. O teste correto é paridade, com a
-- contagem da direção garantidamente > 0.
--
-- ⚠️ `tests.encerrar_sessao()` PRIMEIRO, e isto não é higiene: as seções 1 a 3
--    rodaram em contexto de rotina, e dentro dele `tem_permissao()` é sempre
--    verdadeira (card 2.2 §2.2) — é o que faz o `pg_cron` enxergar linha com
--    `force row level security` ligado. Sem limpar a GUC, `tests.conta_como`
--    autentica o usuário e a RLS continua liberando tudo: medido em 05/09/2026,
--    com `semperfil@` vendo as 7 linhas da grade e as 49 do detalhe. As sete
--    asserções desta seção passariam **verdes e sem medir nada**, que é o modo
--    de falha que o card 2.8 §6.3 existe para evitar.
select tests.encerrar_sessao();

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_projecao_material_mes'),
  '>', 0::bigint,
  'a direcao ve linhas na grade (a contagem de referencia da paridade e > 0)');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select 1 from public.v_projecao_material_mes') as n
       from (values ('direcao@escola-a.test'), ('secretaria@escola-a.test'),
                    ('pedagogico@escola-a.test'), ('monitor@escola-a.test')) v(e)) x),
  1::bigint,
  'os quatro perfis veem a MESMA grade: a tela 8 nao mente para ninguem');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select 1 from public.v_projecao_aluno_detalhe') as n
       from (values ('direcao@escola-a.test'), ('secretaria@escola-a.test'),
                    ('pedagogico@escola-a.test'), ('monitor@escola-a.test')) v(e)) x),
  1::bigint,
  'e o MESMO drill-down — o monitor confere a compra com os mesmos alunos que a direcao');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_projecao_material_mes'),
  0::bigint,
  'quem nao tem perfil ve ZERO linha na grade — e a rota e barrada antes, pelo guarda do card 3.7');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_projecao_aluno_detalhe'),
  0::bigint,
  'idem no drill-down');

-- Isolamento de unidade: as duas escolas têm projeção, e nenhuma vê a da outra.
select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_projecao_material_mes g
                     where g.unidade_id = ''' || (select unidade_a from t_ids) || ''''),
  0::bigint,
  'a ESCOLA_B nao ve uma linha da grade da ESCOLA_A, e as duas tem projecao gravada');

-- ---------------------------------------------------------------------------
-- 4.1 As duas reduções silenciosas, e elas são DIFERENTES
-- ---------------------------------------------------------------------------
-- Sem `materiais.ler` as duas views vêm vazias (join interno em `material`, e o
-- `metodo` que v_projecao_aluno já junta). Sem `alunos.ler` o detalhe vem vazio
-- e a grade continua CHEIA — o mesmo desenho de v_turma_modular_aluno (7.3).
-- É por isso que a rota da tela exige os quatro códigos: a tela que decide a
-- compra não pode vir vazia com cara de escola sem demanda.
delete from public.perfil_permissao pp
 using public.perfil pe, public.permissao pm
 where pp.perfil_id = pe.id and pp.permissao_id = pm.id
   and pe.unidade_id = (select unidade_a from t_ids) and pe.nome = 'Monitor'
   and pm.codigo = 'materiais.ler';

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_projecao_material_mes'),
  0::bigint,
  'sem materiais.ler a grade vem VAZIA, nao errada — e ninguem recebe erro nenhum');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_projecao_aluno_detalhe'),
  0::bigint,
  'e o drill-down tambem: os dois juntam material internamente');

delete from public.perfil_permissao pp
 using public.perfil pe, public.permissao pm
 where pp.perfil_id = pe.id and pp.permissao_id = pm.id
   and pe.unidade_id = (select unidade_a from t_ids) and pe.nome = 'Pedagógico'
   and pm.codigo = 'alunos.ler';

select is(
  tests.conta_como(tests.uid('pedagogico@escola-a.test'),
                   'select 1 from public.v_projecao_aluno_detalhe'),
  0::bigint,
  'sem alunos.ler o drill-down vem VAZIO — a lista de nomes exige a permissao de quem tem nome');

select cmp_ok(
  tests.conta_como(tests.uid('pedagogico@escola-a.test'),
                   'select 1 from public.v_projecao_material_mes'),
  '>', 0::bigint,
  'e a grade dele continua CHEIA na mesma transacao: as duas reducoes sao diferentes, e a tela precisa saber disso');

select * from finish();
rollback;
