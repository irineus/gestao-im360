-- =============================================================================
-- As três views do Dashboard completo — card 8.7
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- ⚠️ O §17 NÃO PREVIA ARQUIVO PARA O 8.7, e a divergência é a sétima da mesma
--    família: `053` (6.6), `061` (6.7), `062` (6.8), `072` (7.3), `082` (8.5) e
--    `083` (8.6). A diferença aqui é que estas três views estavam previstas
--    desde 01/09/2026 em `views-leitura.md` §8, com o card 8.7 ao lado — o que
--    faltava era o arquivo de teste. Mora no bloco `08x`, entre o `083` e o
--    `085`. Registrada no §17, não seguida em silêncio.
--
-- Obrigação de **View** (§13): paridade de linhas por perfil + zero para quem
-- não pode + isolamento de unidade (§6.3), mais as armadilhas do card 2.3 §3.
-- As reduções silenciosas por falta de `materiais.ler` — o bloqueante nº 1 de
-- `permissoes-matriz.md` §7 — ficam no `095` §7, ao lado das outras quatro views
-- do mesmo achado, que é onde ele se fecha.
--
-- Quatro coisas que este arquivo prova e que nenhum catálogo enxerga:
--
--   • **`em_ultimo_livro` ≠ `em_fim`** (card 2.3 §8.1). O plano chama as duas de
--     "último livro" e o cartão mostra a primeira. Na fixture os números são
--     opostos por método — trocar as colunas produziria uma tela plausível e
--     errada, sem erro em lugar nenhum;
--
--   • **`sem_previsao` FECHA A CONTA.** Para cada método, alunos em curso =
--     `sem_previsao` + a soma dos semestres. É a razão de a coluna existir: sem
--     ela ninguém sabe se faltou aluno ou faltou data;
--
--   • **previsão no passado NÃO é descartada** — fica no semestre dela e entra
--     em `qtd_vencidas`, medida com `fn_hoje()` e não com `current_date`;
--
--   • **`v_dashboard_tipos_bloco` conta ALOCAÇÕES, não alunos.** A fixture tem
--     blocos disjuntos de propósito (card 5.1), então na partida os dois números
--     coincidem; este arquivo cria a aceleração que os separa.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(23);

-- Chaves naturais em um lugar só (card 2.8 §11: nunca `limit` sem ordem, nunca
-- UUID literal).
create temporary table t_ids as
  select tests.unidade('ESCOLA_A') as unidade_a,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Ana Paula Ribeiro') as ana,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Karina Bastos')     as karina,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Diego Alves')       as diego,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Henrique Dias')     as henrique,
         (select b.id from public.bloco_horario b
            join public.sala s on s.id = b.sala_id
           where b.unidade_id = tests.unidade('ESCOLA_A')
             and s.nome = 'Laboratório 1' and b.dia_semana = 1)                             as bloco_vazio;

-- A seção 5 chama `fn_bloco_admitir` já em `authenticated`, e nesse papel a
-- tabela temporária não é alcançável sem isto (mesma razão do `083`).
grant select on t_ids to authenticated;

-- ===========================================================================
-- 1. O panorama das três views na fixture
-- ===========================================================================
-- Uma linha por view, e é a asserção mais barata que existe contra `where`
-- frouxo ou `group by` errado: qualquer deslize muda a string inteira.
select is(
  (select string_agg(format('%s=%s/%s/%s/%s/%s/%s',
                            v.metodo_codigo, v.ativos, v.acelerar, v.standby,
                            v.trancados, v.cancelados, v.formados),
                     ' | ' order by v.metodo_codigo)
     from public.v_dashboard_alunos_metodo v
    where v.unidade_id = (select unidade_a from t_ids)),
  'INGLES=0/1/1/0/0/0 | INTERATIVO=19/0/0/1/1/1 | MODULAR=2/0/0/0/0/0',
  'alunos por metodo e status: os doze da camada alunos mais os treze de lotacao');

select is(
  (select string_agg(format('%s=%s/%s/%s/%s/%s',
                            v.metodo_codigo, v.rem, v.pre, v.rep, v.novo, v.alocacoes),
                     ' | ' order by v.metodo_codigo)
     from public.v_dashboard_tipos_bloco v
    where v.unidade_id = (select unidade_a from t_ids)),
  'INTERATIVO=15/2/1/1/19',
  'tipos na turma: so o INTERATIVO tem bloco de horario na fixture, com 19 alocacoes ativas');

