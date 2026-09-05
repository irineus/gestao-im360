-- =============================================================================
-- Turmas Modular — card 7.1
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Card de "Schema", então o §13 cobra duas listas: suíte de catálogo verde com
-- as tabelas novas (010 e 011 fazem sozinhas, derivando do catálogo do Postgres)
-- e um teste por `check`/`unique` que expresse regra de negócio (camada 1).
--
-- Fora dessas duas, o arquivo prova as quatro coisas que este card decidiu e que
-- nenhum catálogo enxerga:
--   • o `or` da política de update de `turma_modular_aluno` existe para a
--     desalocação sem ator e vaza todas as outras colunas, porque RLS não é por
--     coluna (achado 6 do card 2.4 §7; o card 5.1 nomeou esta tabela como o
--     próximo caso, depois de `bloco_aluno.tipo`);
--   • a cascata de `turma_modular_aluno.turma_id` apagava, em silêncio, o
--     registro de quem esteve na turma — o achado do card 4.3 na sua terceira
--     encarnação;
--   • `tg_aluno_status_desaloca` passou a citar a TERCEIRA tabela do card 2.2
--     §3.2, e é o comportamento — não a citação — que está medido aqui, com a
--     contraprova por construção que o portão do 040 não pode mais fazer;
--   • `ALUNO_SEM_TURMA` passou a olhar as DUAS formas de turma, que é o portão
--     que o card 5.5 deixou escrito dentro da própria rotina.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(31);

-- ===========================================================================
-- 1. As premissas da fixture (camada `modular` do card 3.4.5)
-- ===========================================================================
-- A terceira turma é do card 7.4,5 (05/09/2026): `Eletricista Individual 2026`,
-- capacidade 1 e vazia, é o cenário da suíte de concorrência
-- (`supabase/tests_concorrencia/admissao_turma_modular.sh`). Ela entra aqui
-- como premissa porque é a fixture que a sustenta: uma turma de capacidade 1
-- vazia é o único jeito de a borda "existe UMA vaga" custar zero linha.
select is(
  (select string_agg(t.nome, ', ' order by t.nome) from public.turma_modular t
    where t.unidade_id = tests.unidade('ESCOLA_A')),
  'Eletricista 2025.2, Eletricista 2026.1, Eletricista Individual 2026',
  'fixture: tres turmas Modular na unidade A — a com aluna, a vazia e a individual da concorrencia');

-- Contagem direta, e não `fn_turma_modular_ocupacao`: aqui ainda não há sessão
-- autenticada, e a função é `security definer` filtrada por `fn_unidade_atual()`
-- — devolveria NULO e a asserção mediria o contexto, não a fixture.
select is(
  (select format('%s/%s', t.capacidade,
                 (select count(*) from public.turma_modular_aluno ta
                   where ta.turma_id = t.id and ta.ativo))
     from public.turma_modular t
    where t.unidade_id = tests.unidade('ESCOLA_A')
      and t.nome = 'Eletricista Individual 2026'),
  '1/0',
  'a turma da concorrencia nasce com UMA vaga livre — 0 de 1, o cenario do card 7.4,5');

-- O módulo CORRENTE é o primeiro não concluído por `modulo.ordem`, e a ordem
-- vem do catálogo (card 2.2 §9), não de coluna de turma_modular_modulo. A
-- fixture põe o 1 concluído e o 2 em curso justamente para que uma
-- implementação que tomasse "o último inserido" ou "o de menor data" desse
-- outro resultado.
select is(
  (select m.nome
     from public.turma_modular_modulo tm
     join public.turma_modular t on t.id = tm.turma_id
     join public.modulo m on m.id = tm.modulo_id
    where t.unidade_id = tests.unidade('ESCOLA_A') and t.nome = 'Eletricista 2026.1'
      and not tm.concluido
    order by m.ordem
    limit 1),
  'Módulo 2 — Instalações prediais',
  'fixture: cronograma de tres modulos, com o 1 concluido e o 2 corrente');

