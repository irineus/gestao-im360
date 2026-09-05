-- =============================================================================
-- Regras Modular — card 7.2
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Card de "Função/regra", então o §13 cobra o caminho feliz, o caminho do erro
-- COM O CÓDIGO do catálogo, e a camada 2 exercitada POR FORA da função de
-- aplicação — um teste que só chama `fn_turma_modular_admitir` nunca descobre
-- que o trigger não existe (card 2.8 §6.1).
--
-- O arquivo prova, nesta ordem:
--   • as duas derivadas do §9 — ocupação (que devolve NULO, não zero, para turma
--     de outra unidade) e módulo corrente (o primeiro não concluído por
--     `modulo.ordem`, não por data nem por ordem de inserção);
--   • a camada 3: admitir REATIVA em vez de duplicar, remover grava o motivo, e
--     as duas exigem `turmas.alocar`;
--   • a camada 2, atacada com `insert`/`update` direto na tabela: método,
--     status, unidade e — o que nenhuma constraint pega — a CAPACIDADE, que é
--     regra de agregado;
--   • o avanço CONJUNTO: conclui o corrente gravando a data real onde a projeção
--     do card 8.1 a lê, abre o próximo com o passo aprendido, e PRESERVA as
--     datas que alguém já tiver informado na tela do 7.3;
--   • o motivo da saída na desalocação sem ator, que é a coluna que este card
--     acrescentou;
--   • a trilha do aluno Modular sendo os livros do curso, e o cronograma da
--     turma apontando para o MESMO material — que é a junta de onde a projeção
--     Modular sai;
--   • `TURMA_MODULAR_SEM_CRONOGRAMA` aceito pelo `check` de `pendencia.tipo` —
--     o ajuste 3 do §17 que o card 5.5 não aplicou e três documentos davam como
--     aplicado.
--
-- O advisory lock do §4.5 NÃO se mede aqui: a suíte pgTAP roda numa conexão só e
-- jamais o exercita (card 2.8 §7). Quem o mede é a suíte de concorrência.
--
-- ⚠️ Disciplina de papel, e ela custou uma rodada: DEPOIS de `tests.autenticar`
--    a sessão está em `authenticated` e NÃO alcança mais o schema `tests` (o
--    seed revoga o USAGE de propósito). Por isso todo bloco que volta a usar
--    `tests.*` é precedido de `reset role;`. E nenhuma função com EFEITO —
--    admitir, remover, avançar — é chamada dentro de subconsulta de uma
--    asserção: a ordem de avaliação dentro de um `select` não é garantida, e a
--    armadilha do card 6.9 (`select (fn(x)).*` chamando a função uma vez por
--    coluna) é a mesma família.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(34);

