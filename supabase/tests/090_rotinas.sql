-- =============================================================================
-- Pendências e a rotina diária — card 5.5
-- (mapa suíte → card: docs/estrategia-testes.md §17 — `090_rotinas` nasce aqui,
--  com a primeira rotina do projeto, e cresce no card 8.1)
--
-- Card de "Schema/migração" com rotina dentro, então o §13 cobra as duas
-- metades: o schema (RLS, políticas, dedup) e o COMPORTAMENTO da regra — abrir,
-- não duplicar, fechar sozinha e reabrir. As quatro são propriedades da mesma
-- função, e é a quarta que quase ninguém escreve.
--
-- Quatro coisas que este arquivo prova e que nenhum catálogo enxerga:
--   • a rotina FECHA o que deixou de ser verdade, e fecha POR CHAVE: fechar por
--     tipo levaria junto a pendência do aluno ao lado, e a lista passaria a
--     esconder o que devia mostrar;
--   • a rotina REABRE o que continua verdadeiro, inclusive o que alguém IGNOROU
--     — é decisão, não descuido, e está escrita na seção 6 da migração;
--   • a contagem da aceleração filtra `tipo <> 'REP'` (ajuste 4 do card 2.5),
--     com CONTRAPROVA: o mesmo aluno com dois blocos de verdade não abre
--     pendência nenhuma. Sem a contraprova, a asserção passaria com o filtro
--     escrito ao contrário;
--   • o SUFIXO da chave REP é o que permite as duas sugestões coexistirem. A
--     asserção mede o descarte silencioso que aconteceria sem ele.
--
-- A fixture NÃO tem camada de pendência, e é decisão: pendência não se semeia e
-- não se importa — é GERADA pela rotina a partir do dado do ambiente (Notas do
-- card 5.5). Uma camada de fixture com pendências escritas à mão faria a suíte
-- medir o que ela mesma escreveu.
--
-- ⚠️ Os dois alunos da fixture SEM turma são de método MODULAR e INGLES, e os
--    três blocos são INTERATIVO: admiti-los daria METODO_INCOMPATIVEL. Por isso
--    a seção 4 abre e fecha a pendência TIRANDO e devolvendo um aluno que já
--    está numa turma — o que de quebra exercita o caminho mais realista, o da
--    condição que aparece e some.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
-- 60 → 67 no card 8.4,5 (05/09/2026): a §17, do alerta de ESTADO do MATERIAL,
-- mais a asserção-espelho do §2 — que existia só para pendência de aluno e por
-- isso não teria reprovado nada com um tipo de material acrescentado à rotina.
--
-- Era 60 desde o card 8.4 (as §15 e §16, dos dois alertas de TEMPO do aluno) e
-- 49 desde o card 7.1, por coincidência aritmética que vale explicar: o portão
-- condicional do §13 perdeu uma asserção (três viraram duas, porque a tabela que
-- ele esperava passou a existir) e o §2 ganhou uma, a que fixa por que Eduarda
-- Lima saiu da lista de ALUNO_SEM_TURMA.
select plan(67);

-- ===========================================================================
-- 1. As premissas da fixture, que dão sentido a todos os números de baixo
-- ===========================================================================
-- Contexto de rotina: as rt_* o exigem (fn_unidade_atual é nula para `postgres`
-- sem sessão), e é nele que a rotina de verdade roda.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

select is(
  (select string_agg(a.nome, ', ' order by a.nome)
     from public.aluno a
    where a.unidade_id = tests.unidade('ESCOLA_A')
      and a.status in ('ATIVO', 'ACELERAR')
      and not exists (select 1 from public.bloco_aluno ba
                       where ba.aluno_id = a.id and ba.ativo)),
  'Aluno Modular 01, Eduarda Lima, Felipe Nunes',
  'fixture: exatamente tres alunos ATIVO/ACELERAR sem bloco — os dois MODULAR e Felipe (ACELERAR)');

-- ⚠️ MUDOU NO CARD 5.4, e a mudança é o contrário de um relaxamento. Até aqui a
--    fixture nascia sem pendência nenhuma. Com o trigger tg_pc_revalida_blocos,
--    o `insert` em `pc_manutencao` da camada `infra_fisica` passa a abrir
--    PC_SEM_SUBSTITUTO para o LAB2-05 — que está em manutenção aberta e sem
--    substituto POR DESENHO (nota (c) da camada). A pendência continua não sendo
--    SEMEADA: ela é gerada pela regra, a partir do dado que a fixture escreve, e
--    a asserção agora prova as duas coisas de uma vez — que o caminho por evento
--    dispara até no seed, e que ele não abre nada além do que é verdade.
select is(
  (select string_agg(format('%s:%s', p.tipo, pc.identificador), ', '
                     order by pc.identificador)
     from public.pendencia p
     join public.pc pc on pc.id = p.pc_id
    where p.unidade_id = tests.unidade('ESCOLA_A')),
  'PC_SEM_SUBSTITUTO:LAB2-05',
  'a fixture nasce com UMA pendencia, e ela e GERADA pelo trigger do card 5.4 — nao semeada');

select is(
  (select count(*)::bigint from public.pendencia
    where unidade_id = tests.unidade('ESCOLA_A') and pc_id is null),
  0::bigint,
  'e nenhuma pendencia de aluno ou de bloco: essas nascem das rotinas, mais abaixo');

-- ===========================================================================
-- 2. rt_pendencias_diaria abre os tipos de TEMPO do catálogo §10.1
-- ===========================================================================
-- ⚠️ MUDOU NO CARD 8.4 (05/09/2026), e esta asserção é o portão que obrigou:
--    ela lista TUDO o que a rotina abriu, sem filtrar por tipo, então acrescentar
--    um tipo à rotina sem passar por aqui é impossível. Entraram
--    PREVISAO_VENCIDA (Diego, previsão 15 dias no passado) e STANDBY_PROLONGADO
--    (Gabriela, em STANDBY há 45 dias, acima dos 30 do parâmetro) — as duas
--    marcas que a fixture do card 4.2 já carregava e que ninguém lia. O detalhe
--    de cada uma, com contraprova, está nas §15 e §16.
select public.rt_pendencias_diaria();