select is(
  (select string_agg(a.nome, ', ' order by a.nome)
     from public.turma_modular_aluno ta
     join public.turma_modular t on t.id = ta.turma_id
     join public.aluno a on a.id = ta.aluno_id
    where t.unidade_id = tests.unidade('ESCOLA_A') and t.nome = 'Eletricista 2026.1'
      and ta.ativo),
  'Eduarda Lima',
  'fixture: a unica aluna MODULAR da camada `alunos` esta na turma');

-- A turma vazia com módulo VENCIDO é o outro valor de `modulo_atrasado` (card
-- 7.4) e o lado "apagável" da guarda de exclusão. Fixture em que toda turma
-- está no mesmo estado não distingue implementação nenhuma.
select is(
  (select format('%s aluno(s), modulo corrente %s',
                 (select count(*) from public.turma_modular_aluno ta where ta.turma_id = t.id),
                 (select case when bool_or(tm.prev_conclusao < public.fn_hoje())
                              then 'vencido' else 'em dia' end
                    from public.turma_modular_modulo tm
                   where tm.turma_id = t.id and not tm.concluido))
     from public.turma_modular t
    where t.unidade_id = tests.unidade('ESCOLA_A') and t.nome = 'Eletricista 2025.2'),
  '0 aluno(s), modulo corrente vencido',
  'fixture: a segunda turma esta VAZIA e com o modulo corrente vencido');

-- ===========================================================================
-- 2. Camada 1: os `check` e as `unique` que expressam regra (§13, §6.1)
-- ===========================================================================
-- Turma de teste, criada aqui e só aqui: é ela que recebe as escritas
-- destrutivas das seções 2, 5 e 8, para que as duas turmas da fixture cheguem
-- inteiras às seções de RLS, pendência e desalocação.
insert into public.turma_modular (unidade_id, curso_id, nome, sala_id, capacidade, data_inicio)
select tests.unidade('ESCOLA_A'), c.id, 'Eletricista TESTE', s.id, 2, public.fn_hoje()
  from public.curso c
  join public.metodo me on me.id = c.metodo_id
  join public.sala s on s.unidade_id = c.unidade_id and s.nome = 'Sala Eletricista'
 where c.unidade_id = tests.unidade('ESCOLA_A')
   and me.codigo = 'MODULAR' and c.nome = 'Eletricista Instalador';

-- `capacidade > 0` e não `>= 0`: turma fechada é `ativo = false`, e uma turma de
-- capacidade zero seria uma turma permanentemente lotada sem dizer por quê — o
-- mesmo argumento do `capacidade_override` do card 5.1.
select throws_ok(
  $$insert into public.turma_modular (unidade_id, curso_id, nome, sala_id, capacidade, data_inicio)
    select unidade_id, curso_id, 'Capacidade zero', sala_id, 0, data_inicio
      from public.turma_modular where nome = 'Eletricista TESTE'$$,
  '23514', null,
  'capacidade 0 e recusada pelo check — turma fechada e ativo = false');

select throws_ok(
  $$insert into public.turma_modular (unidade_id, curso_id, nome, sala_id, capacidade, data_inicio)
    select unidade_id, curso_id, 'Eletricista 2026.1', sala_id, 10, data_inicio
      from public.turma_modular where nome = 'Eletricista TESTE'$$,
  '23505', null,
  'duas turmas com o mesmo nome na mesma unidade sao recusadas');

-- E o outro lado da mesma unique, que é o que prova que ela tem `unidade_id`:
-- as duas unidades da fixture têm turmas de nome IDÊNTICO. Escrita sem o
-- unidade_id, a unique recusaria o seed da segunda unidade e a fixture nem
-- subiria — mas recusaria em voz alta, e é isso que esta asserção fixa.
select is(
  (select count(*)::bigint from public.turma_modular where nome = 'Eletricista 2026.1'),
  2::bigint,
  'o mesmo nome existe nas DUAS unidades — turma_modular_nome_uk e por unidade');

select throws_ok(
  $$insert into public.turma_modular_modulo (unidade_id, turma_id, modulo_id)
    select t.unidade_id, t.id, tm.modulo_id
      from public.turma_modular t
      join public.turma_modular_modulo tm on tm.turma_id = t.id
     where t.nome = 'Eletricista 2026.1'
       and t.unidade_id = tests.unidade('ESCOLA_A')
     limit 1$$,
  '23505', null,
  'o mesmo modulo duas vezes no cronograma da turma e recusado');