-- Ids de que o teste precisa e que a RLS de ESCOLA_A esconderia. Colhidos como
-- `postgres`, ANTES de qualquer autenticação — é o mesmo recurso que o 070 usa
-- para alcançar a unidade B.
create temporary table t_ids as
select tests.unidade('ESCOLA_A') as unidade_a,
       (select id from public.turma_modular
         where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eletricista 2026.1') as turma_a,
       (select id from public.turma_modular
         where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eletricista 2025.2') as turma_vazia,
       (select id from public.turma_modular
         where unidade_id = tests.unidade('ESCOLA_B') and nome = 'Eletricista 2026.1') as turma_b,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Eduarda Lima') as eduarda,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Ana Paula Ribeiro') as interativa;

-- Tabela temporária nasce sem privilégio para `authenticated`, e metade das
-- asserções roda na pele de alguém.
grant select on t_ids to authenticated;

-- ===========================================================================
-- 1. As duas derivadas do §9
-- ===========================================================================
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select is(
  public.fn_turma_modular_ocupacao((select turma_a from t_ids)),
  1,
  'ocupacao conta os alunos ATIVOS da turma');

-- 0 e nulo têm de ser distinguíveis, e é a razão de a turma vazia existir na
-- fixture: uma implementação que devolvesse nulo para turma sem aluno passaria
-- na asserção de cima e faria a admissão morrer com TURMA_INEXISTENTE na
-- primeira turma nova da escola.
select is(
  public.fn_turma_modular_ocupacao((select turma_vazia from t_ids)),
  0,
  'turma sem aluno e 0, nao nulo');

-- NULO para turma de outra unidade é o contrato do card 5.2, e é o que a seção 3
-- transforma em TURMA_INEXISTENTE. Zero aqui deixaria a admissão passar numa
-- turma que o chamador nem deveria enxergar.
select is(
  public.fn_turma_modular_ocupacao((select turma_b from t_ids)),
  null,
  'turma de outra unidade devolve NULO, nao zero');

-- A fixture põe o módulo 1 concluído e o 2 em curso justamente para que uma
-- implementação que tomasse "o último inserido" ou "o de menor data" desse outro
-- resultado.
select is(
  (select m.nome from public.modulo m
    where m.id = public.fn_turma_modular_modulo_corrente((select turma_a from t_ids))),
  'Módulo 2 — Instalações prediais',
  'modulo corrente e o primeiro NAO concluido por modulo.ordem');

reset role;

-- ===========================================================================
-- 2. A camada 3 — fn_turma_modular_admitir / fn_turma_modular_remover
-- ===========================================================================
-- Um segundo aluno MODULAR, criado aqui e não na fixture: a camada `modular` do
-- card 7.1 escreveu que a borda de capacidade da turma «é aritmética que o card
-- 7.2 monta dentro da própria transação, sem custo de fixture». É esta linha.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

-- `codigo_sgf` nulo de propósito: a camada `turmas` da fixture já usa a faixa
-- 90xx nos alunos de lotação, e `aluno_codigo_sgf_uk` é único por unidade.
insert into public.aluno (unidade_id, codigo_sgf, nome, metodo_id, combo_id,
                          status, data_inicio)
select public.fn_unidade_atual(), null, 'Modular TESTE', me.id, cb.id,
       'ATIVO', public.fn_hoje()
  from public.metodo me
  join public.combo  cb on cb.unidade_id = me.unidade_id
                       and cb.nome = 'Eletricista Completo'
 where me.unidade_id = public.fn_unidade_atual() and me.codigo = 'MODULAR';

reset role;

create temporary table t_novo as
select id from public.aluno
 where unidade_id = (select unidade_a from t_ids) and nome = 'Modular TESTE';

grant select on t_novo to authenticated;

select tests.autenticar(tests.uid('secretaria@escola-a.test'));
select public.fn_turma_modular_admitir((select turma_a from t_ids),
                                       (select id from t_novo));

select is(
  public.fn_turma_modular_ocupacao((select turma_a from t_ids)),
  2,
  'admitir poe o aluno na turma e a ocupacao sobe');

select public.fn_turma_modular_remover((select turma_a from t_ids),
                                       (select id from t_novo), 'mudou de turno');

select is(
  (select format('%s / %s / %s', ta.ativo, ta.motivo_saida,
                 public.fn_turma_modular_ocupacao(ta.turma_id))
     from public.turma_modular_aluno ta
    where ta.turma_id = (select turma_a from t_ids)
      and ta.aluno_id = (select id from t_novo)),
  'f / mudou de turno / 1',
  'remover desativa a linha, grava o motivo e a vaga volta');

-- Reativar em vez de duplicar é o que a unique PARCIAL do card 7.1 permite, e o
-- motivo antigo tem de sumir: mantê-lo faria a ficha do aluno dizer que ele saiu
-- da turma em que está.
select public.fn_turma_modular_admitir((select turma_a from t_ids),
                                       (select id from t_novo));

select is(
  (select format('%s linha(s), ativo=%s, motivo=%s',
                 count(*), bool_and(ta.ativo), coalesce(max(ta.motivo_saida), 'nulo'))
     from public.turma_modular_aluno ta
    where ta.turma_id = (select turma_a from t_ids)
      and ta.aluno_id = (select id from t_novo)),
  '1 linha(s), ativo=t, motivo=nulo',
  'readmitir REATIVA a linha existente e limpa o motivo — nao duplica');

-- Deixa o aluno de teste FORA da turma (ocupação volta a 1) e mede o segundo
-- `remover`: silêncio aqui seria a tela dizendo "removido" sobre uma turma em
-- que o aluno continua.
select public.fn_turma_modular_remover((select turma_a from t_ids),
                                       (select id from t_novo), 'saiu de vez');

reset role;

select is(
  tests.codigo_do_erro(
    format($$select public.fn_turma_modular_remover(%L::uuid, %L::uuid, 'de novo')$$,
           (select turma_a from t_ids), (select id from t_novo)),
    tests.uid('secretaria@escola-a.test')),
  'ALOCACAO_INEXISTENTE',
  'remover quem nao esta na turma DOI, em vez de nao fazer nada');

reset role;

select is(
  tests.codigo_do_erro(
    format($$select public.fn_turma_modular_admitir(%L::uuid, %L::uuid)$$,
           (select turma_a from t_ids), (select id from t_novo)),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'admitir exige turmas.alocar — o monitor nao aloca');

reset role;

select is(
  tests.codigo_do_erro(
    format($$select public.fn_turma_modular_remover(%L::uuid, %L::uuid, 'x')$$,
           (select turma_a from t_ids), (select eduarda from t_ids)),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'remover exige turmas.alocar — turmas.alocar cobre admitir E remover');

reset role;

-- ===========================================================================
-- 3. A camada 2 — atacada POR FORA da função de aplicação
-- ===========================================================================
-- Tudo aqui é `insert`/`update` direto em `turma_modular_aluno`, que é o que um
-- POST no PostgREST faz. A secretaria tem `turmas.alocar`, então a RLS deixa
-- passar: quem recusa é o trigger, e é isso que está sendo medido.
select is(
  tests.codigo_do_erro(
    format($$insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id)
             values (%L::uuid, %L::uuid, %L::uuid)$$,
           (select unidade_a from t_ids), (select turma_a from t_ids),
           (select interativa from t_ids)),
    tests.uid('secretaria@escola-a.test')),
  'ALUNO_NAO_MODULAR',
  'aluno de outro metodo nao entra em turma Modular, nem por POST direto');

reset role;

-- Um MODULAR fora de ATIVO/ACELERAR: o status muda pela via normal
-- (`fn_aluno_alterar_status`, a camada 3 do card 4.2), e a desalocação sem ator
-- não tem o que desalocar — ele está fora da turma desde a seção 2. STANDBY e
-- não TRANCADO porque ATIVO → TRANCADO não existe na tabela de decisão do card
-- 2.2 §3.1: o caminho é ATIVO → STANDBY → TRANCADO.
select tests.autenticar(tests.uid('direcao@escola-a.test'));
select public.fn_aluno_alterar_status((select id from t_novo), 'STANDBY', 'pausa');
reset role;

select is(
  tests.codigo_do_erro(
    format($$insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id)
             values (%L::uuid, %L::uuid, %L::uuid)$$,
           (select unidade_a from t_ids), (select turma_a from t_ids),
           (select id from t_novo)),
    tests.uid('secretaria@escola-a.test')),
  'ALUNO_INATIVO',
  'aluno que nao esta ATIVO/ACELERAR nao ocupa vaga em turma');

reset role;

-- A capacidade é regra de AGREGADO: nenhuma constraint a pega, e é por isso que
-- ela mora no trigger. `capacidade = 1` com Eduarda dentro põe a turma na borda
-- exata, sem precisar de quinze alunos de fixture.
select tests.autenticar(tests.uid('direcao@escola-a.test'));
update public.turma_modular set capacidade = 1 where id = (select turma_a from t_ids);
select public.fn_aluno_alterar_status((select id from t_novo), 'ATIVO', 'voltou');
reset role;

select is(
  tests.codigo_do_erro(
    format($$insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id)
             values (%L::uuid, %L::uuid, %L::uuid)$$,
           (select unidade_a from t_ids), (select turma_a from t_ids),
           (select id from t_novo)),
    tests.uid('secretaria@escola-a.test')),
  'TURMA_LOTADA',
  'turma cheia recusa o proximo — a capacidade e COLUNA, e vale');

