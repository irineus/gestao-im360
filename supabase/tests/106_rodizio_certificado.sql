-- =============================================================================
-- Turma em rodízio: certificado, previsão e combo — card 9.2,885
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- As três decisões de Irineu de 11/11/2026 (docs/turma-rodizio.md §10):
--   D1  o certificado do aluno MODULAR abre na conclusão dos MÓDULOS, não na
--       última apostila;
--   D2  PREVISAO_VENCIDA deixa de olhar o aluno em turma Modular;
--   D3  com mais de um curso Modular no combo, o certificado abre no fim do combo.
--
-- A aluna é Eduarda Lima, na turma `Eletricista 2026.1` (três módulos, o M1 já
-- dado pela turma antes de ela ter registro). O que este arquivo prova e nenhum
-- outro enxerga:
--   • entregar a última APOSTILA dela não abre checklist nem aviso — e ela sai
--     da fila de certificados, onde estaria pelo critério antigo;
--   • a fila passa a contar MÓDULOS: "no último módulo" e "concluiu";
--   • quem avança o módulo NÃO precisa de certificados.criar para o checklist
--     nascer (o pedagógico não tem);
--   • remover um módulo desfaz: o checklist intocado é apagado, o trabalhado é
--     mantido com aviso;
--   • com um segundo curso no combo, concluir o primeiro não abre nada.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(24);

create temporary table t_ids as
select (select id from public.turma_modular
         where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eletricista 2026.1') as turma,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Eduarda Lima') as eduarda,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.codigo_sgf = '9101') as novo;
grant select on t_ids to authenticated;

create temporary table t_mod as
select m.ordem, m.id
  from public.modulo m
  join public.turma_modular t on t.curso_id = m.curso_id
 where t.id = (select turma from t_ids);
grant select on t_mod to authenticated;

-- "FIM/0", "ULTIMO_LIVRO/1" ou "fora da fila", como a DIREÇÃO lê.
create function pg_temp.fila(p_aluno uuid) returns text language plpgsql as $$
declare v text;
begin
  perform tests.autenticar(tests.uid('direcao@escola-a.test'));
  select f.situacao || '/' || f.itens_pendentes
           || case when f.checklist_id is null then '' else ' +checklist' end
    into v
    from public.v_certificado_fila f where f.aluno_id = p_aluno;
  reset role;
  perform tests.encerrar_sessao();
  return coalesce(v, 'fora da fila');
end $$;

create function pg_temp.checklist(p_aluno uuid) returns text language sql stable as $$
  select coalesce(
    (select 'aberto em ' || case when cc.data_fim_curso >= public.fn_hoje()
                                 then '+' || (cc.data_fim_curso - public.fn_hoje())
                                 else (cc.data_fim_curso - public.fn_hoje())::text end
       from public.certificado_checklist cc where cc.aluno_id = p_aluno),
    'nenhum')
$$;

create function pg_temp.aviso(p_aluno uuid, p_tipo text) returns text language sql stable as $$
  select coalesce(
    (select case when p.resolvida_em is null then 'aberta' else 'fechada' end
       from public.pendencia p
      where p.aluno_id = p_aluno and p.tipo = p_tipo
      order by (p.resolvida_em is null) desc, p.criado_em desc, p.id desc
      limit 1),
    'nenhuma')
$$;

-- Avança a turma na pele do PEDAGÓGICO: tem turmas.editar e NÃO tem
-- certificados.criar — é a prova de que o avanço não depende dela.
create function pg_temp.avancar(p_dias integer) returns void language plpgsql as $$
begin
  perform tests.autenticar(tests.uid('pedagogico@escola-a.test'));
  perform public.fn_turma_modular_avancar((select turma from t_ids),
                                          public.fn_hoje() + p_dias);
  reset role;
  perform tests.encerrar_sessao();
end $$;

-- ===========================================================================
-- 1. D2 — PREVISAO_VENCIDA não olha o aluno em turma Modular
-- ===========================================================================
-- As DUAS previsões vencidas, e só a de quem está FORA de turma abre aviso.
update public.aluno set prev_conclusao_curso = public.fn_hoje() - 10
 where id in ((select eduarda from t_ids), (select novo from t_ids));

