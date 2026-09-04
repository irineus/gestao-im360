-- =============================================================================
-- Views de leitura: a grade semanal (card 5.6) e as quatro de estoque, demanda
-- e pedido sugerido (card 6.4)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- ⚠️ O card 6.4 acrescentou as seções 9 a 14, sobre `v_estoque_atual`,
--    `v_demanda_imediata_aluno`, `v_demanda_imediata` e `v_pedido_sugerido`
--    (docs/views-leitura.md §4.1, §5.1, §5.2 e §6). O que elas medem, e que
--    nenhuma outra suíte enxerga:
--      • as DUAS armadilhas do §3 que moram em `v_estoque_atual` — soma de
--        conjunto vazio (§3.1) e `count(*)` sobre `left join` (§3.2) —, com um
--        material criado SEM movimento nenhum, que é o caso que a fixture do
--        card 6.1 não tem e o mais urgente de comprar que existe;
--      • que `RASCUNHO` não abate e `ENVIADO` abate, cada um com a linha da
--        fixture que os separa — o mesmo erro nas duas direções;
--      • que `qtd_projetada` nasce como `0` NA POSIÇÃO DEFINITIVA (§6.2), por
--        `attnum` do catálogo, que é o que o card 8.2 vai depender;
--      • as QUATRO reduções silenciosas do §3.4, uma por permissão do conjunto
--        mínimo do §11 — e as duas formas opostas que elas tomam: sem
--        `materiais.ler` o estoque vem VAZIO, sem `estoque.ler` vem CHEIO com
--        saldo 0 em tudo, e sem `compras.ler` o pedido sugerido manda comprar
--        de novo o que já está a caminho;
--      • o ajuste 12 do §7 de docs/permissoes-matriz.md, atribuído ao 6.4:
--        `alunos.ler` SOZINHO devolve a demanda inteira, porque a view não lê
--        tabela de material nenhuma.
--
-- ⚠️ DIVERGÊNCIA REGISTRADA, não seguida em silêncio: o §17 atribui o
--    nascimento deste arquivo ao card **6.4** ("primeiras views") e diz que ele
--    "cresce em 5.6, 5.9, 8.7". O 6.4 é da fase 06 e este card é da 05, então
--    quem chega primeiro é o 5.6 — o arquivo nasce aqui e o 6.4 acrescenta as
--    views de estoque. A ordem prevista mudou; a obrigação, não.
--
-- Obrigação de teste de um card de **View** (§13): paridade de linhas por perfil
-- + zero para quem não pode + isolamento de unidade (§6.3), mais as armadilhas
-- do card 2.3 §3 que se aplicam aqui — `fn_hoje` em vez de `current_date` (C6
-- cobre a estrutura; a seção 2 cobre a aritmética) e a RLS que reduz em silêncio.
--
-- Quatro coisas que este arquivo prova e que nenhum catálogo enxerga:
--   • a view é a FUNÇÃO na semana corrente, linha por linha — sem isso as duas
--     ficariam livres para divergir no dia em que alguém mexesse numa só, que é
--     exatamente o que "escrever a view em cima da função" existe para impedir;
--   • `p_segunda` responde pela SEMANA que a contém: quarta e segunda dão a
--     mesma grade, com as mesmas datas;
--   • a ocupação é de uma DATA — a reposição PREVISTA aparece na semana dela e
--     some na seguinte, que é a razão de a função receber parâmetro;
--   • o `join` interno em `sala` e o `left join` em `professor` têm consequências
--     OPOSTAS quando falta permissão: sem `salas.ler` a grade vem VAZIA, sem
--     `professores.ler` ela vem CHEIA e sem professor nenhum. As duas são o
--     motivo escrito de o card 2.4 ter aberto as duas permissões para os quatro
--     perfis, e aqui isso deixa de ser parágrafo e vira asserção. O card 5.9
--     acrescentou o terceiro `join` interno, `metodo`/`materiais.ler`, que é o
--     bloqueante nº 1 de docs/permissoes-matriz.md §7 — escrito em 01/09/2026 e
--     nunca executado até aqui.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(86);

-- ===========================================================================
-- 1. As premissas da fixture, que são o que dá sentido aos números abaixo
-- ===========================================================================
select is(
  (select count(*)::bigint
     from public.bloco_horario b
     join public.sala s on s.id = b.sala_id
    where b.unidade_id = tests.unidade('ESCOLA_A')
      and s.nome = 'Laboratório 1' and b.ativo),
  3::bigint,
  'tres blocos ativos no Laboratorio 1 — a grade da fixture');

select is(
  (select count(*)::bigint
     from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A')
      and b.capacidade_override is not null),
  0::bigint,
  'nenhum bloco com capacidade_override: a capacidade TEM de sair dos PCs');

