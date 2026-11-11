-- =============================================================================
-- A projeção MODULAR por aluno, com a turma em rodízio — card 9.2,89
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- A regra (docs/turma-rodizio.md §6): o livro é necessário quando a turma entra
-- no PRIMEIRO MÓDULO, DOS QUE FALTAM AO ALUNO, daquele livro.
--
-- O cenário é a turma `Eletricista 2026.1` — M1 concluído; M2 corrente
-- (hoje−25 … hoje+35); M3 sem data — e dois livros: o `01` cobre M1 e M2, o
-- `02` cobre M3. Dois alunos na MESMA turma:
--
--   Eduarda   já estava na turma; falta-lhe tudo. Trilha: 01, depois 02.
--   Novo      entra para começar no PRÓXIMO módulo (M3). Sequência dele:
--             M3 → M1 → M2. Trilha montada aqui na ordem em que ele precisa
--             dos livros: 02, depois 01.
--
-- O que este arquivo prova e nenhum outro enxerga:
--   • o MESMO livro, na MESMA turma, em datas diferentes para alunos diferentes
--     — a "urgência" que o dono do produto pediu;
--   • a regra antiga (por turma) daria outra data, e o teste a calcula ao lado;
--   • aberto o segundo ciclo, nenhum aluno é contado duas vezes — o aviso que o
--     card 9.2,88 deixou;
--   • módulo já feito tira o livro dele da projeção;
--   • as duas views do progresso contam a mesma história, aluno a aluno;
--   • a agenda é INVOKER: lida como dono, sem contexto, ela responde — foi por
--     aí que o defeito do card 9.2,88 apareceu.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(17);

create temporary table t_ids as
select tests.unidade('ESCOLA_A') as unidade,
       (select id from public.turma_modular
         where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eletricista 2026.1') as turma,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Eduarda Lima') as eduarda,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.codigo_sgf = '9101') as novo;
grant select on t_ids to authenticated;

create temporary table t_mod as
select m.ordem, m.id, m.material_id
  from public.modulo m
  join public.turma_modular t on t.curso_id = m.curso_id
 where t.id = (select turma from t_ids);
grant select on t_mod to authenticated;

-- "02:+36" — o que a projeção diz de um aluno: código do livro e dias a partir
-- de hoje, por ordem do livro. "nada" quando ele não tem linha.
create function pg_temp.projecao(p_aluno uuid) returns text language sql stable as $$
  select coalesce(
    string_agg(format('%s:%s:%s', mt.codigo, p.regra,
                      case when p.data_prevista >= public.fn_hoje()
                           then '+' || (p.data_prevista - public.fn_hoje())
                           else (p.data_prevista - public.fn_hoje())::text end),
               ' ' order by mt.codigo),
    'nada')
    from public.v_projecao_aluno p
    join public.material mt on mt.id = p.material_id
   where p.aluno_id = p_aluno
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
-- 1. A agenda é INVOKER — e responde a quem lê sem contexto
-- ===========================================================================
select is(
  (select p.prosecdef::text from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_turma_modular_agenda'),
  'false',
  'fn_turma_modular_agenda nao e mais security definer (correcao do card 9.2,88)');

-- Como dono, sem auth.uid() e sem contexto de rotina: é exatamente a leitura
-- que vinha VAZIA quando a função era definer com filtro de unidade.
select is(
  (select count(*)::integer from public.fn_turma_modular_agenda((select turma from t_ids))),
  4,
  'lida sem contexto nenhum, a agenda responde: tres modulos mais o corrente outra vez');

-- ===========================================================================
-- 2. A aluna que já estava na turma: a mesma data de antes
-- ===========================================================================
-- Falta-lhe tudo, então o primeiro módulo do livro 02 que lhe falta é o M3, que
-- começa no dia seguinte ao fim do M2 — hoje+36, o mesmo número do teste 080.
select is(pg_temp.projecao((select eduarda from t_ids)), '02:MODULAR:+36',
  'a aluna a quem falta tudo: o livro 02 quando a turma entrar no M3');

-- ===========================================================================
-- 3. O MESMO livro, em outra data, para quem entrou em outro módulo
-- ===========================================================================
-- O aluno novo entra para começar no M3. A trilha dele é montada na ordem em
-- que ELE precisa dos livros (02, depois 01) — reordenar a trilha na admissão é
-- do card 9.2,886; aqui ela é escrita à mão, como dono.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));
select public.fn_turma_modular_admitir((select turma from t_ids), (select novo from t_ids),
                                       (select id from t_mod where ordem = 3));