-- `data_entrada` omitida de propósito: o que se mede é o DEFAULT. `fn_hoje()` e
-- não `current_date` (ajuste 2 do card 2.3 §10) — com `current_date` a linha
-- nasceria com o dia seguinte entre 21h e a meia-noite, porque o Postgres do
-- Supabase roda em UTC. O C6 prova que `current_date` não está escrito; esta
-- asserção prova que o valor gravado é o certo.
--
-- ⚠️ O ocupante desta turma era 'Aluno de Lotação 01' (INTERATIVO) até o card
--    7.2, e a troca por Eduarda não é cosmética: o card 7.2 criou
--    `tg_turma_modular_aluno_admissao`, que exige método MODULAR (§9 do card
--    2.2 — «exige aluno ATIVO/ACELERAR do método MODULAR»). Este arquivo
--    reprovou com ALUNO_NAO_MODULAR no primeiro `supabase test db` depois da
--    migração, que é o desfecho certo: a escolha de aluno aqui era arbitrária
--    porque em 7.1 nenhuma regra a olhava, e hoje uma olha.
--
-- ⚠️ E o CONTEXTO DE ROTINA, pela mesma razão que a camada `modular` do seed
--    passou a tê-lo no card 7.2: daqui até o fim desta seção as escritas correm
--    como `postgres`, sem `auth.uid()`, e `tg_turma_modular_aluno_admissao`
--    chama `fn_turma_modular_ocupacao`, que é `security definer` filtrada por
--    `fn_unidade_atual()`. Sem unidade no contexto a ocupação vem NULA e o
--    trigger a lê como "turma de outra unidade" — PT404 numa turma que está bem
--    ali. Como `postgres` já ignora a RLS, o contexto aqui só supre a unidade:
--    nenhuma asserção desta seção mede permissão.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id)
select t.unidade_id, t.id, a.id
  from public.turma_modular t, public.aluno a
 where t.nome = 'Eletricista TESTE' and t.unidade_id = tests.unidade('ESCOLA_A')
   and a.nome = 'Eduarda Lima' and a.unidade_id = t.unidade_id;

select is(
  (select ta.data_entrada from public.turma_modular_aluno ta
     join public.turma_modular t on t.id = ta.turma_id
    where t.nome = 'Eletricista TESTE'),
  public.fn_hoje(),
  'data_entrada omitida nasce de fn_hoje(), nunca de current_date');

select throws_ok(
  $$insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id)
    select t.unidade_id, t.id, a.id
      from public.turma_modular t, public.aluno a
     where t.nome = 'Eletricista TESTE' and t.unidade_id = tests.unidade('ESCOLA_A')
       and a.nome = 'Eduarda Lima' and a.unidade_id = t.unidade_id$$,
  '23505', null,
  'o mesmo aluno duas vezes ATIVO na mesma turma e recusado');

-- A unique é PARCIAL (`where ativo`), e a diferença aparece aqui: com a entrada
-- anterior desativada, a mesma dupla (turma, aluno) entra de novo. É o que
-- permite ao card 7.2 REATIVAR em vez de duplicar, como fn_bloco_admitir faz em
-- bloco_aluno — e uma unique total teria travado a volta do aluno para sempre,
-- sem que nada além desta asserção denunciasse.
update public.turma_modular_aluno ta set ativo = false
  from public.turma_modular t
 where t.id = ta.turma_id and t.nome = 'Eletricista TESTE';

select lives_ok(
  $$insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id)
    select t.unidade_id, t.id, a.id
      from public.turma_modular t, public.aluno a
     where t.nome = 'Eletricista TESTE' and t.unidade_id = tests.unidade('ESCOLA_A')
       and a.nome = 'Eduarda Lima' and a.unidade_id = t.unidade_id$$,
  'com a entrada anterior INATIVA a dupla volta a entrar — a unique e parcial');

select tests.encerrar_sessao();