-- O bloco de 10 alunos é justamente o que a fixture criou SEM professor
-- (comentário do seed_turmas): é ele que reprova a grade escrita com `join`
-- interno em `professor`, porque a linha inteira sumiria.
select is(
  (select count(*)::bigint
     from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A') and b.professor_id is null),
  1::bigint,
  'exatamente um bloco sem professor na fixture — o caso que o left join existe para carregar');

-- Apelidos estáveis dos três blocos (mesma convenção do teste 041).
create temporary view t_bloco as
  select b.id,
         case b.dia_semana when 1 then 'vazio' when 2 then 'quase' else 'cheio' end
           as apelido
    from public.bloco_horario b
    join public.sala s on s.id = b.sala_id
   where b.unidade_id = tests.unidade('ESCOLA_A') and s.nome = 'Laboratório 1';

-- Uma segunda-feira três semanas à frente: longe da única reposição PREVISTA da
-- fixture (hoje + 3), para a seção 3 medir o que ela mesma escreve e não uma
-- coincidência de calendário.
create temporary view t_semana as
  select (date_trunc('week', public.fn_hoje() + 21)::date) as segunda;

-- As três funções do card 5.2 filtram a unidade NO CORPO, e `postgres` sem
-- `auth.uid()` não tem unidade nenhuma: sem contexto, capacidade e ocupação
-- viriam nulas e as seções 2 a 5 testariam o nada. O contexto de ROTINA é o
-- mesmo em que rt_capacidades (card 5.4) chama estas funções — e é também o que
-- permite escrever a reposição da seção 3, como faz o seed_turmas (card 5.3).
-- A seção 6 o desliga e prova que foi desligado.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

-- ===========================================================================
-- 2. A aritmética da semana: segunda ISO + (dia_semana − 1)
-- ===========================================================================
select is(
  (select g.data_referencia
     from public.fn_grade_semana((select segunda from t_semana)) g
     join t_bloco b on b.id = g.bloco_id
    where b.apelido = 'vazio'),
  (select segunda from t_semana),
  'bloco de segunda (dia_semana = 1): data_referencia e a propria segunda da semana pedida');

select is(
  (select g.data_referencia
     from public.fn_grade_semana((select segunda from t_semana)) g
     join t_bloco b on b.id = g.bloco_id
    where b.apelido = 'cheio'),
  (select segunda + 2 from t_semana),
  'bloco de quarta (dia_semana = 3): segunda + 2, a data DAQUELE bloco naquela semana');

-- A normalização da decisão (b): a função responde pela SEMANA de qualquer data
-- que receba. Sem ela, um clique que passasse a quarta devolveria a grade com as
-- datas deslocadas — e a data só aparece no rótulo, então a ocupação sairia
-- errada sem nada na tela dizendo.
select is(
  (select count(*)::bigint
     from (select bloco_id, data_referencia
             from public.fn_grade_semana((select segunda from t_semana))
           except
           select bloco_id, data_referencia
             from public.fn_grade_semana((select segunda + 2 from t_semana))) d),
  0::bigint,
  'fn_grade_semana(quarta) e fn_grade_semana(segunda) dao a MESMA grade: p_segunda e normalizada');

-- ===========================================================================
-- 3. As três parcelas são as do card 5.2, medidas NAQUELA data
-- ===========================================================================
select is(
  (select g.capacidade::text || '/' || g.ocupacao::text || '/' ||
          g.vagas_livres::text || '/' || g.acima_capacidade::text
     from public.fn_grade_semana((select segunda from t_semana)) g
     join t_bloco b on b.id = g.bloco_id
    where b.apelido = 'cheio'),
  '10/10/0/false',
  'bloco cheio: capacidade 10, ocupacao 10, zero vagas e NAO acima da capacidade');

select is(
  (select g.ocupacao
     from public.fn_grade_semana((select segunda from t_semana)) g
     join t_bloco b on b.id = g.bloco_id
    where b.apelido = 'vazio'),
  0,
  'bloco vazio numa semana sem reposicao: ocupacao 0 — e 0 e diferente de nulo');

-- A razão de a função receber parâmetro: a alocação vale toda semana, a
-- reposição vale só no dia (card 2.1 §8). Escrita na segunda da semana de teste,
-- que é o dia do bloco vazio.
insert into public.bloco_aluno_reposicao
       (unidade_id, bloco_id, aluno_id, data, status, observacao)
select tests.unidade('ESCOLA_A'),
       (select id from t_bloco where apelido = 'vazio'),
       a.id,
       (select segunda from t_semana),
       'PREVISTA',
       'teste 095: a reposicao aparece na semana dela e some na seguinte'
  from public.aluno a
 where a.unidade_id = tests.unidade('ESCOLA_A')
   and a.nome = 'Aluno de Lotação 01';

select is(
  (select g.ocupacao
     from public.fn_grade_semana((select segunda from t_semana)) g
     join t_bloco b on b.id = g.bloco_id
    where b.apelido = 'vazio'),
  1,
  'a reposicao PREVISTA daquele dia entra na ocupacao — a metade pontual do REP hibrido');

select is(
  (select g.ocupacao
     from public.fn_grade_semana((select segunda + 7 from t_semana)) g
     join t_bloco b on b.id = g.bloco_id
    where b.apelido = 'vazio'),
  0,
  'e na semana SEGUINTE ela nao entra: a lotacao e de uma data, nao do bloco');

-- ===========================================================================
-- 4. acima_capacidade — o mesmo fato da pendência BLOCO_ACIMA_CAPACIDADE
-- ===========================================================================
-- A view não abre pendência (view não escreve); mostra. Quem abre é
-- fn_revalidar_blocos_sala / rt_capacidades (card 5.4).
update public.bloco_horario
   set capacidade_override = 5
 where id = (select id from t_bloco where apelido = 'cheio');

select is(
  (select g.acima_capacidade
     from public.fn_grade_semana((select segunda from t_semana)) g
     join t_bloco b on b.id = g.bloco_id
    where b.apelido = 'cheio'),
  true,
  'dez alunos com override 5: acima_capacidade verdadeiro');

select is(
  (select g.vagas_livres
     from public.fn_grade_semana((select segunda from t_semana)) g
     join t_bloco b on b.id = g.bloco_id
    where b.apelido = 'cheio'),
  0,
  'e vagas_livres continua 0 e nunca negativo — quem mostra o excesso e acima_capacidade');

update public.bloco_horario
   set capacidade_override = null
 where id = (select id from t_bloco where apelido = 'cheio');

-- ===========================================================================
-- 5. A view é a função na semana corrente, linha por linha
-- ===========================================================================
select is(
  (select count(*)::bigint
     from (select * from public.v_bloco_vagas_semana
           except
           select * from public.fn_grade_semana(
                          date_trunc('week', public.fn_hoje())::date)) d),
  0::bigint,
  'nenhuma linha da view que a funcao nao devolva');

select is(
  (select count(*)::bigint
     from (select * from public.fn_grade_semana(
                          date_trunc('week', public.fn_hoje())::date)
           except
           select * from public.v_bloco_vagas_semana) d),
  0::bigint,
  'nem da funcao que a view nao devolva: a view E a funcao na semana corrente');

-- ===========================================================================
-- 6. Paridade de linhas por perfil (§6.3) — a decisão que o card 2.4 tomou
-- ===========================================================================
select tests.encerrar_sessao();

-- Sem esta primeira asserção, todas as de paridade abaixo passariam comparando
-- zero com zero (card 2.8 §6.3).
select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  '>', 0::bigint,
  'a direcao ve grade: paridade de zero com zero passaria sempre');

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  'secretaria ve a MESMA grade que a direcao');

