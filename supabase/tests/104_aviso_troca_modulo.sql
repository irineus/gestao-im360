-- =============================================================================
-- Aviso de troca de módulo — card 9.2,85
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- A fixture já tem as três turmas de que este arquivo precisa (camada
-- `modular`), em estados diferentes de propósito:
--
--   Eletricista 2026.1          corrente = módulo 2 (livro 01), previsão +35
--                               dias; o próximo é o módulo 3, do livro 02
--   Eletricista 2025.2          corrente = módulo 1, previsão VENCIDA há 40
--                               dias; o módulo 2 NÃO está no cronograma
--   Eletricista Individual 2026 corrente = módulo 1, previsão +45 dias
--
-- O que este arquivo prova e nenhum outro enxerga:
--   • as QUATRO bordas da situação, movendo a DATA e depois o PARÂMETRO — a
--     segunda é a única prova de que a janela vem de `troca_modulo_alerta_dias`
--     e não de um 10 escrito na view (lição do card 8.4);
--   • que o vermelho começa NO DIA, e que `modulo_atrasado` NÃO mudou de
--     sentido — as duas colunas, lado a lado, na mesma linha;
--   • que o próximo módulo sai do CATÁLOGO (a `2025.2` não tem a linha no
--     cronograma) e que a troca de livro é verdadeira numa turma e falsa na
--     outra;
--   • as três regras da pendência que a tornam diferente das outras da rotina:
--     resolvida por gente não reabre, ignorada reabre, e avançar o módulo não
--     fecha;
--   • quem enxerga: direção e pedagógico sim, secretaria e monitor NÃO — e a
--     secretaria, que tem `pendencias.resolver`, recebe PENDENCIA_INEXISTENTE.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(38);

create temporary view turma (nome, id) as
  select t.nome, t.id from public.turma_modular t
   where t.unidade_id = tests.unidade('ESCOLA_A');

-- A linha do cronograma do módulo CORRENTE de uma turma, lida das tabelas e
-- não da view em teste.
create function pg_temp.crono(p_turma text) returns uuid language sql stable as $$
  select tm.id
    from public.turma_modular_modulo tm
    join public.modulo m on m.id = tm.modulo_id
   where tm.turma_id = (select id from turma where nome = p_turma)
     and not tm.concluido
   order by m.ordem, tm.modulo_id
   limit 1
$$;

create function pg_temp.chave(p_turma text) returns text language sql stable as $$
  select 'TROCA_MODULO:' || (select id::text from turma where nome = p_turma)
         || ':' || pg_temp.crono(p_turma)::text
$$;

-- Move a previsão do módulo corrente para `hoje + p_dias` (nulo apaga).
create function pg_temp.prever(p_turma text, p_dias integer) returns void
language sql as $$
  update public.turma_modular_modulo
     set prev_conclusao = public.fn_hoje() + p_dias
   where id = pg_temp.crono(p_turma)
$$;

create function pg_temp.situacao(p_turma text) returns text language sql stable as $$
  select l.situacao_troca from public.v_turma_modular_lotacao l
   where l.turma_id = (select id from turma where nome = p_turma)
$$;

-- "ABERTA:MEDIA", "FECHADA:RESOLVIDA:GENTE", ou "nenhuma". A ABERTA vem primeiro:
-- dentro de uma transação `now()` não anda, então `criado_em` empata entre a
-- linha fechada e a reaberta, e ordenar só por ele seria sorteio (§11 da
-- estratégia de testes). O índice parcial garante que aberta há no máximo uma.
create function pg_temp.pendencia_de(p_chave text) returns text language sql stable as $$
  select coalesce(
    (select case when p.resolvida_em is null then 'ABERTA:' || p.severidade
                 else 'FECHADA:' || p.resolucao
                      || case when p.resolvida_por is null then ':SISTEMA' else ':GENTE' end
            end
       from public.pendencia p
      where p.unidade_id = tests.unidade('ESCOLA_A') and p.chave_dedup = p_chave
      order by (p.resolvida_em is null) desc, p.criado_em desc, p.id desc
      limit 1),
    'nenhuma')
$$;

create function pg_temp.rodar() returns void language plpgsql as $$
begin
  perform tests.como_rotina(tests.unidade('ESCOLA_A'));
  perform public.rt_pendencias_diaria();
  perform tests.encerrar_sessao();
end $$;

select tests.como_rotina(tests.unidade('ESCOLA_A'));

