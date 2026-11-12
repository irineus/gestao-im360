-- =============================================================================
-- Turma Modular em rodízio — card 9.2,88 (docs/turma-rodizio.md)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- O cenário é a turma `Eletricista 2026.1` da fixture, curso de TRÊS módulos:
--
--   M1  concluído   hoje−60 … hoje−25   (36 dias)
--   M2  corrente    hoje−25 … hoje+35   (61 dias)
--   M3  sem data
--
-- com DOIS alunos: Eduarda Lima, que já está na turma (linha anterior ao
-- rodízio, sem módulo de entrada), e o `Aluno Modular 01`, admitido aqui para
-- começar no PRÓXIMO módulo. A história que o arquivo percorre é a que o dono do
-- produto contou: a turma dá a volta, uma aluna para e volta, um aluno conclui.
--
-- O que este arquivo prova e nenhum outro enxerga:
--   • a agenda dá a volta e data o que não tem data (N + 1 posições);
--   • o avanço grava o módulo de quem está ATIVO, e NÃO de quem entrou para
--     começar no próximo nem de quem está em STANDBY;
--   • o módulo perdido em STANDBY cai no FIM da sequência — sem código que
--     reordene nada;
--   • depois do último módulo abre-se o ciclo seguinte, e não "a turma terminou";
--   • quem completa o curso sai da turma, libera a vaga e NÃO muda de status;
--   • a exceção à mão registra, remove com motivo e deixa rastro;
--   • quem enxerga e quem escreve `aluno_modulo`.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(43);

create temporary table t_ids as
select (select id from public.turma_modular
         where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eletricista 2026.1') as turma,
       (select id from public.turma_modular
         where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eletricista Individual 2026') as individual,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Eduarda Lima') as eduarda,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.codigo_sgf = '9101') as novo;
grant select on t_ids to authenticated;

-- Os três módulos do curso, por ordem.
create temporary table t_mod as
select m.ordem, m.id
  from public.modulo m
  join public.turma_modular t on t.curso_id = m.curso_id
 where t.id = (select turma from t_ids);
grant select on t_mod to authenticated;

-- "M2,M3" — os módulos que o aluno já fez, por ordem do catálogo.
-- "+35" / "-25": dias a partir de hoje, com sinal e sem preenchimento.
create function pg_temp.dias(p_data date) returns text language sql stable as $$
  select case when p_data is null then 'nulo'
              when p_data >= public.fn_hoje() then '+' || (p_data - public.fn_hoje())
              else (p_data - public.fn_hoje())::text end
$$;

create function pg_temp.feitos(p_aluno uuid) returns text language sql stable as $$
  select coalesce(string_agg('M' || m.ordem, ',' order by m.ordem), 'nenhum')
    from public.aluno_modulo am
    join public.modulo m on m.id = am.modulo_id
   where am.aluno_id = p_aluno
$$;

-- "2 de 3 | próximo M1 | fim +N | aguardando f" — o progresso do aluno, com a
-- previsão em dias a partir de hoje.
create function pg_temp.progresso(p_aluno uuid) returns text language sql stable as $$
  select coalesce(
    (select format('%s de %s | próximo M%s | fim %s | aguardando %s',
                   p.modulos_feitos, p.modulos_total,
                   (select m.ordem from public.modulo m where m.id = p.proximo_modulo_id),
                   pg_temp.dias(p.prev_conclusao),
                   p.aguardando_entrada::text)
       from public.v_aluno_modular_progresso p
      where p.aluno_id = p_aluno and p.turma_id = (select turma from t_ids)),
    'fora da turma')
$$;

-- "M2c1(-25..+35) M3c1(+36..+84) …" — a agenda, em dias a partir de hoje.
create function pg_temp.agenda() returns text language sql stable as $$
  select string_agg(format('M%sc%s(%s..%s)', a.modulo_ordem, a.ciclo,
                           pg_temp.dias(a.data_inicio), pg_temp.dias(a.data_fim)),
                    ' ' order by a.posicao)
    from public.fn_turma_modular_agenda((select turma from t_ids)) a