reset role;
select tests.encerrar_sessao();

select tests.como_rotina((select unidade from t_ids));

insert into public.aluno_material (unidade_id, aluno_id, material_id, ordem, origem)
select (select unidade from t_ids), (select novo from t_ids), x.material_id, x.ordem, 'MANUAL'
  from (select (select material_id from t_mod where ordem = 3) as material_id, 10 as ordem
        union all
        select (select material_id from t_mod where ordem = 1), 20) x;

select tests.encerrar_sessao();

-- A sequência dele é M3 → M1 → M2. O livro 01 (M1 e M2) só lhe serve quando a
-- turma VOLTAR ao M1, no ciclo 2: hoje+85. (O livro 02 é o próximo dele, k = 1
-- — demanda imediata, que esta view não conta.)
select is(pg_temp.projecao((select novo from t_ids)), '01:MODULAR:+85',
  'quem entrou no M3 so precisa do livro 01 quando a turma voltar ao M1, no ciclo 2');

-- A regra ANTIGA, calculada ao lado: a turma entrou no primeiro módulo do livro
-- 01 há 60 dias. Para a turma, esse livro é passado; para ele, é daqui a 85.
select is(
  (select min(tm.data_inicio) - public.fn_hoje()
     from public.turma_modular_modulo tm
     join public.modulo m on m.id = tm.modulo_id
    where tm.turma_id = (select turma from t_ids)
      and m.material_id = (select material_id from t_mod where ordem = 1)),
  -60,
  'pela regra antiga (por turma) o livro 01 teria a data de 60 dias atras — a diferenca e a regra');

-- Os dois, lado a lado: mesma turma, livros e datas diferentes.
select is(
  (select string_agg(a.nome || ' ' || mt.codigo || ' ' || (p.data_prevista - public.fn_hoje()),
                     ' | ' order by a.nome)
     from public.v_projecao_aluno p
     join public.aluno a on a.id = p.aluno_id
     join public.material mt on mt.id = p.material_id
    where p.aluno_id in ((select eduarda from t_ids), (select novo from t_ids))),
  'Aluno Modular 01 01 85 | Eduarda Lima 02 36',
  'dois alunos da MESMA turma, cada um com o livro e a data da sequencia dele');

-- ===========================================================================
-- 4. As duas views do progresso contam a mesma história
-- ===========================================================================
-- `v_aluno_modular_agenda` (a lista) e `v_aluno_modular_progresso` (o resumo)
-- escrevem a mesma condição de "aguardando a entrada" cada uma. Aluno a aluno:
-- o primeiro da lista é o próximo do resumo, o fim do último é a previsão, e a
-- lista tem total − feitos linhas.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select is(
  (select string_agg(format('%s:%s:%s:%s', p.aluno_nome,
            (l.primeiro = p.proximo_modulo_id)::text,
            (l.fim = p.prev_conclusao)::text,
            (l.n = p.modulos_total - p.modulos_feitos)::text),
          ' | ' order by p.aluno_nome)
     from public.v_aluno_modular_progresso p
     join lateral (
            select (array_agg(g.modulo_id order by g.posicao))[1] as primeiro,
                   max(g.data_fim) as fim, count(*)::integer as n
              from public.v_aluno_modular_agenda g
             where g.alocacao_id = p.alocacao_id) l on true
    where p.turma_id = (select turma from t_ids)),
  'Aluno Modular 01:true:true:true | Eduarda Lima:true:true:true',
  'a lista e o resumo do progresso dizem o mesmo proximo modulo, a mesma previsao e a mesma contagem');

select is(
  (select string_agg('M' || g.modulo_ordem || 'c' || g.ciclo, ' ' order by g.posicao)
     from public.v_aluno_modular_agenda g
    where g.aluno_id = (select novo from t_ids)),
  'M3c1 M1c2 M2c2',
  'a sequencia do aluno novo: M3, depois o M1 e o M2 do ciclo 2 — o corrente de hoje e o ultimo');

reset role;
select tests.encerrar_sessao();

-- ===========================================================================
-- 5. Segundo ciclo aberto: ninguém é contado duas vezes
-- ===========================================================================
select pg_temp.avancar(0);    -- fecha o M2
select pg_temp.avancar(10);   -- fecha o M3 e abre o ciclo 2

