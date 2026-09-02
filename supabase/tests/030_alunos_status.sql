-- =============================================================================
-- Alunos e transições de status — card 4.2
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- O card é de "Migração de schema" E de "Função de aplicação", então o §13 cobra
-- as duas listas: suíte de catálogo verde com as tabelas novas (010 e 011 fazem
-- sozinhas, derivando do catálogo do Postgres) + um teste por check/unique que
-- expresse regra de negócio; e, para cada função, caminho feliz com efeito
-- conferido, um `codigo` por erro possível, negativo de permissão e o teste de
-- CAMADA 2 — escrever direto na tabela, contornando a função.
--
-- A camada 2 é a que mais vale aqui: com "Automatically expose new tables"
-- ligado, `aluno` é uma API REST, e um PATCH de status pelo PostgREST não passa
-- por fn_aluno_alterar_status. Se a regra morasse só na função, o caminho aberto
-- seria o mais fácil.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(56);

-- ===========================================================================
-- 1. A fixture chegou (camada `alunos` do card 3.4.5)
-- ===========================================================================
select is(
  (select count(*)::bigint from public.aluno a
     join public.unidade u on u.id = a.unidade_id where u.codigo = 'ESCOLA_A'),
  12::bigint,
  'doze alunos na unidade A, um por caso que alguma decisao criou');

select is(
  (select string_agg(distinct a.status, ',' order by a.status) from public.aluno a
     join public.unidade u on u.id = a.unidade_id where u.codigo = 'ESCOLA_A'),
  'ACELERAR,ATIVO,CANCELADO,FORMADO,STANDBY,TRANCADO',
  'os SEIS status estao representados — inclusive os dois terminais, que sao a unica entrada de fn_aluno_reverter_status');

-- `status_desde` e `data_inicio` são datas DIFERENTES: é a diferença entre elas
-- que o alerta de STANDBY prolongado (30 dias, card 5.5) lê. Uma fixture que as
-- igualasse passaria sem exercitar nada.
select ok(
  (select a.status_desde = public.fn_hoje() - 45
      and a.data_inicio  = public.fn_hoje() - 200
      and a.status_desde > a.data_inicio
     from public.aluno a join public.unidade u on u.id = a.unidade_id
    where u.codigo = 'ESCOLA_A' and a.nome = 'Gabriela Souza'),
  'a aluna esta em STANDBY ha 45 dias e matriculada ha 200 — o alerta de 30 dias do card 5.5 le a primeira data, nao a segunda');

-- ===========================================================================
-- 2. Regra em constraint — camada 1 (§6.1)
-- ===========================================================================
-- `codigo_sgf` é único POR UNIDADE e o índice é PARCIAL. Escrito sem o
-- `where codigo_sgf is not null`, o segundo aluno sem código seria recusado na
-- importação do card 9.1 — e aluno sem código é o caso comum na planilha.
select throws_ok(
  $$insert into public.aluno (unidade_id, nome, metodo_id, codigo_sgf)
    select u.id, 'Clone do 3001', m.id, '3001'
      from public.unidade u
      join public.metodo m on m.unidade_id = u.id and m.codigo = 'INTERATIVO'
     where u.codigo = 'ESCOLA_A'$$,
  '23505', null,
  'codigo_sgf repetido na MESMA unidade e recusado');

select is(
  (select count(*)::bigint from public.aluno where codigo_sgf = '3001'),
  2::bigint,
  'o mesmo codigo_sgf convive nas duas unidades — a unique carrega unidade_id');

select is(
  (select count(*)::bigint from public.aluno a
     join public.unidade u on u.id = a.unidade_id
    where u.codigo = 'ESCOLA_A' and a.codigo_sgf is null),
  3::bigint,
  'tres alunos sem codigo_sgf na mesma unidade');

select lives_ok(
  $$insert into public.aluno (unidade_id, nome, metodo_id)
    select u.id, 'Quarto aluno sem codigo', m.id
      from public.unidade u
      join public.metodo m on m.unidade_id = u.id and m.codigo = 'INTERATIVO'
     where u.codigo = 'ESCOLA_A'$$,
  'e o quarto nulo entra: nulo nao colide com nulo (o indice e parcial)');

