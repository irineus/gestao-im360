-- =============================================================================
-- Importação — card 9.1 (a tela 13, e as duas funções que ela chama)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Obrigação de **Tela** com objeto de banco próprio (§13): o conjunto da rota
-- medido por PARIDADE (§6.3), a função exercitada de ponta a ponta e a
-- reexecutabilidade — que é pré-condição (3) do card 9.7 e linha própria do §14
-- («importar duas vezes o mesmo snapshot produz os mesmos totais, sem duplicar»).
--
-- Quatro propriedades que este arquivo prova e que nenhum catálogo enxerga:
--
--   • **A SIMULAÇÃO NÃO ESCREVE.** `fn_importacao_aplicar(id, true)` passa por
--     todos os dezoito passos, colhe os totais que os TRIGGERS REAIS produziram
--     e desfaz a subtransação. A seção 4 conta as linhas antes e depois: se um
--     dia alguém trocar a subtransação por uma segunda implementação da conta,
--     as contagens deixam de bater e não há como o teste passar por engano.
--
--   • **A SEGUNDA IMPORTAÇÃO DO MESMO SNAPSHOT NÃO DUPLICA NADA.** Dezessete
--     entidades se reconhecem por chave natural; `movimento_estoque`, que não
--     tem nenhuma e é IMUTÁVEL, se reconhece pelo mapa `importacao_referencia`.
--     A seção 6 aplica o mesmo arquivo de novo e exige `no_sistema` idêntico.
--
--   • **ERRO DE TRIGGER DESFAZ TUDO E VIRA RELATÓRIO.** A seção 7 importa dois
--     alunos para um bloco de duas vagas com uma ocupada. `tg_bloco_aluno_
--     admissao` recusa, a transação inteira volta — os DOIS alunos somem, não só
--     o segundo — e o lote fica FALHOU com o código do trigger na ocorrência.
--
--   • **A TRILHA NÃO É REIMPLEMENTADA.** O aluno entra com combo e quem gera a
--     trilha é `tg_aluno_trilha_inicial` (card 6.2), no mesmo insert. O arquivo
--     traz UMA linha de `aluno_material` e o sistema fica com QUATRO: duas por
--     aluno, vindas do combo. É a seção 5 que mede isso.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(33);

-- ---------------------------------------------------------------------------
-- Os três arquivos, em um lugar só (card 2.8 §11: nada de literal solto).
-- TABELA temporária e não view, pelo motivo do 081/083: a seção 3 lê isto já em
-- `authenticated`, e de lá o schema `tests` é inalcançável.
-- ---------------------------------------------------------------------------
create temporary table t_arquivo (nome text primary key, dados jsonb);

insert into t_arquivo values ('limpo', $json$
{
  "professor": [{"nome": "Prof. Importado"}],
  "sala": [{"nome": "Sala Importada", "tipo": "LABORATORIO", "capacidade_nominal": 4}],
  "pc": [{"sala": "Sala Importada", "identificador": "PC-IMP-01"},
         {"sala": "Sala Importada", "identificador": "PC-IMP-02"},
         {"sala": "Sala Importada", "identificador": "PC-IMP-03", "status": "MANUTENCAO"}],
  "material": [{"metodo": "INTERATIVO", "codigo": "IMP01", "nome": "Apostila Importada 1",
                "categoria": "APOSTILA", "estoque_minimo": 2},
               {"metodo": "INTERATIVO", "codigo": "IMP02", "nome": "Apostila Importada 2",
                "categoria": "APOSTILA"}],
  "curso": [{"metodo": "INTERATIVO", "nome": "Curso Importado"}],
  "curso_material": [{"metodo": "INTERATIVO", "curso": "Curso Importado", "material": "IMP01", "ordem": 1},
                     {"metodo": "INTERATIVO", "curso": "Curso Importado", "material": "IMP02", "ordem": 2}],
  "combo": [{"metodo": "INTERATIVO", "nome": "Combo Importado"}],
  "combo_curso": [{"combo": "Combo Importado", "metodo": "INTERATIVO",
                   "curso": "Curso Importado", "ordem": 1}],
  "aluno": [{"codigo": "IMP-9001", "nome": "Aluno Importado 1", "metodo": "INTERATIVO",
             "combo": "Combo Importado", "data_inicio": "2026-02-01",
             "prev_conclusao_curso": "2026-12-01"},
            {"codigo": "IMP-9002", "nome": "Aluno Importado 2", "metodo": "INTERATIVO",
             "combo": "Combo Importado", "data_inicio": "2026-02-01",
             "prev_conclusao_curso": "2020-01-01"}],
  "bloco_horario": [{"dia_semana": 2, "hora_inicio": "09:00", "metodo": "INTERATIVO",
                     "sala": "Sala Importada", "professor": "Prof. Importado"}],
  "bloco_aluno": [{"aluno": "IMP-9001", "sala": "Sala Importada", "dia_semana": 2,
                   "hora_inicio": "09:00", "tipo": "REM"}],
  "aluno_material": [{"aluno": "IMP-9001", "metodo": "INTERATIVO", "material": "IMP01",
                      "ordem": 1, "entregue": true, "data_entrega": "2026-03-02"}],
  "movimento_estoque": [{"chave": "E-IMP01-1", "metodo": "INTERATIVO", "material": "IMP01",
                         "tipo": "ENTRADA", "quantidade": 10, "ocorrido_em": "2026-03-01"},
                        {"chave": "S-IMP01-9001", "metodo": "INTERATIVO", "material": "IMP01",
                         "tipo": "SAIDA", "quantidade": -1, "ocorrido_em": "2026-03-02",
                         "aluno": "IMP-9001"}]
}
$json$::jsonb);

