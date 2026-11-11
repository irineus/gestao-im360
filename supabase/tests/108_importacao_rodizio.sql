-- =============================================================================
-- Importação: a turma em rodízio no arquivo — card 9.2,91
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- O que este arquivo prova, e que os testes 100 a 102 não alcançam:
--
--   • **O ARQUIVO CARREGA O RODÍZIO INTEIRO.** Uma turma no segundo ciclo, um
--     aluno que entrou pelo terceiro módulo e já fez dois, outro que entrou
--     agora e outro que entrou para começar no próximo. Depois de aplicar, o
--     sistema responde o mesmo que responderia se tudo tivesse sido feito pelas
--     telas: o corrente é o do ciclo 2, o progresso do primeiro aluno é "2 de 3"
--     e o terceiro está esperando a entrada.
--
--   • **`modulo_entrada` AUSENTE NÃO APAGA.** Reimportar sem a chave não zera o
--     módulo de entrada gravado. Zerar não daria erro nenhum — só faria o
--     avanço seguinte tratar o aluno como quem já vinha estudando.
--
--   • **A IMPORTAÇÃO NÃO TROCA FATO POR PALPITE.** Módulo registrado pela turma
--     ou pela ficha tem data real; a do arquivo é a previsão da planilha. Só a
--     linha que veio de importação é atualizada por importação.
--
--   • **O ARQUIVO TORTO É DITO LINHA A LINHA**, e não descoberto na aplicação:
--     ciclo zero, cronograma repetido (o `on conflict` morreria cru), módulo de
--     entrada que não é do curso, módulo feito de aluno que não existe.
--
-- Roda com begin/rollback.
-- =============================================================================

begin;
select plan(31);

create temporary table t_arquivo (nome text primary key, dados jsonb);

-- A escola do rodízio. Curso de três módulos; a turma já deu a volta uma vez e
-- está no módulo 2 do ciclo 2.
--   RD-1 entrou pelo módulo 3 (ciclo 1), fez o 3 e o 1; falta o 2, que é o atual.
--   RD-2 entrou agora, pelo módulo 2, que é o corrente.
--   RD-3 entrou para começar no PRÓXIMO (módulo 3) e ainda não fez nada.
insert into t_arquivo values ('rodizio', $json$
{
  "sala": [{"nome": "Sala Rodízio", "tipo": "SALA_MODULAR", "capacidade_nominal": 10}],
  "material": [{"metodo": "MODULAR", "codigo": "RD01", "nome": "Livro Rodízio",
                "categoria": "APOSTILA"}],
  "curso": [{"metodo": "MODULAR", "nome": "Curso Rodízio"}],
  "modulo": [
    {"metodo": "MODULAR", "curso": "Curso Rodízio", "ordem": 1, "nome": "Rodízio 1", "material": "RD01"},
    {"metodo": "MODULAR", "curso": "Curso Rodízio", "ordem": 2, "nome": "Rodízio 2", "material": "RD01"},
    {"metodo": "MODULAR", "curso": "Curso Rodízio", "ordem": 3, "nome": "Rodízio 3", "material": "RD01"}],
  "aluno": [
    {"codigo": "RD-1", "nome": "Aluno Rodízio 1", "metodo": "MODULAR", "data_inicio": "2026-08-01"},
    {"codigo": "RD-2", "nome": "Aluno Rodízio 2", "metodo": "MODULAR", "data_inicio": "2026-10-01"},
    {"codigo": "RD-3", "nome": "Aluno Rodízio 3", "metodo": "MODULAR", "data_inicio": "2026-10-20"}],
  "turma_modular": [{"nome": "Turma Rodízio", "metodo": "MODULAR", "curso": "Curso Rodízio",
                     "sala": "Sala Rodízio", "capacidade": 10, "data_inicio": "2026-05-01"}],
  "turma_modular_modulo": [
    {"turma": "Turma Rodízio", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 1,
     "data_inicio": "2026-05-01", "prev_conclusao": "2026-05-31", "concluido": true},
    {"turma": "Turma Rodízio", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 2,
     "data_inicio": "2026-06-01", "prev_conclusao": "2026-07-31", "concluido": true},
    {"turma": "Turma Rodízio", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 3,
     "data_inicio": "2026-08-01", "prev_conclusao": "2026-08-31", "concluido": true},
    {"turma": "Turma Rodízio", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 1,
     "ciclo": 2, "data_inicio": "2026-09-01", "prev_conclusao": "2026-09-30", "concluido": true},
    {"turma": "Turma Rodízio", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 2,
     "ciclo": 2, "data_inicio": "2026-10-01", "prev_conclusao": "2026-11-20"},
    {"turma": "Turma Rodízio", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 3,
     "ciclo": 2}],
  "turma_modular_aluno": [
    {"turma": "Turma Rodízio", "aluno": "RD-1", "data_entrada": "2026-08-01", "modulo_entrada": 3},
    {"turma": "Turma Rodízio", "aluno": "RD-2", "data_entrada": "2026-10-01", "modulo_entrada": 2},
    {"turma": "Turma Rodízio", "aluno": "RD-3", "data_entrada": "2026-10-20", "modulo_entrada": 3}],
  "aluno_modulo": [
    {"aluno": "RD-1", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 3,
     "data_conclusao": "2026-08-31"},
    {"aluno": "RD-1", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 1,
     "data_conclusao": "2026-09-30"}]
}
$json$::jsonb);

