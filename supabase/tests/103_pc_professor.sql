-- =============================================================================
-- PC que não é lugar de aluno: a máquina do professor não conta como vaga
-- — card 9.2,77 (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- O achado do monitor (30/09/2026), medido no dev: a sala Tecnologia/Inglês tem
-- 11 PCs — dez de aluno e o do professor — e capacidade nominal 10. A fórmula
-- do card 5.2 contava os onze, e o `least` com a nominal ESCONDIA o erro com
-- tudo operacional (10) e o mantinha escondido com UM PC de aluno parado
-- (least(10, 10) = 10): a máquina do professor tapava o buraco. A partir da
-- primeira quebra o sistema admite um aluno a mais, em silêncio.
--
-- Este arquivo reproduz a sala inteira — onze PCs, um do professor, nominal 10
-- — e assere o par que o card pede: 10 com todos operacionais e 9 com um PC de
-- aluno parado. A CONTRAPROVA é a própria marcação: desmarcado o PC do
-- professor, a segunda asserção volta a 10, que é o número de antes do card.
--
-- Depois: a pendência PC_SEM_SUBSTITUTO não abre para a máquina do professor
-- (ela não derruba capacidade nenhuma), marcar a máquina é EVENTO e fecha na
-- mesma transação a pendência que ela tinha, só quem tem `salas.editar` marca,
-- e o importador do card 9.1 aceita a chave — e NÃO a apaga quando ela vem
-- ausente.
--
-- ⚠️ As seções com ATOR (secretaria, monitor) saem do contexto de rotina antes:
--    lá dentro tem_permissao() é sempre verdadeira e a asserção de permissão
--    passaria sem provar nada (lição do teste 090, seção 11).
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(17);

-- ===========================================================================
-- 1. A sala do achado: onze PCs, um do professor, nominal 10
-- ===========================================================================
select tests.como_rotina(tests.unidade('ESCOLA_A'));

insert into public.sala (unidade_id, nome, tipo, capacidade_nominal)
values (tests.unidade('ESCOLA_A'), 'Tecnologia 9.2,77', 'LABORATORIO', 10);

insert into public.pc (unidade_id, sala_id, identificador, de_professor)
select tests.unidade('ESCOLA_A'), s.id, x.identificador, x.identificador = 'T77-PROF'
  from public.sala s
 cross join (select format('T77-%s', lpad(g::text, 2, '0')) as identificador
               from generate_series(1, 10) g
             union all select 'T77-PROF') x
 where s.unidade_id = tests.unidade('ESCOLA_A') and s.nome = 'Tecnologia 9.2,77';

insert into public.bloco_horario (unidade_id, dia_semana, hora_inicio, metodo_id, sala_id)
select tests.unidade('ESCOLA_A'), 1, time '08:00',
       (select id from public.metodo
         where unidade_id = tests.unidade('ESCOLA_A') and codigo = 'INTERATIVO'),
       s.id
  from public.sala s
 where s.unidade_id = tests.unidade('ESCOLA_A') and s.nome = 'Tecnologia 9.2,77';

create temporary view t_cap as
  select public.fn_capacidade_efetiva(b.id) as cap
    from public.bloco_horario b
    join public.sala s on s.id = b.sala_id
   where s.nome = 'Tecnologia 9.2,77' and b.unidade_id = tests.unidade('ESCOLA_A');

create temporary view t_pc_sem_subst as
  select pc.identificador
    from public.pendencia p
    join public.pc pc on pc.id = p.pc_id
   where p.tipo = 'PC_SEM_SUBSTITUTO' and p.resolvida_em is null
     and pc.identificador like 'T77-%';

select is(
  (select format('%s PCs, %s do professor, %s operacionais',
                 count(*), count(*) filter (where p.de_professor),
                 count(*) filter (where p.status = 'OPERACIONAL'))
     from public.pc p where p.identificador like 'T77-%'),
  '11 PCs, 1 do professor, 11 operacionais',
  'premissa: a sala do achado — dez PCs de aluno e o do professor, todos operacionais');

select is((select cap from t_cap), 10,
  'todos operacionais: capacidade 10 — os dez lugares de aluno (antes do card tambem dava 10, pelo least com a nominal)');

-- ===========================================================================
-- 2. Um PC de aluno parado: 9, e não 10
-- ===========================================================================
insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, descricao)
select tests.unidade('ESCOLA_A'), p.id, 'CORRETIVA', public.fn_hoje(), 'teste 103'
  from public.pc p where p.identificador = 'T77-01';

select is((select cap from t_cap), 9,
  'UM PC de aluno parado: capacidade 9 — antes do card dava 10, porque a maquina do professor tapava o buraco');

select is((select string_agg(identificador, ',' order by identificador) from t_pc_sem_subst),
  'T77-01',
  'e PC_SEM_SUBSTITUTO aberta para o PC de aluno parado, e so para ele');

-- A contraprova, na forma que o card pediu: sem a marcação, a mesma sala volta
-- a dizer 10 com um PC de aluno parado.
update public.pc set de_professor = false where identificador = 'T77-PROF';

select is((select cap from t_cap), 10,
  'CONTRAPROVA: desmarcado o PC do professor, a capacidade volta a 10 com um PC de aluno parado — o defeito do achado');

update public.pc set de_professor = true where identificador = 'T77-PROF';

select is((select cap from t_cap), 9,
  'remarcado, volta a 9');

-- ===========================================================================
-- 3. A máquina do professor parada não "derruba a capacidade da sala"
-- ===========================================================================
insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, descricao)
select tests.unidade('ESCOLA_A'), p.id, 'PREVENTIVA', public.fn_hoje(), 'teste 103'
  from public.pc p where p.identificador = 'T77-PROF';