select tests.como_rotina(tests.unidade('ESCOLA_A'));
select public.rt_pendencias_diaria();
select tests.encerrar_sessao();

select is(
  format('%s | %s', pg_temp.aviso((select eduarda from t_ids), 'PREVISAO_VENCIDA'),
                    pg_temp.aviso((select novo from t_ids),    'PREVISAO_VENCIDA')),
  'nenhuma | aberta',
  'previsao digitada vencida: a aluna em turma Modular NAO recebe aviso; o aluno Modular sem turma recebe');

-- ===========================================================================
-- 2. D1 — a última APOSTILA não abre o certificado do aluno Modular
-- ===========================================================================
-- Entrega tudo o que falta na trilha dela, como o monitor. Em tabela: função
-- volátil chamada em `select` solto, uma vez por linha gerada.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

create temporary table t_entregas as
select (public.fn_registrar_entrega((select eduarda from t_ids))).em_fim
  from generate_series(1, (select count(*)::integer from public.aluno_material am
                            where am.aluno_id = (select eduarda from t_ids)
                              and not am.entregue));

reset role;
select tests.encerrar_sessao();

select is(
  (select count(*)::integer from public.aluno_material am
    where am.aluno_id = (select eduarda from t_ids) and not am.entregue),
  0, 'a trilha de apostilas da aluna chegou ao FIM');

select is(
  format('%s | %s', pg_temp.checklist((select eduarda from t_ids)),
                    pg_temp.aviso((select eduarda from t_ids), 'ALUNO_ULTIMO_LIVRO')),
  'nenhum | nenhuma',
  'e NADA abriu: nem o checklist do certificado, nem o aviso da ultima apostila');

-- Pelo critério antigo ela estaria na fila como FIM. Faltam-lhe os três módulos.
select is(pg_temp.fila((select eduarda from t_ids)), 'fora da fila',
  'com todas as apostilas e nenhum modulo feito, ela NAO esta na fila de certificados');

select is(
  (select public.fn_aluno_modular_modulos_pendentes((select novo from t_ids)) is null)::text,
  'true',
  'aluno Modular que ainda nao entrou em turma nenhuma: pendentes NULO, nao zero');

-- ===========================================================================
-- 3. A fila conta MÓDULOS
-- ===========================================================================
select pg_temp.avancar(0);    -- fecha o M2
select pg_temp.avancar(10);   -- fecha o M3, abre o ciclo 2

select is(pg_temp.fila((select eduarda from t_ids)), 'ULTIMO_LIVRO/1',
  'com dois dos tres modulos, ela entra na fila como "no ultimo modulo", ainda sem checklist');

select is(pg_temp.checklist((select eduarda from t_ids)), 'nenhum',
  'e o checklist continua fechado: falta um modulo');

-- ===========================================================================
-- 4. A conclusão dos módulos abre o certificado — sem certificados.criar
-- ===========================================================================
select is(
  (select string_agg(pe.codigo, ',' order by pe.codigo)
     from public.perfil_permissao pp
     join public.perfil    pe on pe.id = pp.perfil_id
     join public.permissao pm on pm.id = pp.permissao_id
    where pe.unidade_id = tests.unidade('ESCOLA_A') and pm.codigo = 'certificados.criar'),
  'DIRECAO,MONITOR,SECRETARIA',
  'fixture: o pedagogico, que avanca a turma, NAO tem certificados.criar');

select pg_temp.avancar(20);   -- fecha o M1 do ciclo 2: ela completa

select is(pg_temp.checklist((select eduarda from t_ids)), 'aberto em +20',
  'concluir os modulos abre o checklist, com a data do ULTIMO modulo — e quem avancou nao tem certificados.criar');

select is(pg_temp.aviso((select eduarda from t_ids), 'ALUNO_ULTIMO_LIVRO'), 'aberta',
  'e abre o aviso de que o checklist esta aberto');