-- Um erro de cada família das dezesseis verificações que BLOQUEIAM.
insert into t_arquivo values ('torto', $json$
{
  "aluno": [{"codigo": "", "nome": "Sem código", "metodo": "INTERATIVO"},
            {"codigo": "IMP-9003", "nome": "Duplicado", "metodo": "INTERATIVO"},
            {"codigo": "IMP-9003", "nome": "Duplicado de novo", "metodo": "MARCIANO"}],
  "bloco_aluno": [{"aluno": "NAO-EXISTE", "sala": "Sala Importada", "dia_semana": 2,
                   "hora_inicio": "09:00", "tipo": "XPTO"}],
  "movimento_estoque": [{"chave": "S-IMP01-NEG", "metodo": "INTERATIVO", "material": "IMP01",
                         "tipo": "SAIDA", "quantidade": -999, "ocorrido_em": "2026-03-05"}],
  "aba_nova_da_planilha": []
}
$json$::jsonb);

-- O arquivo que consome o saldo até ZERO. Existe por causa de uma contraprova
-- que PASSOU VERDE em 06/09/2026: a verificação V10 (saldo negativo) ignora os
-- movimentos que uma importação anterior já gravou, e removê-la não quebrava
-- nada — porque, com material NOVO, o saldo depois da primeira carga é
-- exatamente a soma do arquivo, e `S + S` nunca é negativo quando `S` não é.
-- O caso só se separa quando o material JÁ TEM saldo de outra origem e o arquivo
-- só o consome: aí a segunda leitura do mesmo arquivo veria 0 + (−9).
insert into t_arquivo values ('consome', $json$
{
  "movimento_estoque": [{"chave": "S-IMP01-CONSOME", "metodo": "INTERATIVO", "material": "IMP01",
                         "tipo": "SAIDA", "quantidade": -9, "ocorrido_em": "2026-03-10"}]
}
$json$::jsonb);

-- Dois alunos para um bloco com DUAS vagas e uma ocupada. Passa na validação de
-- propósito: capacidade não se confere aqui — quem a confere é o trigger, que
-- tem a única implementação de fn_capacidade_efetiva.
insert into t_arquivo values ('lotado', $json$
{
  "aluno": [{"codigo": "IMP-9004", "nome": "Aluno Importado 4", "metodo": "INTERATIVO"},
            {"codigo": "IMP-9005", "nome": "Aluno Importado 5", "metodo": "INTERATIVO"}],
  "bloco_aluno": [{"aluno": "IMP-9004", "sala": "Sala Importada", "dia_semana": 2,
                   "hora_inicio": "09:00", "tipo": "REM"},
                  {"aluno": "IMP-9005", "sala": "Sala Importada", "dia_semana": 2,
                   "hora_inicio": "09:00", "tipo": "REM"}]
}
$json$::jsonb);

grant select on t_arquivo to authenticated;

-- ===========================================================================
-- 1. O guarda: o conjunto exato da rota 13, e por que ele é da direção
-- ===========================================================================
-- `admin.ler` é o que separa: os quatorze códigos de escrita do conjunto a
-- secretaria também tem (permissoes-matriz.md §5). Sem ele no conjunto, a tela
-- que carrega a escola inteira abriria para ela.
select is(
  (select count(*)::integer from unnest(public.fn_importacao_conjunto())), 15,
  'o conjunto da rota 13 tem os 15 codigos que o card 9.1 fixou'
);