reset role;

-- A linha inativa que VOLTA disputa a vaga como qualquer outra: sem isso,
-- reativar seria a porta dos fundos da lotação.
select is(
  tests.codigo_do_erro(
    format($$update public.turma_modular_aluno set ativo = true
              where turma_id = %L::uuid and aluno_id = %L::uuid$$,
           (select turma_a from t_ids), (select id from t_novo)),
    tests.uid('secretaria@escola-a.test')),
  'TURMA_LOTADA',
  'reativar linha inativa numa turma cheia tambem bate em TURMA_LOTADA');

reset role;

-- E a contraprova, que é o achado do card 5.3: um update de linha JÁ ativa não
-- pode ver a própria linha na contagem e responder "lotada" numa turma que não
-- mudou de tamanho.
select is(
  tests.codigo_do_erro(
    format($$update public.turma_modular_aluno set ativo = true
              where turma_id = %L::uuid and aluno_id = %L::uuid$$,
           (select turma_a from t_ids), (select eduarda from t_ids)),
    tests.uid('secretaria@escola-a.test')),
  null,
  'update de linha JA ativa nao dispara TURMA_LOTADA — so quem ENTRA disputa');

reset role;

-- Uma `turma_modular` cujo curso é de outro método: nada no schema impede que
-- ela nasça, e é por isso que a igualdade de métodos é conferida além do
-- ALUNO_NAO_MODULAR. Com uma checagem só, esta turma aceitaria a aluna.
select tests.autenticar(tests.uid('direcao@escola-a.test'));
insert into public.turma_modular (unidade_id, curso_id, nome, sala_id, capacidade,
                                  data_inicio)