-- ===========================================================================
-- 1. A situação da troca — as quatro bordas, pela DATA
-- ===========================================================================
select is(
  (select string_agg(l.turma_nome || '=' || l.situacao_troca || '(' || l.dias_para_troca || ')',
                     ', ' order by l.turma_nome)
     from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')),
  'Eletricista 2025.2=HOJE_OU_VENCIDA(-40), Eletricista 2026.1=EM_DIA(35), '
  'Eletricista Individual 2026=EM_DIA(45)',
  'as tres turmas da fixture, cada uma com a sua situacao e os dias para a troca');

select pg_temp.prever('Eletricista 2026.1', 11);
select is(pg_temp.situacao('Eletricista 2026.1'), 'EM_DIA',
  'faltando 11 dias, com a janela de 10: ainda em dia');

select pg_temp.prever('Eletricista 2026.1', 10);
select is(pg_temp.situacao('Eletricista 2026.1'), 'PROXIMA',
  'faltando exatamente 10 dias: laranja — a borda e <=, "10 dias ou menos"');

select pg_temp.prever('Eletricista 2026.1', 1);
select is(pg_temp.situacao('Eletricista 2026.1'), 'PROXIMA',
  'faltando 1 dia: ainda laranja');

-- A borda que separa este card do 7.4: NO DIA já é vermelho, e `modulo_atrasado`
-- continua falso — as duas colunas convivem, cada uma com a sua pergunta.
select pg_temp.prever('Eletricista 2026.1', 0);
select is(
  (select l.situacao_troca || ' / atrasado=' || l.modulo_atrasado::text
     from public.v_turma_modular_lotacao l
    where l.turma_id = (select id from turma where nome = 'Eletricista 2026.1')),
  'HOJE_OU_VENCIDA / atrasado=false',
  'no DIA da troca a situacao ja e vermelha, e modulo_atrasado continua falso (borda <, card 7.4)');

select pg_temp.prever('Eletricista 2026.1', null);
select is(
  (select l.situacao_troca || ' / dias=' || coalesce(l.dias_para_troca::text, 'nulo')
     from public.v_turma_modular_lotacao l
    where l.turma_id = (select id from turma where nome = 'Eletricista 2026.1')),
  'SEM_PREVISAO / dias=nulo',
  'sem previsao nao ha troca a anunciar: nulo e ausencia, nao previsao vencida');

-- ===========================================================================
-- 2. A janela vem do PARÂMETRO
-- ===========================================================================
select pg_temp.prever('Eletricista 2026.1', 35);

update public.parametro set valor = '40'
 where unidade_id = tests.unidade('ESCOLA_A') and chave = 'troca_modulo_alerta_dias';

select is(pg_temp.situacao('Eletricista 2026.1'), 'PROXIMA',
  'com a janela em 40 dias, a turma a 35 dias passa a laranja: o limiar e o parametro');

update public.parametro set valor = '10'
 where unidade_id = tests.unidade('ESCOLA_A') and chave = 'troca_modulo_alerta_dias';

select is(pg_temp.situacao('Eletricista 2026.1'), 'EM_DIA',
  'e de volta a 10, volta a estar em dia');

-- Sem default embutido (card 8.4): parâmetro ausente fala alto.
delete from public.parametro
 where unidade_id = tests.unidade('ESCOLA_A') and chave = 'troca_modulo_alerta_dias';

select is(
  tests.codigo_do_erro(
    'select situacao_troca from public.v_turma_modular_lotacao'),
  'PARAMETRO_AUSENTE',
  'sem troca_modulo_alerta_dias a view NAO inventa um 10: PARAMETRO_AUSENTE');

select tests.como_rotina(tests.unidade('ESCOLA_A'));
select public.fn_seed_parametros(tests.unidade('ESCOLA_A'));

select is(
  (select valor from public.parametro
    where unidade_id = tests.unidade('ESCOLA_A') and chave = 'troca_modulo_alerta_dias'),
  '10', 'o seed devolve o parametro com o valor inicial decidido em 10/11/2026');

-- ===========================================================================
-- 3. O próximo módulo e a troca de livro
-- ===========================================================================
select is(
  (select format('%s -> %s | livro %s | troca=%s', l.modulo_corrente_nome,
                 l.proximo_modulo_nome, l.proximo_material_nome, l.troca_de_livro::text)
     from public.v_turma_modular_lotacao l
    where l.turma_id = (select id from turma where nome = 'Eletricista 2026.1')),
  (select format('Módulo 2 — Instalações prediais -> Módulo 3 — Projetos | livro %s | troca=true', m.nome)
     from public.material m
     join public.metodo me on me.id = m.metodo_id
    where m.unidade_id = tests.unidade('ESCOLA_A') and me.codigo = 'MODULAR' and m.codigo = '02'),
  'o modulo 3 e do livro 02 e o corrente do 01: troca de livro');

-- A `2025.2` só tem o módulo 1 no cronograma. O próximo sai do CATÁLOGO.
select is(
  (select format('%s | troca=%s', l.proximo_modulo_nome, l.troca_de_livro::text)
     from public.v_turma_modular_lotacao l
    where l.turma_id = (select id from turma where nome = 'Eletricista 2025.2')),
  'Módulo 2 — Instalações prediais | troca=false',
  'o proximo modulo vem do catalogo mesmo sem linha no cronograma, e aqui o livro e o mesmo');

-- ⚠️ Card 9.2,88: no último módulo o próximo é o PRIMEIRO — a turma dá a volta.
--    Até o rodízio as duas colunas vinham nulas aqui; agora a troca de livro
--    vale também na virada do ciclo (módulo 3 é do livro 02, o 1 é do 01).
update public.turma_modular_modulo tm set concluido = true
  from public.modulo m
 where m.id = tm.modulo_id and m.ordem = 2
   and tm.turma_id = (select id from turma where nome = 'Eletricista 2026.1');

select is(
  (select format('%s | proximo=%s | troca=%s', l.modulo_corrente_ordem,
                 coalesce(l.proximo_modulo_nome, 'nulo'), coalesce(l.troca_de_livro::text, 'nulo'))
     from public.v_turma_modular_lotacao l
    where l.turma_id = (select id from turma where nome = 'Eletricista 2026.1')),
  '3 | proximo=Módulo 1 — Comandos elétricos | troca=true',
  'turma no ultimo modulo: o proximo e o PRIMEIRO do rodizio, e a troca de livro vale na virada do ciclo');

update public.turma_modular_modulo tm set concluido = false
  from public.modulo m
 where m.id = tm.modulo_id and m.ordem = 2
   and tm.turma_id = (select id from turma where nome = 'Eletricista 2026.1');

-- As colunas novas entraram NO FIM (card 9.2,7): `create or replace view` só
-- aceita acrescentar no fim, e a tela lê por nome — mas a posição é o que
-- garante que a view anterior continua sendo um prefixo desta.
select is(
  (select string_agg(a.attname, ',' order by a.attnum)
     from pg_attribute a
    where a.attrelid = 'public.v_turma_modular_lotacao'::regclass
      and a.attnum > 17 and not a.attisdropped),
  'modulo_corrente_cronograma_id,proximo_modulo_id,proximo_modulo_nome,proximo_material_id,'
  'proximo_material_nome,troca_de_livro,dias_para_troca,situacao_troca,modulo_corrente_ciclo',
  'as oito colunas do card 9.2,85 e o ciclo do 9.2,88 vem depois das dezessete do card 9.2,7, nesta ordem');

-- Quem não tem `parametros.ler` lê a situação do mesmo jeito: fn_param_int é
-- definer (card 8.1, ajuste 1). Sem isso a tela 5 da secretaria quebraria.
select tests.encerrar_sessao();

select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
                   'select 1 from public.v_turma_modular_lotacao where situacao_troca is not null'),
  3::bigint,
  'a secretaria, sem parametros.ler, le a situacao das tres turmas');