select is(
  (select string_agg(format('%s:%s:%s', p.tipo, p.severidade, a.nome), ' | '
                     order by p.tipo, a.nome)
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  'ACELERAR_SEM_2O_BLOCO:BAIXA:Felipe Nunes | ALUNO_SEM_TURMA:ALTA:Aluno Modular 01 | ALUNO_SEM_TURMA:ALTA:Felipe Nunes | PREVISAO_VENCIDA:MEDIA:Diego Alves | STANDBY_PROLONGADO:MEDIA:Gabriela Souza',
  'abre os QUATRO tipos de tempo: sem turma (ALTA), aceleracao sem 2o bloco (BAIXA), previsao vencida e STANDBY prolongado (MEDIA)');

-- ⚠️ EDUARDA LIMA SAIU DESTA LISTA EM 05/09/2026, e não é regressão: é o portão
--    do card 5.5 sendo cobrado. Até o card 7.1 ela era MODULAR sem `bloco_aluno`
--    e recebia ALUNO_SEM_TURMA — o que estava CERTO enquanto turma Modular não
--    existia, e passaria a ser pendência FALSA no dia seguinte. Hoje a fixture a
--    põe na turma `Eletricista 2026.1` (camada `modular`) e a rotina olha as
--    duas formas de turma. O par de asserções que mede isso dos dois lados
--    (turma ativa → sem pendência; turma desativada → com pendência) está no
--    teste 070 §6.
--
--    ⚠️ E DESDE O CARD 7.4,5 (05/09/2026) o lado POSITIVO é fixo: a camada
--    `modular` passou a trazer `Aluno Modular 01` — MODULAR, ATIVO e sem turma
--    nenhuma —, e a asserção de cima o mostra recebendo ALUNO_SEM_TURMA. Até
--    aqui o `not exists` de turma Modular só era medido no negativo fora do 070;
--    a fixture agora tem os dois alunos MODULAR lado a lado, um em cada lado da
--    condição.
select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Eduarda Lima' and p.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'ALUNO_SEM_TURMA' and p.resolvida_em is null),
  0::bigint,
  'a aluna MODULAR esta numa turma Modular ATIVA e por isso nao aparece aqui (portao do card 5.5)');

-- ⚠️ A ASSERÇÃO ACIMA TEM UM ALCANCE QUE O CARD 8.4,5 MEDIU E CORRIGIU: ela faz
--    `join public.aluno`, então lista tudo o que a rotina abre PARA ALUNO — e
--    um tipo de MATERIAL acrescentado à rotina passaria por ela sem tocar em
--    nada. A nota do card 8.4,5 supunha o contrário ("o §2 lista tudo o que a
--    rotina abre sem filtrar por tipo, então ele reprova sozinho"), e a suposição
--    valia só enquanto todo bloco da rotina falasse de aluno. Esta é a metade que
--    faltava: o mesmo formato, do outro lado da referência.
select is(
  (select string_agg(format('%s:%s:%s %s', p.tipo, p.severidade, me.codigo, m.codigo), ' | '
                     order by me.codigo, m.codigo)
     from public.pendencia p
     join public.material m on m.id = p.material_id
     join public.metodo me on me.id = m.metodo_id
    where p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  'ESTOQUE_ABAIXO_MINIMO:BAIXA:INGLES 02 | ESTOQUE_ABAIXO_MINIMO:BAIXA:INTERATIVO 02 | ESTOQUE_ABAIXO_MINIMO:BAIXA:INTERATIVO 04',
  'e abre o tipo de MATERIAL nos tres saldos zero da fixture, e so neles (card 8.4,5)');

-- Ajuste 4 do §10 do card 2.3, BLOQUEANTE: o catálogo do card 2.2 dava INFO a
-- ACELERAR_SEM_2O_BLOCO, e INFO não existe no `check` do DDL. Escrita assim, a
-- rotina morreria no `check` — dentro do `exception` de rt_diaria, virando
-- ROTINA_FALHOU todo dia, longe da causa.
select is(
  (select count(*)::bigint from public.pendencia
    where severidade not in ('BAIXA', 'MEDIA', 'ALTA')),
  0::bigint,
  'nenhuma severidade fora do check do DDL — INFO nao existe (ajuste 4 do card 2.3)');

-- A central mostra a descrição, não o UUID. Sem nome e código a pendência
-- obriga quem a lê a ir procurar de quem se trata.
-- ⚠️ Era Eduarda Lima até o card 7.1; passou a Felipe Nunes pela razão do aviso
--    acima — ela deixou de ter pendência de que ler a descrição.
select ok(
  (select p.descricao like '%Felipe Nunes%' and p.descricao like '%3006%'
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Felipe Nunes' and p.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'ALUNO_SEM_TURMA'),
  'a descricao carrega nome e codigo SGF — a central nao mostra UUID a ninguem');

-- ===========================================================================
-- 3. Idempotência: a rotina roda todo dia e não duplica
-- ===========================================================================
-- Não é o `on conflict` que se está testando: é a promessa de que a rotina pode
-- rodar de novo. Sem ela, a central acumularia uma cópia por dia.
select public.rt_pendencias_diaria();
select public.rt_pendencias_diaria();

-- `aluno_id is not null` desde o card 5.4: a PC_SEM_SUBSTITUTO da seção 1 é da
-- fixture e não tem nada a ver com a idempotência que se está medindo aqui.
-- Três linhas desde o card 7.4,5 e não duas: o `Aluno Modular 01` da camada
-- `modular` traz uma ALUNO_SEM_TURMA própria. CINCO desde o card 8.4, com os
-- dois alertas de tempo. O que se mede continua sendo o mesmo — o número não
-- muda com a terceira execução da rotina.
select is(
  (select count(*)::bigint from public.pendencia
    where unidade_id = tests.unidade('ESCOLA_A') and aluno_id is not null),
  5::bigint,
  'tres execucoes, cinco linhas: o indice parcial pendencia_aberta_uk faz a deduplicacao');

-- ===========================================================================
-- 4. A condição aparece e some — e o fechamento é POR CHAVE
-- ===========================================================================
-- `Aluno de Lotação 01` sai do bloco cheio. Escolhido por chave natural, nunca
-- por `limit` (docs/estrategia-testes.md §11).
select public.fn_bloco_remover(
  (select id from public.bloco_horario
    where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3),
  (select id from public.aluno
    where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Aluno de Lotação 01'),
  'saida de teste');

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Aluno de Lotação 01' and p.tipo = 'ALUNO_SEM_TURMA'
      and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  1::bigint,
  'aluno que sai da turma aparece na central na execucao seguinte');

-- E volta para o MESMO bloco: o cheio precisa continuar 10/10 para a seção 6.
select public.fn_bloco_admitir(
  (select id from public.bloco_horario
    where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3),
  (select id from public.aluno
    where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Aluno de Lotação 01'),
  'REM');

select public.rt_pendencias_diaria();

select is(
  (select format('%s/%s/%s', p.resolucao, p.resolvida_por is null, p.resolvida_em is not null)
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Aluno de Lotação 01' and p.tipo = 'ALUNO_SEM_TURMA'
      and p.unidade_id = tests.unidade('ESCOLA_A')),
  'RESOLVIDA/t/t',
  'a condicao sumiu: fechamento AUTOMATICO, com resolvida_por NULO — foi o sistema, nao uma pessoa');

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Felipe Nunes' and p.tipo = 'ALUNO_SEM_TURMA'
      and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  1::bigint,
  'e a do outro continua ABERTA: o fechamento e por chave_dedup, nao por tipo');

-- ===========================================================================
-- 5. Reabre o que continua verdadeiro — inclusive o que alguém IGNOROU
-- ===========================================================================
-- É a decisão da seção 6 da migração, e está aqui para ser vista: silêncio
-- permanente por chave seria a falha calada que este projeto cataloga. Quem
-- quiser calar um BLOCO_ACIMA_CAPACIDADE mexe em `capacidade_override`; quem
-- quiser calar um ALUNO_SEM_TURMA põe o aluno numa turma.
update public.pendencia p
   set resolvida_em = now(), resolucao = 'IGNORADA',
       justificativa = 'aluno em conversa com a familia'
  from public.aluno a
 where a.id = p.aluno_id and a.nome = 'Felipe Nunes'
   and p.tipo = 'ALUNO_SEM_TURMA' and p.unidade_id = tests.unidade('ESCOLA_A')
   and p.resolvida_em is null;

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Felipe Nunes' and p.tipo = 'ALUNO_SEM_TURMA'
      and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  1::bigint,
  'pendencia IGNORADA volta na execucao seguinte enquanto a condicao valer (decisao, secao 6 da migracao)');

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Felipe Nunes' and p.tipo = 'ALUNO_SEM_TURMA'
      and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolucao = 'IGNORADA'),
  1::bigint,
  'e a linha ignorada CONTINUA la, com a justificativa: reabrir nao apaga historia');

