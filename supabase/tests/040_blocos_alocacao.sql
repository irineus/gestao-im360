-- =============================================================================
-- Blocos de horário e alocação — card 5.1
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Card de "Schema", então o §13 cobra duas listas: suíte de catálogo verde com
-- as tabelas novas (010 e 011 fazem sozinhas, derivando do catálogo do Postgres)
-- e um teste por check/unique que expresse regra de negócio.
--
-- Fora dessas duas, o arquivo prova as três coisas que este card decidiu e que
-- nenhum catálogo enxerga:
--   • `tipo_desde` é derivada e NÃO editável — é o relógio que a virada REP zera
--     (card 2.5 §3.2), e um PATCH que o movesse seria o contorno da regra;
--   • o `or` da política de update de `bloco_aluno` existe para a desalocação
--     sem ator e vaza todas as outras colunas, porque RLS não é por coluna
--     (card 2.4; o card 4.2 nomeou `bloco_aluno.tipo` como o próximo caso);
--   • a cascata de `bloco_aluno.bloco_id` apagava, em silêncio, o registro de
--     quem esteve na turma — o achado do card 4.3, que nomeou esta tabela.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
-- 42 e não 43 desde 05/09/2026 (card 7.1): o portão condicional do §10 virou
-- UMA asserção direta, porque a tabela que ele esperava passou a existir.
select plan(42);

-- ===========================================================================
-- 1. A fixture chegou (camada `turmas` do card 3.4.5)
-- ===========================================================================
select is(
  (select count(*)::bigint from public.bloco_horario b
     join public.unidade u on u.id = b.unidade_id where u.codigo = 'ESCOLA_A'),
  3::bigint,
  'tres blocos de horario na unidade A');

-- 0, 9 e 10 — e os dois cheios com alunos DISJUNTOS, senão nove alunos ATIVO
-- ficariam com dois blocos, que pela decisão de 31/08/2026 é a definição de
-- aceleração: a fixture afirmaria isso sem querer, e a rotina do card 5.5 leria
-- como verdade.
select is(
  (select string_agg(n::text, ',' order by n) from (
     select (select count(*) from public.bloco_aluno ba
              where ba.bloco_id = b.id and ba.ativo) as n
       from public.bloco_horario b
       join public.unidade u on u.id = b.unidade_id
      where u.codigo = 'ESCOLA_A') t(n)),
  '0,9,10',
  'os blocos tem 0, 9 e 10 alunos ativos — o de 9 aceita o decimo, o de 10 recusa o decimo primeiro');

select is(
  (select count(distinct ba.aluno_id)::bigint from public.bloco_aluno ba
     join public.bloco_horario b on b.id = ba.bloco_id
     join public.unidade u on u.id = b.unidade_id
    where u.codigo = 'ESCOLA_A' and ba.ativo),
  19::bigint,
  'dezenove alunos distintos: os dois blocos cheios NAO compartilham ninguem');

-- Nenhum override: a capacidade efetiva do card 5.2 tem de sair dos 10 PCs
-- OPERACIONAIS do Laboratório 1. Com override preenchido, a função passaria sem
-- nunca olhar para um PC.
select is(
  (select count(*)::bigint from public.bloco_horario b
     join public.unidade u on u.id = b.unidade_id
    where u.codigo = 'ESCOLA_A' and b.capacidade_override is not null),
  0::bigint,
  'nenhum bloco da fixture tem capacidade_override — a capacidade sai dos PCs');

-- `professor_id` é opcional (a planilha tem bloco sem professor definido), e a
-- grade do card 5.6 o lê por left join. Um bloco sem professor é o que reprova
-- a grade escrita com join interno, que some com a linha em vez de mostrá-la
-- sem o nome.
select is(
  (select count(*)::bigint from public.bloco_horario b
     join public.unidade u on u.id = b.unidade_id
    where u.codigo = 'ESCOLA_A' and b.professor_id is null),
  1::bigint,
  'um bloco sem professor — o caso que quebra a grade escrita com join interno');