-- ⚠️ A conta do `alocacoes` é a soma dos quatro tipos, e não uma quinta
--    contagem solta: um `tipo` novo no `check` de `bloco_aluno` que ninguém
--    acrescentasse aqui apareceria como diferença, em vez de sumir na coluna
--    total.
select is(
  (select count(*)::bigint from public.v_dashboard_tipos_bloco v
    where v.alocacoes <> v.rem + v.pre + v.rep + v.novo),
  0::bigint,
  'alocacoes e a soma dos quatro tipos — tipo fora da lista apareceria como diferenca');

-- ===========================================================================
-- 2. `em_ultimo_livro` ≠ `em_fim` — a distinção do card 2.3 §8.1
-- ===========================================================================
-- Os números são OPOSTOS por método, e é isso que faz a troca das colunas ser
-- detectável: quem está no último livro é o Felipe (INGLES), e quem tem zero
-- item pendente são a Karina (INTERATIVO) e o Aluno Modular 01 — os dois **sem
-- trilha nenhuma**.
select is(
  (select string_agg(v.metodo_codigo || '=' || v.em_ultimo_livro, ' | '
                     order by v.metodo_codigo)
     from public.v_dashboard_alunos_metodo v
    where v.unidade_id = (select unidade_a from t_ids)),
  'INGLES=1 | INTERATIVO=0 | MODULAR=0',
  'em_ultimo_livro e UM item pendente — o aluno ainda tem aula pela frente');

select is(
  (select string_agg(v.metodo_codigo || '=' || v.em_fim, ' | '
                     order by v.metodo_codigo)
     from public.v_dashboard_alunos_metodo v
    where v.unidade_id = (select unidade_a from t_ids)),
  'INGLES=0 | INTERATIVO=1 | MODULAR=1',
  'em_fim e NENHUM item pendente, e os numeros sao os OPOSTOS: trocar as colunas se ve');

-- O `em_fim` do INTERATIVO é a Karina, ATIVA e sem combo — logo sem trilha. É a
-- mesma verdade que `fn_trilha_em_fim` devolve (card 6.2), e é de propósito: o
-- dashboard CONTA, e quem precisa distinguir "acabou" de "nunca começou" é a
-- fila de certificados, que pergunta pela trilha (card 8.6).
select is(
  (select count(*)::bigint
     from public.aluno a
    where a.unidade_id = (select unidade_a from t_ids)
      and a.metodo_id = (select metodo_id from public.aluno where id = (select karina from t_ids))
      and a.status in ('ATIVO','ACELERAR')
      and not exists (select 1 from public.aluno_material am where am.aluno_id = a.id)),
  1::bigint,
  'o unico em_fim do INTERATIVO e a aluna SEM TRILHA — a coluna conta os dois casos, de proposito');

select ok(
  (select public.fn_trilha_em_fim((select karina from t_ids))),
  'e fn_trilha_em_fim concorda com a coluna: as duas leituras nao podem divergir');

-- Sem número copiado: as duas colunas são a contagem real da trilha, refeita
-- aqui pelo outro caminho.
select is(
  (select count(*)::bigint
     from public.v_dashboard_alunos_metodo v
     join lateral (
       select count(*) filter (where pend.qtd = 1)::integer as ultimo,
              count(*) filter (where pend.qtd = 0)::integer as fim
         from public.aluno a
         cross join lateral (select count(*) as qtd from public.aluno_material am
                              where am.aluno_id = a.id and not am.entregue) pend
        where a.unidade_id = v.unidade_id and a.metodo_id = v.metodo_id
          and a.status in ('ATIVO','ACELERAR')) refeito on true
    where v.unidade_id = (select unidade_a from t_ids)
      and (v.em_ultimo_livro, v.em_fim) is distinct from (refeito.ultimo, refeito.fim)),
  0::bigint,
  'as duas colunas sao a contagem real da trilha, nao um numero copiado');

-- ===========================================================================
-- 3. `sem_previsao` fecha a conta com o total de alunos em curso
-- ===========================================================================
-- ⚠️ É a razão de a coluna existir (docs/views-leitura.md §8.1): a região de
--    conclusões só enxerga quem tem data informada, e sem este número a soma
--    dos semestres não bate com os ativos — ninguém sabe se faltou aluno ou
--    faltou data. A invariante é POR MÉTODO, não no total: no total ela passaria
--    mesmo com os métodos trocados entre si.
select is(
  (select count(*)::bigint
     from public.v_dashboard_alunos_metodo v
     left join lateral (
       select coalesce(sum(c.qtd_alunos), 0) as previstos
         from public.v_dashboard_conclusoes_semestre c
        where c.unidade_id = v.unidade_id and c.metodo_id = v.metodo_id) s on true
    where v.unidade_id = (select unidade_a from t_ids)
      and v.ativos + v.acelerar <> v.sem_previsao + s.previstos),
  0::bigint,
  'por metodo: ativos + acelerar = sem_previsao + a soma dos semestres — a conta FECHA');