select is(pg_temp.fila((select eduarda from t_ids)), 'FIM/0 +checklist',
  'na fila ela passa a "concluiu", com o checklist ao lado');

select is(
  (select format('%s / %s', ta.ativo, ta.motivo_saida)
     from public.turma_modular_aluno ta
    where ta.turma_id = (select turma from t_ids)
      and ta.aluno_id = (select eduarda from t_ids)),
  'f / Concluiu o curso',
  'e ela saiu da turma, liberando a vaga (card 9.2,88)');

-- ===========================================================================
-- 5. Remover um módulo desfaz — checklist INTOCADO é apagado
-- ===========================================================================
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));
select public.fn_aluno_modulo_remover((select eduarda from t_ids),
         (select id from t_mod where ordem = 3), 'precisa refazer');
reset role;
select tests.encerrar_sessao();

select is(
  format('%s | %s | %s', pg_temp.checklist((select eduarda from t_ids)),
         pg_temp.aviso((select eduarda from t_ids), 'ALUNO_ULTIMO_LIVRO'),
         pg_temp.fila((select eduarda from t_ids))),
  'nenhum | fechada | ULTIMO_LIVRO/1',
  'removido um modulo: o checklist intocado e apagado, o aviso fecha e ela volta a "no ultimo modulo"');

-- ===========================================================================
-- 6. D3 — com um segundo curso no combo, concluir o primeiro não abre nada
-- ===========================================================================
-- Um segundo curso Modular, de um módulo, entra no combo dela. Como dono: o
-- catálogo não é o assunto deste arquivo.
create temporary table t_curso_b as
with c as (
  insert into public.curso (unidade_id, metodo_id, nome)
  select tests.unidade('ESCOLA_A'), a.metodo_id, 'Curso B TESTE 106'
    from public.aluno a where a.id = (select eduarda from t_ids)
  returning id, unidade_id)
select id, unidade_id from c;

create temporary table t_mod_b as
with m as (
  insert into public.modulo (unidade_id, curso_id, material_id, nome, ordem)
  select b.unidade_id, b.id,
         (select mo.material_id from public.modulo mo
           where mo.id = (select id from t_mod where ordem = 1)),
         'Módulo único B', 1
    from t_curso_b b
  returning id)
select id from m;
grant select on t_mod_b to authenticated;

insert into public.combo_curso (unidade_id, combo_id, curso_id, ordem)
select b.unidade_id, a.combo_id, b.id, 9
  from t_curso_b b, public.aluno a
 where a.id = (select eduarda from t_ids);

-- Ela refaz o M3: o curso da turma está completo, mas o combo não.
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));
select public.fn_aluno_modulo_registrar((select eduarda from t_ids),
         (select id from t_mod where ordem = 3), public.fn_hoje() + 30, 'refez');
reset role;
select tests.encerrar_sessao();

select is(
  (select count(*)::integer from public.modulo m
    where m.curso_id = (select t.curso_id from public.turma_modular t
                         where t.id = (select turma from t_ids))
      and not exists (select 1 from public.aluno_modulo am
                       where am.aluno_id = (select eduarda from t_ids)
                         and am.modulo_id = m.id)),
  0, 'o curso da turma esta completo outra vez');

select is(
  format('%s | %s', pg_temp.checklist((select eduarda from t_ids)),
                    pg_temp.fila((select eduarda from t_ids))),
  'nenhum | ULTIMO_LIVRO/1',
  'mas o COMBO tem outro curso por fazer: o checklist NAO abre, e a fila conta o modulo que falta');

-- O módulo do segundo curso fecha o combo: agora abre.
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));
select public.fn_aluno_modulo_registrar((select eduarda from t_ids),
         (select id from t_mod_b), public.fn_hoje() + 40, 'curso B');
reset role;
select tests.encerrar_sessao();

select is(
  format('%s | %s', pg_temp.checklist((select eduarda from t_ids)),
                    pg_temp.fila((select eduarda from t_ids))),
  'aberto em +40 | FIM/0 +checklist',
  'concluido o ULTIMO curso do combo, o checklist abre — com a data do ultimo modulo');