-- A segunda carga do mesmo snapshot, com duas diferenças de propósito: o RD-1
-- vem SEM `modulo_entrada`, e as datas dos dois módulos feitos dele mudaram.
insert into t_arquivo values ('segunda', $json$
{
  "turma_modular_aluno": [
    {"turma": "Turma Rodízio", "aluno": "RD-1", "data_entrada": "2026-08-01"}],
  "aluno_modulo": [
    {"aluno": "RD-1", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 3,
     "data_conclusao": "2026-08-25"},
    {"aluno": "RD-1", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 1,
     "data_conclusao": "2026-09-25"}]
}
$json$::jsonb);

-- Um erro de cada família que este card acrescentou, mais o aviso de data.
insert into t_arquivo values ('torto', $json$
{
  "turma_modular_modulo": [
    {"turma": "Turma Rodízio", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 1,
     "ciclo": 0},
    {"turma": "Turma Rodízio", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 2,
     "ciclo": 3},
    {"turma": "Turma Rodízio", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 2,
     "ciclo": 3}],
  "turma_modular_aluno": [
    {"turma": "Turma Rodízio", "aluno": "RD-2", "modulo_entrada": 9},
    {"turma": "Turma Rodízio", "aluno": "RD-3", "modulo_entrada": "dois"}],
  "aluno_modulo": [
    {"aluno": "RD-2", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 1},
    {"aluno": "NAO-EXISTE", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 1,
     "data_conclusao": "2026-09-30"},
    {"aluno": "RD-2", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 9,
     "data_conclusao": "2026-09-30"},
    {"aluno": "RD-2", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 2,
     "data_conclusao": "31/02/2026"},
    {"aluno": "RD-3", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 1,
     "data_conclusao": "2026-12-15"},
    {"aluno": "RD-3", "metodo": "MODULAR", "curso": "Curso Rodízio", "modulo_ordem": 1,
     "data_conclusao": "2026-12-15"}]
}
$json$::jsonb);

grant select on t_arquivo to authenticated;

-- ===========================================================================
-- 1. A lista de entidades tem UMA fonte
-- ===========================================================================
select is(
  array_length(public.fn_importacao_entidades(), 1), 19,
  'sao dezenove entidades: as dezoito do card 9.1 e aluno_modulo'
);

select is(
  (select e.nome from unnest(public.fn_importacao_entidades()) with ordinality e(nome, n)
    where e.n = (select n + 1 from unnest(public.fn_importacao_entidades())
                                   with ordinality x(nome, n)
                  where x.nome = 'turma_modular_aluno')),
  'aluno_modulo',
  'aluno_modulo vem logo depois de turma_modular_aluno — a ordem da lista e a ordem de aplicacao'
);

select is(
  public.fn_importacao_totais_arquivo(
    '{"aluno_modulo": [{}, {}], "aluno": [{}]}'::jsonb) #>> '{aluno_modulo,arquivo}',
  '2',
  'os totais do arquivo contam aluno_modulo — a funcao le a lista unica'
);

-- ===========================================================================
-- 2. O arquivo do rodízio valida com UM aviso, o do aluno que ainda não começou
-- ===========================================================================
select tests.autenticar(tests.uid('direcao@escola-a.test'));

create temporary table t_lote as
  select public.fn_importacao_registrar('rodizio.json', '2026-11-01'::date,
           (select dados from t_arquivo where nome = 'rodizio')) as rodizio;

