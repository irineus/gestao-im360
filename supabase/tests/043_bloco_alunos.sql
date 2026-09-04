-- =============================================================================
-- Alunos do bloco: v_bloco_alunos e fn_bloco_alunos — card 5.7
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Obrigação de teste de um card de **View** (§13): paridade de linhas por perfil
-- + zero para quem não pode + isolamento de unidade (§6.3). Mais três coisas que
-- só este arquivo prova e que nenhum catálogo enxerga:
--
--   • **a lista soma o que o cabeçalho diz.** `count(fn_bloco_alunos)` tem de
--     ser `fn_ocupacao_bloco` na mesma data. Uma lista com nove nomes debaixo de
--     um "10/10" não é reportada como defeito, é reportada como "o sistema está
--     estranho" — e as duas contas nascem de lugares diferentes (a lista, da
--     view; o número, do card 5.2), então nada além desta asserção as prende;
--   • **a reposição aparece na data DELA, com o bloco de origem** (wireframe
--     §7.2 e apontamento #3 do §17) — é a razão de a função receber `p_data`;
--   • **desativar um bloco passou a ter consequência visível.** É o ajuste que o
--     card 5.6 registrou para cá: os alunos continuam alocados, mas
--     `rt_pendencias_diaria` passa a vê-los como sem turma. Antes deste card o
--     desfecho era o pior possível — nenhum aviso, nenhuma pendência, e a turma
--     inteira fora da grade;
--   • **falta de permissão vira ERRO e não lista vazia**, que é a única
--     diferença entre "o bloco está vazio" e "você não pode ver o bloco".
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(36);

-- ===========================================================================
-- 1. As premissas da fixture, que são o que dá sentido aos números abaixo
-- ===========================================================================
create temporary view t_bloco as
  select b.id,
         case b.dia_semana when 1 then 'vazio' when 2 then 'quase' else 'cheio' end
           as apelido
    from public.bloco_horario b
    join public.sala s on s.id = b.sala_id
   where b.unidade_id = tests.unidade('ESCOLA_A') and s.nome = 'Laboratório 1';

select is(
  (select count(*)::bigint from t_bloco), 3::bigint,
  'fixture: os tres blocos do Laboratorio 1 (card 5.1)');

-- A única reposição PREVISTA da fixture: Lucas Ferreira no bloco vazio, em
-- `fn_hoje() + 3`, com origem no bloco cheio (seed_turmas, card 5.3).
create temporary view t_reposicao as
  select br.id, br.data, br.bloco_id, br.aluno_id, br.bloco_origem_id, br.data_origem
    from public.bloco_aluno_reposicao br
   where br.unidade_id = tests.unidade('ESCOLA_A')
     and br.status = 'PREVISTA';

select is(
  (select count(*)::bigint from t_reposicao), 1::bigint,
  'fixture: uma unica reposicao PREVISTA — as outras tres estao quitadas ou desmarcadas');

-- ===========================================================================
-- 2. v_bloco_alunos — a metade permanente da lotação
-- ===========================================================================
select is(
  (select count(*)::bigint from public.v_bloco_alunos t
     join t_bloco b on b.id = t.bloco_id where b.apelido = 'cheio'),
  10::bigint,
  'v_bloco_alunos: dez alocacoes ativas no bloco cheio');

select is(
  (select count(*)::bigint from public.v_bloco_alunos t
     join t_bloco b on b.id = t.bloco_id where b.apelido = 'vazio'),
  0::bigint,
  'e nenhuma no bloco vazio — a reposicao dele NAO e alocacao');

-- A view é o par (bloco, aluno) resolvido: sem isto a aba Turmas da ficha e a
-- coluna Turmas da lista teriam de fazer o join no Dart.
select is(
  (select t.tipo || '|' || (t.tipo_desde = public.fn_hoje() - 30)::text
     from public.v_bloco_alunos t
     join t_bloco b on b.id = t.bloco_id
    where b.apelido = 'cheio' and t.aluno_nome = 'Karina Bastos'),
  'NOVO|true',
  'traz o tipo e o tipo_desde da alocacao — o badge de contorno e o "desde" da ficha');

select is(
  (select t.data_inicio_prevista
     from public.v_bloco_alunos t
     join t_bloco b on b.id = t.bloco_id
    where b.apelido = 'cheio' and t.aluno_nome = 'Karina Bastos'),
  public.fn_hoje() + 7,
  'e a data_inicio_prevista do NOVO, que e a vaga ja reservada (card 5.2)');

select is(
  (select count(*)::bigint from public.v_bloco_alunos t where not t.bloco_ativo),
  0::bigint,
  'fixture nao tem bloco desativado: bloco_ativo verdadeiro em todas as linhas');

-- Alocação encerrada é `ativo = false` (card 2.4 §4) e sai da view: quem esteve
-- na turma continua na tabela, mas não está na turma.
select is(
  (select count(*)::bigint
     from public.v_bloco_alunos t
     join t_bloco b on b.id = t.bloco_id
    where b.apelido = 'quase' and t.aluno_nome = 'Aluno de Lotação 05'),
  1::bigint,
  'contraprova: o aluno esta na view antes de sair');

select tests.como_rotina(tests.unidade('ESCOLA_A'));
select public.fn_bloco_remover(
  (select id from t_bloco where apelido = 'quase'),
  (select id from public.aluno
    where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Aluno de Lotação 05'),
  'teste 043');

select is(
  (select count(*)::bigint
     from public.v_bloco_alunos t
     join t_bloco b on b.id = t.bloco_id
    where b.apelido = 'quase' and t.aluno_nome = 'Aluno de Lotação 05'),
  0::bigint,
  'e sai dela depois de fn_bloco_remover — alocacao encerrada nao e turma');

-- ===========================================================================
-- 3. fn_bloco_alunos — a lotação DAQUELA data, e ela soma o que a grade mostra
-- ===========================================================================
-- O contexto de rotina continua ligado: `fn_ocupacao_bloco` é `security definer`
-- e filtra a unidade NO CORPO (card 5.2), então sem contexto ela devolveria nulo
-- e as asserções desta seção comparariam nada com nada.
select is(
  (select count(*)::bigint
     from public.fn_bloco_alunos((select id from t_bloco where apelido = 'cheio'))),
  10::bigint,
  'fn_bloco_alunos: as dez alocacoes do bloco cheio');

select is(
  (select count(*)::integer
     from public.fn_bloco_alunos((select id from t_bloco where apelido = 'cheio'))),
  public.fn_ocupacao_bloco((select id from t_bloco where apelido = 'cheio')),
  'e a contagem E fn_ocupacao_bloco: a lista nao pode discordar do cabecalho da celula');

select is(
  (select count(*)::integer
     from public.fn_bloco_alunos((select id from t_bloco where apelido = 'quase'))),
  public.fn_ocupacao_bloco((select id from t_bloco where apelido = 'quase')),
  'idem no bloco de 8 (um saiu na secao 2): a igualdade nao depende de numero redondo');

-- A reposição PREVISTA está em `fn_hoje() + 3`, no bloco VAZIO. É o caso que
-- prova as duas metades do REP híbrido de uma vez.
select is(
  (select count(*)::integer
     from public.fn_bloco_alunos((select id from t_bloco where apelido = 'vazio'),
                                 (select data from t_reposicao))),
  public.fn_ocupacao_bloco((select id from t_bloco where apelido = 'vazio'),
                           (select data from t_reposicao)),
  'no bloco vazio, na data da reposicao, lista e ocupacao continuam iguais — e valem 1');

select is(
  (select count(*)::bigint
     from public.fn_bloco_alunos((select id from t_bloco where apelido = 'vazio'),
                                 (select data from t_reposicao))),
  1::bigint,
  'contraprova do numero: a igualdade acima nao e zero com zero');

select is(
  (select count(*)::bigint
     from public.fn_bloco_alunos((select id from t_bloco where apelido = 'vazio'),
                                 (select data + 7 from t_reposicao))),
  0::bigint,
  'e na semana seguinte o bloco vazio esta vazio: a reposicao vale so no dia');

-- Apontamento #3 do §17 do card 2.6, que este card fecha: sem a origem, o rótulo
-- "reposição de Qua 27/08" do wireframe §7.2 não teria de onde sair.
select is(
  (select r.origem || '|' || r.tipo || '|' || r.aluno_nome || '|' ||
          r.bloco_origem_dia::text || '|' || to_char(r.bloco_origem_hora, 'HH24:MI') ||
          '|' || (r.data_origem = public.fn_hoje() - 2)::text
     from public.fn_bloco_alunos((select id from t_bloco where apelido = 'vazio'),
                                 (select data from t_reposicao)) r),
  'REPOSICAO|REP|Lucas Ferreira|3|08:00|true',
  'a linha da reposicao traz o BLOCO DE ORIGEM da falta (dia 3 as 08:00) e a data dela');

select is(
  (select count(*)::bigint
     from public.fn_bloco_alunos((select id from t_bloco where apelido = 'cheio')) r
    where r.origem <> 'ALOCACAO'),
  0::bigint,
  'e o bloco cheio nao tem linha de reposicao: origem separa as duas metades');

-- Reposição que não é PREVISTA não ocupa vaga (card 2.2 §4.2) e por isso não
-- entra na lista: o passado não bloqueia o presente, e mostrá-lo aqui inflaria a
-- lotação exatamente como inflaria a ocupação.
select is(
  (select count(*)::bigint
     from public.bloco_aluno_reposicao br
     join t_bloco b on b.id = br.bloco_id
    where b.apelido = 'vazio' and br.status <> 'PREVISTA'),
  3::bigint,
  'fixture: tres reposicoes nao PREVISTAS no bloco vazio (REALIZADA, FALTOU, CANCELADA)');

select is(
  (select count(*)::bigint
     from public.fn_bloco_alunos((select id from t_bloco where apelido = 'vazio'),
                                 public.fn_hoje() - 9)),
  0::bigint,
  'e nenhuma delas aparece na lista da sua propria data — so PREVISTA ocupa vaga');

-- ===========================================================================
-- 4. Desativar o bloco: o ajuste que o card 5.6 deixou para cá
-- ===========================================================================
-- Contraprova primeiro: enquanto o bloco está ativo, ninguém do bloco quase
-- cheio tem ALUNO_SEM_TURMA. Sem esta linha, a asserção seguinte passaria mesmo
-- que a rotina abrisse pendência para todo mundo desde sempre.
select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint
     from public.pendencia p
     join public.v_bloco_alunos t on t.aluno_id = p.aluno_id
     join t_bloco b on b.id = t.bloco_id
    where b.apelido = 'quase' and p.tipo = 'ALUNO_SEM_TURMA'
      and p.resolvida_em is null),
  0::bigint,
  'com o bloco ativo, nenhum aluno dele tem ALUNO_SEM_TURMA');