-- ===========================================================================
-- 6. BLOCO_ACIMA_CAPACIDADE — a capacidade cai, a pendência aparece
-- ===========================================================================
-- 10 alunos para 10 PCs não é "acima": a borda é o que se mede — e a rotina roda
-- ANTES da asserção, senão o zero significaria "ninguém olhou".
select public.rt_capacidades();

select is(
  (select count(*)::bigint from public.pendencia
    where tipo = 'BLOCO_ACIMA_CAPACIDADE' and resolvida_em is null),
  0::bigint,
  'bloco lotado (10/10) NAO e bloco acima da capacidade — a borda e >, nao >=');

-- ⚠️ REESCRITA NO CARD 5.4, e a escolha da fonte da queda é o ponto. Até aqui a
--    capacidade caía pondo um PC em MANUTENCAO — e a partir do card 5.4 isso
--    dispara `tg_pc_revalida_blocos`, de modo que a pendência apareceria ANTES
--    de a rotina rodar: a asserção passaria sem que a rotina fizesse nada, que é
--    a definição de teste que cegou. A queda passa a vir de `capacidade_override`
--    reduzido à mão, que é a única fonte que trigger NENHUM observa — o caminho
--    diário volta a ser a única explicação possível para a pendência. O caminho
--    por EVENTO tem arquivo próprio (091).
--
-- 10 alunos para uma capacidade de 9: o bloco cheio passa a estar acima.
update public.bloco_horario set capacidade_override = 9
 where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3;

select public.rt_capacidades();

select is(
  (select format('%s/%s/%s', p.severidade,
                 p.descricao like '%10 aluno(s) para capacidade de 9%',
                 b.dia_semana)
     from public.pendencia p
     join public.bloco_horario b on b.id = p.bloco_id
    where p.tipo = 'BLOCO_ACIMA_CAPACIDADE'
      and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  'ALTA/t/3',
  'a capacidade cai e a pendencia aparece com os DOIS numeros na descricao');

-- A rotina desfaz o que ela mesma abriu — sem ninguém pedir.
update public.bloco_horario set capacidade_override = null
 where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3;

select public.rt_capacidades();

select is(
  (select count(*)::bigint from public.pendencia
    where tipo = 'BLOCO_ACIMA_CAPACIDADE' and resolvida_em is null),
  0::bigint,
  'normalizada a capacidade, a rotina fecha sozinha');

-- E a rotina que PERDEU o tipo continua sem abri-lo: BLOCO_ACIMA_CAPACIDADE saiu
-- de rt_pendencias_diaria no card 5.4 e voltou ao dono do catálogo §10.1. Sem
-- esta asserção, a cópia poderia voltar num `create or replace` futuro e as duas
-- implementações conviveriam em silêncio, livres para divergir.
update public.bloco_horario set capacidade_override = 9
 where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3;

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint from public.pendencia
    where tipo = 'BLOCO_ACIMA_CAPACIDADE' and resolvida_em is null),
  0::bigint,
  'rt_pendencias_diaria NAO abre mais BLOCO_ACIMA_CAPACIDADE — o dono e fn_revalidar_blocos_sala');

update public.bloco_horario set capacidade_override = null
 where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3;

-- ===========================================================================
-- 7. ACELERAR_SEM_2O_BLOCO conta só bloco de VERDADE — ajuste 4 do card 2.5
-- ===========================================================================
-- Diego Alves está no bloco cheio com tipo PRE. Posto em ACELERAR e com uma
-- alocação de REPOSIÇÃO contínua no bloco vazio, ele tem duas linhas em
-- `bloco_aluno` e UM bloco de aula: reposição não é aceleração.
update public.aluno set status = 'ACELERAR'
 where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Diego Alves';

select public.fn_bloco_admitir(
  (select id from public.bloco_horario
    where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 1),
  (select id from public.aluno
    where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Diego Alves'),
  'REP');

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Diego Alves' and p.tipo = 'ACELERAR_SEM_2O_BLOCO'
      and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  1::bigint,
  'PRE + REP e UM bloco de aula, nao dois: a pendencia de aceleracao ABRE (ajuste 4 do card 2.5)');

-- CONTRAPROVA. Sem ela a asserção acima passaria também com o filtro escrito ao
-- contrário — bastaria a rotina contar errado para o outro lado. A alocação REP
-- vira REM: agora são dois blocos de aula de verdade, e a pendência tem de sumir.
update public.bloco_aluno ba set tipo = 'REM'
  from public.aluno a
 where a.id = ba.aluno_id and a.nome = 'Diego Alves'
   and ba.unidade_id = tests.unidade('ESCOLA_A') and ba.ativo and ba.tipo = 'REP';

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Diego Alves' and p.tipo = 'ACELERAR_SEM_2O_BLOCO'
      and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  0::bigint,
  'CONTRAPROVA: as MESMAS duas linhas, agora as duas de aula, fecham a pendencia — o filtro e do tipo');

-- ===========================================================================
-- 8. O sufixo da chave REP, medido pelo descarte que ele evita
-- ===========================================================================
-- Card 2.5 §6. Sem o sufixo, `pendencia_aberta_uk` descartaria a sugestão de
-- volta enquanto a de ida estivesse aberta — em silêncio, porque `on conflict`
-- não levanta erro. Os dois sentidos nunca coexistem hoje; depender disso é que
-- é frágil.
select public.fn_pendencia_abrir('REP_VIRADA', 'REP:teste:CONTINUO', 'ida',   'MEDIA');
select public.fn_pendencia_abrir('REP_VIRADA', 'REP:teste:VOLTA',    'volta', 'BAIXA');

select is(
  (select count(*)::bigint from public.pendencia
    where chave_dedup like 'REP:teste:%' and resolvida_em is null),
  2::bigint,
  'COM sufixo as duas sugestoes do mesmo aluno coexistem');

select public.fn_pendencia_abrir('REP_VIRADA', 'REP:semsufixo', 'ida',   'MEDIA');
select public.fn_pendencia_abrir('REP_VIRADA', 'REP:semsufixo', 'volta', 'BAIXA');

select is(
  (select count(*)::bigint from public.pendencia
    where chave_dedup = 'REP:semsufixo' and resolvida_em is null),
  1::bigint,
  'SEM sufixo a segunda seria engolida pela dedup — sem erro nenhum, que e o problema');