select is(
  tests.conta_como(tests.uid('monitor@escola-a.test'),
                   'select 1 from public.v_turma_modular_lotacao where situacao_troca is not null'),
  3::bigint,
  'e o monitor tambem');

-- ===========================================================================
-- 4. A pendência — abre no laranja, sobe no vermelho
-- ===========================================================================
select pg_temp.rodar();

select is(pg_temp.pendencia_de(pg_temp.chave('Eletricista 2025.2')), 'ABERTA:ALTA',
  'a turma com o modulo vencido abre TROCA_MODULO_ALINHAR em ALTA');

select is(pg_temp.pendencia_de(pg_temp.chave('Eletricista 2026.1')), 'nenhuma',
  'a turma a 35 dias da troca nao abre nada');

select pg_temp.prever('Eletricista 2026.1', 10);
select pg_temp.rodar();

select is(pg_temp.pendencia_de(pg_temp.chave('Eletricista 2026.1')), 'ABERTA:MEDIA',
  'entrando na janela de 10 dias, abre em MEDIA');

select matches(
  (select p.descricao from public.pendencia p
    where p.chave_dedup = pg_temp.chave('Eletricista 2026.1') and p.resolvida_em is null),
  '^Turma Eletricista 2026\.1 \(Eletricista Instalador\): o módulo Módulo 2 — Instalações prediais termina em \d\d/\d\d/\d{4}, em 10 dia\(s\)\. Alinhar a troca de módulo com o professor — o próximo módulo, Módulo 3 — Projetos, é de outro livro \(.+\)\.$',
  'a descricao diz a turma, o modulo, a data, os dias e a troca de livro');