-- String vazia NÃO é "sem código": ela colidiria no índice parcial e o card 9.1
-- receberia erro de chave duplicada por causa de uma célula em branco.
select throws_ok(
  $$insert into public.aluno (unidade_id, nome, metodo_id, codigo_sgf)
    select u.id, 'Codigo vazio', m.id, '   '
      from public.unidade u
      join public.metodo m on m.unidade_id = u.id and m.codigo = 'INTERATIVO'
     where u.codigo = 'ESCOLA_A'$$,
  '23514', null,
  'codigo_sgf em branco e recusado pelo check: sem codigo e NULO');

select throws_ok(
  $$insert into public.aluno (unidade_id, nome, metodo_id, status)
    select u.id, 'Status inventado', m.id, 'FORMANDO'
      from public.unidade u
      join public.metodo m on m.unidade_id = u.id and m.codigo = 'INTERATIVO'
     where u.codigo = 'ESCOLA_A'$$,
  '23514', null,
  'status fora dos seis do check e recusado — o conjunto e fechado (card 2.1 a)');

-- ===========================================================================
-- 3. fn_aluno_transicao_valida — tabela de decisão pura (§3.1 do card 2.2)
-- ===========================================================================
select is(
  (select coalesce(string_agg(format('%s->%s', de, para), ', ' order by de, para), '')
     from (values ('ATIVO','ACELERAR'), ('ACELERAR','ATIVO'),
                  ('ATIVO','STANDBY'),  ('ACELERAR','STANDBY'),
                  ('STANDBY','ATIVO'),  ('STANDBY','ACELERAR'), ('STANDBY','TRANCADO'),
                  ('TRANCADO','ATIVO'), ('TRANCADO','ACELERAR'),
                  ('ATIVO','FORMADO'),  ('ACELERAR','FORMADO'),
                  ('ATIVO','CANCELADO'), ('STANDBY','CANCELADO'), ('FORMADO','CANCELADO')
          ) as t(de, para)
    where not public.fn_aluno_transicao_valida(de, para)),
  '',
  'as onze transicoes do card 2.2 §3.1 valem, e qualquer origem vai a CANCELADO');

select is(
  (select coalesce(string_agg(format('%s->%s', de, para), ', ' order by de, para), '')
     from (values ('FORMADO','ATIVO'), ('FORMADO','ACELERAR'), ('CANCELADO','ATIVO'),
                  ('TRANCADO','STANDBY'), ('STANDBY','FORMADO'), ('TRANCADO','FORMADO'),
                  ('ATIVO','ATIVO'), ('CANCELADO','CANCELADO')
          ) as t(de, para)
    where public.fn_aluno_transicao_valida(de, para)),
  '',
  'terminais nao saem por transicao comum, TRANCADO/STANDBY nao formam e status igual nao e transicao');

-- ===========================================================================
-- 4. Camada 2 — o trigger vale para o PATCH direto no PostgREST
-- ===========================================================================
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select throws_ok(
  $$update public.aluno set status = 'ATIVO'
     where nome = 'João Pedro Martins' and unidade_id = public.fn_unidade_atual()$$,
  'PT409', null,
  'sair de FORMADO por UPDATE direto e recusado, sem passar por funcao nenhuma');

-- O `when (old.status is distinct from new.status)` dos dois triggers não é
-- otimização: sem ele, um PATCH que reenvia a linha inteira com o MESMO status
-- dispararia a validação com (CANCELADO, CANCELADO), que não está na tabela — e
-- corrigir a observação de um aluno cancelado responderia TRANSICAO_INVALIDA.
select lives_ok(
  $$update public.aluno set status = status, observacoes = 'observação corrigida na ficha'
     where nome = 'Isabela Rocha' and unidade_id = public.fn_unidade_atual()$$,
  'reenviar o MESMO status junto com outra coluna nao dispara a validacao');

reset role;

select is(
  (select count(*)::bigint from public.aluno_status_hist h
     join public.aluno a on a.id = h.aluno_id
    where a.nome = 'Isabela Rocha'),
  0::bigint,
  'e nao gerou linha de historico: status que nao mudou nao e transicao');