create temporary view t_alunos_quase as
  select t.aluno_id
    from public.v_bloco_alunos t
    join t_bloco b on b.id = t.bloco_id
   where b.apelido = 'quase';

select is(
  (select count(*)::bigint from t_alunos_quase), 8::bigint,
  'oito alunos no bloco quase cheio depois da remocao da secao 2');

update public.bloco_horario set ativo = false
 where id = (select id from t_bloco where apelido = 'quase');

select is(
  (select count(*)::bigint
     from public.v_bloco_alunos t
     join t_bloco b on b.id = t.bloco_id
    where b.apelido = 'quase' and t.bloco_ativo),
  0::bigint,
  'desativado o bloco, bloco_ativo vira falso — e as alocacoes CONTINUAM na view');

select is(
  (select count(*)::bigint
     from public.v_bloco_alunos t
     join t_bloco b on b.id = t.bloco_id
    where b.apelido = 'quase'),
  8::bigint,
  'porque a ficha do aluno e o unico lugar de onde alguem desfaz a alocacao orfa');

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint
     from public.pendencia p
    where p.tipo = 'ALUNO_SEM_TURMA'
      and p.resolvida_em is null
      and p.aluno_id in (select aluno_id from t_alunos_quase)),
  8::bigint,
  'AJUSTE DO CARD 5.6 FECHADO: desativar o bloco abre ALUNO_SEM_TURMA para os oito');

