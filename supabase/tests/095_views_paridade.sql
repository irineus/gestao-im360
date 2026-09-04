-- =============================================================================
-- Grade semanal: fn_grade_semana e v_bloco_vagas_semana — card 5.6
-- (mapa suíte → card: docs/estrategia-testes.md §17)
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
--     perfis, e aqui isso deixa de ser parágrafo e vira asserção.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(27);

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

select * from finish();
rollback;