-- A política de update de `aluno` aceita o `or` de três códigos, e RLS NÃO é por
-- coluna (card 2.4): sem o guarda no trigger, um perfil com apenas
-- `alunos.editar` mudaria status pelo PostgREST. Nenhum perfil da matriz inicial
-- é assim — os três que editam também alteram status —, então o perfil é
-- montado aqui, dentro da transação, que é o único jeito de exercitar o caso
-- que a tela do card 4.7 vai tornar possível.
delete from public.perfil_permissao pp
 using public.perfil pe, public.permissao pm
 where pp.perfil_id = pe.id and pp.permissao_id = pm.id
   and pe.unidade_id = tests.unidade('ESCOLA_A') and pe.codigo = 'PEDAGOGICO'
   and pm.codigo in ('alunos.alterar_status', 'alunos.reverter_status');

select is(
  tests.codigo_do_erro(
    $$update public.aluno set status = 'STANDBY'
       where nome = 'Diego Alves' and unidade_id = public.fn_unidade_atual()$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'quem tem alunos.editar e nao tem alunos.alterar_status nao muda status pelo PostgREST');

-- Contraprova: o mesmo perfil, com o mesmo `alunos.editar`, continua editando as
-- outras colunas. Sem esta linha o negativo acima passaria mesmo que o trigger
-- estivesse barrando tudo.
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));

select lives_ok(
  $$update public.aluno set observacoes = 'telefone novo'
     where nome = 'Diego Alves' and unidade_id = public.fn_unidade_atual()$$,
  'e continua editando as demais colunas com alunos.editar');

reset role;

-- Devolve a permissão: os testes seguintes contam com a matriz do seed.
insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select pe.unidade_id, pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A') and pe.codigo = 'PEDAGOGICO'
   and pm.unidade_id = pe.unidade_id and pm.codigo = 'alunos.alterar_status';

-- ===========================================================================
-- 5. O gate de FORMADO (§3.3 do card 2.2)
-- ===========================================================================
-- O gate é permissão, nunca perfil (Decisões vigentes, card 2.2 g). Pedagógico
-- tem `alunos.alterar_status` e não tem `alunos.formar_sem_certificado`.
select is(
  tests.codigo_do_erro(
    $$update public.aluno set status = 'FORMADO'
       where nome = 'Ana Paula Ribeiro' and unidade_id = public.fn_unidade_atual()$$,
    tests.uid('pedagogico@escola-a.test')),
  'FORMATURA_SEM_CERTIFICADO',
  'sem certificado e sem a permissao de excecao, formar e recusado');

select tests.autenticar(tests.uid('direcao@escola-a.test'));

select lives_ok(
  $$update public.aluno set status = 'FORMADO'
     where nome = 'Ana Paula Ribeiro' and unidade_id = public.fn_unidade_atual()$$,
  'a direcao tem alunos.formar_sem_certificado e forma — a contraprova do negativo acima');

reset role;

-- ⚠️ PORTÃO DO CARD 8.3 — a metade do gate que ainda não pode existir.
--
-- `fn_aluno_pode_formar` hoje só implementa a condição (2), a permissão: a (1),
-- "existe certificado_checklist ENTREGUE", depende de uma tabela do card 8.3.
-- Esquecer de voltar aqui não daria erro nenhum — daria o erro ERRADO: o
-- pedagógico com o certificado na mão receberia FORMATURA_SEM_CERTIFICADO, e a
-- leitura óbvia da mensagem seria falsa.
--
-- Os comentários do corpo são REMOVIDOS antes de procurar a citação. Sem isso o
-- portão passaria pelo próprio comentário que descreve o que falta — que é
-- exatamente o texto que está lá hoje —, e um portão que aprova o estado que
-- deveria reprovar é pior que portão nenhum.
create temporary view corpo_pode_formar as
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as fonte
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_aluno_pode_formar';

create temporary view portao_formado as
  select to_regclass('public.certificado_checklist') is null
      or (select fonte ~ 'certificado_checklist' from corpo_pode_formar) as em_dia;

select ok((select em_dia from portao_formado),
  'gate de FORMADO em dia: enquanto certificado_checklist nao existe, nada e devido');

select ok(
  not (select fonte ~ 'certificado_checklist' from corpo_pode_formar),
  'e hoje o portao esta VAZIO de proposito — a citacao so existe no comentario, que foi removido');