select pg_temp.prever('Eletricista 2026.1', 0);
select pg_temp.rodar();

select is(pg_temp.pendencia_de(pg_temp.chave('Eletricista 2026.1')), 'ABERTA:ALTA',
  'no dia da troca a MESMA pendencia sobe para ALTA');

select is(
  (select count(*)::bigint from public.pendencia p
    where p.chave_dedup = pg_temp.chave('Eletricista 2026.1')),
  1::bigint,
  'e continua sendo UMA linha: a rotina refresca, nao duplica');

select matches(
  (select p.descricao from public.pendencia p
    where p.chave_dedup = pg_temp.chave('Eletricista 2026.1') and p.resolvida_em is null),
  'termina hoje',
  'e a descricao acompanha o dia: "termina hoje"');

-- ===========================================================================
-- 5. Quem enxerga e quem resolve
-- ===========================================================================
select is(
  (select string_agg(pe.codigo, ',' order by pe.codigo)
     from public.perfil_permissao pp
     join public.perfil    pe on pe.id = pp.perfil_id
     join public.permissao pm on pm.id = pp.permissao_id
    where pe.unidade_id = tests.unidade('ESCOLA_A') and pm.codigo = 'turmas.alinhar_modulo'),
  'DIRECAO,PEDAGOGICO',
  'turmas.alinhar_modulo nasce so na direcao e no pedagogico (decisao de 10/11/2026)');

select is(
  (select format('direcao=%s pedagogico=%s secretaria=%s monitor=%s',
     tests.conta_como(tests.uid('direcao@escola-a.test'),
       'select 1 from public.v_pendencias_abertas where tipo = ''TROCA_MODULO_ALINHAR'''),
     tests.conta_como(tests.uid('pedagogico@escola-a.test'),
       'select 1 from public.v_pendencias_abertas where tipo = ''TROCA_MODULO_ALINHAR'''),
     tests.conta_como(tests.uid('secretaria@escola-a.test'),
       'select 1 from public.v_pendencias_abertas where tipo = ''TROCA_MODULO_ALINHAR'''),
     tests.conta_como(tests.uid('monitor@escola-a.test'),
       'select 1 from public.v_pendencias_abertas where tipo = ''TROCA_MODULO_ALINHAR'''))),
  'direcao=2 pedagogico=2 secretaria=0 monitor=0',
  'direcao e pedagogico veem os dois avisos; secretaria e monitor, nenhum');

-- A secretaria TEM `pendencias.resolver`. O que a barra é a leitura: para ela a
-- pendência não existe, pelo mesmo caminho que isola unidade (card 5.5 §5).
select is(
  tests.codigo_do_erro(
    format('select public.fn_pendencia_resolver_id(%L, ''RESOLVIDA'')',
           (select p.id from public.pendencia p
             where p.chave_dedup = pg_temp.chave('Eletricista 2026.1') and p.resolvida_em is null)),
    tests.uid('secretaria@escola-a.test')),
  'PENDENCIA_INEXISTENTE',
  'a secretaria, com pendencias.resolver e sem turmas.alinhar_modulo, nao resolve o que nao ve');

select is(pg_temp.pendencia_de(pg_temp.chave('Eletricista 2026.1')), 'ABERTA:ALTA',
  'e a pendencia continua aberta depois da tentativa');

-- O update direto, sem passar pela função, esbarra na política de update.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

with u as (
  update public.pendencia
     set resolvida_em = now(), resolucao = 'RESOLVIDA'
   where tipo = 'TROCA_MODULO_ALINHAR'
  returning 1)