select is(
  (select string_agg(v.metodo_codigo || '=' || v.sem_previsao, ' | '
                     order by v.metodo_codigo)
     from public.v_dashboard_alunos_metodo v
    where v.unidade_id = (select unidade_a from t_ids)),
  'INGLES=0 | INTERATIVO=16 | MODULAR=2',
  'e os treze Aluno de Lotacao, que nascem sem previsao, estao dentro dos 16 do INTERATIVO');

-- ===========================================================================
-- 4. As conclusões: o semestre, as vencidas e o filtro de status
-- ===========================================================================
-- Quatro alunos em curso têm previsão informada (Bruno +90, Carla +120,
-- Diego −15 e Felipe +60), e as datas são SEMPRE relativas a `fn_hoje()` — por
-- isso o ano e o semestre se recalculam aqui em vez de virarem literal.
select is(
  (select sum(c.qtd_alunos)::bigint from public.v_dashboard_conclusoes_semestre c
    where c.unidade_id = (select unidade_a from t_ids)),
  4::bigint,
  'quatro alunos em curso com previsao informada — os demais estao em sem_previsao');

select is(
  (select sum(c.qtd_vencidas)::bigint from public.v_dashboard_conclusoes_semestre c
    where c.unidade_id = (select unidade_a from t_ids)),
  1::bigint,
  'uma vencida: a previsao do Diego esta 15 dias no passado');

-- ⚠️ E ela NÃO foi descartada: está no semestre DELA e dentro do `qtd_alunos`
--    daquela linha — quem prova o "não descartada" é a soma de 4 logo acima,
--    que já conta os quatro alunos com previsão. Descartá-la faria a
--    conferência contra a planilha não fechar, que traz previsões de 2023 e de
--    2050 (card 9.3).
--
-- ⚠️ O ano e o semestre saem da PRÓPRIA data do aluno, nunca de um literal: as
--    datas da fixture são relativas a `fn_hoje()`, e um `2026/2` escrito aqui
--    reprovaria sozinho num dia de junho — falha de calendário com cara de
--    regressão.
select is(
  (select format('%s/%s', c.qtd_vencidas, c.qtd_alunos >= c.qtd_vencidas)
     from public.v_dashboard_conclusoes_semestre c
     join public.aluno a on a.id = (select diego from t_ids)
    where c.unidade_id = (select unidade_a from t_ids)
      and c.metodo_id = a.metodo_id
      and c.ano = extract(year from a.prev_conclusao_curso)::integer
      and c.semestre = (case when extract(month from a.prev_conclusao_curso) <= 6
                             then 1 else 2 end)::smallint),
  '1/t',
  'a vencida fica no semestre DELA e dentro do total daquele semestre, nao fora dele');

-- O filtro de status é medido pelo caminho que a fixture não dá de graça: um
-- TRANCADO com previsão informada não pode entrar em semestre nenhum.
update public.aluno
   set prev_conclusao_curso = public.fn_hoje() + 30
 where id = (select henrique from t_ids);

select is(
  (select sum(c.qtd_alunos)::bigint from public.v_dashboard_conclusoes_semestre c
    where c.unidade_id = (select unidade_a from t_ids)),
  4::bigint,
  'TRANCADO com previsao informada NAO entra: a regiao e de quem esta em curso');

-- ===========================================================================
-- 5. Tipos na turma: ALOCAÇÕES, e não alunos
-- ===========================================================================
-- ⚠️ A fixture do card 5.1 pôs alunos DISJUNTOS nos dois blocos cheios de
--    propósito, então na partida "19 alocações" e "19 alunos alocados" são o
--    mesmo número — e uma view que contasse alunos distintos passaria por aqui
--    sem ninguém ver. O segundo bloco de Ana Paula é o que separa os dois, e é
--    a definição de aceleração (card 2.2).
select is(
  (select count(distinct ba.aluno_id)::bigint from public.bloco_aluno ba
     join public.bloco_horario b on b.id = ba.bloco_id
    where ba.unidade_id = (select unidade_a from t_ids) and ba.ativo),
  19::bigint,
  'premissa: na partida os 19 sao 19 alunos distintos — sem isto a assercao abaixo nao mede nada');