-- Prova por construção: portão que nunca foi visto vermelho é decoração.
create table public.certificado_checklist (id uuid primary key);

select ok(not (select em_dia from portao_formado),
  'nascida a tabela do card 8.3, o portao REPROVA enquanto fn_aluno_pode_formar nao a citar');

drop table public.certificado_checklist;

-- ===========================================================================
-- 6. Portão dos três triggers que este card não pode escrever
-- ===========================================================================
-- Card 2.2 §3.2 lista cinco triggers em `aluno`; dois entram aqui e três
-- dependem de tabelas de outras fases. O mais caro de esquecer é
-- `tg_aluno_status_desaloca`: sem ele o aluno em STANDBY continua ocupando vaga
-- toda semana, sem erro nenhum e sem nada na tela dizendo isso.
create temporary view portao_trigger (tabela, gatilho, card) as values
  ('public.bloco_aluno',    'tg_aluno_status_desaloca', '5.1'),
  ('public.aluno_material', 'tg_aluno_trilha_inicial',  '6.2'),
  ('public.pendencia',      'tg_aluno_combo_alterado',  '5.5');

create temporary view portao_trigger_devido as
  select coalesce(string_agg(format('%s existe (card %s) e %s nao', p.tabela, p.card, p.gatilho),
                             '; ' order by p.gatilho), '') as devido
    from portao_trigger p
   where to_regclass(p.tabela) is not null
     and not exists (select 1 from pg_trigger t
                      where t.tgname = p.gatilho and not t.tgisinternal);

select is((select devido from portao_trigger_devido), '',
  'nenhum trigger de aluno esta devido — as tres tabelas que os tornam devidos ainda nao existem');

create table public.pendencia (id uuid primary key);

select is((select devido from portao_trigger_devido),
  'public.pendencia existe (card 5.5) e tg_aluno_combo_alterado nao',
  'nascida a tabela, o portao nomeia o trigger que ficou para tras e o card dele');

drop table public.pendencia;

-- ===========================================================================
-- 7. fn_aluno_alterar_status — caminho feliz com efeito conferido
-- ===========================================================================
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));