select is((select count(*)::bigint from u), 0::bigint,
  'o update direto da secretaria afeta ZERO linhas deste tipo');

reset role;
select tests.encerrar_sessao();

-- ===========================================================================
-- 6. Resolvida por gente NÃO reabre; ignorada reabre
-- ===========================================================================
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));

select lives_ok(
  format('select public.fn_pendencia_resolver_id(%L, ''RESOLVIDA'', ''Alinhado com o professor'')',
         (select p.pendencia_id from public.v_pendencias_abertas p
           where p.chave_dedup like 'TROCA_MODULO:%'
             and p.descricao like 'Turma Eletricista 2026.1 %')),
  'o pedagogico resolve: o alinhamento com o professor foi feito');

select lives_ok(
  format('select public.fn_pendencia_resolver_id(%L, ''IGNORADA'', ''Turma sem aluno'')',
         (select p.pendencia_id from public.v_pendencias_abertas p
           where p.chave_dedup like 'TROCA_MODULO:%'
             and p.descricao like 'Turma Eletricista 2025.2 %')),
  'e ignora a da outra turma, com justificativa');

reset role;
select tests.encerrar_sessao();

select pg_temp.rodar();

select is(pg_temp.pendencia_de(pg_temp.chave('Eletricista 2026.1')), 'FECHADA:RESOLVIDA:GENTE',
  'a rotina do dia seguinte NAO reabre o alinhamento ja feito, com a troca ainda no dia');

select is(pg_temp.pendencia_de(pg_temp.chave('Eletricista 2025.2')), 'ABERTA:ALTA',
  'a IGNORADA volta enquanto a condicao valer, como em todo tipo (card 5.5)');

-- ===========================================================================
-- 7. Avançar o módulo não fecha; adiar a data fecha
-- ===========================================================================
-- A `2025.2` tem a pendência ABERTA. A direção avança o módulo sem que ninguém
-- registre o alinhamento: é exatamente o caso que o aviso existe para pegar.
create temporary table t_chave_antiga as
  select pg_temp.chave('Eletricista 2025.2') as chave,
         (select id from turma where nome = 'Eletricista 2025.2') as turma_id;
grant select on t_chave_antiga to authenticated;

select tests.autenticar(tests.uid('direcao@escola-a.test'));

select lives_ok(
  format('select public.fn_turma_modular_avancar(%L)',
         (select turma_id from t_chave_antiga)),
  'a direcao avanca o modulo da turma com o alinhamento pendente');

reset role;
select tests.encerrar_sessao();
select pg_temp.rodar();

select is(pg_temp.pendencia_de((select chave from t_chave_antiga)), 'ABERTA:ALTA',
  'avancar o modulo NAO fecha a pendencia: ela fica, em ALTA');

select matches(
  (select p.descricao from public.pendencia p
    where p.chave_dedup = (select chave from t_chave_antiga) and p.resolvida_em is null),
  'foi concluído sem o alinhamento com o professor registrado',
  'e passa a dizer que o modulo foi concluido sem o alinhamento');

-- A Individual: entra na janela, abre; a data é adiada para além dela, fecha
-- sozinha — a troca deixou de estar próxima.
select tests.como_rotina(tests.unidade('ESCOLA_A'));
select pg_temp.prever('Eletricista Individual 2026', 5);
select pg_temp.rodar();

select is(pg_temp.pendencia_de(pg_temp.chave('Eletricista Individual 2026')), 'ABERTA:MEDIA',
  'a terceira turma entra na janela e abre');

select tests.como_rotina(tests.unidade('ESCOLA_A'));
select pg_temp.prever('Eletricista Individual 2026', 30);
select pg_temp.rodar();

select is(pg_temp.pendencia_de(pg_temp.chave('Eletricista Individual 2026')), 'FECHADA:RESOLVIDA:SISTEMA',
  'adiada a previsao para alem da janela, a pendencia fecha SOZINHA (resolvida_por nulo)');

-- E reabre se a data voltar: o fechamento automático não é alinhamento.
select tests.como_rotina(tests.unidade('ESCOLA_A'));
select pg_temp.prever('Eletricista Individual 2026', 3);
select pg_temp.rodar();

select is(pg_temp.pendencia_de(pg_temp.chave('Eletricista Individual 2026')), 'ABERTA:MEDIA',
  'e volta a abrir quando a data volta para dentro da janela: fechamento automatico nao e alinhamento');

select * from finish();
rollback;