select is(
  (select i.status from public.importacao i where i.id = (select rodizio from t_lote)),
  'VALIDADA',
  'o arquivo do rodizio nasce VALIDADA'
);

select is(
  (select string_agg(o.codigo || ':' || o.valor, ',' order by o.codigo, o.valor)
     from public.importacao_ocorrencia o
    where o.importacao_id = (select rodizio from t_lote)),
  'ENTRADA_SEM_MODULO_FEITO:RD-3',
  'um aviso so: o RD-3 entrou pelo modulo 3, que nao e o corrente, e nao fez nada — o RD-1 fez, e o RD-2 entrou pelo corrente'
);

select is(
  (select o.severidade from public.importacao_ocorrencia o
    where o.importacao_id = (select rodizio from t_lote)),
  'AVISO',
  'e e AVISO: entrar para comecar no proximo modulo e situacao legitima'
);

-- ===========================================================================
-- 3. Aplicado, o sistema responde como se tudo tivesse sido feito pelas telas
-- ===========================================================================
create temporary table t_aplicacao as
  select public.fn_importacao_aplicar((select rodizio from t_lote), false) as r;

select is(
  (select r ->> 'status' from t_aplicacao), 'APLICADA',
  'a aplicacao devolve APLICADA'
);

select is(
  (select string_agg(tm.ciclo || '/' || m.ordem || '/' || tm.concluido, ','
                     order by tm.ciclo, m.ordem)
     from public.turma_modular_modulo tm
     join public.modulo m on m.id = tm.modulo_id
     join public.turma_modular t on t.id = tm.turma_id
    where t.nome = 'Turma Rodízio'),
  '1/1/true,1/2/true,1/3/true,2/1/true,2/2/false,2/3/false',
  'o cronograma entrou com os DOIS ciclos — sem o ciclo no arquivo, as seis linhas seriam tres'
);

select is(
  (select m.ordem::text || ' no ciclo ' || l.modulo_corrente_ciclo
     from public.v_turma_modular_lotacao l
     join public.modulo m on m.id = l.modulo_corrente_id
    where l.turma_nome = 'Turma Rodízio'),
  '2 no ciclo 2',
  'e o modulo corrente e o 2 do ciclo 2'
);

select is(
  (select string_agg(a.codigo_sgf || '=' || m.ordem, ',' order by a.codigo_sgf)
     from public.turma_modular_aluno ta
     join public.aluno a on a.id = ta.aluno_id
     join public.modulo m on m.id = ta.modulo_entrada_id
    where a.codigo_sgf like 'RD-%'),
  'RD-1=3,RD-2=2,RD-3=3',
  'cada aluno com o modulo em que entrou'
);

select is(
  (select string_agg(m.ordem || ':' || am.data_conclusao || ':' || am.origem, ','
                     order by am.data_conclusao)
     from public.aluno_modulo am
     join public.aluno a on a.id = am.aluno_id
     join public.modulo m on m.id = am.modulo_id
    where a.codigo_sgf = 'RD-1'),
  '3:2026-08-31:IMPORTACAO,1:2026-09-30:IMPORTACAO',
  'os dois modulos feitos do RD-1, com a data e a origem IMPORTACAO'
);