-- E o `do update` de fn_pendencia_abrir: a segunda chamada não duplicou, mas
-- REFRESCOU os números. Pendência aberta na segunda-feira mostrando os números
-- de segunda na sexta é número errado com cara de certo (card 2.3 §3.4).
select is(
  (select format('%s/%s', descricao, severidade) from public.pendencia
    where chave_dedup = 'REP:semsufixo' and resolvida_em is null),
  'volta/BAIXA',
  'a chamada seguinte ATUALIZA descricao e severidade da pendencia aberta em vez de ignorar');

-- ===========================================================================
-- 9. rt_rep_avaliar — abre e fecha a sugestão da virada (card 2.5 §5.3)
-- ===========================================================================
-- `Aluno de Lotação 13` é o único da fixture em REP contínuo, há 40 dias, fora
-- da carência (rep_janela_volta_dias = 30) e sem débito: SUGERIR_VOLTA.
select public.rt_rep_avaliar();

select is(
  (select format('%s/%s', p.severidade, p.chave_dedup = 'REP:' || a.id::text || ':VOLTA')
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Aluno de Lotação 13' and p.tipo = 'REP_VIRADA'
      and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  'BAIXA/t',
  'quem esta em REP continuo sem debito recebe a sugestao de VOLTA, severidade BAIXA');

-- Lucas está com o débito EXATAMENTE no limite (card 2.5 §3.3, fixture (e)):
-- veredito MANTER, e a rotina não abre nada. Um teste que só medisse o caso
-- positivo não distinguiria uma rotina que abre para todo mundo.
select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Lucas Ferreira' and p.tipo = 'REP_VIRADA'
      and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  0::bigint,
  'no limite exato o veredito e MANTER e a rotina nao abre pendencia nenhuma');

-- Uma aula a mais vira o veredito. Origem mais RECENTE que a mais antiga: o
-- prazo não muda, só o débito — a asserção mede o débito, não o calendário.
insert into public.bloco_aluno_reposicao
  (unidade_id, bloco_id, aluno_id, data, bloco_origem_id, data_origem, status)
select tests.unidade('ESCOLA_A'),
       (select id from public.bloco_horario
         where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 1),
       a.id, public.fn_hoje() + 8,
       (select id from public.bloco_horario
         where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3),
       public.fn_hoje() - 3, 'PREVISTA'
  from public.aluno a
 where a.nome = 'Lucas Ferreira' and a.unidade_id = tests.unidade('ESCOLA_A');

select public.rt_rep_avaliar();