-- Um aluno em REP contínuo, e um só: é o que a contagem de aceleração do card
-- 5.5 precisa FILTRAR (ajuste 4 do card 2.5 — alocação de reposição não é
-- aceleração) e o que o fn_rep_voltar_pontual do 5.3 precisa encontrar, com o
-- relógio já fora da carência de rep_janela_volta_dias.
select is(
  (select (public.fn_hoje() - ba.tipo_desde)::text
     from public.bloco_aluno ba
     join public.bloco_horario b on b.id = ba.bloco_id
     join public.unidade u on u.id = b.unidade_id
    where u.codigo = 'ESCOLA_A' and ba.tipo = 'REP' and ba.ativo),
  '40',
  'o unico aluno em REP continuo esta nele ha 40 dias — fora da carencia de volta (30)');

-- ===========================================================================
-- 2. Os checks e uniques que exprimem regra de negócio
-- ===========================================================================
-- ⚠️ AJUSTADO EM 03/09/2026 PELO CARD 5.3, e o motivo é estrutural, não de
-- conveniência: tg_bloco_aluno_admissao e tg_reposicao_admissao passaram a
-- falar ANTES das constraints — trigger BEFORE roda antes do `check`, da
-- `unique` e até do WITH CHECK da RLS. Uma asserção de camada 1 escrita com um
-- aluno de outro método ou num bloco lotado deixa de medir o `check` e passa a
-- medir o trigger, e o pior é que ela continua VERMELHA por um motivo plausível
-- (foi assim que este arquivo reprovou: "wanted 23514, caught PT422"). Duas
-- consequências, as duas aplicadas aqui:
--   • esta seção escreve como `postgres`, sem sessão, e sem sessão
--     fn_unidade_atual() é nula, fn_capacidade_efetiva devolve NULO e a admissão
--     responde BLOCO_INEXISTENTE. O contexto de ROTINA resolve, é o mesmo que a
--     seção 1 do teste 041 já usa e o mesmo em que o seed escreve a camada
--     `turmas` desde este card;
--   • cada caso de camada 1 precisa ser válido para a camada 2, senão a camada 2
--     responde primeiro. Daí um aluno INTERATIVO no bloco de INTERATIVO, e a
--     duplicata ativa indo para o bloco de 9 (que tem vaga) e não para o de 10.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

-- Ajuste 2 do §8 do card 2.5, BLOQUEANTE: sem `FALTOU`, quem não aparece à
-- reposição fica indistinguível de quem a desmarcou com antecedência — e é
-- exatamente essa diferença que o gatilho de reincidência do card 2.5 §3.4 mede.
select lives_ok(
  $$insert into public.bloco_aluno_reposicao
      (unidade_id, bloco_id, aluno_id, data, status)
    select b.unidade_id, b.id,
           (select id from public.aluno
             where nome = 'Bruno Carvalho' and unidade_id = b.unidade_id),
           public.fn_hoje() + 30, 'FALTOU'
      from public.bloco_horario b
      join public.unidade u on u.id = b.unidade_id
     where u.codigo = 'ESCOLA_A' and b.dia_semana = 1$$,
  'FALTOU e valor aceito em bloco_aluno_reposicao.status (ajuste bloqueante do card 2.5)');

select throws_ok(
  $$insert into public.bloco_aluno_reposicao
      (unidade_id, bloco_id, aluno_id, data, status)
    select b.unidade_id, b.id,
           (select id from public.aluno
             where nome = 'Bruno Carvalho' and unidade_id = b.unidade_id),
           public.fn_hoje() + 31, 'ESQUECEU'
      from public.bloco_horario b
      join public.unidade u on u.id = b.unidade_id
     where u.codigo = 'ESCOLA_A' and b.dia_semana = 1$$,
  '23514', null,
  'e o check continua fechado: status inventado e recusado');

-- NOVO sem data prevista é a alocação que a grade não sabe desenhar: o aluno
-- ainda não começou, e sem a data ninguém sabe quando a vaga passa a ser dele.
select throws_ok(
  $$insert into public.bloco_aluno (unidade_id, bloco_id, aluno_id, tipo)
    select b.unidade_id, b.id,
           (select id from public.aluno
             where nome = 'Carla Menezes' and unidade_id = b.unidade_id),
           'NOVO'
      from public.bloco_horario b
      join public.unidade u on u.id = b.unidade_id
     where u.codigo = 'ESCOLA_A' and b.dia_semana = 1$$,
  '23514', null,
  'tipo NOVO sem data_inicio_prevista e recusado (bloco_aluno_novo_ck)');