select is(
  tests.conta_como(tests.uid('pedagogico@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  'pedagogico ve a MESMA grade que a direcao');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  'monitor ve a MESMA grade que a direcao — a grade e das quatro (wireframes §7)');

-- A tela chama a FUNÇÃO (navega semanas) e o dashboard do 5.9 chama a view. Se a
-- função fosse `definer`, o caminho do app seria um desvio da RLS que a view
-- respeita — e ninguém notaria, porque hoje os dois números coincidem.
select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.fn_grade_semana(date_trunc(''week'', public.fn_hoje())::date)'),
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  'a FUNCAO obedece a mesma RLS que a view: o caminho do app nao e desvio');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  0::bigint,
  'sem turmas.ler a grade e vazia — e vazia por RLS, que e o que a view NAO pode esconder');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_bloco_vagas_semana where unidade_id = ' ||
                   quote_literal(tests.unidade('ESCOLA_A')::text) || '::uuid'),
  0::bigint,
  'a direcao da Escola B nao ve bloco da Escola A: security_invoker + RLS por unidade');

-- ===========================================================================
-- 7. Os dois joins, e as consequências OPOSTAS de faltar permissão
-- ===========================================================================
-- É o motivo escrito de o card 2.4 ter aberto `salas.ler`, `materiais.ler` e
-- `professores.ler` aos quatro perfis. Os dois perfis abaixo existem só para que
-- esse motivo seja executável: quem um dia enxugar a matriz vê aqui o que custa.
insert into public.perfil (unidade_id, codigo, nome)
values (tests.unidade('ESCOLA_A'), 'SEM_SALAS',  'Turmas sem salas (teste 095)'),
       (tests.unidade('ESCOLA_A'), 'SEM_PROFES', 'Turmas sem professores (teste 095)');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select tests.unidade('ESCOLA_A'), pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A')
   and pm.unidade_id = tests.unidade('ESCOLA_A')
   and ((pe.codigo = 'SEM_SALAS'
         and pm.codigo in ('turmas.ler', 'materiais.ler', 'professores.ler'))
        or (pe.codigo = 'SEM_PROFES'
            and pm.codigo in ('turmas.ler', 'materiais.ler', 'salas.ler')));

select tests.criar_usuario('semsalas@escola-a.test',  'SEM_SALAS');
select tests.criar_usuario('semprofes@escola-a.test', 'SEM_PROFES');