$$;

create function pg_temp.avancar(p_dias integer) returns void language plpgsql as $$
begin
  perform tests.autenticar(tests.uid('direcao@escola-a.test'));
  perform public.fn_turma_modular_avancar((select turma from t_ids),
                                          public.fn_hoje() + p_dias);
  reset role;
  perform tests.encerrar_sessao();
end $$;

-- ===========================================================================
-- 1. A agenda dá a volta e data o que não tem data
-- ===========================================================================
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

-- Passo = média de 36 e 61 dias = 48,5 → 49. M3 não tem data: começa no dia
-- seguinte ao fim de M2 e dura o passo. Depois do último vem o M1 de novo, no
-- ciclo 2; e a posição N + 1 repete o corrente, na outra volta.
select is(
  pg_temp.agenda(),
  'M2c1(-25..+35) M3c1(+36..+84) M1c2(+85..+133) M2c2(+134..+182)',
  'a agenda: o corrente, o seguinte extrapolado pelo passo, a volta ao primeiro no ciclo 2 e o corrente outra vez');

reset role;
select tests.encerrar_sessao();

-- Sem `turmas.ler` a agenda vem VAZIA — é o que a RLS do cronograma já diria.
select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   format('select 1 from public.fn_turma_modular_agenda(%L)',
                          (select turma from t_ids))),
  0::bigint,
  'sem turmas.ler a agenda vem vazia');

-- E turma de outra unidade também: a função é definer, e o filtro é no corpo.
select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   format('select 1 from public.fn_turma_modular_agenda(%L)',
                          (select turma from t_ids))),
  0::bigint,
  'a direcao da Escola B nao le a agenda de uma turma da Escola A');

-- ===========================================================================
-- 2. Admissão com módulo de entrada
-- ===========================================================================
select is(
  tests.codigo_do_erro(
    format('select public.fn_turma_modular_admitir(%L, %L, %L)',
           (select turma from t_ids), (select novo from t_ids),
           (select id from t_mod where ordem = 1)),
    tests.uid('secretaria@escola-a.test')),
  'MODULO_ENTRADA_INVALIDO',
  'entrar dois modulos a frente e recusado: so o atual ou o proximo');

reset role;
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  format('select public.fn_turma_modular_admitir(%L, %L, %L)',
         (select turma from t_ids), (select novo from t_ids),
         (select id from t_mod where ordem = 3)),
  'a secretaria admite o aluno para comecar no PROXIMO modulo (M3)');

reset role;
select tests.encerrar_sessao();

select is(
  (select m.ordem from public.turma_modular_aluno ta
     join public.modulo m on m.id = ta.modulo_entrada_id
    where ta.turma_id = (select turma from t_ids)
      and ta.aluno_id = (select novo from t_ids)),
  3, 'o modulo de entrada fica gravado na alocacao');

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

-- A aluna da linha antiga (sem módulo de entrada) precisa dos três: o último é
-- o M1, que só volta no ciclo 2.
select is(pg_temp.progresso((select eduarda from t_ids)),
  '0 de 3 | próximo M2 | fim +133 | aguardando false',
  'a aluna que ja estava na turma: faltam os tres, e ela conclui quando a turma terminar o M1 do ciclo 2');

-- O que entrou para começar no próximo: o M2 de HOJE não é dele. A sequência
-- dele é M3 → M1 → M2, e o M2 só volta na outra volta — a posição N + 1.
select is(pg_temp.progresso((select novo from t_ids)),
  '0 de 3 | próximo M3 | fim +182 | aguardando true',
  'quem entrou para comecar no proximo: o corrente de hoje e o ULTIMO da sequencia dele');

select is(
  (select string_agg(format('M%s:%s', s.modulo_ordem,
                            case when s.de_entrada then 'entrada' else 'a fazer' end),
                     ' ' order by s.sequencia)
     from public.v_aluno_modular_modulo s
    where s.aluno_id = (select novo from t_ids)),
  'M3:entrada M1:a fazer M2:a fazer',
  'a sequencia do aluno, na ordem em que a turma lhe dara os modulos');