select is(
  (select format('%s/%s/%s', p.severidade,
                 p.chave_dedup = 'REP:' || a.id::text || ':CONTINUO',
                 p.descricao like '%4 aula(s) a repor%')
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Lucas Ferreira' and p.tipo = 'REP_VIRADA'
      and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  'MEDIA/t/t',
  'uma aula a mais e a rotina abre REP:<aluno>:CONTINUO (MEDIA) com os numeros do criterio na descricao');

-- As chaves de teste da seção 8 não correspondem a aluno nenhum: a rotina as
-- fecha, e é o "some sozinha quando deixa de ser verdade" valendo também para o
-- que ela não abriu.
select is(
  (select count(*)::bigint from public.pendencia
    where chave_dedup in ('REP:teste:CONTINUO', 'REP:teste:VOLTA', 'REP:semsufixo')
      and resolvida_em is null),
  0::bigint,
  'e fecha as chaves REP_VIRADA que nao correspondem a veredito nenhum');

-- ===========================================================================
-- 10. O portão do card 5.3 dispara: a virada fecha a pendência NA HORA
-- ===========================================================================
-- Entre a virada e a rotina do dia seguinte passa até um dia, e nesse dia a
-- central mentiria para a pessoa que acabou de agir. É o passo 4 do §5.2 do
-- card 2.5, e era o portão da seção 6 do teste 085.
select lives_ok(
  $$select public.fn_rep_virar_continuo(
      (select id from public.aluno
        where unidade_id = public.fn_unidade_atual() and nome = 'Lucas Ferreira'),
      (select id from public.bloco_horario
        where unidade_id = public.fn_unidade_atual() and dia_semana = 1))$$,
  'a virada acontece: fn_bloco_admitir cuida da vaga e do metodo');

select is(
  (select format('%s/%s', p.resolucao, p.resolvida_por is null)
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Lucas Ferreira' and p.tipo = 'REP_VIRADA'
      and p.chave_dedup like '%:CONTINUO'
      and p.unidade_id = tests.unidade('ESCOLA_A')),
  'RESOLVIDA/t',
  'fn_rep_virar_continuo fecha REP:<aluno>:CONTINUO na MESMA transacao — sem esperar a rotina');

select public.fn_rep_voltar_pontual(
  (select id from public.aluno
    where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Aluno de Lotação 13'),
  'voltou a dar conta das reposicoes pontuais');

select is(
  (select p.resolucao
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Aluno de Lotação 13' and p.tipo = 'REP_VIRADA'
      and p.chave_dedup like '%:VOLTA'
      and p.unidade_id = tests.unidade('ESCOLA_A')),
  'RESOLVIDA',
  'e fn_rep_voltar_pontual fecha REP:<aluno>:VOLTA — o sufixo permite fechar uma sem tocar na outra');

-- ===========================================================================
-- 11. fn_pendencia_resolver_id — o fechamento HUMANO, que exige a permissão
-- ===========================================================================
-- É aqui, e só aqui, que `pendencias.resolver` vale alguma coisa: as duas
-- funções automáticas são `security definer` de propósito (seção 5 da migração).
--
-- ⚠️ SAIR DO CONTEXTO DE ROTINA ANTES, e isto derrubaria o arquivo inteiro em
--    silêncio: dentro dele `tem_permissao()` é sempre VERDADEIRA (card 2.2 §2.2),
--    então toda asserção de permissão daqui para baixo passaria dizendo que o
--    monitor pode — e o teste estaria medindo o contexto, não a matriz.
select tests.encerrar_sessao();
select is(
  tests.codigo_do_erro(
    format('select public.fn_pendencia_resolver_id(%L, ''RESOLVIDA'')',
           (select p.id from public.pendencia p
             join public.aluno a on a.id = p.aluno_id
            where a.nome = 'Felipe Nunes' and p.tipo = 'ALUNO_SEM_TURMA'
              and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null)),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor le a central mas nao encerra pendencia (card 2.4 §5.1 (7))');

select is(
  tests.codigo_do_erro(
    format('select public.fn_pendencia_resolver_id(%L, ''ARQUIVADA'')',
           (select p.id from public.pendencia p
             join public.aluno a on a.id = p.aluno_id
            where a.nome = 'Felipe Nunes' and p.tipo = 'ALUNO_SEM_TURMA'
              and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null)),
    tests.uid('direcao@escola-a.test')),
  'RESOLUCAO_INVALIDA',
  'resolucao fora de (RESOLVIDA, IGNORADA) devolve codigo, nao erro cru de check');

select is(
  tests.codigo_do_erro(
    format('select public.fn_pendencia_resolver_id(%L, ''IGNORADA'')',
           (select p.id from public.pendencia p
             join public.aluno a on a.id = p.aluno_id
            where a.nome = 'Felipe Nunes' and p.tipo = 'ALUNO_SEM_TURMA'
              and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null)),
    tests.uid('direcao@escola-a.test')),
  'MOTIVO_OBRIGATORIO',
  'ignorar sem justificativa e recusado ANTES do check da tabela — decisao sem porque e decisao perdida');

select is(
  tests.codigo_do_erro(
    'select public.fn_pendencia_resolver_id(''00000000-0000-0000-0000-000000000000'', ''RESOLVIDA'')',
    tests.uid('direcao@escola-a.test')),
  'PENDENCIA_INEXISTENTE',
  'pendencia que nao existe (ou de outra unidade) devolve PT404, nao silencio');

-- Caminho feliz, com EFEITO conferido: quem fechou e por quê ficam gravados.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select lives_ok(
  $$select public.fn_pendencia_resolver_id(
      (select p.id from public.pendencia p
         join public.aluno a on a.id = p.aluno_id
        where a.nome = 'Felipe Nunes' and p.tipo = 'ALUNO_SEM_TURMA'
          and p.resolvida_em is null),
      'IGNORADA', 'aluno em conversa com a familia')$$,
  'a direcao ignora a pendencia com justificativa');

reset role;
select tests.como_rotina(tests.unidade('ESCOLA_A'));

select is(
  (select format('%s/%s/%s', p.resolucao, u.email, p.justificativa)
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
     join public.usuario u on u.id = p.resolvida_por
    where a.nome = 'Felipe Nunes' and p.tipo = 'ALUNO_SEM_TURMA'
      and p.unidade_id = tests.unidade('ESCOLA_A')
      and p.resolvida_por is not null),
  'IGNORADA/direcao@escola-a.test/aluno em conversa com a familia',
  'fechamento humano grava QUEM e POR QUE — e resolvida_por preenchida o distingue do automatico');

select is(
  tests.codigo_do_erro(
    format('select public.fn_pendencia_resolver_id(%L, ''RESOLVIDA'')',
           (select p.id from public.pendencia p
             join public.aluno a on a.id = p.aluno_id
            where a.nome = 'Felipe Nunes' and p.tipo = 'ALUNO_SEM_TURMA'
              and p.unidade_id = tests.unidade('ESCOLA_A')
              and p.resolvida_por is not null)),
    tests.uid('direcao@escola-a.test')),
  'PENDENCIA_JA_RESOLVIDA',
  'fechar de novo devolve PT409 — e nao um update silencioso de zero linhas');

-- ===========================================================================
-- 12. rt_diaria — as duas unidades, e a falha que vira pendência
-- ===========================================================================
select tests.encerrar_sessao();

select public.rt_diaria();

-- ⚠️ O tipo importa: desde o card 5.4 a fixture nasce com PC_SEM_SUBSTITUTO nas
--    DUAS unidades (seção 1), então contar pendência de qualquer tipo passaria
--    mesmo que rt_diaria não tivesse saído do lugar. ALUNO_SEM_TURMA só existe
--    se a rotina rodou, e só existe na Escola B se ela rodou LÁ.
select is(
  (select count(distinct p.unidade_id)::bigint from public.pendencia p
    where p.resolvida_em is null and p.tipo = 'ALUNO_SEM_TURMA'),
  2::bigint,
  'rt_diaria percorre as unidades ATIVAS: a Escola B tem as pendencias dela, e o contexto nao vaza');

-- Uma rt_* que quebra não pode levar junto a que funciona, e não pode sumir com
-- o log de 1 dia do Supabase (card 3.12 (g)). O `create or replace` abaixo vive
-- só dentro desta transação.
create or replace function public.rt_rep_avaliar()
returns void language plpgsql security definer set search_path = public, pg_temp
as $$ begin raise exception 'sabotagem do teste 090'; end $$;

select public.rt_diaria();

select is(
  (select format('%s/%s/%s', p.tipo, p.severidade, p.descricao like '%sabotagem do teste 090%')
     from public.pendencia p
    where p.chave_dedup = 'ROTINA_FALHOU:rt_rep_avaliar'
      and p.unidade_id = tests.unidade('ESCOLA_A') and p.resolvida_em is null),
  'ROTINA_FALHOU/ALTA/t',
  'rotina que falha vira pendencia ALTA com a mensagem do banco — nao some com a retencao de 1 dia');

select is(
  (select count(*)::bigint from public.pendencia p
    where p.chave_dedup = 'ROTINA_FALHOU:rt_pendencias_diaria' and p.resolvida_em is null),
  0::bigint,
  'e a OUTRA rotina correu: o bloco de excecao isola, nao interrompe');

-- Restaurada, a execução seguinte fecha a pendência de falha. Sem isso a lista
-- guardaria para sempre um problema que passou.
create or replace function public.rt_rep_avaliar()
returns void language plpgsql security definer set search_path = public, pg_temp
as $$ begin return; end $$;

select public.rt_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
    where p.chave_dedup = 'ROTINA_FALHOU:rt_rep_avaliar' and p.resolvida_em is null),
  0::bigint,
  'execucao seguinte bem-sucedida FECHA a ROTINA_FALHOU');

-- ===========================================================================
-- 13. Portões: o que ainda não existe, e o dia em que passar a existir
-- ===========================================================================
-- ⚠️ PORTÃO DO CARD 8.1 — e ele DISPAROU DUAS VEZES, no 5.4 e no próprio 8.1. O
--    §11 do card 2.2 dá cinco passos a rt_diaria; `rt_pcs_normaliza` e
--    `rt_capacidades` nasceram no 5.4 e entraram aqui no mesmo commit, e
--    `rt_projecao_demanda` fez o mesmo em 05/09/2026 — criá-la e esquecer de
--    chamá-la aqui não daria erro nenhum: daria uma rotina que roda todo dia sem
--    fazer o que passou a ser dela, e uma projeção que nunca sairia do zero.
--    Com a quinta, a lista do §11 fecha; o portão continua armado para a sexta.
--    `prosrc` inclui os comentários do corpo — daí o regexp_replace, a lição que
--    custou uma sessão no card 5.3.
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'rt\_%'
      and p.proname <> 'rt_diaria'
      and (select regexp_replace(d.prosrc, '--[^\n]*', '', 'g')
             from pg_proc d
             join pg_namespace dn on dn.oid = d.pronamespace
            where dn.nspname = 'public' and d.proname = 'rt_diaria') !~ p.proname),
  '',
  'PORTAO 8.1 (disparou no 5.4): toda rt_* do projeto e chamada por rt_diaria');

