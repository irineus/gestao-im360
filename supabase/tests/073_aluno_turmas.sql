-- =============================================================================
-- v_aluno_turmas — as duas formas de turma do lado do aluno (card 9.2,6)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- O defeito que o card fecha, medido em 24/09/2026: a lista de Alunos marcava
-- Eduarda Lima (ATIVA na turma Modular "Eletricista 2026.1") como "sem turma",
-- porque a tela contava só bloco de horário, enquanto `rt_pendencias_diaria` —
-- desde o card 7.1 — conta as DUAS formas e, corretamente, não abria pendência
-- nenhuma para ela. Tela e banco dizendo o oposto sobre o mesmo aluno.
--
-- O que este arquivo prova:
--   • a PARIDADE que prende as duas pontas: "sem turma" pela view (ATIVO/
--     ACELERAR sem nenhuma linha `turma_ativa`) = alunos com ALUNO_SEM_TURMA
--     aberta depois da rotina — antes e depois de desativar a turma Modular e
--     de tirar a aluna dela. A rotina NÃO lê a view, de propósito: é isso que
--     deixa a contraprova (apagar a metade Modular da view) ficar vermelha;
--   • o conjunto comparado é NÃO VAZIO dos dois lados (a fixture tem aluno sem
--     turma de verdade), senão a paridade seria zero contra zero;
--   • RLS na pele de cada perfil — nunca em `tests.como_rotina`, que roda como
--     `postgres` e ignora RLS (card 8.3): direção vê tudo; sem `turmas.ler`,
--     nada; com `turmas.ler` e sem `alunos.ler`, nada DAS DUAS formas — a
--     simetria que impede o ⚠ falso de voltar pelo outro lado; e a outra
--     unidade não vê nada.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(20);

-- "sem turma" segundo a VIEW — o que a coluna Turmas da lista mostra.
create temporary view t_sem_turma_view as
  select a.id
    from public.aluno a
   where a.unidade_id = tests.unidade('ESCOLA_A')
     and a.status in ('ATIVO', 'ACELERAR')
     and not exists (select 1 from public.v_aluno_turmas v
                      where v.aluno_id = a.id and v.turma_ativa);

-- "sem turma" segundo o BANCO — a pendência que a rotina abre.
create temporary view t_sem_turma_pendencia as
  select p.aluno_id as id
    from public.pendencia p
   where p.unidade_id = tests.unidade('ESCOLA_A')
     and p.tipo = 'ALUNO_SEM_TURMA'
     and p.resolvida_em is null;

create temporary view t_eduarda as
  select id from public.aluno
   where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eduarda Lima';

-- ===========================================================================
-- 1. As premissas: o caso do defeito existe na fixture
-- ===========================================================================
select is(
  (select count(*)::bigint from public.v_bloco_alunos t
    where t.aluno_id = (select id from t_eduarda)),
  0::bigint,
  'fixture: Eduarda nao esta em bloco nenhum — so v_bloco_alunos a chamaria de sem turma');

select is(
  (select v.forma || '|' || v.turma_nome || '|' || v.turma_ativa::text
     from public.v_aluno_turmas v
    where v.aluno_id = (select id from t_eduarda)),
  'MODULAR|Eletricista 2026.1|true',
  'v_aluno_turmas: Eduarda aparece com a turma Modular, ativa — e so ela');

select is(
  (select count(*)::bigint from public.v_aluno_turmas v
    where v.forma = 'BLOCO' and v.unidade_id = tests.unidade('ESCOLA_A')),
  (select count(*)::bigint from public.v_bloco_alunos t
    where t.unidade_id = tests.unidade('ESCOLA_A')),
  'a metade BLOCO e v_bloco_alunos inteira, linha por linha');

select is(
  (select count(*)::bigint from public.v_aluno_turmas v
    where v.forma = 'MODULAR' and v.unidade_id = tests.unidade('ESCOLA_A')),
  (select count(*)::bigint from public.turma_modular_aluno ta
    where ta.unidade_id = tests.unidade('ESCOLA_A') and ta.ativo),
  'a metade MODULAR e toda alocacao Modular ativa, e so ela');

-- ===========================================================================
-- 2. A paridade com a rotina, na fixture como está
-- ===========================================================================
select tests.como_rotina(tests.unidade('ESCOLA_A'));
select public.rt_pendencias_diaria();
select tests.encerrar_sessao();

-- Zero contra zero passaria sempre (card 2.8 §6.3): a fixture tem de ter aluno
-- sem turma DE VERDADE para a comparação dizer alguma coisa.
select cmp_ok(
  (select count(*)::bigint from t_sem_turma_pendencia), '>', 0::bigint,
  'fixture: ha aluno com ALUNO_SEM_TURMA aberta — a paridade abaixo nao e vazio contra vazio');

select set_eq(
  'select id from t_sem_turma_view',
  'select id from t_sem_turma_pendencia',
  'PARIDADE: sem turma pela view = ALUNO_SEM_TURMA aberta pela rotina');

select is(
  (select count(*)::bigint from t_sem_turma_view where id = (select id from t_eduarda)),
  0::bigint,
  'e Eduarda NAO esta sem turma pela view — o defeito do card 9.2,6');

-- ===========================================================================
-- 3. Turma Modular desativada: o vínculo aparece e não conta
-- ===========================================================================
update public.turma_modular set ativo = false
 where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eletricista 2026.1';