-- ===========================================================================
-- 3. Sem política de delete, o delete NÃO dá erro: devolve zero linhas
-- ===========================================================================
-- Card 3.4 (d), a mesma asserção que o card 5.1 escreveu para `bloco_aluno`. É o
-- silêncio posto como asserção: sem ela ninguém sabe que a ausência de política
-- ainda é a decisão, e não um esquecimento de quem escreveu a migração.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

with d as (delete from public.turma_modular_aluno where true returning 1)
select is((select count(*) from d)::bigint, 0::bigint,
  'ninguem apaga aluno de turma — nem a direcao; saida da turma e ativo = false');

reset role;

-- ===========================================================================
-- 4. RLS — paridade, silêncio e isolamento (card 2.8 §6.3)
-- ===========================================================================
-- `turmas.ler` é dos quatro perfis: sem ela a tela do card 7.3 abriria VAZIA,
-- não com erro.
select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'), 'select id from public.turma_modular'),
  '>', 0::bigint,
  'a direcao le turmas Modular (a contagem de referencia da paridade e > 0)');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select id from public.turma_modular_aluno') as n
       from (values ('direcao@escola-a.test'), ('pedagogico@escola-a.test'),
                    ('secretaria@escola-a.test'), ('monitor@escola-a.test')) as u(e)
   ) t)::bigint,
  1::bigint,
  'paridade: os quatro perfis com turmas.ler leem a MESMA contagem de alunos de turma');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'), 'select id from public.turma_modular'),
  0::bigint,
  'quem nao tem turmas.ler le zero — a RLS reduz em silencio, nao acusa');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   format('select id from public.turma_modular where unidade_id = %L',
                          tests.unidade('ESCOLA_A'))),
  0::bigint,
  'a unidade B nao ve turma Modular nenhuma da unidade A');

-- O monitor lê e não aloca: `turmas.alocar` é dos outros três (card 2.4 §5).
select tests.autenticar(tests.uid('monitor@escola-a.test'));

-- ⚠️ A aluna aqui era 'Carla Menezes' (INTERATIVO) até o card 7.2, e a troca é
--    obrigatória pela mesma razão da seção 2: `tg_turma_modular_aluno_admissao`
--    é BEFORE e roda ANTES da `with check` da política, então o método errado
--    respondia PT422 e a asserção de RLS media outra coisa. Com uma aluna
--    MODULAR o insert chega até a política, que é o que este teste quer medir.
select throws_ok(
  $$insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id)
    select public.fn_unidade_atual(),
           (select id from public.turma_modular
             where nome = 'Eletricista 2025.2' and unidade_id = public.fn_unidade_atual()),
           (select id from public.aluno
             where nome = 'Eduarda Lima' and unidade_id = public.fn_unidade_atual())$$,
  '42501', null,
  'o monitor tem turmas.ler e nao tem turmas.alocar');

reset role;

-- ===========================================================================
-- 5. RLS não é por coluna — a folga do `or` na política de update
-- ===========================================================================
-- O `or` existe por um motivo só: deixar tg_aluno_status_desaloca escrever
-- `ativo = false` na transação de quem mudou o status. Mas ele autoriza junto
-- qualquer outra coluna, e nenhum perfil da matriz inicial é assim — os três que
-- alteram status também alocam. O perfil é montado aqui, dentro da transação,
-- que é o único jeito de exercitar o caso que a tela do card 4.7 torna possível.
delete from public.perfil_permissao pp
 using public.perfil pe, public.permissao pm
 where pp.perfil_id = pe.id and pp.permissao_id = pm.id
   and pe.unidade_id = tests.unidade('ESCOLA_A') and pe.codigo = 'PEDAGOGICO'
   and pm.codigo = 'turmas.alocar';