-- ⚠️ O PORTÃO DO CARD 7.1 FOI COBRADO EM 05/09/2026, e este bloco é o que
--    sobrou dele. Enquanto `turma_modular_aluno` não existia, ele era
--    condicional e provava que reprovava criando a tabela dentro da transação;
--    nascida a tabela de verdade, o `create table` morreria com "already exists"
--    e a condição `is null` deixa de separar dois mundos. O que fica é a
--    asserção direta.
--
--    O que ela mede continua sendo o motivo pelo qual o portão existiu: sem esta
--    metade, todo aluno MODULAR alocado numa turma receberia ALUNO_SEM_TURMA
--    todo dia — pendência falsa, e das piores, porque ensina a lista a ser
--    ignorada. A prova de COMPORTAMENTO (a aluna Modular da fixture não aparece
--    na lista, e aparece quando a turma é desativada) está no teste 070 §7.
--
--    `prosrc` inclui os comentários do corpo, e o desta rotina cita a tabela
--    duas vezes em comentário: sem o `regexp_replace` a asserção passaria com o
--    `not exists` apagado.
create temporary view corpo_pendencias as
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as fonte
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rt_pendencias_diaria';

select ok(
  (select fonte ~ 'turma_modular_aluno' from corpo_pendencias),
  'ALUNO_SEM_TURMA olha as DUAS formas de turma — bloco de horario e turma Modular');

-- E a turma Modular só conta ATIVA, pela mesma razão que o card 5.7 deu ao
-- `bloco_ativo`: turma desativada não é turma. Sem esta metade, desativar uma
-- turma tiraria a turma da tela sem abrir pendência nenhuma para os alunos dela.
select ok(
  (select fonte ~ 'turma_modular' from corpo_pendencias
    where fonte ~ 'tm\.ativo'),
  'e a turma Modular so conta quando ela propria esta ativa');

-- ===========================================================================
-- 14. RLS e a view: quem vê o quê
-- ===========================================================================
-- Teste de PARIDADE (card 2.8 §6.3): contar na pele de cada usuário é o único
-- formato que prova alguma coisa quando a RLS reduz linhas em silêncio.
select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_pendencias_abertas'),
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_pendencias_abertas'),
  'direcao e monitor veem a MESMA central: os dois tem pendencias.ler (card 2.4 §5)');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_pendencias_abertas'),
  0::bigint,
  'sem pendencias.ler a central e vazia — e vazia por RLS, que e o que a view NAO pode esconder');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_pendencias_abertas where unidade_id = ' ||
                   quote_literal(tests.unidade('ESCOLA_A')::text) || '::uuid'),
  0::bigint,
  'a direcao da Escola B nao ve pendencia da Escola A: security_invoker + RLS por unidade');

-- A decisão (b) do §9 do card 2.3: `left join` em tudo. Um perfil com
-- `pendencias.ler` e SEM `alunos.ler` precisa continuar VENDO a pendência, com a
-- referência degradando para nulo. Com `join` interno a linha sumiria, e a
-- central diria "nenhuma pendência" em vez de "uma pendência sobre alguém que
-- você não pode ver" — que é a pior forma de errar (card 2.3 §3.4).
insert into public.perfil (unidade_id, codigo, nome)
values (tests.unidade('ESCOLA_A'), 'SO_PENDENCIAS', 'Só pendências (teste 090)');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select tests.unidade('ESCOLA_A'), pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A') and pe.codigo = 'SO_PENDENCIAS'
   and pm.unidade_id = tests.unidade('ESCOLA_A') and pm.codigo = 'pendencias.ler';

select tests.criar_usuario('sopendencias@escola-a.test', 'SO_PENDENCIAS');

select is(
  tests.conta_como(tests.uid('sopendencias@escola-a.test'),
                   'select 1 from public.v_pendencias_abertas where aluno_id is not null'),
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_pendencias_abertas where aluno_id is not null'),
  'quem so tem pendencias.ler ve as MESMAS linhas: o left join nao deixa a referencia levar a pendencia embora');

select is(
  tests.conta_como(tests.uid('sopendencias@escola-a.test'),
                   'select 1 from public.v_pendencias_abertas where aluno_id is not null and aluno_nome is not null'),
  0::bigint,
  'e o nome do aluno vem NULO para ele — a referencia degrada, a pendencia fica');

-- A view é das ABERTAS. Pendência fechada não some da tabela (é história), mas
-- sai da central.
select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_pendencias_abertas v join public.pendencia p on p.id = v.pendencia_id where p.resolvida_em is not null'),
  0::bigint,
  'v_pendencias_abertas nao mostra pendencia fechada, e a tabela continua guardando o historico');

-- ===========================================================================
-- 15. STANDBY_PROLONGADO — card 8.4, e a borda que só o parâmetro revela
-- ===========================================================================
-- Estas duas seções ficam no FIM do arquivo de propósito, e não ao lado da §2
-- onde a leitura pediria: as seções são numeradas pela história do arquivo, e
-- outros documentos e migrações citam "teste 090 §13", "§2" e "§14" pelo número.
-- Renumerar por estética quebraria referência escrita em cinco lugares.
--
-- O que a §2 prova é que os dois tipos ENTRARAM na rotina. O que se prova aqui é
-- que eles entraram com a regra certa — e as três armadilhas medidas são:
--   • o filtro é de STATUS, não só de tempo (Henrique está parado há 75 dias, e
--     TRANCADO não é STANDBY: quem está trancado já teve a decisão tomada);
--   • o limiar é o PARÂMETRO e não um 30 literal — medido movendo o parâmetro,
--     que é o único jeito de distinguir os dois mundos;
--   • a borda é `>` e não `>=`, e ela some no uso: com o parâmetro em 45 a aluna
--     de 45 dias tem de SAIR da lista, porque "há mais de 45 dias" ainda não é
--     verdade.
select tests.encerrar_sessao();
select tests.como_rotina(tests.unidade('ESCOLA_A'));
select public.rt_pendencias_diaria();

select is(
  (select format('%s/%s/%s/%s', p.severidade,
                 p.chave_dedup = 'STANDBY:' || a.id::text,
                 p.descricao like '%3007%',
                 p.descricao like '%45 dia(s)%30 configurados%')
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Gabriela Souza' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'STANDBY_PROLONGADO' and p.resolvida_em is null),
  'MEDIA/t/t/t',
  'STANDBY ha 45 dias abre a pendencia MEDIA, com o codigo SGF e os DOIS numeros (dias e limiar) na descricao');

-- Henrique Dias está parado há 75 dias — MAIS que Gabriela — e não recebe nada,
-- porque está TRANCADO. Sem esta linha, uma regra que ignorasse o status
-- passaria na asserção de cima: o tempo dele é maior, o resultado seria o mesmo.
select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Henrique Dias' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'STANDBY_PROLONGADO' and p.resolvida_em is null),
  0::bigint,
  'TRANCADO ha 75 dias NAO abre STANDBY_PROLONGADO — o filtro e de status, nao so de tempo');

-- A borda, e a prova de que o limiar sai do `parametro`. 45 dias com o parâmetro
-- em 45 não é "há mais de 45 dias": a rotina fecha o que ela mesma abriu.
update public.parametro set valor = '45'
 where unidade_id = tests.unidade('ESCOLA_A') and chave = 'standby_alerta_dias';

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Gabriela Souza' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'STANDBY_PROLONGADO' and p.resolvida_em is null),
  0::bigint,
  'com o parametro em 45 a aluna de 45 dias SAI da lista: a borda e >, nao >= — e o limiar vem do parametro');