-- A mesma sala não pode ter dois blocos no mesmo dia e horário: seria a mesma
-- sala com duas turmas ao mesmo tempo, e as duas contariam os mesmos PCs.
select throws_ok(
  $$insert into public.bloco_horario (unidade_id, dia_semana, hora_inicio, metodo_id, sala_id)
    select b.unidade_id, b.dia_semana, b.hora_inicio, b.metodo_id, b.sala_id
      from public.bloco_horario b
      join public.unidade u on u.id = b.unidade_id
     where u.codigo = 'ESCOLA_A' and b.dia_semana = 1$$,
  '23505', null,
  'a mesma sala nao tem dois blocos no mesmo dia e horario');

-- O mesmo bloco e o mesmo dia da semana existem nas DUAS unidades, e a unique
-- precisa aceitar — recusaria se estivesse escrita sem o unidade_id.
select is(
  (select count(*)::bigint from public.bloco_horario b
    where b.dia_semana = 1 and b.hora_inicio = time '08:00'),
  2::bigint,
  'o mesmo dia e horario convivem nas duas unidades — a unique carrega unidade_id');

-- A unique de alocação ativa é PARCIAL: proíbe a segunda vaga ATIVA e permite a
-- linha inativa ao lado, que é o que deixa fn_bloco_admitir (card 5.3)
-- REATIVAR em vez de duplicar.
--
-- ⚠️ O aluno é NOMEADO, e não `limit 1` (correção do card 5.2, 03/09/2026). As
-- duas consultas eram `... and ba.ativo limit 1`, sem `order by`: o Postgres pode
-- devolver qualquer uma das dezenove alocações ativas, e a segunda escreve uma
-- linha INATIVA para o aluno sorteado. No dia em que o sorteio caísse no `Aluno de
-- Lotação 13`, a asserção de `tipo_desde` da seção 3 passaria a ler DUAS linhas e
-- o arquivo inteiro morreria em "more than one row returned by a subquery" — 27
-- dos 43 testes sem rodar, com a mensagem apontando para 100 linhas adiante da
-- causa. Foi o que aconteceu ao exercitar a suíte num stack local novo, e não é
-- instabilidade de ambiente: é a fonte nº 1 do §11 (ordem não pedida é ordem não
-- garantida). Nenhuma asserção posterior conta linhas do aluno escolhido.
--
-- ⚠️ O aluno passou de `Lotação 01` para `Lotação 05` no card 5.3, e a troca é a
-- diferença entre medir a unique e medir o trigger: `01` está no bloco de 10/10,
-- onde a duplicata ATIVA agora bate em BLOCO_LOTADO antes de chegar ao índice.
-- `05` está no de 9/10, que tem a vaga que deixa o insert alcançar a unique.
select throws_ok(
  $$insert into public.bloco_aluno (unidade_id, bloco_id, aluno_id, tipo)
    select ba.unidade_id, ba.bloco_id, ba.aluno_id, 'REM'
      from public.bloco_aluno ba
      join public.aluno a on a.id = ba.aluno_id
      join public.bloco_horario b on b.id = ba.bloco_id
      join public.unidade u on u.id = b.unidade_id
     where u.codigo = 'ESCOLA_A' and ba.ativo
       and a.nome = 'Aluno de Lotação 05'$$,
  '23505', null,
  'um aluno nao ocupa duas vagas ATIVAS no mesmo bloco');

select lives_ok(
  $$insert into public.bloco_aluno (unidade_id, bloco_id, aluno_id, tipo, ativo)
    select ba.unidade_id, ba.bloco_id, ba.aluno_id, 'REM', false
      from public.bloco_aluno ba
      join public.aluno a on a.id = ba.aluno_id
      join public.bloco_horario b on b.id = ba.bloco_id
      join public.unidade u on u.id = b.unidade_id
     where u.codigo = 'ESCOLA_A' and ba.ativo
       and a.nome = 'Aluno de Lotação 05'$$,
  'mas a alocacao INATIVA ao lado passa — o indice e parcial, e e isso que deixa reativar');