select tests.autenticar(tests.uid('secretaria@escola-a.test'));
select public.fn_bloco_admitir((select bloco_vazio from t_ids), (select ana from t_ids), 'REM');
reset role;

select is(
  (select format('%s/%s',
                 (select v.alocacoes from public.v_dashboard_tipos_bloco v
                   where v.unidade_id = (select unidade_a from t_ids)),
                 (select count(distinct ba.aluno_id) from public.bloco_aluno ba
                   where ba.unidade_id = (select unidade_a from t_ids) and ba.ativo))),
  '20/19',
  'em aceleracao o aluno conta DUAS vezes: 20 alocacoes para 19 alunos, que e o total REM/PRE da planilha');

-- E a alocação desativada sai da conta. Ela nunca se apaga (as duas tabelas de
-- alocação nasceram sem política de `delete`, card 5.1), então sem o `where
-- ba.ativo` o total cresceria para sempre, mesmo com a escola encolhendo.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));
select public.fn_bloco_remover((select bloco_vazio from t_ids), (select ana from t_ids),
                               'desfazendo a aceleracao do teste');
reset role;

select is(
  (select v.alocacoes from public.v_dashboard_tipos_bloco v
    where v.unidade_id = (select unidade_a from t_ids)),
  19,
  'alocacao desativada sai da conta — a linha continua na tabela, como historico');

-- ===========================================================================
-- 6. Paridade de linhas, silêncio e isolamento (card 2.8 §6.3)
-- ===========================================================================
-- "O perfil X lê a view sem erro" é asserção quase vazia: a RLS não devolve
-- erro, ela REDUZ LINHAS em silêncio. O teste correto é paridade, com a
-- contagem da direção garantidamente > 0.
--
-- ⚠️ `tests.encerrar_sessao()` primeiro: a seção 5 autenticou a secretaria, e
--    `tests.conta_como` sobre uma sessão já montada mediria a permissão errada
--    (a lição do `082` §4).
select tests.encerrar_sessao();

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e),
                             'select 1 from public.v_dashboard_alunos_metodo') as n
       from (values ('direcao@escola-a.test'), ('secretaria@escola-a.test'),
                    ('pedagogico@escola-a.test'), ('monitor@escola-a.test')) v(e)) x),
  1::bigint,
  'os quatro perfis contam os MESMOS metodos — o dashboard e de todos (card 2.4 §6)');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e),
                             'select 1 from public.v_dashboard_conclusoes_semestre') as n
       from (values ('direcao@escola-a.test'), ('secretaria@escola-a.test'),
                    ('pedagogico@escola-a.test'), ('monitor@escola-a.test')) v(e)) x),
  1::bigint,
  'idem nas conclusoes por semestre');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e),
                             'select 1 from public.v_dashboard_tipos_bloco') as n
       from (values ('direcao@escola-a.test'), ('secretaria@escola-a.test'),
                    ('pedagogico@escola-a.test'), ('monitor@escola-a.test')) v(e)) x),
  1::bigint,
  'idem nos tipos na turma');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_dashboard_alunos_metodo'),
  '>', 0::bigint,
  'a direcao ve linhas (a contagem de referencia da paridade e > 0, nao zero contra zero)');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_dashboard_alunos_metodo'),
  0::bigint,
  'quem nao tem perfil ve ZERO linha — e a rota e barrada antes, pelo guarda do card 3.7');

-- ⚠️ Isolamento medido nas TRÊS de uma vez: as duas escolas têm a mesma fixture,
--    e uma view que esquecesse o `unidade_id` no `group by` devolveria números
--    somados que parecem certos.
select is(
  (select tests.conta_como(tests.uid('direcao@escola-b.test'),
            'select 1 from public.v_dashboard_alunos_metodo v where v.unidade_id = '''
            || (select unidade_a from t_ids) || '''')
        + tests.conta_como(tests.uid('direcao@escola-b.test'),
            'select 1 from public.v_dashboard_conclusoes_semestre v where v.unidade_id = '''
            || (select unidade_a from t_ids) || '''')
        + tests.conta_como(tests.uid('direcao@escola-b.test'),
            'select 1 from public.v_dashboard_tipos_bloco v where v.unidade_id = '''
            || (select unidade_a from t_ids) || '''')),
  0::bigint,
  'a ESCOLA_B nao ve uma linha das tres views da ESCOLA_A, e as duas tem a mesma fixture');

select * from finish();
rollback;