select is(
  (select bool_and(exists (select 1 from public.permissao p
                            where p.codigo = c.codigo))
     from unnest(public.fn_importacao_conjunto()) as c(codigo)),
  true,
  'todo codigo do conjunto EXISTE no catalogo — nenhum inventado aqui'
);

select is(
  (select string_agg(u.perfil, ',' order by u.perfil)
     from (values ('DIRECAO',    'direcao@escola-a.test'),
                  ('MONITOR',    'monitor@escola-a.test'),
                  ('PEDAGOGICO', 'pedagogico@escola-a.test'),
                  ('SECRETARIA', 'secretaria@escola-a.test')) u(perfil, email)
    where tests.conta_como(tests.uid(u.email),
            'select 1 where public.fn_importacao_pode()') = 1),
  'DIRECAO',
  'so a direcao passa por fn_importacao_pode — a secretaria tem os quatorze de escrita e nao tem admin.ler'
);

select is(
  tests.codigo_do_erro(
    $sql$ select public.fn_importacao_registrar('x.json', '2026-08-29'::date, '{"aluno":[]}'::jsonb) $sql$,
    tests.uid('secretaria@escola-a.test')),
  'SEM_PERMISSAO',
  'a secretaria recebe SEM_PERMISSAO com o codigo que falta, nao um 42501 cru na decima setima entidade'
);

-- ===========================================================================
-- 2. Registro e validação do arquivo limpo — três avisos, nenhum erro
-- ===========================================================================
select tests.autenticar(tests.uid('direcao@escola-a.test'));

create temporary table t_lote as
  select public.fn_importacao_registrar('planilha-2026-08-29.json', '2026-08-29'::date,
           (select dados from t_arquivo where nome = 'limpo')) as limpo;

select is(
  (select i.status from public.importacao i
    where i.id = (select limpo from t_lote)),
  'VALIDADA',
  'arquivo sem erro nasce VALIDADA'
);

-- Os três avisos são exatamente os três casos que o §16 desenha como ⚠, e cada
-- um vem de uma verificação diferente: V11, V12 e V14.
select is(
  (select string_agg(distinct o.codigo, ',' order by o.codigo)
     from public.importacao_ocorrencia o
    where o.importacao_id = (select limpo from t_lote)),
  'ALUNO_SEM_TURMA,PC_SEM_MANUTENCAO,PREVISAO_ATIPICA',
  'os tres avisos do arquivo limpo, e nenhum erro junto'
);

select is(
  (select o.valor from public.importacao_ocorrencia o
    where o.importacao_id = (select limpo from t_lote)
      and o.codigo = 'ALUNO_SEM_TURMA'),
  'IMP-9002',
  'sem turma e o 9002 — o 9001 esta no bloco, e a verificacao olha o arquivo inteiro'
);

-- A previsão atípica é medida contra o SNAPSHOT, não contra hoje: a mesma
-- planilha não pode mudar de veredito conforme o dia em que alguém a importa.
select is(
  (select o.valor from public.importacao_ocorrencia o
    where o.importacao_id = (select limpo from t_lote)
      and o.codigo = 'PREVISAO_ATIPICA'),
  '2020-01-01',
  'previsao de 2020 contra snapshot de 2026 e atipica; a de 2026-12 nao e'
);

-- ===========================================================================
-- 3. A simulação escreve tudo e desfaz
-- ===========================================================================
create temporary table t_antes as
  select (select count(*) from public.aluno    where unidade_id = public.fn_unidade_atual()) as alunos,
         (select count(*) from public.material where unidade_id = public.fn_unidade_atual()) as materiais,
         (select count(*) from public.movimento_estoque
           where unidade_id = public.fn_unidade_atual()) as movimentos;

create temporary table t_simulacao as
  select public.fn_importacao_aplicar((select limpo from t_lote), true) as r;

select is(
  (select r ->> 'status' from t_simulacao), 'SIMULADA',
  'a simulacao devolve SIMULADA'
);