reset role;
select tests.encerrar_sessao();

-- ===========================================================================
-- 3. O avanço grava o módulo de quem está ativo — e só de quem começou
-- ===========================================================================
select pg_temp.avancar(0);

select is(pg_temp.feitos((select eduarda from t_ids)), 'M2',
  'a aluna ativa na turma recebe o modulo que fechou');

select is(pg_temp.feitos((select novo from t_ids)), 'nenhum',
  'quem entrou para comecar no PROXIMO nao recebe o modulo que fechou');

select is(
  (select format('%s / %s / %s', am.origem, am.data_conclusao - public.fn_hoje(),
                 (am.turma_id = (select turma from t_ids))::text)
     from public.aluno_modulo am
    where am.aluno_id = (select eduarda from t_ids)),
  'TURMA / 0 / true',
  'o registro traz a origem, a data REAL e a turma');

-- Avança o M3, o último do ciclo 1: os dois recebem, e abre-se o ciclo 2.
select pg_temp.avancar(10);

select is(
  format('%s | %s', pg_temp.feitos((select eduarda from t_ids)),
                    pg_temp.feitos((select novo from t_ids))),
  'M2,M3 | M3',
  'no modulo de entrada dele, o aluno novo passa a receber');

select is(
  (select format('ciclo %s, %s linha(s), corrente M%s', l.modulo_corrente_ciclo,
                 (select count(*) from public.turma_modular_modulo tm
                   where tm.turma_id = l.turma_id and tm.ciclo = 2),
                 l.modulo_corrente_ordem)
     from public.v_turma_modular_lotacao l
    where l.turma_id = (select turma from t_ids)),
  'ciclo 2, 3 linha(s), corrente M1',
  'depois do ultimo modulo abre-se o CICLO 2, com uma linha por modulo, e o corrente e o primeiro');

select is(
  (select format('%s .. %s', tm.data_inicio - public.fn_hoje(),
                 (tm.prev_conclusao is not null)::text)
     from public.turma_modular_modulo tm
    where tm.turma_id = (select turma from t_ids) and tm.ciclo = 2
      and tm.modulo_id = (select id from t_mod where ordem = 1)),
  '11 .. true',
  'o primeiro modulo do ciclo novo comeca no dia seguinte e ja nasce com previsao');

-- As três definições do corrente continuam a mesma (o teste 072 §3 as compara
-- no ciclo 1; aqui, no ciclo 2, que é onde a ordem por ciclo faz diferença).
select is(
  (select format('%s / %s / %s',
     (select m.ordem from public.modulo m
       where m.id = public.fn_turma_modular_modulo_corrente((select turma from t_ids))),
     (select l.modulo_corrente_ordem from public.v_turma_modular_lotacao l
       where l.turma_id = (select turma from t_ids)),
     (select string_agg(c.modulo_ordem || 'c' || c.ciclo, ',')
        from public.v_turma_modular_cronograma c
       where c.turma_id = (select turma from t_ids) and c.corrente))),
  '1 / 1 / 1c2',
  'funcao, lotacao e cronograma apontam o MESMO corrente no ciclo 2 — e so uma linha e corrente');

-- ===========================================================================
-- 4. STANDBY: o módulo perdido cai no fim da sequência
-- ===========================================================================
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));
select public.fn_aluno_alterar_status((select eduarda from t_ids), 'STANDBY', 'parou de vir');
reset role;
select tests.encerrar_sessao();

-- A turma dá o M1 do ciclo 2 sem ela.
select pg_temp.avancar(20);

select is(
  format('%s | %s', pg_temp.feitos((select eduarda from t_ids)),
                    pg_temp.feitos((select novo from t_ids))),
  'M2,M3 | M1,M3',
  'quem esta em STANDBY nao recebe o modulo; o aluno ativo recebe');

-- Ela volta e é readmitida: continua de onde parou.
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));
select public.fn_aluno_alterar_status((select eduarda from t_ids), 'ATIVO', 'voltou');
reset role;
select tests.autenticar(tests.uid('secretaria@escola-a.test'));
select public.fn_turma_modular_admitir((select turma from t_ids), (select eduarda from t_ids));