update public.parametro set valor = '44'
 where unidade_id = tests.unidade('ESCOLA_A') and chave = 'standby_alerta_dias';

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Gabriela Souza' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'STANDBY_PROLONGADO' and p.resolvida_em is null),
  1::bigint,
  'um dia a menos no parametro e ela volta: e o parametro que decide, nao um 30 escrito na funcao');

update public.parametro set valor = '30'
 where unidade_id = tests.unidade('ESCOLA_A') and chave = 'standby_alerta_dias';

-- "Fechada por mudança de status" (catálogo §10.1) NÃO é um trigger: é a mesma
-- reavaliação diária. Trancar a aluna — que é justamente o que a pendência
-- sugere — tira a chave da lista, e o fechamento é AUTOMÁTICO (resolvida_por
-- nula), do jeito que a §4 mede para ALUNO_SEM_TURMA.
update public.aluno set status = 'TRANCADO'
 where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Gabriela Souza';

select public.rt_pendencias_diaria();

-- ⚠️ São DUAS linhas de história, e não uma — o que este arquivo já dizia na §5
--    sobre a pendência ignorada: reabrir não reaproveita a linha fechada, abre
--    outra (o `pendencia_aberta_uk` é PARCIAL, só sobre as abertas). Aqui a
--    aluna abriu, fechou na borda do parâmetro, reabriu e fechou de novo. Uma
--    asserção escrita como `select ... where tipo = ...` sem agregado morre em
--    "more than one row" — foi o que aconteceu na primeira execução deste teste.
select is(
  (select format('%s/%s/%s',
                 count(*) filter (where p.resolvida_em is null),
                 count(*),
                 bool_and(p.resolucao = 'RESOLVIDA' and p.resolvida_por is null))
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Gabriela Souza' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'STANDBY_PROLONGADO'),
  '0/2/t',
  'trancar a aluna fecha a pendencia sozinha na execucao seguinte, e as DUAS linhas da historia sao RESOLVIDA sem pessoa — sem trigger de fechamento');

-- ===========================================================================
-- 16. PREVISAO_VENCIDA — card 8.4
-- ===========================================================================
-- Diego Alves tem `prev_conclusao_curso` 15 dias no passado (fixture do card
-- 4.2), e é o mesmo dado que a projeção do card 8.1 RECUSA como base: com passo
-- negativo, o degrau PREVISAO_CURSO despejaria a trilha inteira no mês corrente,
-- então `v_projecao_aluno` cai para MEDIA_METODO e segue em silêncio. Esta
-- pendência é o que tira o silêncio dali — sem ela, o aluno é projetado como
-- quem não tem previsão nenhuma e ninguém nunca fica sabendo que há uma data a
-- corrigir.
select is(
  (select format('%s/%s/%s/%s', p.severidade,
                 p.chave_dedup = 'PREVISAO:' || a.id::text,
                 p.descricao like '%3004%',
                 p.descricao like '%' || to_char(a.prev_conclusao_curso, 'DD/MM/YYYY') || '%15 dia(s)%')
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Diego Alves' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'PREVISAO_VENCIDA' and p.resolvida_em is null),
  'MEDIA/t/t/t',
  'previsao 15 dias no passado abre a pendencia MEDIA, com a DATA vencida e ha quantos dias na descricao');

-- Bruno (+90) e Carla (+120) têm previsão informada e FUTURA, e são o contraste
-- que falta na asserção de cima: sem eles, uma regra que abrisse para toda
-- previsão preenchida passaria igual.
select is(
  (select count(*)::bigint from public.pendencia
    where unidade_id = tests.unidade('ESCOLA_A')
      and tipo = 'PREVISAO_VENCIDA' and resolvida_em is null),
  1::bigint,
  'e SO ele: os dois alunos com previsao futura nao abrem nada — o criterio e a data, nao o campo preenchido');

-- O filtro de status, medido do lado que importa: é ele que faz a formatura
-- fechar a pendência sozinha (catálogo §10.1, "fechada por ... formatura"), sem
-- trigger nenhum. Henrique está TRANCADO e ganha uma previsão vencida de 60
-- dias — o dobro da de Diego — e continua sem pendência.
update public.aluno set prev_conclusao_curso = public.fn_hoje() - 60
 where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Henrique Dias';

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Henrique Dias' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'PREVISAO_VENCIDA' and p.resolvida_em is null),
  0::bigint,
  'previsao vencida de quem NAO e ATIVO/ACELERAR nao abre pendencia: nao ha o que pedir a ninguem');

-- Corrigir a data — que é a ação que a pendência pede — fecha sozinha.
update public.aluno set prev_conclusao_curso = public.fn_hoje() + 45
 where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Diego Alves';

select public.rt_pendencias_diaria();

select is(
  (select format('%s/%s', p.resolucao, p.resolvida_por is null)
     from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Diego Alves' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'PREVISAO_VENCIDA'),
  'RESOLVIDA/t',
  'nova prev_conclusao_curso no futuro fecha a pendencia automaticamente');

-- E reabre enquanto a condição valer, como toda pendência de tempo (§5).
update public.aluno set prev_conclusao_curso = public.fn_hoje() - 15
 where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Diego Alves';

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Diego Alves' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'PREVISAO_VENCIDA' and p.resolvida_em is null),
  1::bigint,
  'e a data vencida de volta reabre a pendencia: o caminho de ida e volta existe nos dois tipos novos');

-- Sair de ATIVO/ACELERAR fecha pela MESMA expressão que fecharia na formatura —
-- CANCELADO só evita depender do gate de certificado do card 8.3 para provar o
-- que é uma propriedade do `where`, não do status escolhido.
update public.aluno set status = 'CANCELADO'
 where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Diego Alves';

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Diego Alves' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'PREVISAO_VENCIDA' and p.resolvida_em is null),
  0::bigint,
  'e sair de ATIVO/ACELERAR fecha: e a mesma metade do where que faz a formatura fechar sozinha');

-- ===========================================================================
-- 17. ESTOQUE_ABAIXO_MINIMO — card 8.4,5, e os dois filtros que a view não tem
-- ===========================================================================
-- O que a §2 prova é que o tipo ENTROU na rotina, nos três saldos zero da
-- fixture. O que se prova aqui é que ele entrou com a regra certa, e as quatro
-- armadilhas medidas são:
--   • a borda é `<`, e ela mora na view: `INTERATIVO 03` tem saldo 1 e mínimo 1,
--     e "igual ao mínimo" NÃO é abaixo do mínimo;
--   • material sem movimento NENHUM tem de aparecer — é a armadilha §3.2 do card
--     2.3, e é o material que mais precisa ser comprado;
--   • material INATIVO fica de fora, senão aposentar uma apostila abre uma
--     pendência que ninguém pode fechar;
--   • `estoque_minimo = 0` não é "mínimo zero", é mínimo não configurado.
--
-- Os dois últimos filtros são os que `v_estoque_atual` NÃO aplica, de propósito
-- (`docs/views-leitura.md` §2.3): a view fala do estoque que a escola TEM, a
-- pendência fala do que ela precisa COMPRAR.
select is(
  (select format('%s/%s/%s', p.severidade,
                 p.chave_dedup = 'MINIMO:' || m.id::text,
                 p.descricao)
     from public.pendencia p
     join public.material m on m.id = p.material_id
     join public.metodo me on me.id = m.metodo_id
    where me.codigo = 'INTERATIVO' and m.codigo = '02'
      and p.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'ESTOQUE_ABAIXO_MINIMO' and p.resolvida_em is null),
  'BAIXA/t/Informática Essencial 2 (INTERATIVO 02) está com saldo 0, abaixo do mínimo de 1 — avaliar compra.',
  'a pendencia e BAIXA, com a chave do catalogo e os DOIS numeros (saldo e minimo) na descricao');