-- ⚠️ Um SEGUNDO aluno MODULAR, criado aqui e não na fixture, e ele existe por
--    causa do card 7.2: a asserção "nem põe outra pessoa na vaga" trocava o
--    `aluno_id` por 'Carla Menezes' (INTERATIVO), e desde o 7.2 esse update
--    morre em ALUNO_NAO_MODULAR no `tg_turma_modular_aluno_admissao` — que roda
--    ANTES da guarda de coluna, como em `bloco_aluno` (o nome do trigger de
--    admissão vem antes na ordem alfabética, e é ela que decide a ordem dos
--    BEFORE do Postgres). A guarda continuaria certa e o teste deixaria de
--    medi-la: o write seria barrado pelo motivo errado. Com um MODULAR de
--    verdade o update chega à guarda, que é o que esta seção existe para medir.
--
--    Contexto de rotina para o `insert`: `tg_aluno_trilha_inicial` chama
--    `fn_trilha_gerar`, que exige `alunos.criar` — como `postgres`, sem
--    `auth.uid()`, `tem_permissao` é falsa e a matrícula morre em PT403.
--    `codigo_sgf` nulo porque a faixa 90xx é dos alunos de lotação da fixture.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

insert into public.aluno (unidade_id, codigo_sgf, nome, metodo_id, combo_id,
                          status, data_inicio)
select tests.unidade('ESCOLA_A'), null, 'Modular Suplente TESTE', me.id, cb.id,
       'ATIVO', public.fn_hoje()
  from public.metodo me
  join public.combo  cb on cb.unidade_id = me.unidade_id
                       and cb.nome = 'Eletricista Completo'
 where me.unidade_id = tests.unidade('ESCOLA_A') and me.codigo = 'MODULAR';

select tests.encerrar_sessao();

select is(
  tests.codigo_do_erro(
    $$update public.turma_modular_aluno ta set turma_id =
        (select id from public.turma_modular
          where nome = 'Eletricista 2025.2' and unidade_id = public.fn_unidade_atual())
       from public.turma_modular t
      where t.id = ta.turma_id and t.nome = 'Eletricista TESTE'$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'quem altera status e nao aloca NAO troca o aluno de turma — a capacidade do 7.2 nao se contorna');

select is(
  tests.codigo_do_erro(
    $$update public.turma_modular_aluno ta set aluno_id =
        (select id from public.aluno
          where nome = 'Modular Suplente TESTE' and unidade_id = public.fn_unidade_atual())
       from public.turma_modular t
      where t.id = ta.turma_id and t.nome = 'Eletricista TESTE' and ta.ativo$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'nem poe outra pessoa na vaga');

select is(
  tests.codigo_do_erro(
    $$update public.turma_modular_aluno ta set data_entrada = public.fn_hoje() - 400
       from public.turma_modular t
      where t.id = ta.turma_id and t.nome = 'Eletricista TESTE'$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'nem move a data de entrada, que e o que a previsao do modulo le');

-- Contraprova: o mesmo perfil, sem `turmas.alocar`, continua fazendo a escrita
-- que o `or` existe para permitir. Sem esta linha os três negativos acima
-- passariam mesmo que a guarda estivesse barrando tudo — e a desalocação sem
-- ator da seção 7 nasceria quebrada.
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));

select lives_ok(
  $$update public.turma_modular_aluno ta set ativo = false
     from public.turma_modular t
    where t.id = ta.turma_id and t.nome = 'Eletricista TESTE' and ta.ativo$$,
  'e continua desativando a linha — que e o que tg_aluno_status_desaloca faz');

reset role;

-- Devolve a permissão: as seções seguintes contam com a matriz do seed.
insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select pe.unidade_id, pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A') and pe.codigo = 'PEDAGOGICO'
   and pm.unidade_id = pe.unidade_id and pm.codigo = 'turmas.alocar';

-- ===========================================================================
-- 6. ALUNO_SEM_TURMA passou a olhar as DUAS formas de turma
-- ===========================================================================
-- É o portão que o card 5.5 escreveu dentro da própria rotina: enquanto
-- `turma_modular_aluno` não existisse, "sem turma" era "sem bloco ativo" — e no
-- dia em que existisse, o aluno MODULAR alocado numa turma passaria a receber a
-- pendência todo dia. Eduarda é exatamente esse aluno, e é a fixture deste card
-- que faz a correção ser MEDIDA em vez de declarada.
select tests.como_rotina(tests.unidade('ESCOLA_A'));
select public.rt_pendencias_diaria();
select tests.encerrar_sessao();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Eduarda Lima' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'ALUNO_SEM_TURMA' and p.resolvida_em is null),
  0::bigint,
  'a aluna MODULAR em turma NAO recebe ALUNO_SEM_TURMA — a pendencia falsa que o 5.5 previu');