select public.fn_unidade_atual(), c.id, 'Turma de metodo errado TESTE', s.id, 5,
       public.fn_hoje()
  from public.curso c
  join public.sala  s on s.unidade_id = c.unidade_id and s.nome = 'Sala Eletricista'
 where c.unidade_id = public.fn_unidade_atual() and c.nome = 'Informática Essencial';
reset role;

select is(
  tests.codigo_do_erro(
    format($$insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id)
             select %L::uuid, t.id, %L::uuid from public.turma_modular t
              where t.nome = 'Turma de metodo errado TESTE'
                and t.unidade_id = public.fn_unidade_atual()$$,
           (select unidade_a from t_ids), (select eduarda from t_ids)),
    tests.uid('secretaria@escola-a.test')),
  'METODO_INCOMPATIVEL',
  'turma cujo curso e de outro metodo recusa o aluno Modular');

reset role;

select is(
  tests.codigo_do_erro(
    format($$insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id)
             values (%L::uuid, %L::uuid, %L::uuid)$$,
           (select unidade_a from t_ids), (select turma_b from t_ids),
           (select eduarda from t_ids)),
    tests.uid('secretaria@escola-a.test')),
  'TURMA_INEXISTENTE',
  'turma de outra unidade e TURMA_INEXISTENTE — a ocupacao nula vira erro');

reset role;

-- ===========================================================================
-- 4. fn_turma_modular_avancar — o avanço CONJUNTO
-- ===========================================================================
-- Uma turma própria para o caso da PRESERVAÇÃO, com os três módulos já datados:
-- a previsão digitada por quem conhece a turma vale mais que uma média, e o
-- avanço não pode apagá-la em silêncio.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

insert into public.turma_modular (unidade_id, curso_id, nome, sala_id, capacidade,
                                  data_inicio)
select public.fn_unidade_atual(), c.id, 'Eletricista TESTE 7.2', s.id, 5,
       public.fn_hoje() - 30
  from public.curso c
  join public.metodo me on me.id = c.metodo_id and me.codigo = 'MODULAR'
  join public.sala   s  on s.unidade_id = c.unidade_id and s.nome = 'Sala Eletricista'
 where c.unidade_id = public.fn_unidade_atual() and c.nome = 'Eletricista Instalador';

insert into public.turma_modular_modulo (unidade_id, turma_id, modulo_id,
                                         data_inicio, prev_conclusao, concluido)
select public.fn_unidade_atual(), t.id, m.id,
       public.fn_hoje() - 30 + (m.ordem - 1) * 10,
       public.fn_hoje() - 30 + m.ordem * 10 - 1,
       m.ordem = 1
  from public.turma_modular t
  join public.modulo m on m.curso_id = t.curso_id
 where t.unidade_id = public.fn_unidade_atual() and t.nome = 'Eletricista TESTE 7.2';

select public.fn_turma_modular_avancar(
  (select id from public.turma_modular
    where nome = 'Eletricista TESTE 7.2' and unidade_id = public.fn_unidade_atual()),
  public.fn_hoje());