-- ===========================================================================
-- 7. Remover módulo com checklist JÁ TRABALHADO: mantém e avisa
-- ===========================================================================
-- Na pele da DIREÇÃO: a guarda de coluna do checklist (card 8.3) exige
-- certificados.marcar_pedagogico de quem marca, inclusive do dono.
select tests.autenticar(tests.uid('direcao@escola-a.test'));
update public.certificado_checklist set pedagogico_ok = true
 where aluno_id = (select eduarda from t_ids);
reset role;
select tests.encerrar_sessao();

select tests.autenticar(tests.uid('pedagogico@escola-a.test'));
select public.fn_aluno_modulo_remover((select eduarda from t_ids),
         (select id from t_mod_b), 'lançado por engano');
reset role;
select tests.encerrar_sessao();

select is(
  format('%s | %s', (pg_temp.checklist((select eduarda from t_ids)) <> 'nenhum')::text,
                    pg_temp.aviso((select eduarda from t_ids), 'CERTIFICADO_INCONSISTENTE')),
  'true | aberta',
  'checklist com item ja marcado NAO e apagado: fica, com o aviso de inconsistencia');

-- ===========================================================================
-- 8. Interativo e Inglês não mudaram
-- ===========================================================================
-- A medida completa é o teste 081; aqui, só a fronteira: a função que decide.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select is(
  (select string_agg(distinct me.codigo || '=' || public.fn_aluno_e_modular(a.id)::text, ', '
                     order by me.codigo || '=' || public.fn_aluno_e_modular(a.id)::text)
     from public.aluno a
     join public.metodo me on me.id = a.metodo_id),
  'INGLES=false, INTERATIVO=false, MODULAR=true',
  'fn_aluno_e_modular separa os tres metodos, e so o MODULAR e verdadeiro');

reset role;
select tests.encerrar_sessao();

-- Aluno de OUTRA unidade: as duas perguntas não o enxergam.
select tests.autenticar(tests.uid('direcao@escola-b.test'));

select is(
  format('%s | %s', public.fn_aluno_e_modular((select eduarda from t_ids)),
         coalesce(public.fn_aluno_modular_modulos_pendentes((select eduarda from t_ids))::text,
                  'nulo')),
  'f | nulo',
  'a direcao da Escola B nao descobre nada de uma aluna da Escola A');

select is(
  public.fn_aluno_modular_avaliar_certificado((select eduarda from t_ids)),
  false,
  'nem abre certificado para ela');

reset role;
select tests.encerrar_sessao();

-- As três funções novas chegam a authenticated, e a anon não.
select is(
  (select string_agg(p.proname || ':' ||
            has_function_privilege('anon', p.oid, 'execute')::text || '/' ||
            has_function_privilege('authenticated', p.oid, 'execute')::text,
            ' ' order by p.proname)
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_aluno_e_modular', 'fn_aluno_modular_modulos_pendentes',
                        'fn_aluno_modular_avaliar_certificado')),
  'fn_aluno_e_modular:false/true fn_aluno_modular_avaliar_certificado:false/true '
  'fn_aluno_modular_modulos_pendentes:false/true',
  'as tres funcoes: anon nao executa, authenticated executa');

-- A rotina continua com o bloco da troca de módulo (card 9.2,85): substituir a
-- função inteira a partir de outra definição o apagaria sem nada denunciar.
select ok(
  (select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'TROCA_MODULO_ALINHAR'
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rt_pendencias_diaria'),
  'rt_pendencias_diaria continua abrindo TROCA_MODULO_ALINHAR depois desta substituicao');

select ok(
  (select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'ESTOQUE_ABAIXO_MINIMO'
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rt_pendencias_diaria'),
  'e continua abrindo ESTOQUE_ABAIXO_MINIMO');

select ok(
  (select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'fn_certificado_abrir'
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_registrar_entrega'),
  'fn_registrar_entrega continua abrindo o checklist para quem nao e Modular');

select * from finish();
rollback;