-- O contexto de rotina TEM de morrer aqui: dentro dele tem_permissao() responde
-- verdadeiro para qualquer código, e as asserções de SEM_PERMISSAO da seção 4
-- passariam de graça — o teste de permissão mais perigoso é o que roda com
-- permissão de mais.
select tests.encerrar_sessao();

-- ===========================================================================
-- 3. tipo_desde é derivada, não editável (ajuste 1 do card 2.5)
-- ===========================================================================
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$update public.bloco_aluno set tipo = 'REP'
     where aluno_id = (select id from public.aluno
                        where nome = 'Ana Paula Ribeiro'
                          and unidade_id = public.fn_unidade_atual())
       and ativo$$,
  'a secretaria (turmas.alocar) muda o tipo da alocacao');

reset role;

select is(
  (select ba.tipo_desde from public.bloco_aluno ba
     join public.aluno a on a.id = ba.aluno_id
    where a.nome = 'Ana Paula Ribeiro'
      and a.unidade_id = tests.unidade('ESCOLA_A') and ba.ativo),
  public.fn_hoje(),
  'mudar o tipo move tipo_desde para hoje — e o relogio que a virada REP zera');

-- O valor enviado é IGNORADO. Se o PATCH pudesse escrevê-lo, a virada teria um
-- contorno pelo PostgREST: para trás o débito volta a pesar, para a frente ele
-- some.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

update public.bloco_aluno set tipo_desde = public.fn_hoje() - 500
 where aluno_id = (select id from public.aluno
                    where nome = 'Ana Paula Ribeiro'
                      and unidade_id = public.fn_unidade_atual())
   and ativo;

reset role;

select is(
  (select ba.tipo_desde from public.bloco_aluno ba
     join public.aluno a on a.id = ba.aluno_id
    where a.nome = 'Ana Paula Ribeiro'
      and a.unidade_id = tests.unidade('ESCOLA_A') and ba.ativo),
  public.fn_hoje(),
  'e o valor enviado no UPDATE e ignorado: tipo_desde nao e editavel');

-- Desativar a alocação NÃO é mudar o tipo. Sem esta distinção, toda saída de
-- aluno da turma zeraria o relógio do débito dele.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

update public.bloco_aluno set ativo = false
 where aluno_id = (select id from public.aluno
                    where nome = 'Aluno de Lotação 13'
                      and unidade_id = public.fn_unidade_atual())
   and ativo;

reset role;

select is(
  (select (public.fn_hoje() - ba.tipo_desde)::text from public.bloco_aluno ba
     join public.aluno a on a.id = ba.aluno_id
    where a.nome = 'Aluno de Lotação 13'
      and a.unidade_id = tests.unidade('ESCOLA_A')),
  '40',
  'desativar a alocacao nao mexe em tipo_desde — sair da turma nao e mudar de tipo');

-- ===========================================================================
-- 4. RLS não é por coluna — a folga do `or` na política de update
-- ===========================================================================
-- O `or` existe por um motivo só: deixar tg_aluno_status_desaloca (card 5.3)
-- escrever `ativo = false` na transação de quem mudou o status. Mas ele
-- autoriza junto qualquer outra coluna, e nenhum perfil da matriz inicial é
-- assim — os três que alteram status também alocam. O perfil é montado aqui,
-- dentro da transação, que é o único jeito de exercitar o caso que a tela do
-- card 4.7 torna possível.
delete from public.perfil_permissao pp
 using public.perfil pe, public.permissao pm
 where pp.perfil_id = pe.id and pp.permissao_id = pm.id
   and pe.unidade_id = tests.unidade('ESCOLA_A') and pe.codigo = 'PEDAGOGICO'
   and pm.codigo = 'turmas.alocar';