select is(
  (select (r #>> '{totais,aluno_modulo,aplicadas}')::integer from t_aplicacao), 2,
  'os totais dizem que duas linhas de aluno_modulo foram aplicadas'
);

select is(
  (select (r #>> '{totais,no_sistema,aluno_modulo}')::integer from t_aplicacao),
  (select count(*)::integer from public.aluno_modulo
    where unidade_id = public.fn_unidade_atual()),
  'e no_sistema conta aluno_modulo'
);

-- O progresso é DERIVADO, e é ele que prova que o que entrou faz sentido junto.
select is(
  (select p.modulos_feitos || ' de ' || p.modulos_total || ', falta ' || p.proximo_modulo_nome
     from public.v_aluno_modular_progresso p
    where p.aluno_nome = 'Aluno Rodízio 1'),
  '2 de 3, falta Rodízio 2',
  'o RD-1 fez 2 de 3 e falta-lhe o modulo em curso'
);

select is(
  (select string_agg(p.aluno_nome, ',' order by p.aluno_nome)
     from public.v_aluno_modular_progresso p
    where p.turma_nome = 'Turma Rodízio' and p.aguardando_entrada),
  'Aluno Rodízio 3',
  'so o RD-3 esta esperando a entrada — o RD-2 entrou pelo corrente e o RD-1 ja vinha estudando'
);

-- ===========================================================================
-- 4. O avanço seguinte trata cada um como deve
-- ===========================================================================
-- É para isto que o módulo de entrada e os módulos feitos existem: fechar o
-- módulo 2 dá o módulo ao RD-1 (que com ele CONCLUI o curso e sai) e ao RD-2, e
-- NÃO ao RD-3, que entrou para começar no próximo.
create temporary table t_avanco as
  select public.fn_turma_modular_avancar(
           (select t.id from public.turma_modular t where t.nome = 'Turma Rodízio'),
           '2026-11-20'::date) as proximo;

select is(
  (select string_agg(a.codigo_sgf, ',' order by a.codigo_sgf)
     from public.aluno_modulo am
     join public.aluno a on a.id = am.aluno_id
     join public.modulo m on m.id = am.modulo_id
    where m.nome = 'Rodízio 2' and am.origem = 'TURMA'),
  'RD-1,RD-2',
  'o avanco deu o modulo 2 ao RD-1 e ao RD-2, e NAO ao RD-3'
);

select is(
  (select string_agg(a.codigo_sgf, ',' order by a.codigo_sgf)
     from public.turma_modular_aluno ta
     join public.aluno a on a.id = ta.aluno_id
    where a.codigo_sgf like 'RD-%' and ta.ativo),
  'RD-2,RD-3',
  'e o RD-1, que completou os tres modulos, saiu da turma por conclusao'
);

-- ===========================================================================
-- 5. A segunda carga: não duplica, não apaga o módulo de entrada, não troca
--    fato por palpite
-- ===========================================================================
-- O RD-1 volta para a turma (a planilha ainda o traz) — e SEM `modulo_entrada`.
-- O módulo 1 dele passa a ser um registro da FICHA, como se alguém o tivesse
-- corrigido à mão; o 3 continua sendo de importação.
reset role;
update public.aluno_modulo am
   set origem = 'MANUAL'
  from public.aluno a, public.modulo m
 where a.id = am.aluno_id and m.id = am.modulo_id
   and a.codigo_sgf = 'RD-1' and m.nome = 'Rodízio 1';
select tests.autenticar(tests.uid('direcao@escola-a.test'));

create temporary table t_segunda as
  select public.fn_importacao_registrar('rodizio-2.json', '2026-11-01'::date,
           (select dados from t_arquivo where nome = 'segunda')) as id;

create temporary table t_aplicacao2 as
  select public.fn_importacao_aplicar((select id from t_segunda), false) as r;

select is(
  (select r ->> 'status' from t_aplicacao2), 'APLICADA',
  'a segunda carga aplica'
);

select is(
  (select count(*)::integer from public.aluno_modulo am
     join public.aluno a on a.id = am.aluno_id
    where a.codigo_sgf = 'RD-1'),
  3,
  'o RD-1 continua com tres modulos — a segunda carga nao duplicou nenhum'
);

select is(
  (select am.data_conclusao::text from public.aluno_modulo am
     join public.aluno a on a.id = am.aluno_id
     join public.modulo m on m.id = am.modulo_id
    where a.codigo_sgf = 'RD-1' and m.nome = 'Rodízio 3'),
  '2026-08-25',
  'o modulo que veio de IMPORTACAO recebe a data nova do arquivo'
);

select is(
  (select am.data_conclusao::text || ':' || am.origem from public.aluno_modulo am
     join public.aluno a on a.id = am.aluno_id
     join public.modulo m on m.id = am.modulo_id
    where a.codigo_sgf = 'RD-1' and m.nome = 'Rodízio 1'),
  '2026-09-30:MANUAL',
  'o que a FICHA registrou fica como estava — a importacao nao troca fato por palpite'
);

select is(
  (select (r #>> '{totais,aluno_modulo,aplicadas}')::integer from t_aplicacao2), 1,
  'e os totais dizem a verdade: UMA linha aplicada, e nao duas'
);

-- ⚠️ O RD-1 foi readmitido por ESTA carga, numa alocação nova — a anterior saiu
-- por conclusão. O que se mede é o RD-2, que já estava: uma carga sem a chave
-- não pode apagar o módulo de entrada dele.
create temporary table t_terceira as
  select public.fn_importacao_registrar('rodizio-3.json', '2026-11-01'::date,
           '{"turma_modular_aluno": [{"turma": "Turma Rodízio", "aluno": "RD-2"}]}'::jsonb) as id;

select is(
  (select public.fn_importacao_aplicar((select id from t_terceira), false) ->> 'status'),
  'APLICADA',
  'uma carga so com a alocacao do RD-2, sem modulo_entrada, aplica'
);

select is(
  (select m.ordem from public.turma_modular_aluno ta
     join public.aluno a on a.id = ta.aluno_id
     join public.modulo m on m.id = ta.modulo_entrada_id
    where a.codigo_sgf = 'RD-2' and ta.ativo),
  2,
  'e o modulo de entrada do RD-2 continua o 2 — ausente no arquivo e "nao sei", nao "nenhum"'
);

-- ===========================================================================
-- 6. O arquivo torto: cada defeito dito na linha dele, antes de aplicar
-- ===========================================================================
create temporary table t_torto as
  select public.fn_importacao_registrar('torto.json', '2026-11-01'::date,
           (select dados from t_arquivo where nome = 'torto')) as id;

select is(
  (select i.status from public.importacao i where i.id = (select id from t_torto)),
  'REPROVADA',
  'o arquivo torto nasce REPROVADA'
);

select is(
  (select string_agg(o.entidade || ':' || o.codigo || ':' || coalesce(o.linha::text, '-'), ','
                     order by o.entidade, o.codigo, o.linha)
     from public.importacao_ocorrencia o
    where o.importacao_id = (select id from t_torto)
      and o.severidade = 'ERRO'
      and o.entidade = 'turma_modular_modulo'),
  'turma_modular_modulo:CHAVE_DUPLICADA:-,turma_modular_modulo:VALOR_INVALIDO:1',
  'cronograma: ciclo zero e invalido (linha 1) e o modulo repetido no mesmo ciclo e chave duplicada'
);

select is(
  (select string_agg(o.codigo || ':' || o.linha, ',' order by o.codigo, o.linha)
     from public.importacao_ocorrencia o
    where o.importacao_id = (select id from t_torto)
      and o.severidade = 'ERRO'
      and o.entidade = 'turma_modular_aluno'),
  'REFERENCIA_AUSENTE:1,VALOR_INVALIDO:2',
  'alocacao: o modulo 9 nao existe no curso da turma (linha 1) e "dois" nao e numero (linha 2)'
);

select is(
  (select string_agg(o.codigo || ':' || coalesce(o.linha::text, '-'), ','
                     order by o.codigo, o.linha)
     from public.importacao_ocorrencia o
    where o.importacao_id = (select id from t_torto)
      and o.severidade = 'ERRO'
      and o.entidade = 'aluno_modulo'),
  'CAMPO_OBRIGATORIO:1,CHAVE_DUPLICADA:-,DATA_INVALIDA:4,REFERENCIA_AUSENTE:2,REFERENCIA_AUSENTE:3',
  'modulo feito: sem data (1), aluno inexistente (2), modulo inexistente (3), data torta (4) e a linha repetida'
);

select is(
  (select count(*)::integer from public.importacao_ocorrencia o
    where o.importacao_id = (select id from t_torto)
      and o.codigo = 'MODULO_DATA_FUTURA' and o.severidade = 'AVISO'),
  2,
  'e o modulo "feito" em dezembro, com snapshot de novembro, e AVISO nas duas linhas — ainda nao terminou'
);

-- `reset role` antes de tocar em `tests.*`: depois de tests.autenticar o schema
-- `tests` é inalcançável (o mesmo cuidado do teste 100).
reset role;

select is(
  tests.codigo_do_erro(
    format('select public.fn_importacao_aplicar(%L::uuid, false)', (select id from t_torto)),
    tests.uid('direcao@escola-a.test')),
  'IMPORTACAO_REPROVADA',
  'lote reprovado nao aplica'
);

-- O cronograma que o arquivo torto trazia NÃO entrou: a turma continua com as
-- linhas de antes (seis do arquivo, mais as que o avanço abriu).
select is(
  (select count(*)::integer from public.turma_modular_modulo tm
     join public.turma_modular t on t.id = tm.turma_id
    where t.nome = 'Turma Rodízio' and tm.ciclo = 3),
  0,
  'e nada do arquivo torto foi gravado: nao ha ciclo 3 na turma'
);

select * from finish();
rollback;