select is(
  (select format('%s a %s',
                 to_char(tm.data_inicio, 'DD/MM'), to_char(tm.prev_conclusao, 'DD/MM'))
     from public.turma_modular_modulo tm
     join public.modulo m on m.id = tm.modulo_id
     join public.turma_modular t on t.id = tm.turma_id
    where t.nome = 'Eletricista TESTE 7.2' and m.ordem = 3),
  format('%s a %s',
         to_char(public.fn_hoje() - 10, 'DD/MM'), to_char(public.fn_hoje() - 1, 'DD/MM')),
  'o avanco PRESERVA as datas ja informadas do proximo modulo');

-- Agora a turma da fixture, cujo módulo 3 está sem datas: é o caso em que o
-- passo é calculado. Módulo 1 durou 36 dias planejados (hoje-60 a hoje-25) e o
-- módulo 2, concluído HOJE, durou 26 (hoje-25 a hoje) — média 31.
create temporary table t_avanco as
select public.fn_turma_modular_avancar((select turma_a from t_ids),
                                       public.fn_hoje()) as novo;

select is(
  (select m.nome from public.modulo m where m.id = (select novo from t_avanco)),
  'Módulo 3 — Projetos',
  'avancar devolve o modulo_id do NOVO corrente');

select is(
  (select format('%s / %s', tm.concluido, to_char(tm.prev_conclusao, 'DD/MM/YYYY'))
     from public.turma_modular_modulo tm
     join public.modulo m on m.id = tm.modulo_id
    where tm.turma_id = (select turma_a from t_ids) and m.ordem = 2),
  format('t / %s', to_char(public.fn_hoje(), 'DD/MM/YYYY')),
  'o modulo corrente fecha com a data REAL em prev_conclusao — de onde o 8.1 le');

select is(
  (select to_char(tm.data_inicio, 'DD/MM/YYYY')
     from public.turma_modular_modulo tm
     join public.modulo m on m.id = tm.modulo_id
    where tm.turma_id = (select turma_a from t_ids) and m.ordem = 3),
  to_char(public.fn_hoje() + 1, 'DD/MM/YYYY'),
  'o proximo modulo comeca no dia seguinte a conclusao do anterior');

-- 36 e 26 dias planejados → passo 31 → previsão em data_inicio + 31 - 1.
-- O passo é medido DEPOIS de fechar o módulo corrente, de propósito: a média
-- aprende com a duração real do que acabou de acontecer, em vez de usar a
-- previsão que a turma acabou de desmentir. Com a ordem trocada o passo seria
-- 36 e esta asserção daria hoje+36.
select is(
  (select to_char(tm.prev_conclusao, 'DD/MM/YYYY')
     from public.turma_modular_modulo tm
     join public.modulo m on m.id = tm.modulo_id
    where tm.turma_id = (select turma_a from t_ids) and m.ordem = 3),
  to_char(public.fn_hoje() + 31, 'DD/MM/YYYY'),
  'a previsao do proximo usa o passo APRENDIDO com os modulos ja datados');

-- Avançar o último módulo devolve NULO: é o estado "turma terminou", e não um
-- erro. A turma continua ativa e continua aparecendo na lotação do card 7.4.
select is(
  public.fn_turma_modular_avancar((select turma_a from t_ids), public.fn_hoje() + 31),
  null,
  'avancar o ULTIMO modulo devolve NULO — a turma terminou');

reset role;

select is(
  tests.codigo_do_erro(
    format($$select public.fn_turma_modular_avancar(%L::uuid)$$,
           (select turma_a from t_ids)),
    tests.uid('direcao@escola-a.test')),
  'TURMA_SEM_MODULO_CORRENTE',
  'avancar turma ja terminada e erro, com codigo proprio');

reset role;

-- Turma sem cronograma nenhum tem código DIFERENTE: dizer "todos os módulos já
-- foram concluídos" a quem nunca montou o cronograma manda a pessoa procurar o
-- erro no lugar errado.
select tests.autenticar(tests.uid('direcao@escola-a.test'));
insert into public.turma_modular (unidade_id, curso_id, nome, sala_id, capacidade,
                                  data_inicio)
select public.fn_unidade_atual(), c.id, 'Sem cronograma TESTE', s.id, 5,
       public.fn_hoje()
  from public.curso c
  join public.metodo me on me.id = c.metodo_id and me.codigo = 'MODULAR'
  join public.sala   s  on s.unidade_id = c.unidade_id and s.nome = 'Sala Eletricista'
 where c.unidade_id = public.fn_unidade_atual() and c.nome = 'Eletricista Instalador';
reset role;

