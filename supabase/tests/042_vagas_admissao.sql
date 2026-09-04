-- =============================================================================
-- Vagas, admissão e reposições — card 5.3
-- (mapa suíte → card: docs/estrategia-testes.md §17 — era `040` até o card 5.1
--  ocupar o número e `041` até o 5.2 ocupar o seguinte)
--
-- Card de "Função/regra", então o §13 cobra quatro coisas: caminho feliz com
-- EFEITO conferido, um `throws_ok`/`codigo` por código que a função pode
-- levantar, um negativo de permissão e o teste de CAMADA 2 — escrever direto na
-- tabela, sem passar pela função de aplicação (§6.1). O de camada 2 é o que mais
-- vale aqui: com "Automatically expose new tables" ligado, `bloco_aluno` é uma
-- API REST, e um teste que só chama fn_bloco_admitir nunca descobre que o
-- trigger não existe.
--
-- Três coisas que este arquivo prova e que nenhum catálogo enxerga:
--   • a lotação é comparada com a CAPACIDADE, e capacidade NULA (bloco de outra
--     unidade, card 5.2) é ERRO e não "sem opinião" — `ocupacao >= null` é nulo,
--     e um `if` escrito sem pensar nisso deixaria o BLOCO_LOTADO passar calado
--     justamente na escrita que não deveria existir;
--   • mudar só o `tipo` de uma alocação JÁ ativa não disputa vaga nenhuma: a
--     linha já está contada, e a checagem ingênua responderia BLOCO_LOTADO num
--     bloco que não mudou de tamanho — é o que quebraria a virada REP dentro do
--     próprio bloco do aluno;
--   • reposição PREVISTA ocupa vaga NA DATA, e as outras três não: o passado não
--     bloqueia o presente.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(42);

-- ===========================================================================
-- 1. As premissas da fixture, que dão sentido aos números de baixo
-- ===========================================================================
-- Contexto de rotina pela mesma razão do teste 041: as funções de capacidade são
-- `security definer` e filtram a unidade NO CORPO, e `postgres` sem sessão não
-- tem unidade nenhuma — sem isto, esta seção mediria o nada.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