select is(
  tests.conta_como(tests.uid('semsalas@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  0::bigint,
  'sem salas.ler a grade vem VAZIA — o join interno em sala, e o motivo de salas.ler ser dos quatro perfis');

select is(
  tests.conta_como(tests.uid('semprofes@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  'sem professores.ler a grade vem CHEIA: o left join nao deixa o professor levar o bloco embora');

select is(
  tests.conta_como(tests.uid('semprofes@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana where professor_nome is not null'),
  0::bigint,
  'e vem sem professor NENHUM — nao quebra, MENTE: e por isso que professores.ler e dos quatro perfis');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana where professor_nome is not null'),
  '>', 0::bigint,
  'contraprova: para quem tem professores.ler o nome VEM — senao a assercao acima passaria de graca');

-- O terceiro `join` interno é em `metodo`, e ele tem a MESMA consequência do de
-- `sala`. É o bloqueante nº 1 de docs/permissoes-matriz.md §7, aberto desde
-- 01/09/2026 e até aqui só escrito: o dashboard do card 5.9 é o segundo
-- consumidor desta view, a rota dele já exige `materiais.ler`, e o que faltava
-- era a prova de que exigir é obrigatório — sem ela, alguém enxuga a matriz e o
-- dashboard abre VAZIO, sem erro nenhum, com cara de escola sem turma.
insert into public.perfil (unidade_id, codigo, nome)
values (tests.unidade('ESCOLA_A'), 'SEM_MATERI', 'Turmas sem materiais (teste 095)');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select tests.unidade('ESCOLA_A'), pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A')
   and pm.unidade_id = tests.unidade('ESCOLA_A')
   and pe.codigo = 'SEM_MATERI'
   and pm.codigo in ('turmas.ler', 'salas.ler', 'professores.ler');

select tests.criar_usuario('semmateriais@escola-a.test', 'SEM_MATERI');

select is(
  tests.conta_como(tests.uid('semmateriais@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  0::bigint,
  'sem materiais.ler a grade vem VAZIA — o join interno em metodo (bloqueante 1 do card 2.4 §7)');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select tests.unidade('ESCOLA_A'), pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A')
   and pm.unidade_id = tests.unidade('ESCOLA_A')
   and pe.codigo = 'SEM_MATERI'
   and pm.codigo = 'materiais.ler';

select is(
  tests.conta_como(tests.uid('semmateriais@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana'),
  'e volta INTEIRA com materiais.ler: a causa e a permissao, e nao outra coisa do perfil');

-- ===========================================================================
-- 8. Bloco inativo sai da grade (e continua na tabela)
-- ===========================================================================
-- Bloco desativado não tem vaga a oferecer, então não é linha de grade. A tela
-- do card 5.6 tem lista própria para reabri-lo — sem ela, desativar seria porta
-- de mão única.
update public.bloco_horario set ativo = false
 where id = (select id from t_bloco where apelido = 'quase');

select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_vagas_semana v where v.bloco_id = ' ||
                   quote_literal((select id from t_bloco where apelido = 'quase')::text) || '::uuid'),
  0::bigint,
  'bloco inativo nao aparece na grade');

select is(
  (select count(*)::bigint from public.bloco_horario
    where id = (select id from t_bloco where apelido = 'quase')),
  1::bigint,
  'e continua na tabela: inativar nao apaga, e as alocacoes seguem sendo historico');

-- ###########################################################################
-- CARD 6.4 — v_estoque_atual, v_demanda_imediata_aluno, v_demanda_imediata
--            e v_pedido_sugerido
-- ###########################################################################

-- Apelido estável de cada material, pela CHAVE NATURAL (método + código) e
-- nunca pelo código sozinho: `material_codigo_uk` é (unidade, metodo, codigo) e
-- o '01' existe nos três métodos da fixture (seed §4 (a)). É view, não tabela
-- temporária, para acompanhar o material que a seção 10 cria.
create temporary view t_mat as
  select m.id, me.codigo || ' ' || m.codigo as apelido, m.estoque_minimo
    from public.material m
    join public.metodo me on me.id = m.metodo_id
   where m.unidade_id = tests.unidade('ESCOLA_A');

-- As seções 9 a 13 medem ARITMÉTICA e rodam como `postgres`, que tem BYPASSRLS
-- (card 3.3): o `join` em `t_mat` é o que restringe o resultado à ESCOLA_A, e
-- não a RLS. Quem mede a RLS é a seção 14, e é lá que a paridade acontece —
-- misturar as duas coisas é como se produz o teste que passa sem testar nada
-- (card 2.8 §6.3).

-- ===========================================================================
-- 9. v_estoque_atual: os seis saldos da fixture são a SOMA COM SINAL
-- ===========================================================================
-- Os saldos 0/0/1/n/n/n do card 2.8 §4.2 não estão escritos em coluna nenhuma
-- (seed §8 (a)): cada um é a soma dos movimentos que o produziram. Se algum dia
-- alguém trocar `sum(quantidade)` por uma soma com `case` por tipo, o ESTORNO e
-- o AJUSTE saem da conta e estas quatro asserções mudam de valor.
select is(
  (select count(*)::bigint from public.v_estoque_atual v
     join t_mat t on t.id = v.material_id),
  6::bigint,
  'os seis materiais da fixture aparecem em v_estoque_atual');

select is(
  (select string_agg(t.apelido || '=' || v.saldo, ' | ' order by t.apelido)
     from public.v_estoque_atual v join t_mat t on t.id = v.material_id),
  'INGLES 01=10 | INGLES 02=0 | INTERATIVO 01=20 | INTERATIVO 02=0 | INTERATIVO 03=1 | MODULAR 01=10',
  'saldo = sum(quantidade) com sinal: os 0/0/1/n/n/n do card 2.8 §4.2, derivados e nao escritos');

select is(
  (select string_agg(t.apelido || '=' || v.qtd_movimentos, ' | ' order by t.apelido)
     from public.v_estoque_atual v join t_mat t on t.id = v.material_id),
  'INGLES 01=2 | INGLES 02=2 | INTERATIVO 01=7 | INTERATIVO 02=4 | INTERATIVO 03=2 | MODULAR 01=3',
  'qtd_movimentos conta a linha de movimento, nao a de material');

select is(
  (select string_agg(t.apelido, ', ' order by t.apelido)
     from public.v_estoque_atual v join t_mat t on t.id = v.material_id
    where v.abaixo_minimo),
  'INGLES 02, INTERATIVO 02',
  'abaixo_minimo e os dois saldos zero, e so eles: 1 < 1 e falso e 20 < 2 tambem');

-- O AJUSTE negativo da fixture (extravio de INGLES 02) é o que leva um saldo a
-- zero SEM entrega nenhuma. Sem ele, `saldo = 0` e `nunca saiu para aluno`
-- seriam a mesma coisa e uma soma com `case` que ignorasse AJUSTE passaria.
select is(
  (select count(*)::bigint from public.movimento_estoque mv
     join t_mat t on t.id = mv.material_id
    where t.apelido = 'INGLES 02' and mv.tipo = 'SAIDA'),
  0::bigint,
  'INGLES 02 zerou pelo AJUSTE, sem nenhuma SAIDA — saldo zero nao implica entrega');

-- O par saída + estorno de Eduarda: o saldo volta ao que era e as DUAS linhas
-- continuam na tabela. É o contrato do estorno (card 2.2 §6.3) visto pela view.
select is(
  (select count(*)::bigint from public.movimento_estoque mv
     join t_mat t on t.id = mv.material_id
    where t.apelido = 'MODULAR 01' and mv.tipo in ('SAIDA','ESTORNO')),
  2::bigint,
  'MODULAR 01 tem a saida E o estorno, e ainda assim saldo 10: correcao e por estorno');

-- ===========================================================================
-- 10. O material sem movimento nenhum — as duas armadilhas do card 2.3 §3
-- ===========================================================================
-- A fixture do card 6.1 dá a TODOS os seis materiais pelo menos uma ENTRADA, e
-- é justamente o material recém-cadastrado — o que nunca foi comprado, o mais
-- urgente de todos — que o `left join` e o `coalesce` existem para carregar.
-- Sem esta seção, trocar `left join` por `join`, tirar o `coalesce` ou usar
-- `count(*)` passaria verde nesta suíte inteira.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

insert into public.material (unidade_id, metodo_id, codigo, nome, categoria, estoque_minimo)
select tests.unidade('ESCOLA_A'), me.id, '04', 'Informática Avançada 2', 'APOSTILA', 3
  from public.metodo me
 where me.unidade_id = tests.unidade('ESCOLA_A') and me.codigo = 'INTERATIVO';

select is(
  (select count(*)::bigint from public.v_estoque_atual v
     join t_mat t on t.id = v.material_id),
  7::bigint,
  'material recem-cadastrado NAO some da lista: left join, e nunca join (card 2.3 §3.1)');

select is(
  (select v.saldo from public.v_estoque_atual v
     join t_mat t on t.id = v.material_id where t.apelido = 'INTERATIVO 04'),
  0,
  'e o saldo dele e 0, nao nulo: sum() de conjunto vazio e null, e null some de toda comparacao');

select is(
  (select v.qtd_movimentos from public.v_estoque_atual v
     join t_mat t on t.id = v.material_id where t.apelido = 'INTERATIVO 04'),
  0,
  'qtd_movimentos 0: count(mov.id) nao conta a linha nula do left join (card 2.3 §3.2)');

select ok(
  (select v.ultimo_movimento_em is null from public.v_estoque_atual v
     join t_mat t on t.id = v.material_id where t.apelido = 'INTERATIVO 04'),
  'ultimo_movimento_em nulo — aqui o nulo e a verdade, e por isso max() nao leva coalesce');

select ok(
  (select v.abaixo_minimo from public.v_estoque_atual v
     join t_mat t on t.id = v.material_id where t.apelido = 'INTERATIVO 04'),
  'e ele aparece ABAIXO DO MINIMO: com saldo nulo a comparacao daria null e ele sumiria da compra');

-- ===========================================================================
-- 11. v_demanda_imediata_aluno e v_demanda_imediata
-- ===========================================================================
-- O "próximo livro" é a menor `ordem` com `entregue = false` (card 2.2 §5.2),
-- escrito uma vez para todos os alunos pelo `distinct on`. Nenhuma coluna o
-- guarda — é o critério (1) do marco 6.9.
--
-- Vinte linhas, e o número não é redondo por acaso: sete dos doze alunos da
-- camada `alunos` (os ATIVO/ACELERAR com trilha pendente) mais os treze
-- `Aluno de Lotação` da camada `turmas`, que também são ATIVO e também têm
-- combo — o preço escrito na seção 8.3 do seed.
select is(
  (select count(*)::bigint from public.v_demanda_imediata_aluno
    where unidade_id = tests.unidade('ESCOLA_A')),
  20::bigint,
  'vinte alunos com proximo livro: sete da camada alunos e os treze de lotacao');

select is_empty(
  $$ select 1 from public.v_demanda_imediata_aluno
      where aluno_status not in ('ATIVO','ACELERAR') $$,
  'so ATIVO e ACELERAR: STANDBY, TRANCADO, CANCELADO e FORMADO nao geram compra');

select is(
  (select count(distinct aluno_id)::bigint from public.v_demanda_imediata_aluno
    where unidade_id = tests.unidade('ESCOLA_A')),
  20::bigint,
  'uma linha por aluno, nunca duas: e o distinct on que faz o proximo ser UM');

select is(
  (select t.apelido || '|' || v.ordem || '|' || v.itens_pendentes
     from public.v_demanda_imediata_aluno v
     join t_mat t on t.id = v.material_id
     join public.aluno a on a.id = v.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Ana Paula Ribeiro'),
  'INTERATIVO 03|30|1',
  'Ana Paula recebeu 01 e 02: o proximo e o 03, na ordem 30, com 1 item pendente');

select is(
  (select t.apelido || '|' || v.itens_pendentes
     from public.v_demanda_imediata_aluno v
     join t_mat t on t.id = v.material_id
     join public.aluno a on a.id = v.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Carla Menezes'),
  'INTERATIVO 01|3',
  'Carla nao recebeu nada: o proximo e o primeiro da trilha, com os tres pendentes');

-- A entrega de Eduarda foi ESTORNADA (seed §8.5): o livro voltou ao estoque e o
-- item voltou a ser o próximo dela. Sem esta linha, o estorno provaria só que o
-- saldo volta — e metade do contrato ficaria sem asserção.
select is(
  (select t.apelido from public.v_demanda_imediata_aluno v
     join t_mat t on t.id = v.material_id
     join public.aluno a on a.id = v.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Eduarda Lima'),
  'MODULAR 01',
  'entrega estornada devolve o item a condicao de PROXIMO, e nao so o saldo ao estoque');

select is(
  (select count(*)::bigint from public.v_demanda_imediata_aluno v
     join public.aluno a on a.id = v.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'),
  0::bigint,
  'Gabriela esta em STANDBY ha 45 dias e NAO entra na demanda — aluno parado nao gera compra');

select is(
  (select count(*)::bigint from public.v_demanda_imediata_aluno v
     join public.aluno a on a.id = v.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Karina Bastos'),
  0::bigint,
  'Karina e ATIVO e nao tem combo, logo nao tem trilha: ausencia de demanda, nao de dado');

select is(
  (select string_agg(t.apelido || '=' || v.qtd_alunos, ' | ' order by t.apelido)
     from public.v_demanda_imediata v join t_mat t on t.id = v.material_id),
  'INGLES 02=1 | INTERATIVO 01=14 | INTERATIVO 02=2 | INTERATIVO 03=2 | MODULAR 01=1',
  'a agregada e a coluna DEMANDA da planilha: 14 no 01 (Carla + os treze de lotacao)');

select is(
  (select count(*)::bigint from public.v_demanda_imediata v
     join t_mat t on t.id = v.material_id where t.apelido = 'INGLES 01'),
  0::bigint,
  'material sem demanda NAO tem linha aqui — quem precisa da lista inteira e v_pedido_sugerido');

-- ===========================================================================
-- 12. v_pedido_sugerido: a fórmula, e o que abate e o que não abate
-- ===========================================================================
select is(
  (select count(*)::bigint from public.v_pedido_sugerido v
     join t_mat t on t.id = v.material_id),
  7::bigint,
  'todo material ATIVO aparece, inclusive com qtd_sugerida 0: quem filtra e a tela (card 2.3 §2.3)');

-- INTERATIVO 03 é o único com sugestão > 0, e a conta inteira está aqui:
-- 2 (imediata) + 0 (projetada) + 1 (mínimo) − 1 (saldo) − 0 (pendente) = 2.
select is(
  (select 'saldo=' || v.saldo || ' min=' || v.estoque_minimo ||
          ' imediata=' || v.qtd_imediata || ' projetada=' || v.qtd_projetada ||
          ' pendente=' || v.qtd_pedida_pendente || ' sugerida=' || v.qtd_sugerida
     from public.v_pedido_sugerido v join t_mat t on t.id = v.material_id
    where t.apelido = 'INTERATIVO 03'),
  'saldo=1 min=1 imediata=2 projetada=0 pendente=0 sugerida=2',
  'INTERATIVO 03: as cinco parcelas ao lado do total, e a conta fecha em 2');

-- A contraprova do RASCUNHO, e ela é o que dá sentido ao `pendente=0` acima: há
-- um pedido RASCUNHO com 5 exemplares deste mesmo material. Se RASCUNHO
-- abatesse, a sugestão viraria 0 e o sistema pararia de pedir uma compra que
-- nunca vai chegar — o erro que a asserção anterior existe para pegar.
select is(
  (select sum(pi.qtd_pedida)::integer
     from public.pedido_item pi
     join public.pedido_compra pc on pc.id = pi.pedido_id
     join t_mat t on t.id = pi.material_id
    where pc.status = 'RASCUNHO' and t.apelido = 'INTERATIVO 03'),
  5,
  'contraprova: existe um RASCUNHO de 5 do INTERATIVO 03, e ele NAO abateu nada');

-- E o outro lado do mesmo erro: ENVIADO abate. Sem isso, INTERATIVO 02 sairia
-- com sugestao 3 e a escola compraria de novo o que ja esta a caminho.
select is(
  (select v.qtd_pedida_pendente || '/' || v.qtd_sugerida
     from public.v_pedido_sugerido v join t_mat t on t.id = v.material_id
    where t.apelido = 'INTERATIVO 02'),
  '10/0',
  'ENVIADO abate: 10 pendentes do pedido 2026-002 derrubam a sugestao a zero');

select is_empty(
  $$ select 1 from public.v_pedido_sugerido where qtd_sugerida < 0 $$,
  'nenhuma qtd_sugerida negativa: o greatest(…, 0) zera, e zerar nao e esconder');

select is(
  (select v.qtd_sugerida from public.v_pedido_sugerido v
     join t_mat t on t.id = v.material_id where t.apelido = 'INTERATIVO 01'),
  0,
  'INTERATIVO 01 daria −4 pela formula e sai 0 — com a linha e as parcelas na tela');

select is_empty(
  $$ select 1 from public.v_pedido_sugerido where qtd_projetada <> 0 $$,
  'qtd_projetada e 0 em toda linha ate o card 8.1 existir: reserva, nao esquecimento');

select is(
  (select v.qtd_imediata || '/' || v.qtd_sugerida
     from public.v_pedido_sugerido v join t_mat t on t.id = v.material_id
    where t.apelido = 'INTERATIVO 04'),
  '0/3',
  'material sem demanda e sem movimento entra com a sugestao igual ao MINIMO — o que a planilha perdia');

-- A exceção declarada do §2.3: material aposentado sai da COMPRA e fica no
-- ESTOQUE. As duas metades juntas, porque uma sem a outra passaria com a view
-- restringindo `ativo` nos dois lugares (ou em nenhum).
update public.material set ativo = false
 where id = (select id from t_mat where apelido = 'INGLES 01');

select is(
  (select count(*)::bigint from public.v_pedido_sugerido v
     join t_mat t on t.id = v.material_id),
  6::bigint,
  'material inativo SAI do pedido sugerido: nao se sugere comprar apostila aposentada');

select is(
  (select count(*)::bigint from public.v_estoque_atual v
     join t_mat t on t.id = v.material_id),
  7::bigint,
  'e CONTINUA no estoque atual: apostila aposentada com saldo e estoque que a escola tem');

update public.material set ativo = true
 where id = (select id from t_mat where apelido = 'INGLES 01');

-- ===========================================================================
-- 13. A coluna reservada está na POSIÇÃO definitiva — card 2.3 §6.2
-- ===========================================================================
-- É o que o card 8.2 vai depender: `create or replace view` não insere coluna
-- no meio, não renomeia e não troca tipo. Com a coluna no lugar certo, o 8.2
-- troca duas expressões; fora dele, precisaria de `drop view` em cascata. A
-- asserção é de CATÁLOGO porque é a ordem, e não o valor, que está em jogo.
select is(
  (select a.attnum::integer
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'v_pedido_sugerido'
      and a.attname = 'qtd_projetada'),
  10,
  'qtd_projetada e a 10a coluna de v_pedido_sugerido, entre qtd_imediata e qtd_pedida_pendente');

select is(
  (select max(a.attnum)::integer
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'v_pedido_sugerido' and a.attnum > 0),
  12,
  'e a view tem doze colunas, com qtd_sugerida na ultima — a forma que o 8.2 encontra');

-- ===========================================================================
-- 14. Paridade de linhas por perfil, e as quatro reduções silenciosas do §3.4
-- ===========================================================================
select tests.encerrar_sessao();

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  '>', 0::bigint,
  'a direcao ve estoque: sem isso toda paridade abaixo compararia zero com zero');

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  'secretaria ve o MESMO estoque que a direcao');

select is(
  tests.conta_como(tests.uid('pedagogico@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  'pedagogico ve o MESMO estoque — ele nao compra, mas enxerga (card 2.4 §5)');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  'monitor ve o MESMO estoque: e por isso que estoque.ler esta nos quatro perfis');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  0::bigint,
  'sem perfil nenhum o estoque e vazio — e vazio por RLS, que a view nao pode esconder');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_estoque_atual where unidade_id = ' ||
                   quote_literal(tests.unidade('ESCOLA_A')::text) || '::uuid'),
  0::bigint,
  'a direcao da Escola B nao ve material da Escola A: security_invoker + RLS por unidade');

-- As duas reduções OPOSTAS de v_estoque_atual. É o mesmo par do §7 deste
-- arquivo, agora sobre estoque: um `join` que esvazia e um que mente. Os dois
-- perfis existem só para que o motivo escrito do card 2.4 seja executável.
insert into public.perfil (unidade_id, codigo, nome)
values (tests.unidade('ESCOLA_A'), 'SEM_MATER', 'Estoque sem materiais (teste 095)'),
       (tests.unidade('ESCOLA_A'), 'SEM_ESTOQ', 'Estoque sem estoque.ler (teste 095)'),
       (tests.unidade('ESCOLA_A'), 'SO_ALUNOS', 'Somente alunos.ler (teste 095)');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select tests.unidade('ESCOLA_A'), pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A')
   and pm.unidade_id = tests.unidade('ESCOLA_A')
   and ((pe.codigo = 'SEM_MATER'
         and pm.codigo in ('estoque.ler', 'alunos.ler', 'compras.ler'))
        or (pe.codigo = 'SEM_ESTOQ'
            and pm.codigo in ('materiais.ler', 'alunos.ler', 'compras.ler'))
        or (pe.codigo = 'SO_ALUNOS'
            and pm.codigo = 'alunos.ler'));

select tests.criar_usuario('semmaterial@escola-a.test', 'SEM_MATER');
select tests.criar_usuario('semestoque@escola-a.test',  'SEM_ESTOQ');
select tests.criar_usuario('soalunos@escola-a.test',    'SO_ALUNOS');

select is(
  tests.conta_como(tests.uid('semmaterial@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  0::bigint,
  'sem materiais.ler o estoque vem VAZIO: material e a tabela de onde a view parte');

select is(
  tests.conta_como(tests.uid('semestoque@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  'sem estoque.ler o estoque vem CHEIO — o left join nao deixa o movimento levar o material embora');

select is(
  tests.conta_como(tests.uid('semestoque@escola-a.test'),
                   'select 1 from public.v_estoque_atual where saldo <> 0'),
  0::bigint,
  'e com saldo 0 em TUDO: nao quebra, MENTE — o motivo de estoque.ler ser dos quatro perfis');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_estoque_atual where saldo <> 0'),
  '>', 0::bigint,
  'contraprova: para quem tem estoque.ler o saldo VEM — senao a assercao acima passaria de graca');

-- O ajuste 12 do §7 de docs/permissoes-matriz.md, atribuído a este card: a
-- demanda declarava `materiais.ler` e não lê tabela de material nenhuma.
-- `alunos.ler` SOZINHO tem de devolver a view inteira; se um dia alguém
-- acrescentar um `join` em `material` aqui, esta asserção cai — e é ela que
-- diz que o conjunto declarado no §11 voltou a estar errado.
select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_demanda_imediata_aluno'),
  '>', 0::bigint,
  'a direcao ve demanda: de novo, zero contra zero passaria sempre');

select is(
  tests.conta_como(tests.uid('soalunos@escola-a.test'),
                   'select 1 from public.v_demanda_imediata_aluno'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_demanda_imediata_aluno'),
  'alunos.ler SOZINHO devolve a demanda inteira — o ajuste 12 do card 2.4 §7, fechado aqui');

select is(
  tests.conta_como(tests.uid('soalunos@escola-a.test'),
                   'select 1 from public.v_demanda_imediata'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_demanda_imediata'),
  'e a agregada tambem: security_invoker declarado nas DUAS, e a de cima nao herda a de baixo');

select is(
  tests.conta_como(tests.uid('soalunos@escola-a.test'),
                   'select 1 from public.v_estoque_atual'),
  0::bigint,
  'coerencia: o mesmo perfil que ve a demanda inteira nao ve estoque nenhum');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_demanda_imediata_aluno'),
  0::bigint,
  'sem alunos.ler a demanda e vazia');

-- ⚠️ As duas asserções abaixo são sobre a view AGREGADA, e existem porque
-- `security_invoker` NÃO É HERDADO (card 2.3 §2.1) — mas o que elas pegam foi
-- MEDIDO, e não é o que a leitura ingênua da regra sugere (card 6.4):
--
--   • tirar a opção da view de BAIXO (`v_demanda_imediata_aluno`) vaza até aqui:
--     a agregada, que é `invoker`, passa a ler a de baixo como o DONO dela, que
--     tem BYPASSRLS (card 3.3), e a soma das DUAS unidades chega à tela com a
--     cara de um número certo. As três asserções seguintes ficam vermelhas.
--   • tirar a opção da view de CIMA, sozinha, NÃO vaza — e isso surpreende: com
--     a de baixo ainda `invoker`, as tabelas continuam sendo checadas contra o
--     usuário da sessão, e a contagem não muda. Quem acusa esse caso é o C5
--     (`011_catalogo_convencoes`), sozinho, e por isso ele não é redundante com
--     estas linhas.
--
-- A conclusão prática para os cards 8.1 e 8.2, que vão empilhar mais uma view
-- aqui: a opção continua sendo obrigatória nas duas pontas, mas o custo de
-- esquecê-la é assimétrico — embaixo é vazamento silencioso, em cima é só o C5
-- vermelho. Medido com `alter view … reset (security_invoker)` nas duas.
select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_demanda_imediata'),
  0::bigint,
  'a AGREGADA tambem e vazia sem alunos.ler: security_invoker declarado nela, nao herdado');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_demanda_imediata where unidade_id = ' ||
                   quote_literal(tests.unidade('ESCOLA_A')::text) || '::uuid'),
  0::bigint,
  'e a Escola B nao ve a demanda da Escola A pela agregada — view sobre view declara a opcao');

-- v_pedido_sugerido: a rota da tela de Compras (card 6.8) exige o conjunto
-- INTEIRO do §11, e a razão está nas duas asserções do monitor abaixo.
select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_pedido_sugerido'),
  '>', 0::bigint,
  'a direcao ve o pedido sugerido');

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
                   'select 1 from public.v_pedido_sugerido'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_pedido_sugerido'),
  'secretaria ve o MESMO pedido sugerido: os dois perfis que a matriz autoriza em compras');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_pedido_sugerido'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_pedido_sugerido'),
  'o monitor ve o MESMO NUMERO de linhas — e e exatamente por isso que o proximo teste importa');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_pedido_sugerido where material_id = ' ||
                   quote_literal((select id from t_mat where apelido = 'INTERATIVO 02')::text) ||
                   '::uuid and qtd_pedida_pendente = 0 and qtd_sugerida = 3'),
  1::bigint,
  'sem compras.ler o monitor le pendente 0 e sugere comprar 3 do que ja esta a caminho (card 2.3 §3.4)');

select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_pedido_sugerido where material_id = ' ||
                   quote_literal((select id from t_mat where apelido = 'INTERATIVO 02')::text) ||
                   '::uuid and qtd_pedida_pendente = 10 and qtd_sugerida = 0'),
  1::bigint,
  'contraprova: com compras.ler o mesmo material sai com pendente 10 e sugestao 0');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_pedido_sugerido'),
  0::bigint,
  'sem permissao nenhuma o pedido sugerido e vazio');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_pedido_sugerido where unidade_id = ' ||
                   quote_literal(tests.unidade('ESCOLA_A')::text) || '::uuid'),
  0::bigint,
  'e a direcao da Escola B nao ve o pedido sugerido da Escola A');

select * from finish();
rollback;