select lives_ok(
  $$select public.fn_aluno_alterar_status(
      (select id from public.aluno
        where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
      'STANDBY', 'trancou para trabalhar')$$,
  'o pedagogico tem alunos.alterar_status e move ATIVO -> STANDBY');

reset role;

select is(
  (select a.status from public.aluno a
     join public.unidade u on u.id = a.unidade_id
    where u.codigo = 'ESCOLA_A' and a.nome = 'Carla Menezes'),
  'STANDBY',
  'efeito 1: o status mudou');

select is(
  (select a.status_desde from public.aluno a
     join public.unidade u on u.id = a.unidade_id
    where u.codigo = 'ESCOLA_A' and a.nome = 'Carla Menezes'),
  public.fn_hoje(),
  'efeito 2: status_desde foi carimbado com fn_hoje(), nao com current_date');

select is(
  (select h.status_anterior || '->' || h.status_novo || ':' || h.motivo
     from public.aluno_status_hist h
     join public.aluno a on a.id = h.aluno_id
     join public.unidade u on u.id = a.unidade_id
    where u.codigo = 'ESCOLA_A' and a.nome = 'Carla Menezes'),
  'ATIVO->STANDBY:trancou para trabalhar',
  'efeito 3: o historico registra a transicao com o motivo que a funcao passou');

select is(
  (select h.usuario_id from public.aluno_status_hist h
     join public.aluno a on a.id = h.aluno_id
     join public.unidade u on u.id = a.unidade_id
    where u.codigo = 'ESCOLA_A' and a.nome = 'Carla Menezes'),
  tests.uid('pedagogico@escola-a.test'),
  'efeito 4: e registra QUEM mudou, pelo auth.uid() da sessao');

-- ===========================================================================
-- 8. A GUC do motivo é limpa depois de usada
-- ===========================================================================
-- `set_config(..., true)` vale pela TRANSAÇÃO inteira, não pela chamada. Sem a
-- limpeza no fim de fn_aluno_alterar_status, a próxima mudança de status da
-- mesma transação herdaria este motivo — histórico com o motivo de OUTRO aluno,
-- e nada acusando. Aqui a mesma transação faz a segunda mudança por UPDATE
-- direto, que é o caso sem motivo nenhum.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

update public.aluno set status = 'ATIVO'
 where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual();

reset role;

select is(
  (select h.motivo from public.aluno_status_hist h
     join public.aluno a on a.id = h.aluno_id
     join public.unidade u on u.id = a.unidade_id
    where u.codigo = 'ESCOLA_A' and a.nome = 'Carla Menezes'
      and h.status_anterior = 'STANDBY' and h.status_novo = 'ATIVO'),
  'alteração direta',
  'a segunda transicao NAO herdou o motivo da primeira — a GUC foi limpa');

select is(
  (select count(*)::bigint from public.aluno_status_hist h
     join public.aluno a on a.id = h.aluno_id
     join public.unidade u on u.id = a.unidade_id
    where u.codigo = 'ESCOLA_A' and a.nome = 'Carla Menezes'),
  2::bigint,
  'e o historico nunca deixa de existir: duas transicoes, duas linhas');

-- ===========================================================================
-- 9. Um `codigo` por erro que fn_aluno_alterar_status pode levantar (§6.2)
-- ===========================================================================
select is(
  tests.codigo_do_erro(
    $$select public.fn_aluno_alterar_status(
        (select id from public.aluno
          where nome = 'Bruno Carvalho' and unidade_id = public.fn_unidade_atual()),
        'STANDBY', null)$$,
    tests.uid('secretaria@escola-a.test')),
  'MOTIVO_OBRIGATORIO',
  'STANDBY sem motivo e recusado');

select is(
  tests.codigo_do_erro(
    $$select public.fn_aluno_alterar_status(
        (select id from public.aluno
          where nome = 'Bruno Carvalho' and unidade_id = public.fn_unidade_atual()),
        'STANDBY', '   ')$$,
    tests.uid('secretaria@escola-a.test')),
  'MOTIVO_OBRIGATORIO',
  'motivo so com espacos vale como ausente');

select is(
  tests.codigo_do_erro(
    $$select public.fn_aluno_alterar_status(
        (select id from public.aluno
          where nome = 'Bruno Carvalho' and unidade_id = public.fn_unidade_atual()),
        'ATIVO', null)$$,
    tests.uid('secretaria@escola-a.test')),
  'TRANSICAO_INVALIDA',
  'mudar para o status que ja vale e ERRO, nao no-op silencioso');

select is(
  tests.codigo_do_erro(
    $$select public.fn_aluno_alterar_status(
        (select id from public.aluno
          where nome = 'Henrique Dias' and unidade_id = public.fn_unidade_atual()),
        'STANDBY', 'motivo qualquer')$$,
    tests.uid('secretaria@escola-a.test')),
  'TRANSICAO_INVALIDA',
  'TRANCADO -> STANDBY nao esta na tabela de decisao');

select is(
  tests.codigo_do_erro(
    $$select public.fn_aluno_alterar_status(
        (select id from public.aluno
          where nome = 'Bruno Carvalho' and unidade_id = public.fn_unidade_atual()),
        'FORMADO', null)$$,
    tests.uid('secretaria@escola-a.test')),
  'FORMATURA_SEM_CERTIFICADO',
  'o gate de FORMADO vale tambem pela funcao de aplicacao');

select is(
  tests.codigo_do_erro(
    $$select public.fn_aluno_alterar_status(
        (select id from public.aluno
          where nome = 'Bruno Carvalho' and unidade_id = public.fn_unidade_atual()),
        'STANDBY', 'motivo qualquer')$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor tem alunos.ler e nao tem alunos.alterar_status');

-- Aluno de OUTRA unidade: o id é resolvido aqui, como `postgres`, senão a
-- subconsulta rodaria já autenticada e devolveria nulo — o teste passaria pelo
-- motivo errado, provando só que null não é aluno.
select is(
  tests.codigo_do_erro(
    format($$select public.fn_aluno_alterar_status(%L, 'STANDBY', 'motivo qualquer')$$,
           (select a.id from public.aluno a
              join public.unidade u on u.id = a.unidade_id
             where u.codigo = 'ESCOLA_B' and a.nome = 'Bruno Carvalho')),
    tests.uid('direcao@escola-a.test')),
  'ALUNO_INEXISTENTE',
  'aluno de outra unidade responde INEXISTENTE — quem nao pode ver nao descobre que existe');

-- ===========================================================================
-- 10. fn_aluno_reverter_status — o único caminho para sair de um terminal
-- ===========================================================================
select is(
  tests.codigo_do_erro(
    $$select public.fn_aluno_reverter_status(
        (select id from public.aluno
          where nome = 'Isabela Rocha' and unidade_id = public.fn_unidade_atual()),
        'ATIVO', 'matricula cancelada por engano')$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'reverter e so da direcao na matriz inicial (alunos.reverter_status)');

select is(
  tests.codigo_do_erro(
    $$select public.fn_aluno_reverter_status(
        (select id from public.aluno
          where nome = 'Isabela Rocha' and unidade_id = public.fn_unidade_atual()),
        'ATIVO', null)$$,
    tests.uid('direcao@escola-a.test')),
  'MOTIVO_OBRIGATORIO',
  'desfazer um terminal SEM justificativa escrita nao passa');

select is(
  tests.codigo_do_erro(
    $$select public.fn_aluno_reverter_status(
        (select id from public.aluno
          where nome = 'Bruno Carvalho' and unidade_id = public.fn_unidade_atual()),
        'STANDBY', 'motivo qualquer')$$,
    tests.uid('direcao@escola-a.test')),
  'TRANSICAO_INVALIDA',
  'reverter so sai de status TERMINAL — a GUC nao e um desvio geral da tabela de decisao');

select is(
  tests.codigo_do_erro(
    $$select public.fn_aluno_reverter_status(
        (select id from public.aluno
          where nome = 'Isabela Rocha' and unidade_id = public.fn_unidade_atual()),
        'FORMADO', 'motivo qualquer')$$,
    tests.uid('direcao@escola-a.test')),
  'TRANSICAO_INVALIDA',
  'nem chega a outro terminal: CANCELADO -> FORMADO nao e reversao');

select tests.autenticar(tests.uid('direcao@escola-a.test'));

select lives_ok(
  $$select public.fn_aluno_reverter_status(
      (select id from public.aluno
        where nome = 'Isabela Rocha' and unidade_id = public.fn_unidade_atual()),
      'ATIVO', 'cancelamento lancado no aluno errado')$$,
  'a direcao reverte CANCELADO -> ATIVO com motivo');

reset role;

select is(
  (select a.status || '|' || h.motivo
     from public.aluno a
     join public.unidade u on u.id = a.unidade_id
     join public.aluno_status_hist h on h.aluno_id = a.id
    where u.codigo = 'ESCOLA_A' and a.nome = 'Isabela Rocha'),
  'ATIVO|cancelamento lancado no aluno errado',
  'e a reversao aparece no historico com o motivo, como qualquer outra transicao');

-- A GUC de reversão também é limpa: sem isso, a próxima mudança de status da
-- mesma transação sairia pelo desvio dos terminais sem ninguém pedir.
select is(
  tests.codigo_do_erro(
    $$update public.aluno set status = 'ATIVO'
       where nome = 'João Pedro Martins' and unidade_id = public.fn_unidade_atual()$$,
    tests.uid('direcao@escola-a.test')),
  'TRANSICAO_INVALIDA',
  'depois da reversao, sair de FORMADO por UPDATE direto volta a ser recusado');

-- ===========================================================================
-- 11. Histórico: imutável e coerente (camada 2 sobre a própria tabela)
-- ===========================================================================
select tests.autenticar(tests.uid('direcao@escola-a.test'));

-- Sem política de update/delete não há ERRO: o Postgres devolve zero linhas
-- afetadas (card 3.4 d). O silêncio é o comportamento, e o que se assere é que
-- nada mudou.
update public.aluno_status_hist set motivo = 'motivo forjado';
delete from public.aluno_status_hist;

reset role;

select is(
  (select count(*)::bigint from public.aluno_status_hist where motivo = 'motivo forjado'),
  0::bigint,
  'update em aluno_status_hist nao altera nada: sem politica, sem acesso');

select cmp_ok(
  (select count(*) from public.aluno_status_hist)::bigint, '>', 0::bigint,
  'e o delete tambem nao apagou nada — o historico e imutavel por ausencia de politica');

-- A política de insert PRECISA aceitar a escrita do trigger, e com isso aceita
-- um POST direto de quem tem alunos.alterar_status. Sem guarda, dava para
-- escrever histórico que CONTRADIZ o aluno — e histórico que mente é pior que
-- histórico ausente, porque tem cara de prova.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select throws_ok(
  $$insert into public.aluno_status_hist (unidade_id, aluno_id, status_anterior, status_novo)
    select public.fn_unidade_atual(), a.id, 'ATIVO', 'FORMADO'
      from public.aluno a
     where a.nome = 'Bruno Carvalho' and a.unidade_id = public.fn_unidade_atual()$$,
  'PT422', null,
  'historico que diz FORMADO num aluno ATIVO e recusado pelo trigger de coerencia');

select lives_ok(
  $$insert into public.aluno_status_hist (unidade_id, aluno_id, status_anterior, status_novo, motivo)
    select public.fn_unidade_atual(), a.id, 'ACELERAR', a.status, 'correcao de registro'
      from public.aluno a
     where a.nome = 'Bruno Carvalho' and a.unidade_id = public.fn_unidade_atual()$$,
  'e uma linha COERENTE com o estado real do aluno passa — a contraprova do negativo');

reset role;

-- ===========================================================================
-- 12. RLS — paridade, silêncio e isolamento (card 2.8 §6.3)
-- ===========================================================================
-- `alunos.ler` é dos quatro perfis: o monitor precisa achar o aluno para
-- registrar entrega, e sem isso a tela dele abriria VAZIA, não com erro.
select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'), 'select id from public.aluno'),
  '>', 0::bigint,
  'a direcao le alunos (a contagem de referencia da paridade e > 0)');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select id from public.aluno') as n
       from (values ('direcao@escola-a.test'), ('pedagogico@escola-a.test'),
                    ('secretaria@escola-a.test'), ('monitor@escola-a.test')) as u(e)
   ) t)::bigint,
  1::bigint,
  'paridade: os quatro perfis com alunos.ler leem a MESMA contagem');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'), 'select id from public.aluno'),
  0::bigint,
  'quem nao tem alunos.ler le zero — a RLS reduz em silencio, nao acusa');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   format('select id from public.aluno where unidade_id = %L',
                          tests.unidade('ESCOLA_A'))),
  0::bigint,
  'a unidade B nao ve aluno nenhum da unidade A');