select is(
  (select v.turma_ativa from public.v_aluno_turmas v
    where v.aluno_id = (select id from t_eduarda)),
  false,
  'turma Modular desativada: o vinculo de Eduarda continua na view, com turma_ativa falso');

select tests.como_rotina(tests.unidade('ESCOLA_A'));
select public.rt_pendencias_diaria();
select tests.encerrar_sessao();

select is(
  (select count(*)::bigint from t_sem_turma_pendencia where id = (select id from t_eduarda)),
  1::bigint,
  'e a rotina passa a abrir ALUNO_SEM_TURMA para ela');

select set_eq(
  'select id from t_sem_turma_view',
  'select id from t_sem_turma_pendencia',
  'PARIDADE mantida com a turma desativada — as duas pontas mudam juntas');

update public.turma_modular set ativo = true
 where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eletricista 2026.1';

-- ===========================================================================
-- 4. A aluna sai da turma: o vínculo some
-- ===========================================================================
update public.turma_modular_aluno set ativo = false
 where aluno_id = (select id from t_eduarda) and ativo;

select is(
  (select count(*)::bigint from public.v_aluno_turmas v
    where v.aluno_id = (select id from t_eduarda)),
  0::bigint,
  'alocacao Modular encerrada sai da view — quem saiu da turma nao esta nela');

select tests.como_rotina(tests.unidade('ESCOLA_A'));
select public.rt_pendencias_diaria();
select tests.encerrar_sessao();

select set_eq(
  'select id from t_sem_turma_view',
  'select id from t_sem_turma_pendencia',
  'PARIDADE mantida com a aluna fora da turma');

-- Devolve a aluna à turma para a seção de RLS ter linha Modular a contar. Em
-- contexto de rotina: a admissão (card 7.2) confere a vaga com
-- `fn_turma_modular_ocupacao`, que é `definer` e filtra a unidade no corpo —
-- sem unidade no contexto ela recusa com TURMA_INEXISTENTE.
select tests.como_rotina(tests.unidade('ESCOLA_A'));
update public.turma_modular_aluno set ativo = true
 where aluno_id = (select id from t_eduarda)
   and turma_id = (select id from public.turma_modular
                    where unidade_id = tests.unidade('ESCOLA_A')
                      and nome = 'Eletricista 2026.1');
select tests.encerrar_sessao();

select cmp_ok(
  (select count(*)::bigint from public.v_aluno_turmas
    where unidade_id = tests.unidade('ESCOLA_A') and forma = 'MODULAR'),
  '>', 0::bigint,
  'guarda: ha linha MODULAR para a secao de RLS contar');

-- ===========================================================================
-- 5. RLS na pele de cada perfil (nunca em contexto de rotina)
-- ===========================================================================
select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_aluno_turmas'),
  '>', 0::bigint,
  'direcao ve vinculos — a paridade abaixo nao e zero contra zero');

select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_aluno_turmas'),
  (select count(*)::bigint from public.v_aluno_turmas
    where unidade_id = tests.unidade('ESCOLA_A')),
  'direcao: todas as linhas da unidade');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_aluno_turmas where forma = ''MODULAR'''),
  (select count(*)::bigint from public.v_aluno_turmas
    where unidade_id = tests.unidade('ESCOLA_A') and forma = 'MODULAR'),
  'monitor (turmas.ler + alunos.ler): ve a metade Modular — e o perfil da jornada do celular');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_aluno_turmas where aluno_id = '
                   || quote_literal((select id from t_eduarda))),
  0::bigint,
  'direcao da outra unidade nao ve o vinculo de Eduarda');

-- Dois perfis que a matriz inicial não tem e a tela de Administração pode criar
-- amanhã (card 4.7).
insert into public.perfil (unidade_id, codigo, nome)
values (tests.unidade('ESCOLA_A'), 'SEM_TURMAS', 'Alunos sem turmas (teste 073)'),
       (tests.unidade('ESCOLA_A'), 'SO_TURMAS',  'Turmas sem alunos (teste 073)');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select tests.unidade('ESCOLA_A'), pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A')
   and pm.unidade_id = tests.unidade('ESCOLA_A')
   and ((pe.codigo = 'SEM_TURMAS' and pm.codigo in ('alunos.ler', 'materiais.ler'))
     or (pe.codigo = 'SO_TURMAS'  and pm.codigo in ('turmas.ler', 'materiais.ler')));

select tests.criar_usuario('semturmas@escola-a.test', 'SEM_TURMAS');
select tests.criar_usuario('soturmas@escola-a.test',  'SO_TURMAS');

select is(
  tests.conta_como(tests.uid('semturmas@escola-a.test'),
                   'select 1 from public.v_aluno_turmas'),
  0::bigint,
  'sem turmas.ler: nenhuma linha — e a tela esconde a coluna em vez de marcar todos');

select is(
  tests.conta_como(tests.uid('soturmas@escola-a.test'),
                   'select 1 from public.v_aluno_turmas where forma = ''BLOCO'''),
  0::bigint,
  'turmas.ler sem alunos.ler: nenhuma linha de BLOCO (join interno em aluno, card 5.7)');

select is(
  tests.conta_como(tests.uid('soturmas@escola-a.test'),
                   'select 1 from public.v_aluno_turmas where forma = ''MODULAR'''),
  0::bigint,
  'e nenhuma de MODULAR tambem — metade visivel sozinha marcaria a outra metade como sem turma');

select * from finish();
rollback;