select is(pg_temp.feitos((select eduarda from t_ids)), 'M2,M3',
  'a readmissao NAO apaga o que ela ja fez');

-- Falta-lhe o M1. A turma está no M2 do ciclo 2; o M1 só volta no ciclo 3 — a
-- terceira posição da agenda. É o "módulo perdido no fim da sequência", e
-- nenhuma linha de código o pôs lá.
select matches(pg_temp.progresso((select eduarda from t_ids)),
  '^2 de 3 \| próximo M1 \| fim \+\d+ \| aguardando false$',
  'falta-lhe so o modulo perdido, e ele e o proximo DELA');

select is(
  (select format('M%sc%s', a.modulo_ordem, a.ciclo)
     from public.fn_turma_modular_agenda((select turma from t_ids)) a
    where a.modulo_id = (select id from t_mod where ordem = 1)),
  'M1c3',
  'e a turma so volta a ele no ciclo 3 — o fim da sequencia dela');

select is(
  (select (p.prev_conclusao = a.data_fim)::text
     from public.v_aluno_modular_progresso p,
          public.fn_turma_modular_agenda((select turma from t_ids)) a
    where p.aluno_id = (select eduarda from t_ids)
      and a.modulo_id = (select id from t_mod where ordem = 1)),
  'true',
  'a previsao de conclusao dela e o fim do M1 do ciclo 3');

reset role;
select tests.encerrar_sessao();

-- ===========================================================================
-- 5. A previsão acompanha a data da turma
-- ===========================================================================
-- No contexto de rotina da unidade: a agenda é definer e filtra a unidade no
-- corpo, então como dono, sem contexto nenhum, ela vem vazia.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

create temporary table t_antes as
select p.prev_conclusao from public.v_aluno_modular_progresso p
 where p.aluno_id = (select eduarda from t_ids);

-- A turma adia em 30 dias o fim do módulo corrente (M2 do ciclo 2).
update public.turma_modular_modulo tm
   set prev_conclusao = tm.prev_conclusao + 30
 where tm.id = (select l.modulo_corrente_cronograma_id
                  from public.v_turma_modular_lotacao l
                 where l.turma_id = (select turma from t_ids));

-- "Pelo menos 30", e não "exatamente 30": o módulo que ficou mais longo também
-- puxa o PASSO médio da turma para cima, e os módulos seguintes — que ainda não
-- têm data e são extrapolados por ele — esticam junto. Medido: 42 dias.
select cmp_ok(
  (select p.prev_conclusao - (select prev_conclusao from t_antes)
     from public.v_aluno_modular_progresso p
    where p.aluno_id = (select eduarda from t_ids)),
  '>=', 30,
  'adiar o fim de um modulo da turma adia a previsao do aluno, sem tocar em linha dele');

select tests.encerrar_sessao();

-- ===========================================================================
-- 6. Conclusão: libera a vaga e não muda o status
-- ===========================================================================
-- O aluno novo tem M1 e M3. A turma fecha o M2 do ciclo 2: ele completa.
select pg_temp.avancar(60);

select is(pg_temp.feitos((select novo from t_ids)), 'M1,M2,M3',
  'o aluno fez os tres modulos, comecando pelo terceiro');

select is(
  (select format('%s / %s', ta.ativo, ta.motivo_saida)
     from public.turma_modular_aluno ta
    where ta.turma_id = (select turma from t_ids)
      and ta.aluno_id = (select novo from t_ids)),
  'f / Concluiu o curso',
  'quem completa o curso SAI da turma, com o motivo');

select is(
  (select a.status from public.aluno a where a.id = (select novo from t_ids)),
  'ATIVO',
  'e o status dele NAO muda: FORMADO continua sendo decisao de gente');

select is(
  (select l.alocados from public.v_turma_modular_lotacao l
    where l.turma_id = (select turma from t_ids)),
  1,
  'a vaga foi liberada: so a aluna que ainda tem modulo a fazer ocupa a turma');