select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'), 'select id from public.aluno_status_hist'),
  tests.conta_como(tests.uid('monitor@escola-a.test'), 'select id from public.aluno_status_hist'),
  'paridade tambem no historico: alunos.ler cobre as duas tabelas');

-- ===========================================================================
-- 13. Escrita: quem pode matricular
-- ===========================================================================
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select throws_ok(
  $$insert into public.aluno (unidade_id, nome, metodo_id)
    select public.fn_unidade_atual(), 'Matriculado pelo monitor', m.id
      from public.metodo m
     where m.unidade_id = public.fn_unidade_atual() and m.codigo = 'INTERATIVO'$$,
  '42501', null,
  'o monitor nao tem alunos.criar: o insert e barrado pela politica');

reset role;
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$insert into public.aluno (unidade_id, nome, metodo_id)
    select public.fn_unidade_atual(), 'Matriculado pela secretaria', m.id
      from public.metodo m
     where m.unidade_id = public.fn_unidade_atual() and m.codigo = 'INTERATIVO'$$,
  'a secretaria tem alunos.criar e matricula — a contraprova do negativo acima');

-- Aluno não se apaga: vira CANCELADO. Não há política de delete, e é por isso
-- que o catálogo do card 2.4 não tem `alunos.excluir`.
delete from public.aluno where nome = 'Matriculado pela secretaria';

reset role;

select is(
  (select count(*)::bigint from public.aluno where nome = 'Matriculado pela secretaria'),
  1::bigint,
  'delete de aluno nao apaga nada: aluno vira CANCELADO, nao some');

select tests.encerrar_sessao();

select * from finish();
rollback;