select is(
  tests.codigo_do_erro(
    $$select public.fn_turma_modular_avancar(
        (select id from public.turma_modular
          where nome = 'Sem cronograma TESTE' and unidade_id = public.fn_unidade_atual()))$$,
    tests.uid('direcao@escola-a.test')),
  'TURMA_SEM_CRONOGRAMA',
  'turma sem cronograma tem codigo proprio, nao o de turma terminada');

reset role;

select is(
  tests.codigo_do_erro(
    format($$select public.fn_turma_modular_avancar(%L::uuid)$$,
           (select turma_vazia from t_ids)),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'avancar exige turmas.editar — o catalogo do 2.4 §3.4 diz "avanco de modulo"');

reset role;

-- «A turma avança em conjunto — não existe avanço por aluno» (card 2.2 §9): o
-- avanço não pode ter tocado em `turma_modular_aluno`. Eduarda continua lá, com
-- a mesma data de entrada.
select is(
  (select format('%s aluno(s) ativo(s), entrada %s',
                 count(*) filter (where ta.ativo),
                 to_char(max(ta.data_entrada), 'DD/MM/YYYY'))
     from public.turma_modular_aluno ta
    where ta.turma_id = (select turma_a from t_ids) and ta.ativo),
  format('1 aluno(s) ativo(s), entrada %s', to_char(public.fn_hoje() - 60, 'DD/MM/YYYY')),
  'o avanco e da TURMA: nada em turma_modular_aluno se moveu');

-- ===========================================================================
-- 5. A desalocação sem ator grava o motivo — a coluna deste card
-- ===========================================================================
-- Quem executa é o PEDAGÓGICO, que tem `alunos.alterar_status` e NÃO tem
-- `turmas.alocar`: é exatamente por isso que a política de update da tabela
-- aceita as três permissões (achado 6 do card 2.4 §7). Se `motivo_saida` tivesse
-- entrado na guarda de coluna do card 7.1, esta transação morreria com
-- SEM_PERMISSAO numa tela que não fala de turma.
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));
select public.fn_aluno_alterar_status((select eduarda from t_ids), 'STANDBY',
                                      'parou de vir');

select is(
  (select format('%s / %s', ta.ativo, ta.motivo_saida)
     from public.turma_modular_aluno ta
    where ta.turma_id = (select turma_a from t_ids)
      and ta.aluno_id = (select eduarda from t_ids)),
  'f / Aluno passou a STANDBY',
  'sair de ATIVO tira o aluno da turma Modular COM o motivo, na transacao do pedagogico');

-- ===========================================================================
-- 6. A trilha do aluno Modular é a dos livros do curso
-- ===========================================================================
-- Não é regra nova deste card: é o que a expansão combo → curso → material do
-- card 6.2 já produz, e o que o plano §5.6 afirma. O que faltava era a asserção
-- — sem ela, a frase vale enquanto ninguém mexe na geração da trilha.
select is(
  (select string_agg(mt.codigo, ', ' order by am.ordem)
     from public.aluno_material am
     join public.material mt on mt.id = am.material_id
    where am.aluno_id = (select eduarda from t_ids)),
  (select string_agg(mt.codigo, ', ' order by cm.ordem)
     from public.curso_material cm
     join public.material mt on mt.id = cm.material_id
     join public.curso c on c.id = cm.curso_id
     join public.turma_modular t on t.curso_id = c.id
    where t.id = (select turma_a from t_ids)),
  'a trilha do aluno Modular e a sequencia de livros do curso da turma dele');

-- E a junta de onde a projeção Modular sai (card 8.1, docs/projecao-demanda.md
-- §5.4): o cronograma da turma aponta para os MESMOS materiais da trilha. São
-- três módulos sobre DOIS livros — um livro dura mais de um módulo, que é a
-- forma do Modular —, e é por isso que a necessidade do livro nasce no PRIMEIRO
-- módulo dele, não em cada um.
--
-- ⚠️ Eram "3 sobre 1" até o card 8.1, e a mudança é o que torna o degrau MODULAR
--    alcançável: com um livro só, todo aluno Modular tinha exatamente um item
--    pendente, ficava em k = 1 e nunca chegava a v_projecao_aluno, que só conta
--    do SEGUNDO item em diante (a disjunção com a demanda imediata).
select is(
  (select format('%s modulo(s) sobre %s livro(s)',
                 count(*), count(distinct m.material_id))
     from public.turma_modular_modulo tm
     join public.modulo m on m.id = tm.modulo_id
    where tm.turma_id = (select turma_a from t_ids)
      and m.material_id in (select am.material_id from public.aluno_material am
                             where am.aluno_id = (select eduarda from t_ids))),
  '3 modulo(s) sobre 2 livro(s)',
  'o cronograma da turma aponta para os mesmos livros da trilha — a junta da projecao');