-- E a turma tem de estar ATIVA para contar, pela mesma razão que o card 5.7 deu
-- ao `bloco_ativo`: turma desativada não é turma. Sem esta metade, desativar uma
-- turma tiraria os alunos dela da tela sem abrir pendência nenhuma.
update public.turma_modular set ativo = false
 where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eletricista 2026.1';

select tests.como_rotina(tests.unidade('ESCOLA_A'));
select public.rt_pendencias_diaria();
select tests.encerrar_sessao();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.nome = 'Eduarda Lima' and a.unidade_id = tests.unidade('ESCOLA_A')
      and p.tipo = 'ALUNO_SEM_TURMA' and p.resolvida_em is null),
  1::bigint,
  'desativada a turma, a aluna volta a aparecer como sem turma — turma inativa nao e turma');

update public.turma_modular set ativo = true
 where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Eletricista 2026.1';

-- ===========================================================================
-- 7. A terceira tabela de tg_aluno_status_desaloca (card 2.2 §3.2)
-- ===========================================================================
-- Sem esta metade não haveria erro nenhum: haveria o erro ERRADO — o aluno
-- Modular trancado continuando na turma, ocupando vaga, e a previsão do módulo
-- contando com ele. O portão do teste 040 §10 lê a citação no corpo da função;
-- o que se mede aqui é o COMPORTAMENTO, que é o que importa.
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));

select lives_ok(
  $$select public.fn_aluno_alterar_status(
      (select id from public.aluno
        where nome = 'Eduarda Lima' and unidade_id = public.fn_unidade_atual()),
      'STANDBY', 'parou de vir')$$,
  'o pedagogico move Eduarda de ATIVO para STANDBY');

reset role;

select is(
  (select count(*)::bigint from public.turma_modular_aluno ta
     join public.aluno a on a.id = ta.aluno_id
    where a.nome = 'Eduarda Lima' and a.unidade_id = tests.unidade('ESCOLA_A')
      and ta.ativo),
  0::bigint,
  'quem sai de ATIVO larga a vaga TAMBEM na turma Modular — a terceira tabela do card 2.2 §3.2');

-- CONTRAPROVA POR CONSTRUÇÃO. O portão do 040 não pode mais fazê-la (a tabela
-- existe, e a condição dele deixou de ter dois mundos), então ela mora aqui: a
-- função é reescrita SEM o `update` da turma Modular, dentro desta transação, e
-- a mesma operação passa a deixar a aluna dentro da turma. A definição
-- sabotada volta no rollback junto com o resto.
--
-- ⚠️ Duas mudanças que o card 7.2 obrigou nesta preparação, e as duas são o
--    trigger novo funcionando:
--    (a) a aluna volta a ATIVO antes de a linha ser reativada. Desde o 7.2,
--        `tg_turma_modular_aluno_admissao` recusa com ALUNO_INATIVO reativar a
--        vaga de quem não é ATIVO/ACELERAR — que é exatamente a regra, e não um
--        obstáculo do teste;
--    (b) a reativação é escopada à turma da fixture. Com Eduarda também na
--        'Eletricista TESTE' (seção 2), um `update` sem escopo ressuscitaria
--        aquela linha e a seção 8 mediria outra coisa.
--    A transição ATIVO → TRANCADO não existe na tabela de decisão do card 2.2
--    §3.1, então a contraprova usa STANDBY de novo: o que se mede é a linha da
--    turma, não o nome do status.
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));
select public.fn_aluno_alterar_status(
  (select id from public.aluno
    where nome = 'Eduarda Lima' and unidade_id = public.fn_unidade_atual()),
  'ATIVO', 'voltou a frequentar');
reset role;