select is(
  tests.codigo_do_erro(
    $$update public.bloco_aluno set tipo = 'REP'
       where aluno_id = (select id from public.aluno
                          where nome = 'Bruno Carvalho'
                            and unidade_id = public.fn_unidade_atual())
         and ativo$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'quem altera status e nao aloca NAO muda o tipo — a virada REP nao se executa pelo PostgREST');

select is(
  tests.codigo_do_erro(
    $$update public.bloco_aluno set bloco_id =
        (select id from public.bloco_horario
          where dia_semana = 1 and unidade_id = public.fn_unidade_atual())
       where aluno_id = (select id from public.aluno
                          where nome = 'Bruno Carvalho'
                            and unidade_id = public.fn_unidade_atual())
         and ativo$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'nem troca o aluno de bloco pulando a checagem de vaga do card 5.3');

select is(
  tests.codigo_do_erro(
    $$update public.bloco_aluno_reposicao set status = 'REALIZADA'
       where status = 'FALTOU' and unidade_id = public.fn_unidade_atual()$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'nem quita um debito marcando a reposicao como REALIZADA');

-- Contraprova: o mesmo perfil, sem `turmas.alocar`, continua fazendo as DUAS
-- escritas que o `or` existe para permitir. Sem estas linhas os três negativos
-- acima passariam mesmo que as guardas estivessem barrando tudo — e a
-- desalocação sem ator do card 5.3 nasceria quebrada.
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));

select lives_ok(
  $$update public.bloco_aluno set ativo = false
     where aluno_id = (select id from public.aluno
                        where nome = 'Bruno Carvalho'
                          and unidade_id = public.fn_unidade_atual())
       and ativo$$,
  'e continua desativando a alocacao — que e o que tg_aluno_status_desaloca faz');

select lives_ok(
  $$update public.bloco_aluno_reposicao set status = 'CANCELADA'
     where status = 'PREVISTA' and unidade_id = public.fn_unidade_atual()$$,
  'e cancelando a reposicao futura — a outra metade da desalocacao sem ator');

reset role;

-- Devolve a permissão: os testes seguintes contam com a matriz do seed.
insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select pe.unidade_id, pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A') and pe.codigo = 'PEDAGOGICO'
   and pm.unidade_id = pe.unidade_id and pm.codigo = 'turmas.alocar';

-- ===========================================================================
-- 5. A guarda de exclusão e os DOIS MUNDOS (o achado do card 4.3, aqui)
-- ===========================================================================
-- Bloco novo, sem ninguém dentro: o caso que mantém `turmas.excluir` com um uso
-- real. Sem ele, a guarda seria uma proibição total escrita como se fosse uma
-- condição.
insert into public.bloco_horario (unidade_id, dia_semana, hora_inicio, metodo_id, sala_id)
select tests.unidade('ESCOLA_A'), 6, time '10:00', m.id, s.id
  from public.metodo m, public.sala s
 where m.unidade_id = tests.unidade('ESCOLA_A') and m.codigo = 'INTERATIVO'
   and s.unidade_id = tests.unidade('ESCOLA_A') and s.nome = 'Laboratório 1';

select is(
  tests.codigo_do_erro(
    $$delete from public.bloco_horario
       where dia_semana = 3 and unidade_id = public.fn_unidade_atual()$$,
    tests.uid('direcao@escola-a.test')),
  'BLOCO_COM_ALOCACAO',
  'bloco com alunos alocados nao pode ser apagado — "excluir sem alocacao" vira estrutura');

-- O bloco VAZIO tem zero alocações e mesmo assim recusa: as reposições de Lucas
-- estão marcadas nele. Sem contar as reposições, a guarda deixaria passar
-- justamente o delete que a FK RESTRICT abortaria com um 23503 ilegível.
select is(
  tests.codigo_do_erro(
    $$delete from public.bloco_horario
       where dia_semana = 1 and unidade_id = public.fn_unidade_atual()$$,
    tests.uid('direcao@escola-a.test')),
  'BLOCO_COM_ALOCACAO',
  'bloco sem alocacao nenhuma, mas com reposicoes marcadas, tambem recusa');

select tests.autenticar(tests.uid('direcao@escola-a.test'));

select lives_ok(
  $$delete from public.bloco_horario
     where dia_semana = 6 and unidade_id = public.fn_unidade_atual()$$,
  'bloco sem historico continua apagavel — a guarda nao esvazia turmas.excluir');

reset role;

-- CONTRAPROVA: o mundo sem a guarda. O trigger cai dentro desta transação e
-- volta no rollback. Sem ele, apagar o bloco leva junto as alocações — em
-- SILÊNCIO, e apesar de `bloco_aluno` não ter política de delete para ninguém:
-- a ação em cascata de uma FK não passa pela RLS da tabela referenciadora
-- (medido no card 4.3). Guarda que nunca foi vista fazendo diferença é
-- decoração.
--
-- A contraprova usa o bloco de TERÇA e não o de quarta: o de quarta é a origem
-- das aulas perdidas de Lucas, e `bloco_origem_id` é RESTRICT — sem a guarda ele
-- não cascatearia, morreria com um 23503, e a contraprova mostraria o mundo
-- errado. É a assimetria que a seção 8 do arquivo da migração descreve.
select cmp_ok(
  (select count(*)::bigint from public.bloco_aluno ba
     join public.bloco_horario b on b.id = ba.bloco_id
    where b.dia_semana = 2 and b.unidade_id = tests.unidade('ESCOLA_A')),
  '>', 0::bigint,
  'antes da contraprova, o bloco de terca tem as suas alocacoes');

drop trigger tg_bloco_exclusao_valida on public.bloco_horario;

select tests.autenticar(tests.uid('direcao@escola-a.test'));
delete from public.bloco_horario
 where dia_semana = 2 and unidade_id = public.fn_unidade_atual();
reset role;

select is(
  (select count(*)::bigint from public.bloco_aluno ba
    where ba.bloco_id not in (select id from public.bloco_horario)),
  0::bigint,
  'SEM a guarda, a cascata apagou as alocacoes junto com o bloco — sem erro e sem politica de delete');

-- ===========================================================================
-- 6. Sem política de delete, o delete NÃO dá erro: devolve zero linhas
-- ===========================================================================
-- Card 3.4 (d). É o silêncio que se escreve como asserção, senão ninguém sabe
-- que a decisão está viva — e é ele que fn_exige_permissao existe para traduzir
-- dentro das funções de aplicação do card 5.3.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

with d as (delete from public.bloco_aluno where true returning 1)
select is((select count(*) from d)::bigint, 0::bigint,
  'ninguem apaga alocacao — nem a direcao; alocacao encerrada e ativo = false');

with d as (delete from public.bloco_aluno_reposicao where true returning 1)
select is((select count(*) from d)::bigint, 0::bigint,
  'nem reposicao; desmarcar e status = CANCELADA');

reset role;

-- ===========================================================================
-- 7. RLS — paridade, silêncio e isolamento (card 2.8 §6.3)
-- ===========================================================================
-- `turmas.ler` é dos quatro perfis: sem ela a grade do card 5.6 abriria VAZIA,
-- não com erro.
select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'), 'select id from public.bloco_horario'),
  '>', 0::bigint,
  'a direcao le blocos (a contagem de referencia da paridade e > 0)');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select id from public.bloco_aluno') as n
       from (values ('direcao@escola-a.test'), ('pedagogico@escola-a.test'),
                    ('secretaria@escola-a.test'), ('monitor@escola-a.test')) as u(e)
   ) t)::bigint,
  1::bigint,
  'paridade: os quatro perfis com turmas.ler leem a MESMA contagem de alocacoes');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'), 'select id from public.bloco_horario'),
  0::bigint,
  'quem nao tem turmas.ler le zero — a RLS reduz em silencio, nao acusa');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   format('select id from public.bloco_horario where unidade_id = %L',
                          tests.unidade('ESCOLA_A'))),
  0::bigint,
  'a unidade B nao ve bloco nenhum da unidade A');