-- A aluna recebeu o M2 de novo? Não: ela já o tinha, e ninguém faz o mesmo
-- módulo duas vezes para efeito de conclusão.
select is(
  (select count(*)::integer from public.aluno_modulo am
    where am.aluno_id = (select eduarda from t_ids)),
  2,
  'o modulo que a aluna ja tinha nao e gravado de novo');

-- ===========================================================================
-- 7. A exceção à mão
-- ===========================================================================
select is(
  tests.codigo_do_erro(
    format('select public.fn_aluno_modulo_registrar(%L, %L)',
           (select eduarda from t_ids), (select id from t_mod where ordem = 2)),
    tests.uid('pedagogico@escola-a.test')),
  'MODULO_JA_REGISTRADO',
  'registrar modulo que o aluno ja tem e recusado');

reset role;

select is(
  tests.codigo_do_erro(
    format('select public.fn_aluno_modulo_registrar(%L, %L)',
           (select eduarda from t_ids), (select id from t_mod where ordem = 1)),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor, sem alunos.editar_trilha, nao lanca a excecao');

reset role;

select is(
  tests.codigo_do_erro(
    format('select public.fn_aluno_modulo_remover(%L, %L, %L)',
           (select eduarda from t_ids), (select id from t_mod where ordem = 3), '  '),
    tests.uid('pedagogico@escola-a.test')),
  'MOTIVO_OBRIGATORIO',
  'remover exige motivo: e dizer que o aluno precisa refazer');

reset role;
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));

select lives_ok(
  format('select public.fn_aluno_modulo_remover(%L, %L, %L)',
         (select eduarda from t_ids), (select id from t_mod where ordem = 3),
         'faltou a metade do módulo'),
  'o pedagogico remove o M3 da aluna, com motivo');

reset role;
select tests.encerrar_sessao();

select is(pg_temp.feitos((select eduarda from t_ids)), 'M2',
  'o modulo removido volta a faltar');

select is(
  (select format('%s / %s / %s', h.acao, h.motivo,
                 (h.criado_por = tests.uid('pedagogico@escola-a.test'))::text)
     from public.aluno_modulo_hist h
    where h.aluno_id = (select eduarda from t_ids) and h.acao = 'REMOVIDO'),
  'REMOVIDO / faltou a metade do módulo / true',
  'o historico guarda a remocao, o motivo e quem removeu');

select is(
  tests.codigo_do_erro(
    format('select public.fn_aluno_modulo_remover(%L, %L, %L)',
           (select eduarda from t_ids), (select id from t_mod where ordem = 3), 'de novo'),
    tests.uid('pedagogico@escola-a.test')),
  'MODULO_NAO_REGISTRADO',
  'remover o que nao esta registrado e erro, com codigo proprio');

reset role;

-- Registrar à mão os dois que faltam: no último, ela conclui e sai da turma.
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));
select public.fn_aluno_modulo_registrar((select eduarda from t_ids),
         (select id from t_mod where ordem = 3), public.fn_hoje(), 'reposição');
select public.fn_aluno_modulo_registrar((select eduarda from t_ids),
         (select id from t_mod where ordem = 1), public.fn_hoje(), 'reposição');
reset role;
select tests.encerrar_sessao();

select is(
  (select format('%s / %s / %s', ta.ativo, ta.motivo_saida,
                 (select string_agg(distinct am.origem, ',' order by am.origem)
                    from public.aluno_modulo am where am.aluno_id = ta.aluno_id))
     from public.turma_modular_aluno ta
    where ta.turma_id = (select turma from t_ids)
      and ta.aluno_id = (select eduarda from t_ids)),
  'f / Concluiu o curso / MANUAL,TURMA',
  'registrar a mao o ultimo modulo conclui o curso, como o avanco faria');