select is(
  (select count(*)::integer from public.turma_modular_modulo tm
    where tm.turma_id = (select turma from t_ids)),
  6, 'fixture: o cronograma tem agora SEIS linhas — os tres modulos, em dois ciclos');

select is(
  (select count(*) - count(distinct (p.aluno_id, p.material_id))
     from public.v_projecao_aluno p
    where p.aluno_id in ((select eduarda from t_ids), (select novo from t_ids))),
  0::bigint,
  'com dois ciclos no cronograma, nenhum par aluno x livro aparece duas vezes na projecao');

-- A aluna fez M2 e M3: do livro 02 (M3) não lhe falta módulo nenhum, então ele
-- sai da projeção dela — mesmo continuando pendente na trilha.
select is(pg_temp.projecao((select eduarda from t_ids)), 'nada',
  'modulo ja feito tira o livro dele da projecao: a aluna que fez o M3 nao projeta o livro 02');

select is(
  (select count(*)::integer from public.aluno_material am
    where am.aluno_id = (select eduarda from t_ids) and not am.entregue
      and am.material_id = (select material_id from t_mod where ordem = 3)),
  1, 'e o livro continua PENDENTE na trilha dela: quem o tirou foi a regra, nao a entrega');

-- O aluno novo fez o M3. Falta-lhe M1 (corrente, começou em hoje+11) e M2: o
-- livro 01 passou a ser para AGORA — a data é o início do módulo corrente.
select is(pg_temp.projecao((select novo from t_ids)), '01:MODULAR:+11',
  'a turma chegou ao M1: o livro 01 do aluno novo passa de +85 para o inicio do modulo corrente');

-- ===========================================================================
-- 6. A rotina grava o que a view diz
-- ===========================================================================
select tests.como_rotina((select unidade from t_ids));
select public.rt_projecao_demanda();

select is(
  (select coalesce(sum(dp.quantidade), 0)::integer
     from public.demanda_projetada dp
    where dp.unidade_id = (select unidade from t_ids) and dp.regra = 'MODULAR'),
  (select count(*)::integer
     from public.v_projecao_aluno p
    where p.unidade_id = (select unidade from t_ids) and p.regra = 'MODULAR'
      and p.data_prevista <= public.fn_hoje()
                             + public.fn_param_int('projecao_horizonte_dias')
      and date_trunc('month', p.data_prevista) >= date_trunc('month', public.fn_hoje())),
  'o total MODULAR que a rotina grava e o detalhe da view, dentro da janela');

select tests.encerrar_sessao();

-- ===========================================================================
-- 7. Quem lê
-- ===========================================================================
select is(
  (select format('direcao=%s monitor=%s semperfil=%s direcaoB=%s',
     tests.conta_como(tests.uid('direcao@escola-a.test'),
       format('select 1 from public.v_aluno_modular_agenda where turma_id = %L', (select turma from t_ids))),
     tests.conta_como(tests.uid('monitor@escola-a.test'),
       format('select 1 from public.v_aluno_modular_agenda where turma_id = %L', (select turma from t_ids))),
     tests.conta_como(tests.uid('semperfil@escola-a.test'),
       format('select 1 from public.v_aluno_modular_agenda where turma_id = %L', (select turma from t_ids))),
     tests.conta_como(tests.uid('direcao@escola-b.test'),
       format('select 1 from public.v_aluno_modular_agenda where turma_id = %L', (select turma from t_ids))))),
  'direcao=3 monitor=3 semperfil=0 direcaoB=0',
  'quem le turmas e alunos ve as tres linhas que faltam; sem perfil e a outra unidade, nenhuma');

select is(
  (select string_agg(has_table_privilege(r, 'public.v_aluno_modular_agenda', 'select')::text,
                     '/' order by r)
     from unnest(array['anon', 'authenticated']) r),
  'false/true',
  'v_aluno_modular_agenda: anon nao le, authenticated le');

-- Turma SEM data nenhuma continua derrubando o aluno para a média do método.
select tests.como_rotina((select unidade from t_ids));
update public.turma_modular_modulo
   set data_inicio = null, prev_conclusao = null
 where turma_id = (select turma from t_ids);

select is(
  (select string_agg(distinct p.regra, ',')
     from public.v_projecao_aluno p
    where p.aluno_id = (select novo from t_ids)),
  'MEDIA_METODO',
  'turma sem data nenhuma: a agenda nao tem o que extrapolar, e o aluno cai para a media do metodo');

select * from finish();
rollback;