-- E a volta: reativar fecha as oito. Pendência que abre e não fecha é a lista
-- que ninguém lê (card 5.5).
update public.bloco_horario set ativo = true
 where id = (select id from t_bloco where apelido = 'quase');

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint
     from public.pendencia p
    where p.tipo = 'ALUNO_SEM_TURMA'
      and p.resolvida_em is null
      and p.aluno_id in (select aluno_id from t_alunos_quase)),
  0::bigint,
  'reativado, a rotina fecha as oito — o caminho de volta existe');

-- ⚠️ A asserção que este card pagou para aprender, e que fica aqui ao lado da
--    substituição que a provocou: reescrever `rt_pendencias_diaria` inteira é
--    fácil de fazer a partir da definição ERRADA. A primeira versão deste card
--    partiu do corpo do 5.5 e reintroduziu `BLOCO_ACIMA_CAPACIDADE`, desfazendo
--    a decisão do 5.4 sem que nada no diff parecesse errado — o texto de volta
--    era código legítimo, só de outra época. Quem pegou foi a asserção gêmea no
--    teste 090; esta a repete no arquivo do card que mexeu na função, porque o
--    PRÓXIMO card a substituí-la vai olhar para cá.
select is(
  (select count(*)::bigint
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rt_pendencias_diaria'
      and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'BLOCO_ACIMA_CAPACIDADE'),
  0::bigint,
  'rt_pendencias_diaria continua SEM BLOCO_ACIMA_CAPACIDADE: substituir a funcao nao pode desfazer o card 5.4');