-- A borda. `INTERATIVO 03` tem saldo 1 para mínimo 1 — é o último exemplar, o
-- mesmo da corrida do card 6.3 — e não abre nada. Escrita `<=`, a regra abriria
-- aqui e a asserção de cima continuaria passando: é esta linha que separa as
-- duas.
select is(
  (select count(*)::bigint from public.pendencia p
     join public.material m on m.id = p.material_id
     join public.metodo me on me.id = m.metodo_id
    where me.codigo = 'INTERATIVO' and m.codigo = '03'
      and p.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'ESTOQUE_ABAIXO_MINIMO' and p.resolvida_em is null),
  0::bigint,
  'saldo IGUAL ao minimo nao abre pendencia: a comparacao e <, e ela mora em v_estoque_atual');

-- A armadilha §3.2 do card 2.3, medida: material recém-cadastrado, mínimo
-- definido e NENHUM movimento. Lendo `movimento_estoque` direto, com `join`
-- interno, ele sumiria — e some justamente o material de que a escola não tem
-- um exemplar sequer.
insert into public.material (unidade_id, metodo_id, codigo, nome, categoria, estoque_minimo)
select tests.unidade('ESCOLA_A'), me.id, '05', 'Informática Avançada 3', 'APOSTILA', 3
  from public.metodo me
 where me.unidade_id = tests.unidade('ESCOLA_A') and me.codigo = 'INTERATIVO';

select public.rt_pendencias_diaria();

select is(
  (select p.descricao from public.pendencia p
     join public.material m on m.id = p.material_id
    where m.nome = 'Informática Avançada 3'
      and p.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'ESTOQUE_ABAIXO_MINIMO' and p.resolvida_em is null),
  'Informática Avançada 3 (INTERATIVO 05) está com saldo 0, abaixo do mínimo de 3 — avaliar compra.',
  'material SEM MOVIMENTO NENHUM entra na lista com saldo 0 — a armadilha do left join, do lado certo');

-- Aposentar o material fecha a pendência: a view continua mostrando o saldo
-- dele (é estoque que a escola tem), e é a ROTINA que sabe que não se compra o
-- que foi aposentado.
update public.material m
   set ativo = false
  from public.metodo me
 where me.id = m.metodo_id and me.codigo = 'INGLES' and m.codigo = '02'
   and m.unidade_id = tests.unidade('ESCOLA_A');

select public.rt_pendencias_diaria();

select is(
  (select format('%s/%s/%s',
                 count(*) filter (where p.resolvida_em is null),
                 count(*),
                 bool_and(p.resolucao = 'RESOLVIDA' and p.resolvida_por is null))
     from public.pendencia p
     join public.material m on m.id = p.material_id
     join public.metodo me on me.id = m.metodo_id
    where me.codigo = 'INGLES' and m.codigo = '02'
      and p.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'ESTOQUE_ABAIXO_MINIMO'),
  '0/1/t',
  'material INATIVO sai da lista e a pendencia fecha sozinha — nao se compra apostila aposentada');

-- Mínimo zero é mínimo NÃO CONFIGURADO, e o caso que separa isso de uma
-- redundância é o SALDO NEGATIVO — medido, e não suposto: com mínimo 0 e saldo
-- 0 a própria view já devolve `abaixo_minimo` falso (`0 < 0`), então uma
-- asserção escrita assim passaria com o filtro apagado. A primeira versão desta
-- seção era essa, e a contraprova 3 do card 8.4,5 saiu VERDE — foi ela que
-- mandou reescrever isto aqui.
--
-- Saldo negativo não é hipótese: `fn_estoque_ajustar` o recusa (card 6.5), mas a
-- guarda mora na FUNÇÃO, e `movimento_estoque` aceita a linha por qualquer outro
-- caminho — importação do card 9.1, correção feita por fora. É por isso que a
-- tela do card 6.7 DESTACA o saldo negativo em vez de escondê-lo, e é por isso
-- que ele não pode virar uma pendência dizendo "abaixo do mínimo de 0": o que se
-- pede ali é conferência de prateleira, não compra.
update public.material m
   set estoque_minimo = 0
  from public.metodo me
 where me.id = m.metodo_id and me.codigo = 'INTERATIVO' and m.codigo = '04'
   and m.unidade_id = tests.unidade('ESCOLA_A');

insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade,
                                      ocorrido_em, observacao)
select tests.unidade('ESCOLA_A'), m.id, 'AJUSTE', -1, now(),
       'ajuste errado, do tipo que a tela do 6.7 destaca (teste 090 §17)'
  from public.material m
  join public.metodo me on me.id = m.metodo_id
 where me.codigo = 'INTERATIVO' and m.codigo = '04'
   and m.unidade_id = tests.unidade('ESCOLA_A');

select public.rt_pendencias_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.material m on m.id = p.material_id
     join public.metodo me on me.id = m.metodo_id
    where me.codigo = 'INTERATIVO' and m.codigo = '04'
      and p.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'ESTOQUE_ABAIXO_MINIMO' and p.resolvida_em is null),
  0::bigint,
  'minimo ZERO nao abre pendencia nem com saldo NEGATIVO: minimo zero e minimo nao configurado');

-- E a compra chegando fecha, que é a ação que a pendência pede (catálogo §10.1:
-- "fechada quando saldo ≥ mínimo"). Uma entrada de UM exemplar leva
-- `INTERATIVO 02` de 0 para 1, exatamente o mínimo — a mesma borda de cima, do
-- outro lado.
insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade,
                                      ocorrido_em, observacao)
select tests.unidade('ESCOLA_A'), m.id, 'ENTRADA', 1, now(),
       'chegada de compra (teste 090 §17)'
  from public.material m
  join public.metodo me on me.id = m.metodo_id
 where me.codigo = 'INTERATIVO' and m.codigo = '02'
   and m.unidade_id = tests.unidade('ESCOLA_A');

select public.rt_pendencias_diaria();

select is(
  (select format('%s/%s', p.resolucao, p.resolvida_por is null)
     from public.pendencia p
     join public.material m on m.id = p.material_id
     join public.metodo me on me.id = m.metodo_id
    where me.codigo = 'INTERATIVO' and m.codigo = '02'
      and p.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'ESTOQUE_ABAIXO_MINIMO'),
  'RESOLVIDA/t',
  'a entrada que leva o saldo AO minimo fecha a pendencia sozinha, sem pessoa e sem trigger');

select * from finish();
rollback;