-- O monitor lê a grade e não aloca: `turmas.alocar` é dos outros três (card 2.4
-- §5). O erro dele é o silêncio da RLS, não uma exceção — por isso a asserção é
-- sobre a linha que NÃO nasceu.
--
-- ⚠️ O aluno mudou de `Felipe Nunes` (INGLES) para `Carla Menezes` (INTERATIVO)
-- no card 5.3, e a troca guarda um achado: o trigger BEFORE fala ANTES do WITH
-- CHECK da RLS, então uma linha inválida faz o monitor receber
-- METODO_INCOMPATIVEL em vez do 42501 — o teste de permissão passaria a medir o
-- método. Para medir a permissão, a linha tem de ser válida em tudo o mais.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select throws_ok(
  $$insert into public.bloco_aluno (unidade_id, bloco_id, aluno_id, tipo)
    select public.fn_unidade_atual(),
           (select id from public.bloco_horario
             where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
           (select id from public.aluno
             where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
           'REM'$$,
  '42501', null,
  'o monitor tem turmas.ler e nao tem turmas.alocar');

reset role;

-- ===========================================================================
-- 8. O débito de Lucas está EXATAMENTE na borda do critério do card 2.5
-- ===========================================================================
-- O critério é do card 5.3 (fn_rep_avaliar_virada); o que se asserta aqui é que
-- a FIXTURE o coloca na borda, e numa borda em que `ceil` e `floor` divergem.
-- Fixture que passa nas duas implementações não distingue nenhuma.
select is(
  (select count(*)::bigint from public.bloco_aluno_reposicao br
     join public.aluno a on a.id = br.aluno_id
    where a.nome = 'Lucas Ferreira' and a.unidade_id = tests.unidade('ESCOLA_A')
      and br.status <> 'REALIZADA'),
  3::bigint,
  'tres aulas perdidas EM ABERTO: FALTOU, CANCELADA e PREVISTA contam (card 2.5 §3.2)');

-- A aula quitada é a mais ANTIGA de todas, de propósito: uma implementação que
-- tome min(data_origem) sem filtrar as quitadas acha prazo vencido e sugere a
-- virada de um aluno que está em dia.
select is(
  (select (public.fn_hoje() - min(coalesce(br.data_origem, br.data)))::text
     from public.bloco_aluno_reposicao br
     join public.aluno a on a.id = br.aluno_id
    where a.nome = 'Lucas Ferreira' and a.unidade_id = tests.unidade('ESCOLA_A')
      and br.status <> 'REALIZADA'),
  '10',
  'a aula em aberto mais antiga e de dez dias atras — e a quitada, de vinte, nao conta');

-- Com os parâmetros do seed do card 3.6 lidos do banco (nunca escritos aqui:
-- número mágico no teste é o teste passando a acreditar em si mesmo), o limite
-- é rep_capacidade_semanal × semanas_uteis, com semanas_uteis contadas da aula
-- em aberto mais antiga até o prazo dela: 30 − 10 = 20 dias.
--
-- debito(3) > limite_ceil(3) é FALSO — viável, sem pendência, e é a metade que
-- o card 5.3 vai testar de um lado. Com `floor` o limite seria 2, 3 > 2 é
-- verdadeiro, e o mesmo aluno viraria REP contínuo: a fixture separa as duas
-- implementações em vez de passar nas duas.
with p as (
  select max(case when chave = 'rep_prazo_dias'         then valor::int end) as prazo,
         max(case when chave = 'rep_capacidade_semanal' then valor::int end) as cap
    from public.parametro
   where unidade_id = tests.unidade('ESCOLA_A')
     and chave in ('rep_prazo_dias', 'rep_capacidade_semanal')
)
select is(
  (select format('%s/%s',
                 cap * ceil ((prazo - 10)::numeric / 7),
                 cap * floor((prazo - 10)::numeric / 7))
     from p),
  '3/2',
  'o limite e 3 com ceil e 2 com floor — e o debito 3 fica viavel so com o ceil que o card 2.5 exige');

-- ===========================================================================
-- 9. tg_aluno_status_desaloca — a vaga se larga sozinha
-- ===========================================================================
-- É o trigger que o portão do teste 030 (card 4.2) cobra deste card. O que ele
-- protege é silencioso: sem ele o aluno em STANDBY continua ocupando vaga toda
-- semana, e a grade do card 5.6 mostraria uma turma cheia de gente que parou.
--
-- Duas reposições para Diego, uma futura e uma passada: só a futura é cancelada.
-- A passada é histórico e é o débito que o critério do card 2.5 mede — cancelar
-- retroativamente apagaria a razão pela qual ele seria sugerido para REP
-- contínuo quando voltasse.
--
-- Contexto de rotina outra vez (card 5.3): uma das duas datas está no PASSADO, e
-- tg_reposicao_admissao exige turmas.lancar_reposicao_retroativa para isso —
-- `postgres` sem sessão não tem permissão nenhuma. Desligado logo abaixo, antes
-- de qualquer asserção que dependa de quem é quem.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

insert into public.bloco_aluno_reposicao (unidade_id, bloco_id, aluno_id, data, status)
select tests.unidade('ESCOLA_A'), b.id, a.id, public.fn_hoje() + d.dias, 'PREVISTA'
  from public.bloco_horario b, public.aluno a, (values (10), (-3)) as d(dias)
 where b.unidade_id = tests.unidade('ESCOLA_A') and b.dia_semana = 1
   and a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Diego Alves';

select tests.encerrar_sessao();

select tests.autenticar(tests.uid('pedagogico@escola-a.test'));

select lives_ok(
  $$select public.fn_aluno_alterar_status(
      (select id from public.aluno
        where nome = 'Diego Alves' and unidade_id = public.fn_unidade_atual()),
      'STANDBY', 'parou de vir')$$,
  'o pedagogico move Diego de ATIVO para STANDBY');

reset role;

select is(
  (select count(*)::bigint from public.bloco_aluno ba
     join public.aluno a on a.id = ba.aluno_id
    where a.nome = 'Diego Alves' and a.unidade_id = tests.unidade('ESCOLA_A')
      and ba.ativo),
  0::bigint,
  'quem sai de ATIVO larga a vaga — sem isso o aluno parado ocupa lugar toda semana');

select is(
  (select br.status from public.bloco_aluno_reposicao br
     join public.aluno a on a.id = br.aluno_id
    where a.nome = 'Diego Alves' and a.unidade_id = tests.unidade('ESCOLA_A')
      and br.data = public.fn_hoje() + 10),
  'CANCELADA',
  'e a reposicao FUTURA e cancelada junto');

select is(
  (select br.status from public.bloco_aluno_reposicao br
     join public.aluno a on a.id = br.aluno_id
    where a.nome = 'Diego Alves' and a.unidade_id = tests.unidade('ESCOLA_A')
      and br.data = public.fn_hoje() - 3),
  'PREVISTA',
  'mas a passada nao — ela e o debito que o criterio do card 2.5 mede');

-- ===========================================================================
-- 10. As TRÊS tabelas da desalocação (card 2.2 §3.2)
-- ===========================================================================
-- ⚠️ ESTE PORTÃO CUMPRIU O QUE PROMETIA E FOI COBRADO EM 05/09/2026 (card 7.1).
--    Até aqui ele era condicional — `to_regclass('public.turma_modular_aluno')
--    is null or (a função a cita)` — e provava que reprovava criando a tabela
--    dentro da transação. Nascida a tabela DE VERDADE, o `create table` do
--    contraprova morreria com "already exists" e a condição `is null` deixaria
--    de ter dois mundos para separar: o que restava era a asserção direta.
--
--    O que ela mede continua sendo o mesmo, e continua sendo o que nenhum
--    catálogo enxerga: esquecer uma das três não daria erro nenhum: daria o erro
--    ERRADO, com o aluno trancado continuando na turma e a previsão do módulo
--    contando com ele. A prova de COMPORTAMENTO — trancar o aluno e ver a linha
--    da turma Modular cair — está no teste 070 §6, com a contraprova por
--    construção (a função reescrita sem a citação, e o aluno ficando).
--
--    Lição do card 4.2 preservada: `prosrc` inclui os comentários do corpo — e o
--    desta função os cita todos —, então eles saem antes da busca. Sem o
--    `regexp_replace`, esta asserção passaria mesmo com os três `update`
--    apagados.
create temporary view corpo_desaloca as
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as fonte
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_aluno_status_desaloca';

select is(
  (select coalesce(string_agg(t.tabela, ', ' order by t.tabela), '')
     from (values ('bloco_aluno'), ('bloco_aluno_reposicao'), ('turma_modular_aluno'))
            as t(tabela)
    where not (select fonte ~ ('update public\.' || t.tabela || '\M')
                 from corpo_desaloca)),
  '',
  'fn_aluno_status_desaloca escreve nas TRES tabelas do card 2.2 §3.2 — a mensagem diz qual faltou');

select * from finish();
rollback;