select is(
  (select string_agg(format('%s:%s/%s',
                            case b.dia_semana when 1 then 'vazio'
                                              when 2 then 'quase'
                                              else 'cheio' end,
                            public.fn_ocupacao_bloco(b.id),
                            public.fn_capacidade_efetiva(b.id)),
                     ' ' order by b.dia_semana)
     from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A')),
  'vazio:0/10 quase:9/10 cheio:10/10',
  'a fixture da a borda inteira: um bloco com folga, um com UMA vaga e um lotado');

-- A vaga que sobra no bloco de 9 é UMA. Sem esta asserção, "admitiu" e "lotou"
-- passariam os dois num bloco com folga de sobra e o teste não distinguiria
-- implementação nenhuma.
select is(
  (select public.fn_vagas_livres(b.id)
     from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A') and b.dia_semana = 2),
  1,
  'o bloco de 9 tem exatamente UMA vaga livre');

-- O contexto de rotina morre aqui: dentro dele tem_permissao() responde
-- verdadeiro para qualquer código, e todo negativo de permissão abaixo passaria
-- de graça.
select tests.encerrar_sessao();

-- ===========================================================================
-- 2. fn_bloco_admitir — caminho feliz, com o efeito conferido
-- ===========================================================================
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

-- `Aluno de Lotação 01` está no bloco de 10 e NÃO está no de 9: é o décimo do
-- bloco que tinha uma vaga. Escolhido por chave natural, nunca por `limit`
-- (docs/estrategia-testes.md §11).
select lives_ok(
  $$select public.fn_bloco_admitir(
      (select id from public.bloco_horario
        where dia_semana = 2 and unidade_id = public.fn_unidade_atual()),
      (select id from public.aluno
        where nome = 'Aluno de Lotação 01' and unidade_id = public.fn_unidade_atual()),
      'REM')$$,
  'a secretaria admite o decimo aluno no bloco que tinha uma vaga');

reset role;

select is(
  (select format('%s/%s/%s', ba.tipo, ba.ativo, public.fn_hoje() - ba.tipo_desde)
     from public.bloco_aluno ba
     join public.aluno a on a.id = ba.aluno_id
     join public.bloco_horario b on b.id = ba.bloco_id
    where a.nome = 'Aluno de Lotação 01' and b.dia_semana = 2
      and b.unidade_id = tests.unidade('ESCOLA_A')),
  'REM/t/0',
  'a alocacao nasceu ativa, com o tipo pedido e o relogio do tipo zerado hoje');

select tests.como_rotina(tests.unidade('ESCOLA_A'));

select is(
  (select public.fn_vagas_livres(b.id)
     from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A') and b.dia_semana = 2),
  0,
  'e a vaga sumiu: o bloco de 9 virou 10 de 10');

select tests.encerrar_sessao();

-- NOVO com data prevista: a vaga fica reservada desde já (card 5.2), e é por isso
-- que a data é obrigatória — sem ela ninguém sabe quando a vaga passa a ser dele.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_bloco_admitir(
      (select id from public.bloco_horario
        where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
      (select id from public.aluno
        where nome = 'Ana Paula Ribeiro' and unidade_id = public.fn_unidade_atual()),
      'NOVO', public.fn_hoje() + 7)$$,
  'e admite um NOVO com data prevista no bloco vazio');

reset role;

select is(
  (select (ba.data_inicio_prevista - public.fn_hoje())::text
     from public.bloco_aluno ba
     join public.aluno a on a.id = ba.aluno_id
     join public.bloco_horario b on b.id = ba.bloco_id
    where a.nome = 'Ana Paula Ribeiro' and b.dia_semana = 1
      and b.unidade_id = tests.unidade('ESCOLA_A')),
  '7',
  'com a data prevista gravada — a vaga esta reservada para daqui a sete dias');

-- ---------------------------------------------------------------------------
-- 2.1 Remover e readmitir REATIVA a mesma linha, e não duplica
-- ---------------------------------------------------------------------------
-- `bloco_aluno_ativo_uk` é PARCIAL (`where ativo`): nada impede uma linha
-- inativa ao lado de outra ativa, e é justamente por isso que "criar sempre"
-- passaria no banco e encheria a tabela de alocações repetidas — sem erro
-- nenhum, e com a grade histórica do card 5.6 contando a mesma pessoa três
-- vezes.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_bloco_remover(
      (select id from public.bloco_horario
        where dia_semana = 2 and unidade_id = public.fn_unidade_atual()),
      (select id from public.aluno
        where nome = 'Aluno de Lotação 01' and unidade_id = public.fn_unidade_atual()),
      'mudou de horario')$$,
  'a secretaria remove o aluno do bloco');

reset role;

select is(
  (select format('%s/%s', ba.ativo, ba.motivo_saida)
     from public.bloco_aluno ba
     join public.aluno a on a.id = ba.aluno_id
     join public.bloco_horario b on b.id = ba.bloco_id
    where a.nome = 'Aluno de Lotação 01' and b.dia_semana = 2
      and b.unidade_id = tests.unidade('ESCOLA_A')),
  'f/mudou de horario',
  'a linha fica INATIVA com o motivo gravado — exigir motivo e descarta-lo seria mentir para quem digita');

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_bloco_admitir(
      (select id from public.bloco_horario
        where dia_semana = 2 and unidade_id = public.fn_unidade_atual()),
      (select id from public.aluno
        where nome = 'Aluno de Lotação 01' and unidade_id = public.fn_unidade_atual()),
      'PRE')$$,
  'e readmite o mesmo aluno no mesmo bloco');

reset role;

select is(
  (select format('%s linha(s) %s/%s', count(*), max(ba.tipo::text),
                 coalesce(max(ba.motivo_saida), 'sem motivo'))
     from public.bloco_aluno ba
     join public.aluno a on a.id = ba.aluno_id
     join public.bloco_horario b on b.id = ba.bloco_id
    where a.nome = 'Aluno de Lotação 01' and b.dia_semana = 2
      and b.unidade_id = tests.unidade('ESCOLA_A')),
  '1 linha(s) PRE/sem motivo',
  'UMA linha so, reativada com o tipo novo e sem o motivo de uma saida que deixou de valer');

-- ===========================================================================
-- 3. Um código por vez — o §13 para card de Função/regra
-- ===========================================================================
-- O par canônico do §6.2 (SQLSTATE por `throws_ok`, código estável pelo helper)
-- fica com os dois códigos cuja MECÂNICA é deste card; nos demais o código basta,
-- e a mensagem em português nunca é contrato.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select throws_ok(
  $$select public.fn_bloco_admitir(
      (select id from public.bloco_horario
        where dia_semana = 3 and unidade_id = public.fn_unidade_atual()),
      (select id from public.aluno
        where nome = 'Aluno de Lotação 05' and unidade_id = public.fn_unidade_atual()),
      'REM')$$,
  'PT409', null,
  'admissao no bloco de 10/10 devolve PT409');

reset role;

select is(
  tests.codigo_do_erro(
    $$select public.fn_bloco_admitir(
        (select id from public.bloco_horario
          where dia_semana = 3 and unidade_id = public.fn_unidade_atual()),
        (select id from public.aluno
          where nome = 'Aluno de Lotação 05' and unidade_id = public.fn_unidade_atual()),
        'REM')$$,
    tests.uid('secretaria@escola-a.test')),
  'BLOCO_LOTADO',
  'e o codigo estavel e BLOCO_LOTADO — a borda 10/11 que a fixture existe para exercitar');

select is(
  tests.codigo_do_erro(
    $$select public.fn_bloco_admitir(
        (select id from public.bloco_horario
          where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
        (select id from public.aluno
          where nome = 'Henrique Dias' and unidade_id = public.fn_unidade_atual()),
        'REM')$$,
    tests.uid('secretaria@escola-a.test')),
  'ALUNO_INATIVO',
  'aluno TRANCADO nao ocupa vaga — quem parou nao segura lugar toda semana');

select is(
  tests.codigo_do_erro(
    $$select public.fn_bloco_admitir(
        (select id from public.bloco_horario
          where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
        (select id from public.aluno
          where nome = 'Felipe Nunes' and unidade_id = public.fn_unidade_atual()),
        'REM')$$,
    tests.uid('secretaria@escola-a.test')),
  'METODO_INCOMPATIVEL',
  'aluno de INGLES nao entra em bloco de INTERATIVO');

select is(
  tests.codigo_do_erro(
    $$select public.fn_bloco_admitir(
        (select id from public.bloco_horario
          where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
        (select id from public.aluno
          where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
        'NOVO')$$,
    tests.uid('secretaria@escola-a.test')),
  'DATA_PREVISTA_OBRIGATORIA',
  'NOVO sem data prevista para na funcao, com o codigo do catalogo — o check daria um 23514 que a tela nao traduz');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_bloco_admitir(%L,
        (select id from public.aluno
          where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
        'REM')$$, gen_random_uuid()),
    tests.uid('secretaria@escola-a.test')),
  'BLOCO_INEXISTENTE',
  'bloco que nao existe para na funcao, antes do 23503 cru da FK');

-- ⚠️ A asserção que sustenta o desenho: o bloco existe, mas é de OUTRA unidade.
-- fn_capacidade_efetiva devolve NULO nesse caso (card 5.2), e `ocupacao >= null`
-- é nulo, não falso — escrito sem cuidado, o `if` não dispara e a admissão passa
-- para a RLS decidir. Aqui ela decidiria certo; o dia em que uma função
-- `security definer` (que roda com BYPASSRLS, card 3.3) fizer a mesma escrita, a
-- RLS não decide nada e não sobra ninguém para dizer não.
select is(
  tests.codigo_do_erro(
    format($$select public.fn_bloco_admitir(%L,
        (select id from public.aluno
          where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
        'REM')$$,
      (select b.id from public.bloco_horario b
        where b.unidade_id = tests.unidade('ESCOLA_B') and b.dia_semana = 1)),
    tests.uid('secretaria@escola-a.test')),
  'BLOCO_INEXISTENTE',
  'bloco de OUTRA unidade tambem: capacidade nula e erro, nunca "sem opiniao"');

select is(
  tests.codigo_do_erro(
    format($$insert into public.bloco_aluno (unidade_id, bloco_id, aluno_id, tipo)
             select public.fn_unidade_atual(),
                    (select id from public.bloco_horario
                      where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
                    %L, 'REM'$$, gen_random_uuid()),
    tests.uid('secretaria@escola-a.test')),
  'ALUNO_INEXISTENTE',
  'aluno que nao existe para no trigger, com o codigo do card 4.2');

select is(
  tests.codigo_do_erro(
    $$select public.fn_bloco_remover(
        (select id from public.bloco_horario
          where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
        (select id from public.aluno
          where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()))$$,
    tests.uid('secretaria@escola-a.test')),
  'ALOCACAO_INEXISTENTE',
  'remover quem nao esta na turma DOI — silencio aqui e a tela dizendo "removido" sobre uma turma em que o aluno continua');

-- ===========================================================================
-- 4. Negativo de permissão: o monitor lê a grade e não aloca
-- ===========================================================================
select is(
  tests.codigo_do_erro(
    $$select public.fn_bloco_admitir(
        (select id from public.bloco_horario
          where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
        (select id from public.aluno
          where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
        'REM')$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor nao admite ninguem — fn_exige_permissao troca o silencio da RLS pelo codigo certo');

select is(
  tests.codigo_do_erro(
    $$select public.fn_bloco_remover(
        (select id from public.bloco_horario
          where dia_semana = 3 and unidade_id = public.fn_unidade_atual()),
        (select id from public.aluno
          where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()))$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'nem remove');

-- ===========================================================================
-- 5. CAMADA 2 — o POST direto, que é o que o §6.1 cobra
-- ===========================================================================
-- Toda tabela é uma API (pendência técnica 3). O teste que só chama a função
-- nunca descobre que o trigger não existe, e sem o trigger o PostgREST monta
-- onze alunos em dez PCs sem passar por nenhuma linha do card 5.3.
select is(
  tests.codigo_do_erro(
    $$insert into public.bloco_aluno (unidade_id, bloco_id, aluno_id, tipo)
      select public.fn_unidade_atual(),
             (select id from public.bloco_horario
               where dia_semana = 3 and unidade_id = public.fn_unidade_atual()),
             (select id from public.aluno
               where nome = 'Aluno de Lotação 05' and unidade_id = public.fn_unidade_atual()),
             'REM'$$,
    tests.uid('secretaria@escola-a.test')),
  'BLOCO_LOTADO',
  'CAMADA 2: o insert direto na tabela, sem passar por fn_bloco_admitir, tambem bate em BLOCO_LOTADO');

-- Reativar uma alocação antiga num bloco que encheu no meio-tempo é a mesma
-- disputa de vaga, com outra roupa: a linha estava fora da conta e volta para
-- dentro. Sem `not old.ativo` na condição de entrada, isto passaria.
insert into public.bloco_aluno (unidade_id, bloco_id, aluno_id, tipo, ativo)
select tests.unidade('ESCOLA_A'), b.id, a.id, 'REM', false
  from public.bloco_horario b, public.aluno a
 where b.unidade_id = tests.unidade('ESCOLA_A') and b.dia_semana = 3
   and a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Aluno de Lotação 06';

select is(
  tests.codigo_do_erro(
    $$update public.bloco_aluno set ativo = true
       where not ativo
         and bloco_id = (select id from public.bloco_horario
                          where dia_semana = 3 and unidade_id = public.fn_unidade_atual())
         and aluno_id = (select id from public.aluno
                          where nome = 'Aluno de Lotação 06'
                            and unidade_id = public.fn_unidade_atual())$$,
    tests.uid('secretaria@escola-a.test')),
  'BLOCO_LOTADO',
  'e reativar uma alocacao inativa num bloco cheio tambem: a linha volta para a conta');

-- ⚠️ E o caso que a guarda de NULO existe para pegar, reproduzido pelo caminho
-- mais curto que existe: `postgres` tem BYPASSRLS (card 3.3), então ele LÊ o
-- bloco e o aluno — o método confere, o aluno está ativo — mas
-- fn_capacidade_efetiva filtra a unidade no corpo e, sem sessão,
-- fn_unidade_atual() é nula: a capacidade volta NULA. `ocupacao >= null` é nulo,
-- não falso, e sem a guarda o `if` não dispara e a escrita passa SEM CHECAGEM DE
-- VAGA NENHUMA. É a mesma porta pela qual entrará toda função `security definer`
-- de propriedade do postgres — e é por isso que o seed do card 3.4.5 passou a
-- escrever a camada `turmas` em contexto de rotina em vez de ganhar uma exceção
-- dentro do trigger.
select is(
  tests.codigo_do_erro(
    format($$insert into public.bloco_aluno (unidade_id, bloco_id, aluno_id, tipo)
             values (%L,
                     (select id from public.bloco_horario
                       where dia_semana = 3 and unidade_id = %L),
                     (select id from public.aluno
                       where nome = 'Aluno de Lotação 05' and unidade_id = %L),
                     'REM')$$,
           tests.unidade('ESCOLA_A'), tests.unidade('ESCOLA_A'),
           tests.unidade('ESCOLA_A'))),
  'BLOCO_INEXISTENTE',
  'escrita SEM SESSAO e recusada alto: capacidade nula nao pode virar "cabe mais um" em silencio');

-- ⚠️ A contraprova, e é ela que separa "checar a vaga" de "checar sempre":
-- mudar só o `tipo` de uma alocação JÁ ativa não disputa vaga nenhuma — a linha
-- já está contada. Uma implementação que compare ocupação com capacidade em todo
-- update responderia BLOCO_LOTADO aqui, num bloco de 10/10 que continua 10/10, e
-- a virada REP dentro do próprio bloco do aluno ficaria impossível.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$update public.bloco_aluno set tipo = 'PRE'
     where ativo
       and bloco_id = (select id from public.bloco_horario
                        where dia_semana = 3 and unidade_id = public.fn_unidade_atual())
       and aluno_id = (select id from public.aluno
                        where nome = 'Carla Menezes'
                          and unidade_id = public.fn_unidade_atual())$$,
  'mudar o tipo de quem JA esta no bloco lotado passa — a linha nao entra na conta duas vezes');

reset role;

-- ===========================================================================
-- 6. Reposições — a metade pontual, e a vaga é NA DATA
-- ===========================================================================
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_reposicao_agendar(
      (select id from public.aluno
        where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
      (select id from public.bloco_horario
        where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
      public.fn_hoje() + 4)$$,
  'a secretaria agenda uma reposicao futura no bloco vazio');

reset role;

select tests.como_rotina(tests.unidade('ESCOLA_A'));

-- O bloco vazio tem uma alocação NOVO (seção 2) e, no dia da reposição, mais
-- uma cabeça. Nos outros dias, não: o `+1` só existe na data.
select is(
  (select format('%s/%s',
                 public.fn_ocupacao_bloco(b.id, public.fn_hoje() + 4),
                 public.fn_ocupacao_bloco(b.id, public.fn_hoje() + 5))
     from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A') and b.dia_semana = 1),
  '2/1',
  'a reposicao PREVISTA ocupa vaga SO na data dela — no dia seguinte o bloco volta ao que era');

select tests.encerrar_sessao();

-- Lotação também vale para reposição, e na data pedida: o bloco de 10/10 não
-- recebe nem mais uma cabeça por um dia.
select is(
  tests.codigo_do_erro(
    $$select public.fn_reposicao_agendar(
        (select id from public.aluno
          where nome = 'Aluno de Lotação 05' and unidade_id = public.fn_unidade_atual()),
        (select id from public.bloco_horario
          where dia_semana = 3 and unidade_id = public.fn_unidade_atual()),
        public.fn_hoje() + 4)$$,
    tests.uid('secretaria@escola-a.test')),
  'BLOCO_LOTADO',
  'reposicao num bloco lotado tambem e recusada — a vaga e a mesma, so que por um dia');

select is(
  tests.codigo_do_erro(
    $$select public.fn_reposicao_agendar(
        (select id from public.aluno
          where nome = 'Henrique Dias' and unidade_id = public.fn_unidade_atual()),
        (select id from public.bloco_horario
          where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
        public.fn_hoje() + 4)$$,
    tests.uid('secretaria@escola-a.test')),
  'ALUNO_INATIVO',
  'e aluno TRANCADO nao tem reposicao agendada');

-- ---------------------------------------------------------------------------
-- 6.1 A data retroativa tem permissão própria
-- ---------------------------------------------------------------------------
-- Nenhum perfil da matriz inicial tem `turmas.alocar` SEM
-- `turmas.lancar_reposicao_retroativa` — os três que alocam também lançam
-- retroativo. O perfil é montado aqui dentro, que é o único jeito de exercitar o
-- caso que a tela do card 4.7 torna possível.
delete from public.perfil_permissao pp
 using public.perfil pe, public.permissao pm
 where pp.perfil_id = pe.id and pp.permissao_id = pm.id
   and pe.unidade_id = tests.unidade('ESCOLA_A') and pe.codigo = 'SECRETARIA'
   and pm.codigo = 'turmas.lancar_reposicao_retroativa';

select is(
  tests.codigo_do_erro(
    $$select public.fn_reposicao_agendar(
        (select id from public.aluno
          where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
        (select id from public.bloco_horario
          where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
        public.fn_hoje() - 4)$$,
    tests.uid('secretaria@escola-a.test')),
  'SEM_PERMISSAO',
  'lancar reposicao com data no passado exige turmas.lancar_reposicao_retroativa');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select pe.unidade_id, pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A') and pe.codigo = 'SECRETARIA'
   and pm.unidade_id = pe.unidade_id
   and pm.codigo = 'turmas.lancar_reposicao_retroativa';

-- Contraprova: com a permissão de volta, a MESMA chamada passa. Sem ela, o
-- negativo acima passaria mesmo que a data retroativa estivesse proibida para
-- todo mundo.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_reposicao_agendar(
      (select id from public.aluno
        where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
      (select id from public.bloco_horario
        where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
      public.fn_hoje() - 4)$$,
  'e com a permissao de volta a mesma chamada passa');

reset role;

-- ---------------------------------------------------------------------------
-- 6.2 Registrar e cancelar
-- ---------------------------------------------------------------------------
-- fn_reposicao_registrar NASCE devolvendo `text` (ajuste 7 do card 2.2 §14,
-- transferido do 5.1 para cá): o veredito da virada volta para a tela na hora em
-- que a secretaria marca a presença, e não no dia seguinte quando a rotina do
-- card 5.5 abrir a pendência.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select is(
  (select public.fn_reposicao_registrar(
     (select br.id from public.bloco_aluno_reposicao br
        join public.aluno a on a.id = br.aluno_id
       where a.nome = 'Carla Menezes' and a.unidade_id = public.fn_unidade_atual()
         and br.data = public.fn_hoje() + 4),
     true)),
  'MANTER',
  'registrar presenca devolve o VEREDITO da virada, nao void');

reset role;

select is(
  (select br.status from public.bloco_aluno_reposicao br
     join public.aluno a on a.id = br.aluno_id
    where a.nome = 'Carla Menezes' and a.unidade_id = tests.unidade('ESCOLA_A')
      and br.data = public.fn_hoje() + 4),
  'REALIZADA',
  'e a reposicao ficou REALIZADA');

select is(
  tests.codigo_do_erro(
    $$select public.fn_reposicao_registrar(
        (select br.id from public.bloco_aluno_reposicao br
           join public.aluno a on a.id = br.aluno_id
          where a.nome = 'Carla Menezes' and a.unidade_id = public.fn_unidade_atual()
            and br.data = public.fn_hoje() + 4),
        false)$$,
    tests.uid('secretaria@escola-a.test')),
  'REPOSICAO_NAO_PREVISTA',
  'registrar de novo a mesma reposicao e recusado — o segundo clique nao troca o desfecho do primeiro');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_reposicao_cancelar(%L, 'nao vai dar')$$, gen_random_uuid()),
    tests.uid('secretaria@escola-a.test')),
  'REPOSICAO_INEXISTENTE',
  'cancelar reposicao que nao existe e recusado com o codigo proprio');

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_reposicao_cancelar(
      (select br.id from public.bloco_aluno_reposicao br
         join public.aluno a on a.id = br.aluno_id
        where a.nome = 'Lucas Ferreira' and a.unidade_id = public.fn_unidade_atual()
          and br.status = 'PREVISTA'),
      'desmarcada pelo aluno')$$,
  'a secretaria cancela uma reposicao PREVISTA');

reset role;

-- Cancelar NÃO quita a aula perdida: o débito continua em aberto, e é isso que
-- faz a sugestão de virada continuar valendo até alguém remarcar (card 2.5 §3.2).
select is(
  (select count(*)::bigint from public.bloco_aluno_reposicao br
     join public.aluno a on a.id = br.aluno_id
    where a.nome = 'Lucas Ferreira' and a.unidade_id = tests.unidade('ESCOLA_A')
      and br.status = 'REALIZADA'),
  1::bigint,
  'cancelar nao quita a aula: o numero de REALIZADA nao mudou');

-- ===========================================================================
-- 7. A saída sem ator agora diz por quê
-- ===========================================================================
-- tg_aluno_status_desaloca nasceu no card 5.1; aqui ele passa a gravar o motivo.
-- Sem isso, a coluna motivo_saida nasceria nula no caso MAIS COMUM de saída de
-- turma — o aluno que trancou —, e a ficha diria "saiu" sem dizer nada.
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));

select lives_ok(
  $$select public.fn_aluno_alterar_status(
      (select id from public.aluno
        where nome = 'Bruno Carvalho' and unidade_id = public.fn_unidade_atual()),
      'STANDBY', 'foi trabalhar')$$,
  'o pedagogico poe em STANDBY um aluno que estava em turma');

reset role;

select is(
  (select string_agg(distinct ba.motivo_saida, '|')
     from public.bloco_aluno ba
     join public.aluno a on a.id = ba.aluno_id
    where a.nome = 'Bruno Carvalho' and a.unidade_id = tests.unidade('ESCOLA_A')),
  'Aluno passou a STANDBY',
  'a desalocacao sem ator escreve o motivo — quem le a ficha tres meses depois sabe por que ele saiu');

-- ===========================================================================
-- 8. O advisory lock não sumiu (C13, docs/estrategia-testes.md §5.1)
-- ===========================================================================
-- Este é o guarda-chuva barato, e NÃO substitui
-- supabase/tests_concorrencia/admissao_ultima_vaga.sh: a suíte pgTAP roda numa
-- conexão só e o `select` que conta e o `insert` que grava acontecem na mesma
-- transação — a corrida simplesmente não existe aqui. O que este teste garante é
-- que a chamada não desapareceu num refactor.
--
-- `prosrc` inclui os comentários do corpo (lição do card 4.2), e os dois têm o
-- lock citado em comentário: sem removê-los, o teste aprovaria uma função que só
-- FALA do lock.
create temporary view corpo_admissao as
  select p.proname,
         regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as fonte
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('fn_bloco_admitir', 'fn_reposicao_agendar');

select is(
  (select string_agg(proname, ',' order by proname)
     from corpo_admissao where fonte ~ 'pg_advisory_xact_lock'),
  'fn_bloco_admitir,fn_reposicao_agendar',
  'C13: as duas funcoes que disputam vaga serializam o bloco com pg_advisory_xact_lock');

select is(
  (select count(*)::bigint from corpo_admissao
    where fonte ~ 'fn_capacidade_efetiva' or fonte ~ 'fn_ocupacao_bloco'),
  0::bigint,
  'e NENHUMA delas reescreve a conta de capacidade: a formula tem um dono so, o card 5.2');

select * from finish();
rollback;