select is(
  (select count(*)::bigint
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rt_pendencias_diaria'
      and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'v_bloco_alunos'),
  1::bigint,
  'e ela le v_bloco_alunos: o que conta como turma tem UMA definicao, partilhada com o ⚠ da lista');

-- ===========================================================================
-- 5. Permissão: erro alto no lugar de lista vazia
-- ===========================================================================
select tests.encerrar_sessao();

-- Um perfil com `turmas.ler` e SEM `alunos.ler` existe só para provar por que a
-- função exige as duas: com a matriz inicial este caso não acontece (as duas são
-- dos quatro perfis, card 2.4), e é a tela do card 4.7 que pode criá-lo amanhã.
insert into public.perfil (unidade_id, codigo, nome)
values (tests.unidade('ESCOLA_A'), 'SEM_ALUNOS', 'Turmas sem alunos (teste 043)');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select tests.unidade('ESCOLA_A'), pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A')
   and pm.unidade_id = tests.unidade('ESCOLA_A')
   and pe.codigo = 'SEM_ALUNOS'
   and pm.codigo in ('turmas.ler', 'materiais.ler', 'salas.ler', 'professores.ler');

select tests.criar_usuario('semalunos@escola-a.test', 'SEM_ALUNOS');

-- Sem `limit`: a chave natural (sala + dia) é única por unidade e a RLS já fixa
-- a unidade — `limit` sem `order by` é sorteio (docs/estrategia-testes.md §11).
select is(
  tests.codigo_do_erro(
    'select 1 from public.fn_bloco_alunos((select b.id from public.bloco_horario b '
    'join public.sala s on s.id = b.sala_id where s.nome = ''Laboratório 1'' '
    'and b.dia_semana = 3))',
    tests.uid('semalunos@escola-a.test')),
  'SEM_PERMISSAO',
  'sem alunos.ler a funcao ERRA — a alternativa era devolver a turma de dez como vazia');

select is(
  tests.codigo_do_erro(
    'select 1 from public.fn_bloco_alunos((select b.id from public.bloco_horario b '
    'join public.sala s on s.id = b.sala_id where s.nome = ''Laboratório 1'' '
    'and b.dia_semana = 3))',
    tests.uid('semperfil@escola-a.test')),
  'SEM_PERMISSAO',
  'e sem turmas.ler tambem: as duas exigencias sao explicitas de proposito');

-- ===========================================================================
-- 6. Paridade de linhas por perfil (§6.3)
-- ===========================================================================
select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_alunos'),
  '>', 0::bigint,
  'a direcao ve alocacoes: paridade de zero com zero passaria sempre');

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
                   'select 1 from public.v_bloco_alunos'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_alunos'),
  'secretaria ve as MESMAS alocacoes que a direcao');

select is(
  tests.conta_como(tests.uid('pedagogico@escola-a.test'),
                   'select 1 from public.v_bloco_alunos'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_alunos'),
  'pedagogico ve as MESMAS alocacoes que a direcao');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_bloco_alunos'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_bloco_alunos'),
  'monitor ve as MESMAS alocacoes — ele registra entrega e precisa saber quem esta na turma');

select is(
  tests.conta_como(tests.uid('semalunos@escola-a.test'),
                   'select 1 from public.v_bloco_alunos'),
  0::bigint,
  'sem alunos.ler a VIEW vem vazia — o join interno em aluno, e o motivo de a funcao exigir a permissao');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_bloco_alunos'),
  0::bigint,
  'sem turmas.ler idem: vazia por RLS, que e o que a view NAO pode esconder');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_bloco_alunos where unidade_id = ' ||
                   quote_literal(tests.unidade('ESCOLA_A')::text) || '::uuid'),
  0::bigint,
  'a direcao da Escola B nao ve alocacao da Escola A: security_invoker + RLS por unidade');

select * from finish();
rollback;