select is(
  (select (r #>> '{totais,no_sistema,aluno}')::integer from t_simulacao),
  (select alunos::integer + 2 from t_antes),
  'os totais da simulacao ja contam os dois alunos importados — ela escreveu de verdade'
);

select is(
  (select count(*)::integer from public.aluno
    where unidade_id = public.fn_unidade_atual()),
  (select alunos::integer from t_antes),
  'e depois da simulacao nao sobrou NENHUM deles: a subtransacao voltou'
);

select is(
  (select count(*)::integer from public.movimento_estoque
    where unidade_id = public.fn_unidade_atual()),
  (select movimentos::integer from t_antes),
  'nem os movimentos, que sao imutaveis e nao teriam volta'
);

select isnt(
  (select i.simulado_em from public.importacao i where i.id = (select limpo from t_lote)),
  null,
  'o carimbo da simulacao fica: ele e escrito FORA do bloco que voltou'
);

-- ===========================================================================
-- 4. A aplicação de verdade
-- ===========================================================================
create temporary table t_aplicacao as
  select public.fn_importacao_aplicar((select limpo from t_lote), false) as r;

select is(
  (select r ->> 'status' from t_aplicacao), 'APLICADA',
  'a aplicacao devolve APLICADA'
);

select is(
  (select i.status from public.importacao i where i.id = (select limpo from t_lote)),
  'APLICADA',
  'e o lote fica APLICADA'
);

select is(
  (select count(*)::integer from public.aluno
    where unidade_id = public.fn_unidade_atual() and codigo_sgf like 'IMP-%'),
  2,
  'os dois alunos entraram'
);

-- A trilha NÃO veio do arquivo: veio do combo, por tg_aluno_trilha_inicial. O
-- arquivo traz UMA linha de aluno_material e o sistema fica com QUATRO.
select is(
  (select count(*)::integer from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.codigo_sgf like 'IMP-%'),
  4,
  'a trilha dos dois alunos nasceu do combo — a importacao nao a reimplementa'
);

select is(
  (select am.data_entrega::text from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
     join public.material m on m.id = am.material_id
    where a.codigo_sgf = 'IMP-9001' and m.codigo = 'IMP01'),
  '2026-03-02',
  'e o que o arquivo traz e o ESTADO DE ENTREGA dessa trilha'
);

-- O número que se compara com o Dashboard da planilha (card 9.4).
select is(
  (select (r #>> '{totais,no_sistema,movimento_estoque}')::integer from t_aplicacao),
  (select count(*)::integer from public.movimento_estoque
    where unidade_id = public.fn_unidade_atual()),
  'no_sistema conta o que EXISTE, e e por isso que ele serve de conferencia'
);

-- ⚠️ `reset role` antes de tocar em `tests.*`: depois de tests.autenticar a
--    sessão está em `authenticated`, e de lá o schema `tests` é inalcançável
--    (seed.sql §0). E o usuário VAI no segundo argumento — sem ele a função
--    rodaria como `postgres`, sem JWT, e o erro seria SEM_PERMISSAO em vez do
--    que se quer medir.
reset role;

select is(
  tests.codigo_do_erro(format(
    $sql$ select public.fn_importacao_aplicar(%L::uuid, false) $sql$,
    (select limpo from t_lote)),
    tests.uid('direcao@escola-a.test')),
  'IMPORTACAO_JA_APLICADA',
  'aplicar o MESMO lote duas vezes e recusado — reexecutar snapshot e enviar o arquivo de novo'
);

-- ===========================================================================
-- 5. Reexecutabilidade: o mesmo snapshot, de novo, sem duplicar nada
--    (pré-condição (3) do card 9.7 e linha própria do §14 da estratégia)
-- ===========================================================================
reset role;
select tests.autenticar(tests.uid('direcao@escola-a.test'));

create temporary table t_repeticao as
  select public.fn_importacao_aplicar(
           public.fn_importacao_registrar('planilha-2026-08-29.json', '2026-08-29'::date,
             (select dados from t_arquivo where nome = 'limpo')),
           false) as r;

select is(
  (select r #> '{totais,no_sistema}' from t_repeticao),
  (select r #> '{totais,no_sistema}' from t_aplicacao),
  'segunda importacao do mesmo snapshot: totais no_sistema IDENTICOS aos da primeira'
);

select is(
  (select count(*)::integer from public.movimento_estoque mv
     join public.material m on m.id = mv.material_id
    where m.codigo = 'IMP01'),
  2,
  'o movimento imutavel nao duplicou — quem o reconhece e o mapa importacao_referencia'
);

-- O saldo de IMP01 é 9 (entrada 10, saída 1). O arquivo 'consome' o zera; lido
-- de novo, ele NÃO pode acusar saldo negativo, porque a saída que ele traz é a
-- mesma que já está no saldo. É o único par que separa a V10 correta da V10 que
-- soma duas vezes o mesmo movimento.
create temporary table t_consome as
  select public.fn_importacao_aplicar(
           public.fn_importacao_registrar('consome.json', '2026-08-29'::date,
             (select dados from t_arquivo where nome = 'consome')),
           false) as r;

select is(
  (select r ->> 'status' from t_consome), 'APLICADA',
  'a saida que zera o saldo entra: 9 + (-9) = 0, e zero nao e negativo'
);

-- ⚠️ O lote nasce numa tabela temporária ANTES da asserção, e não dentro do
--    `where`: `fn_importacao_registrar` é VOLÁTIL, e no `where` o planejador a
--    executa uma vez POR LINHA de `importacao` — cada chamada criando um lote
--    novo e comparando com um id diferente. O resultado é NULL, e um NULL aqui
--    passaria por "reprovada" na leitura apressada de quem estiver depurando.
create temporary table t_consome_de_novo as
  select public.fn_importacao_registrar('consome.json', '2026-08-29'::date,
           (select dados from t_arquivo where nome = 'consome')) as id;

select is(
  (select i.status from public.importacao i
    where i.id = (select id from t_consome_de_novo)),
  'VALIDADA',
  'e o MESMO arquivo lido de novo continua VALIDADA — a V10 desconta o que ja foi gravado'
);

-- ===========================================================================
-- 6. O arquivo torto: um erro de cada família, e a recusa de aplicar
-- ===========================================================================
create temporary table t_torto as
  select public.fn_importacao_registrar('planilha-torta.json', '2026-08-29'::date,
           (select dados from t_arquivo where nome = 'torto')) as id;

select is(
  (select i.status from public.importacao i where i.id = (select id from t_torto)),
  'REPROVADA',
  'arquivo com erro nasce REPROVADA'
);

select is(
  (select string_agg(distinct o.codigo, ',' order by o.codigo)
     from public.importacao_ocorrencia o
    where o.importacao_id = (select id from t_torto) and o.severidade = 'ERRO'),
  'CAMPO_OBRIGATORIO,CHAVE_DUPLICADA,REFERENCIA_AUSENTE,SALDO_NEGATIVO,VALOR_INVALIDO',
  'as cinco familias de erro do arquivo torto, todas no MESMO relatorio'
);

-- A aba nova que o extrator do card 9.2 inventar não passa em silêncio.
select is(
  (select o.entidade from public.importacao_ocorrencia o
    where o.importacao_id = (select id from t_torto)
      and o.codigo = 'ENTIDADE_DESCONHECIDA'),
  'aba_nova_da_planilha',
  'entidade que a importacao nao conhece vira AVISO, nao silencio'
);

reset role;

select is(
  tests.codigo_do_erro(format(
    $sql$ select public.fn_importacao_aplicar(%L::uuid, false) $sql$,
    (select id from t_torto)),
    tests.uid('direcao@escola-a.test')),
  'IMPORTACAO_REPROVADA',
  'lote com ERRO nao aplica, nem simulado nem de verdade'
);

-- ===========================================================================
-- 7. O trigger recusa: tudo volta, e o motivo vira relatório
-- ===========================================================================
reset role;
select tests.autenticar(tests.uid('direcao@escola-a.test'));

create temporary table t_lotado as
  select public.fn_importacao_registrar('planilha-lotada.json', '2026-08-29'::date,
           (select dados from t_arquivo where nome = 'lotado')) as id;

create temporary table t_falha as
  select public.fn_importacao_aplicar((select id from t_lotado), false) as r;

select is(
  (select r ->> 'codigo' from t_falha), 'BLOCO_LOTADO',
  'a capacidade e conferida pelo TRIGGER, e o codigo dele chega ao relatorio'
);

select is(
  (select count(*)::integer from public.aluno where codigo_sgf in ('IMP-9004', 'IMP-9005')),
  0,
  'e os DOIS alunos sumiram: a transacao inteira voltou, nao so a linha recusada'
);

select is(
  (select i.status from public.importacao i where i.id = (select id from t_lotado)),
  'FALHOU',
  'o lote fica FALHOU — estado que so existe porque a excecao NAO subiu'
);

-- ===========================================================================
-- 8. Paridade de leitura (§6.3): quem não pode importar não vê lote nenhum
-- ===========================================================================
reset role;

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
    'select 1 from public.v_importacao'),
  '>=', 3::bigint,
  'a direcao ve os lotes desta unidade'
);

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
    'select 1 from public.v_importacao')
  + tests.conta_como(tests.uid('monitor@escola-a.test'),
    'select 1 from public.v_importacao')
  + tests.conta_como(tests.uid('pedagogico@escola-a.test'),
    'select 1 from public.v_importacao')
  + tests.conta_como(tests.uid('direcao@escola-b.test'),
    'select 1 from public.v_importacao'),
  0::bigint,
  'os outros tres perfis E a direcao da outra unidade veem ZERO — RLS por conjunto e por unidade'
);

select * from finish();
rollback;