reset role;

-- ===========================================================================
-- 7. TURMA_MODULAR_SEM_CRONOGRAMA no `check` de pendencia.tipo
-- ===========================================================================
-- O ajuste 3 do §17 de docs/estrategia-testes.md, marcado BLOQUEANTE e atribuído
-- ao card 5.5, que não o aplicou — e que o card 7.1 e a nota do 8.1 davam como
-- aplicado. Sem o tipo, o `insert` da rotina de projeção falha e vira
-- ROTINA_FALHOU às 03:10 da manhã, longe da causa.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

select lives_ok(
  $$select public.fn_pendencia_abrir(
      'TURMA_MODULAR_SEM_CRONOGRAMA', 'TMSC:teste',
      'Turma Modular sem cronograma datado.', 'BAIXA')$$,
  'o check de pendencia.tipo aceita TURMA_MODULAR_SEM_CRONOGRAMA');

-- A contraprova: o `check` continua sendo um check. Sem esta linha, a asserção
-- de cima passaria igual se alguém tivesse simplesmente apagado a restrição.
select throws_ok(
  $$select public.fn_pendencia_abrir(
      'TIPO_QUE_NAO_EXISTE', 'TMSC:contraprova', 'x', 'BAIXA')$$,
  '23514',
  null,
  'e continua recusando tipo que nao esta na lista');

reset role;

-- ===========================================================================
-- 8. O advisory lock não sumiu (C13, docs/estrategia-testes.md §5.1)
-- ===========================================================================
-- O guarda-chuva barato, idêntico ao do 042, e ele NÃO é um teste de
-- concorrência: a suíte pgTAP roda numa conexão só, então a corrida não existe
-- aqui. O que ele garante é que a chamada não desapareceu num refactor.
--
-- §7 nomeia DUAS suítes de duas sessões — `admissao_ultima_vaga.sh` (5.3) e
-- `entrega_ultimo_exemplar.sh` (6.3) — e nenhuma terceira. A do Modular virou o
-- card 7.4,5, e não foi escrita aqui por um motivo concreto: a escola-fixture
-- tem UM aluno MODULAR, e o cenário exige dois entrando ao mesmo tempo. Script
-- que precisa criar aluno e apagá-lo fora de transação é a única suíte do
-- projeto sem rollback criando dado novo, e isso é decisão de fixture, não
-- detalhe deste arquivo.
--
-- `prosrc` inclui os comentários do corpo (lição do card 4.2), e as duas têm o
-- lock citado em comentário: sem removê-los, o teste aprovaria uma função que só
-- FALA do lock.
create temporary view corpo_modular as
  select p.proname,
         regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as fonte
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('fn_turma_modular_admitir', 'fn_turma_modular_avancar');

select is(
  (select string_agg(proname, ',' order by proname)
     from corpo_modular where fonte ~ 'pg_advisory_xact_lock'),
  'fn_turma_modular_admitir,fn_turma_modular_avancar',
  'C13: admitir e avancar serializam a TURMA com pg_advisory_xact_lock');

-- E a contagem tem um dono só, como a capacidade do bloco tem o card 5.2: o
-- trigger CHAMA `fn_turma_modular_ocupacao` e não refaz a conta. Duas
-- implementações da mesma pergunta divergem na primeira vez que alguém mexer
-- numa só — e a que divergisse aqui abriria vaga que não existe.
select is(
  (select format('chama=%s, conta_propria=%s',
                 fonte ~ 'fn_turma_modular_ocupacao',
                 fonte ~ 'count\(')
     from (select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as fonte
             from pg_proc p
             join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and p.proname = 'fn_turma_modular_aluno_admissao') x),
  'chama=t, conta_propria=f',
  'o trigger de admissao usa a ocupacao do §9 e nao reescreve a contagem');

select * from finish();
rollback;