select is(
  (select format('%s/%s', p.status, (select cap from t_cap))
     from public.pc p where p.identificador = 'T77-PROF'),
  'MANUTENCAO/9',
  'o PC do professor em manutencao: status derivado normalmente, e a capacidade continua 9 — ele nao contava');

select is((select string_agg(identificador, ',' order by identificador) from t_pc_sem_subst),
  'T77-01',
  'e NAO abre PC_SEM_SUBSTITUTO: a mensagem diria "a capacidade da sala caiu", e nao caiu');

select lives_ok($$ select public.rt_capacidades() $$,
  'a rotina diaria percorre a sala');

select is((select string_agg(identificador, ',' order by identificador) from t_pc_sem_subst),
  'T77-01',
  'e tambem nao a abre pelo caminho diario (rt_capacidades)');

-- ===========================================================================
-- 4. Marcar é EVENTO: a pendência que a máquina tinha fecha na hora
-- ===========================================================================
-- O PC-PROFESSOR do homolog pode estar exatamente assim: parado, desmarcado,
-- com PC_SEM_SUBSTITUTO aberta. Desmarcá-lo aqui reproduz o estado (o gatilho
-- de `pc` revalida a sala e a pendência abre).
update public.pc set de_professor = false where identificador = 'T77-PROF';

select is((select string_agg(identificador, ',' order by identificador) from t_pc_sem_subst),
  'T77-01,T77-PROF',
  'premissa: desmarcado e parado, o PC do professor abre PC_SEM_SUBSTITUTO como qualquer outro — o estado de antes do card');

-- Sai o contexto de rotina: quem marca é uma pessoa, pela tela.
select tests.encerrar_sessao();
select tests.autenticar(tests.uid('monitor@escola-a.test'));

with tentativa as (
  update public.pc set de_professor = true
   where identificador = 'T77-PROF' and unidade_id = public.fn_unidade_atual()
  returning 1)
select is((select count(*)::bigint from tentativa), 0::bigint,
  'o monitor NAO marca: zero linhas — a marcacao e de quem tem salas.editar (direcao ou secretaria)');

reset role;
select tests.encerrar_sessao();
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

with marcado as (
  update public.pc set de_professor = true
   where identificador = 'T77-PROF' and unidade_id = public.fn_unidade_atual()
  returning 1)
select is((select count(*)::bigint from marcado), 1::bigint,
  'a secretaria marca o PC do professor');

reset role;
select tests.encerrar_sessao();

select is((select string_agg(identificador, ',' order by identificador) from t_pc_sem_subst),
  'T77-01',
  'e a pendencia do PC do professor FECHA na mesma transacao — sem de_professor na lista do gatilho, ficaria ate as 03:10');

-- ===========================================================================
-- 5. O importador aceita a chave — e ausente não apaga
-- ===========================================================================
create temporary table t_lote (rotulo text, id uuid);
grant all on t_lote to authenticated;

select tests.autenticar(tests.uid('direcao@escola-a.test'));
insert into t_lote
  select 'com', public.fn_importacao_registrar('pc-professor.json', '2026-08-29'::date, $json$
{
  "sala": [{"nome": "Sala Importada 9.2,77", "tipo": "LABORATORIO", "capacidade_nominal": 2}],
  "pc": [{"identificador": "I77-01", "sala": "Sala Importada 9.2,77"},
         {"identificador": "I77-PROF", "sala": "Sala Importada 9.2,77", "de_professor": true}]
}
$json$::jsonb);
select public.fn_importacao_aplicar((select id from t_lote where rotulo = 'com'), false);

-- O arquivo do extrator do 9.2 não traz a chave (a aba PCS nem tem mapa).
insert into t_lote
  select 'sem', public.fn_importacao_registrar('pc-sem-chave.json', '2026-08-29'::date, $json$
{
  "sala": [{"nome": "Sala Importada 9.2,77", "tipo": "LABORATORIO", "capacidade_nominal": 2}],
  "pc": [{"identificador": "I77-01", "sala": "Sala Importada 9.2,77"},
         {"identificador": "I77-PROF", "sala": "Sala Importada 9.2,77"}]
}
$json$::jsonb);
select public.fn_importacao_aplicar((select id from t_lote where rotulo = 'sem'), false);

insert into t_lote
  select 'invalida', public.fn_importacao_registrar('pc-sim.json', '2026-08-29'::date, $json$
{
  "sala": [{"nome": "Sala Importada 9.2,77", "tipo": "LABORATORIO", "capacidade_nominal": 2}],
  "pc": [{"identificador": "I77-PROF", "sala": "Sala Importada 9.2,77", "de_professor": "sim"}]
}
$json$::jsonb);
reset role;
select tests.encerrar_sessao();

select is(
  (select string_agg(format('%s=%s', identificador, de_professor), ',' order by identificador)
     from public.pc where identificador like 'I77-%'),
  'I77-01=f,I77-PROF=t',
  'o importador grava de_professor quando o arquivo traz a chave, e false quando nao traz (PC novo) — mesmo depois de reimportado SEM a chave');

select is(
  (select format('%s/%s', o.severidade, o.codigo)
     from public.importacao_ocorrencia o
    where o.importacao_id = (select id from t_lote where rotulo = 'invalida')
      and o.entidade = 'pc' and o.valor = 'sim'),
  'ERRO/VALOR_INVALIDO',
  'valor que nao e true/false e ERRO na validacao — e nao 22P02 no cast da aplicacao');

select ok(
  (select pg_get_functiondef('public.fn_importacao_aplicar(uuid, boolean)'::regprocedure)
          !~* 'de_professor\s*=\s*excluded\.de_professor'),
  'o upsert de pc NAO sobrescreve de_professor com o excluded — e isso que preserva a marcacao feita na tela');

select * from finish();
rollback;