-- ===========================================================================
-- 8. Quem lê e quem escreve aluno_modulo
-- ===========================================================================
select is(
  (select format('direcao=%s monitor=%s semperfil=%s direcaoB=%s',
     tests.conta_como(tests.uid('direcao@escola-a.test'),   'select 1 from public.aluno_modulo'),
     tests.conta_como(tests.uid('monitor@escola-a.test'),   'select 1 from public.aluno_modulo'),
     tests.conta_como(tests.uid('semperfil@escola-a.test'), 'select 1 from public.aluno_modulo'),
     tests.conta_como(tests.uid('direcao@escola-b.test'),   'select 1 from public.aluno_modulo'))),
  'direcao=6 monitor=6 semperfil=0 direcaoB=0',
  'quem le alunos ve os seis registros; sem perfil e a outra unidade, nenhum');

-- O monitor lê (tem alunos.ler) e NÃO escreve: nem direto na tabela.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select throws_ok(
  format('insert into public.aluno_modulo (unidade_id, aluno_id, modulo_id, data_conclusao, origem)
          values (public.fn_unidade_atual(), %L, %L, public.fn_hoje(), ''MANUAL'')',
         (select eduarda from t_ids), (select id from t_mod where ordem = 2)),
  '42501', null,
  'o insert direto do monitor e recusado pela RLS');

with d as (delete from public.aluno_modulo returning 1)
select is((select count(*)::integer from d), 0,
  'e o delete direto do monitor afeta ZERO linhas');

reset role;
select tests.encerrar_sessao();

-- O histórico não aceita escrita de ninguém — só o trigger grava.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select throws_ok(
  format('insert into public.aluno_modulo_hist (unidade_id, aluno_id, modulo_id, acao)
          values (public.fn_unidade_atual(), %L, %L, ''REGISTRADO'')',
         (select eduarda from t_ids), (select id from t_mod where ordem = 2)),
  '42501', null,
  'nem a direcao escreve no historico: quem grava e o trigger');

reset role;
select tests.encerrar_sessao();

select is(
  (select format('%s registrado(s), %s removido(s)',
                 count(*) filter (where h.acao = 'REGISTRADO'),
                 count(*) filter (where h.acao = 'REMOVIDO'))
     from public.aluno_modulo_hist h),
  '7 registrado(s), 1 removido(s)',
  'o historico tem uma linha por modulo gravado — pelo avanco ou a mao — e a remocao');

-- ===========================================================================
-- 9. Turma anterior ao rodízio: abrir o ciclo
-- ===========================================================================
-- A Individual tem só o M1, em curso: o ciclo abre sozinho, e abrir à mão é erro.
select is(
  tests.codigo_do_erro(
    format('select public.fn_turma_modular_abrir_ciclo(%L)', (select individual from t_ids)),
    tests.uid('direcao@escola-a.test')),
  'TURMA_COM_MODULO_CORRENTE',
  'turma com modulo em curso nao abre ciclo a mao');

reset role;

-- O estado de antes do rodízio, montado como dono: tudo concluído, sem ciclo 2.
update public.turma_modular_modulo set concluido = true
 where turma_id = (select individual from t_ids);

select tests.autenticar(tests.uid('direcao@escola-a.test'));

create temporary table t_ciclo as
select public.fn_turma_modular_abrir_ciclo((select individual from t_ids)) as modulo;

reset role;
select tests.encerrar_sessao();

select is(
  (select format('M%s | ciclo %s | %s linha(s) | inicio %s',
                 (select ordem from t_mod where id = (select modulo from t_ciclo)),
                 max(tm.ciclo),
                 count(*) filter (where tm.ciclo = 2),
                 min(tm.data_inicio) filter (where tm.ciclo = 2) - public.fn_hoje())
     from public.turma_modular_modulo tm
    where tm.turma_id = (select individual from t_ids)),
  'M1 | ciclo 2 | 3 linha(s) | inicio 0',
  'abrir o ciclo cria uma linha por modulo do curso e data o primeiro');

select is(
  tests.codigo_do_erro(
    format('select public.fn_turma_modular_abrir_ciclo(%L)', (select individual from t_ids)),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'abrir ciclo exige turmas.editar');

select * from finish();
rollback;