update public.turma_modular_aluno ta set ativo = true
  from public.aluno a, public.turma_modular t
 where a.id = ta.aluno_id and a.nome = 'Eduarda Lima'
   and a.unidade_id = tests.unidade('ESCOLA_A')
   and t.id = ta.turma_id and t.nome = 'Eletricista 2026.1';

create or replace function public.fn_aluno_status_desaloca()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $sab$
begin
  if new.status in ('ATIVO', 'ACELERAR') then
    return null;
  end if;

  update public.bloco_aluno
     set ativo = false,
         motivo_saida = format('Aluno passou a %s', new.status)
   where aluno_id = new.id and ativo;

  update public.bloco_aluno_reposicao
     set status = 'CANCELADA'
   where aluno_id = new.id
     and status = 'PREVISTA'
     and data >= public.fn_hoje();

  return null;
end $sab$;

select tests.autenticar(tests.uid('pedagogico@escola-a.test'));
select public.fn_aluno_alterar_status(
  (select id from public.aluno
    where nome = 'Eduarda Lima' and unidade_id = public.fn_unidade_atual()),
  'STANDBY', 'parou de vir de novo');
reset role;

select is(
  (select count(*)::bigint from public.turma_modular_aluno ta
     join public.aluno a on a.id = ta.aluno_id
    where a.nome = 'Eduarda Lima' and a.unidade_id = tests.unidade('ESCOLA_A')
      and ta.ativo),
  1::bigint,
  'SEM o update da turma Modular, a aluna que saiu de ATIVO continua na turma — o erro ERRADO, sem erro nenhum');

-- ===========================================================================
-- 8. A guarda de exclusão e os DOIS MUNDOS (o achado do card 4.3, aqui)
-- ===========================================================================
-- A turma vazia é o caso que mantém `turmas.excluir` com um uso real: sem ele, a
-- guarda seria uma proibição total escrita como se fosse uma condição.
select is(
  tests.codigo_do_erro(
    $$delete from public.turma_modular
       where nome = 'Eletricista TESTE' and unidade_id = public.fn_unidade_atual()$$,
    tests.uid('direcao@escola-a.test')),
  'TURMA_COM_ALUNO',
  'turma com historico de alunos nao pode ser apagada — "excluir sem alocacao" vira estrutura');

-- E as linhas INATIVAS contam: `ativo = false` é como o aluno sai da turma, então
-- uma turma só com linhas inativas é exatamente uma turma que já teve gente. A
-- turma de teste está nesse estado desde a contraprova da seção 5.
select is(
  (select count(*)::bigint from public.turma_modular_aluno ta
     join public.turma_modular t on t.id = ta.turma_id
    where t.nome = 'Eletricista TESTE' and ta.ativo),
  0::bigint,
  'e a turma que recusou nao tem NENHUM aluno ativo — historico inativo conta como historico');

select tests.autenticar(tests.uid('direcao@escola-a.test'));

select lives_ok(
  $$delete from public.turma_modular
     where nome = 'Eletricista 2025.2' and unidade_id = public.fn_unidade_atual()$$,
  'turma sem aluno nenhum continua apagavel — a guarda nao esvazia turmas.excluir');

reset role;

-- CONTRAPROVA: o mundo sem a guarda. O trigger cai dentro desta transação e
-- volta no rollback. Sem ele, apagar a turma leva junto as linhas de aluno — em
-- SILÊNCIO, e apesar de `turma_modular_aluno` não ter política de delete para
-- ninguém: a ação em cascata de uma FK não passa pela RLS da tabela
-- referenciadora (medido no card 4.3). Guarda que nunca foi vista fazendo
-- diferença é decoração.
drop trigger tg_turma_modular_exclusao_valida on public.turma_modular;

select tests.autenticar(tests.uid('direcao@escola-a.test'));
delete from public.turma_modular
 where nome = 'Eletricista TESTE' and unidade_id = public.fn_unidade_atual();
reset role;

select is(
  (select count(*)::bigint from public.turma_modular_aluno ta
    where ta.turma_id not in (select id from public.turma_modular)),
  0::bigint,
  'SEM a guarda, a cascata apagou as linhas de aluno junto com a turma — sem erro e sem politica de delete');

select * from finish();
rollback;
