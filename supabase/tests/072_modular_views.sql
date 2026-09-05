-- =============================================================================
-- v_turma_modular_lotacao, _cronograma e _aluno — card 7.3 (a tela 5)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- ⚠️ O §17 NÃO PREVIA ARQUIVO PARA O 7.3, e a divergência é a mesma do `053`
--    (card 6.6), do `061` (6.7) e do `062` (6.8): a tela 5 foi planejada sem
--    objeto de banco e tem três views. `views-leitura.md` §12.1 já dizia que
--    view de tela pertence ao card da tela; card de View tem obrigação própria
--    no §13, e ela é cumprida aqui. Mora no bloco `07x`, ao lado do
--    `070_turmas_modular` (7.1) e do `071_modular_regras` (7.2), e não no `095`.
--    Registrada no §17, não seguida em silêncio.
--
-- ⚠️ SEGUNDA DIVERGÊNCIA, e é a que este arquivo mede: `v_turma_modular_lotacao`
--    estava atribuída aos cards **7.4 e 5.9** (`views-leitura.md` §7.2 e §12) e
--    NASCE NO 7.3, porque é o §8 do `wireframes.md` que manda a tela 5 lê-la.
--    Vence o §12.1, que é a regra geral. O 7.4 passa a consumi-la.
--
-- Obrigação de **View** (§13): paridade de linhas por perfil + zero para quem
-- não pode + isolamento de unidade (§6.3), mais as armadilhas do card 2.3 §3
-- que se aplicam.
--
-- Cinco coisas que este arquivo prova e que nenhum catálogo enxerga:
--
--   • **`corrente` da view e `fn_turma_modular_modulo_corrente` dizem a MESMA
--     coisa**, turma a turma. São três expressões do mesmo fato (a coluna, a
--     função e o `left join lateral` da lotação), e o card 2.3 §4.1 só as
--     tolera porque esta asserção existe. A contraprova está ao lado: com a
--     comparação escrita por `min(ordem)` sem o filtro de `concluido`, a turma
--     com o módulo 1 fechado apontaria o módulo errado;
--
--   • **`atrasado` NÃO vale para módulo concluído.** `fn_turma_modular_avancar`
--     grava em `prev_conclusao` a data REAL da conclusão (card 7.2 §5), então
--     todo módulo já fechado tem previsão no passado — sem a condição, uma
--     turma em dia apareceria com metade do cronograma em vermelho. A fixture
--     tem exatamente esse caso: o módulo 1 da `2026.1`, concluído e com
--     `prev_conclusao` de 25 dias atrás;
--
--   • **`modulo_atrasado` distingue as duas turmas da fixture** — a `2025.2`
--     está vencida e a `2026.1` não —, e é por isso que a camada `modular` do
--     seed as criou em estados diferentes (card 7.1). Uma implementação que
--     devolvesse sempre `true` (ou sempre `false`) passaria numa fixture
--     homogênea;
--
--   • **`vagas_livres` tem piso ZERO e `alocados` não.** Turma acima da
--     capacidade é estado real, e "−1 vaga livre" não é frase de tela; quem
--     recusa a admissão seguinte é o trigger, não este número;
--
--   • **as três views reagem de forma DIFERENTE à falta de `alunos.ler`**, e
--     isso é decisão, não acaso: lotação e cronograma vêm CHEIAS (nenhuma junta
--     `aluno`), e `v_turma_modular_aluno` vem VAZIA (join interno). A rota da
--     tela 5 não exige `alunos.ler` — daí a região da tela declarar a permissão
--     que falta em vez de listar vazio ao lado de uma lotação `1/15`.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(34);

-- Chaves naturais em um lugar só (card 2.8 §11: nunca `limit` sem ordem, nunca
-- UUID literal). ⚠️ Como no `062`, estas views só servem ao lado `postgres` do
-- arquivo: elas chamam `tests.unidade`, e `authenticated` não tem USAGE no
-- schema `tests`.
create temporary view turma_id (nome, id) as
  select t.nome, t.id from public.turma_modular t
   where t.unidade_id = tests.unidade('ESCOLA_A');

-- ===========================================================================
-- 1. v_turma_modular_lotacao — lotação, vagas e módulo corrente
-- ===========================================================================
select is(
  (select format('%s/%s, %s livre(s)', l.alocados, l.capacidade, l.vagas_livres)
     from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.turma_nome = 'Eletricista 2026.1'),
  '1/15, 14 livre(s)',
  'a lotacao conta so o aluno ATIVO na turma, e as vagas sao capacidade menos ele');

select is(
  (select format('%s. %s', l.modulo_corrente_ordem, l.modulo_corrente_nome)
     from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.turma_nome = 'Eletricista 2026.1'),
  '2. Módulo 2 — Instalações prediais',
  'o modulo corrente e o primeiro NAO concluido por modulo.ordem, e nao o primeiro do curso');

-- As duas turmas em estados OPOSTOS: é o que a camada `modular` do seed montou
-- de propósito, e sem isso `modulo_atrasado` sempre verdadeiro passaria.
select is(
  (select string_agg(l.turma_nome || '=' || l.modulo_atrasado::text, ', '
                     order by l.turma_nome)
     from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.turma_nome like 'Eletricista 202%'),
  'Eletricista 2025.2=true, Eletricista 2026.1=false',
  'modulo_atrasado distingue a turma vencida da em dia — as duas, nao uma so');

-- Contraprova de `fn_hoje()` (armadilha §3.3): a previsão da `2026.1` é 35 dias
-- à frente, então nenhuma leitura de "hoje" plausível a torna atrasada; a da
-- `2025.2` é 40 dias atrás. A distância é grande de propósito — um teste com um
-- dia de folga passaria com `current_date` em UTC.
select cmp_ok(
  (select l.modulo_corrente_prev_conclusao - public.fn_hoje()
     from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.turma_nome = 'Eletricista 2026.1'),
  '>', 30,
  'a previsao da turma em dia esta bem no futuro: o atraso nao e questao de fuso');

-- Turma INATIVA some da lotação (`where t.ativo`), e é por isso que a tela tem
-- uma lista de inativas: sem ela, desativar seria porta de mão única.
update public.turma_modular set ativo = false
 where id = (select id from turma_id where nome = 'Eletricista 2025.2');

select is(
  (select count(*) from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.turma_nome = 'Eletricista 2025.2')::bigint,
  0::bigint,
  'turma inativa sai da lotacao — a view filtra t.ativo');

update public.turma_modular set ativo = true
 where id = (select id from turma_id where nome = 'Eletricista 2025.2');

-- Piso zero: uma turma de capacidade 1 com dois alunos. `alocados` diz a
-- verdade (2), `vagas_livres` não vira negativo.
update public.turma_modular set capacidade = 1
 where id = (select id from turma_id where nome = 'Eletricista 2026.1');

select is(
  (select format('%s/%s, %s livre(s)', l.alocados, l.capacidade, l.vagas_livres)
     from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.turma_nome = 'Eletricista 2026.1'),
  '1/1, 0 livre(s)',
  'turma exatamente cheia: zero vagas, e alocados igual a capacidade');

update public.turma_modular set capacidade = 15
 where id = (select id from turma_id where nome = 'Eletricista 2026.1');

-- Agora ACIMA da capacidade, que é estado REAL: o importador do card 9.1 pode
-- trazê-lo, e a tela do 7.3 tem um aviso próprio para ele. A fixture tem UM só
-- aluno MODULAR (card 7.1 escreveu por quê), então o segundo nasce aqui — dentro
-- da transação, que termina em `rollback`.
--
-- ⚠️ SEM `combo_id`, e não é economia: `tg_aluno_trilha_inicial` (card 6.2)
--    dispara no insert com combo e chama `fn_trilha_gerar`, que exige
--    `alunos.editar_trilha` — e este trecho roda como `postgres`, sem
--    `auth.uid()`, então o `db reset` inteiro morria em `SEM_PERMISSAO`. Medido
--    em 05/09/2026, na primeira execução deste arquivo. Aluno sem combo é o que
--    esta seção precisa: a vaga na turma não olha trilha nenhuma.
insert into public.aluno (unidade_id, nome, metodo_id)
select tests.unidade('ESCOLA_A'), 'Segundo Modular (teste 072)', a.metodo_id
  from public.aluno a
  join public.metodo me on me.id = a.metodo_id
 where a.unidade_id = tests.unidade('ESCOLA_A') and me.codigo = 'MODULAR'
 order by a.nome
 limit 1;

-- ⚠️ CONTEXTO DE ROTINA, pela mesma razão que a camada `modular` do seed
--    (card 7.2): `tg_turma_modular_aluno_admissao` chama
--    `fn_turma_modular_ocupacao`, que é `security definer` e filtra por
--    `fn_unidade_atual()`. Este trecho roda como `postgres`, sem `auth.uid()` —
--    sem o contexto a ocupação vem NULA, o trigger a lê como "turma de outra
--    unidade" e o arquivo morre em PT404/TURMA_INEXISTENTE. Medido em
--    05/09/2026, na primeira execução deste teste.
--    `is_local => true`: morre no fim da transação, que aqui é o `rollback`.
select set_config('app.rotina', 'on', true);
select set_config('app.rotina_unidade', tests.unidade('ESCOLA_A')::text, true);

insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id, ativo)
select tests.unidade('ESCOLA_A'),
       (select id from turma_id where nome = 'Eletricista 2025.2'),
       a.id, true
  from public.aluno a
 where a.unidade_id = tests.unidade('ESCOLA_A')
   and a.nome in ('Eduarda Lima', 'Segundo Modular (teste 072)');

-- Fora do contexto de rotina outra vez: as seções seguintes medem RLS de
-- usuário, e deixar `app.rotina` ligado faria `fn_unidade_atual()` responder
-- pela unidade fixada em vez de pelo perfil de quem está lendo.
select set_config('app.rotina', 'off', true);

-- Uma segunda linha ATIVA do MESMO aluno é impossível (unique parcial), então o
-- "acima" se produz baixando a capacidade DEPOIS de alocar — que é exatamente o
-- caminho real: alguém edita a turma para menos. O trigger de admissão não
-- dispara em `turma_modular`, e é por isso que o caminho existe.
select lives_ok(
  $$update public.turma_modular set capacidade = 1
     where nome = 'Eletricista 2025.2'
       and unidade_id = tests.unidade('ESCOLA_A')$$,
  'baixar a capacidade de turma ja ocupada e permitido — quem reclama e a pendencia');

select is(
  (select format('%s/%s, %s livre(s)', l.alocados, l.capacidade, l.vagas_livres)
     from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.turma_nome = 'Eletricista 2025.2'),
  '2/1, 0 livre(s)',
  'vagas_livres tem piso ZERO com a turma ESTOURADA: "-1 vaga livre" nao e frase de tela');

-- E `alocados` NÃO tem piso: ele diz a verdade (2 numa turma de 1), que é o que
-- a tela precisa para mostrar o aviso de "acima da capacidade". Grampear os dois
-- esconderia o estado que precisa de ação.
select cmp_ok(
  (select l.alocados from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.turma_nome = 'Eletricista 2025.2'),
  '>',
  (select l.capacidade from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.turma_nome = 'Eletricista 2025.2'),
  'alocados NAO tem piso nem teto: e ele que denuncia a turma estourada');

-- Desfaz para as seções seguintes: a `2025.2` volta a ser a turma VAZIA e
-- atrasada da fixture, que é o que a seção 2 mede.
delete from public.turma_modular_aluno
 where turma_id = (select id from turma_id where nome = 'Eletricista 2025.2');
delete from public.aluno
 where unidade_id = tests.unidade('ESCOLA_A')
   and nome = 'Segundo Modular (teste 072)';
update public.turma_modular set capacidade = 15
 where id = (select id from turma_id where nome = 'Eletricista 2025.2');

-- ===========================================================================
-- 2. v_turma_modular_cronograma — ordem, corrente, atrasado
-- ===========================================================================
select is(
  (select string_agg(c.modulo_ordem || ':' ||
                     case when c.concluido then 'v'
                          when c.corrente  then '>'
                          else '.' end, ' ' order by c.modulo_ordem)
     from public.v_turma_modular_cronograma c
    where c.turma_id = (select id from turma_id where nome = 'Eletricista 2026.1')),
  '1:v 2:> 3:.',
  'a faixa do wireframe §8 sai da view: concluido, corrente e futuro na ordem do catalogo');

-- ⚠️ A ASSERÇÃO QUE AUTORIZA A TERCEIRA EXPRESSÃO A EXISTIR (card 2.3 §4.1):
--    a coluna `corrente`, a função do card 7.2 e o `left join lateral` da
--    lotação têm de apontar o MESMO módulo em TODA turma com cronograma.
select is(
  (select count(*) from public.turma_modular t
    where t.unidade_id = tests.unidade('ESCOLA_A')
      and exists (select 1 from public.turma_modular_modulo tm
                   where tm.turma_id = t.id)
      and public.fn_turma_modular_modulo_corrente(t.id) is distinct from
          (select c.modulo_id from public.v_turma_modular_cronograma c
            where c.turma_id = t.id and c.corrente))::bigint,
  0::bigint,
  'a coluna corrente e fn_turma_modular_modulo_corrente apontam o mesmo modulo em toda turma');

select is(
  (select count(*) from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.modulo_corrente_id is distinct from
          (select c.modulo_id from public.v_turma_modular_cronograma c
            where c.turma_id = l.turma_id and c.corrente))::bigint,
  0::bigint,
  'e a lotacao aponta o mesmo: as TRES expressoes do modulo corrente nunca divergem');

-- Contraprova do filtro de `concluido` no `corrente`: sem ele, o primeiro
-- módulo por ordem seria "corrente" mesmo já fechado. A `2026.1` tem o 1
-- concluído, e é ela que separa as duas leituras.
select isnt(
  (select c.modulo_id from public.v_turma_modular_cronograma c
    where c.turma_id = (select id from turma_id where nome = 'Eletricista 2026.1')
      and c.corrente),
  (select c.modulo_id from public.v_turma_modular_cronograma c
    where c.turma_id = (select id from turma_id where nome = 'Eletricista 2026.1')
    order by c.modulo_ordem limit 1),
  'contraprova: corrente NAO e o primeiro do cronograma — o 1 ja foi concluido');

-- ⚠️ O módulo 1 da `2026.1` está CONCLUÍDO e com `prev_conclusao` 25 dias no
--    passado, que é como `fn_turma_modular_avancar` grava a data real. Sem a
--    condição `not concluido`, ele viria `atrasado` — e toda turma em dia
--    apareceria com metade do cronograma em vermelho.
select is(
  (select string_agg(c.modulo_ordem || '=' || c.atrasado::text, ' '
                     order by c.modulo_ordem)
     from public.v_turma_modular_cronograma c
    where c.turma_id = (select id from turma_id where nome = 'Eletricista 2026.1')),
  '1=false 2=false 3=false',
  'modulo CONCLUIDO com previsao no passado nao e atrasado — a data ali e a da conclusao real');

select cmp_ok(
  (select c.prev_conclusao from public.v_turma_modular_cronograma c
    where c.turma_id = (select id from turma_id where nome = 'Eletricista 2026.1')
      and c.modulo_ordem = 1),
  '<', public.fn_hoje(),
  'contraprova: a previsao do modulo 1 ESTA no passado — a assercao acima nao passa de graca');

select is(
  (select c.atrasado from public.v_turma_modular_cronograma c
    where c.turma_id = (select id from turma_id where nome = 'Eletricista 2025.2')
      and c.modulo_ordem = 1),
  true,
  'modulo NAO concluido com previsao vencida e atrasado — e o outro lado do par');

-- Turma com TUDO concluído: nenhuma linha corrente, e a lotação com o corrente
-- nulo. É o estado "turma terminou", e ela NÃO some da lista (wireframe §8).
update public.turma_modular_modulo set concluido = true
 where turma_id = (select id from turma_id where nome = 'Eletricista 2026.1');

select is(
  (select count(*) from public.v_turma_modular_cronograma c
    where c.turma_id = (select id from turma_id where nome = 'Eletricista 2026.1')
      and c.corrente)::bigint,
  0::bigint,
  'turma com tudo concluido nao tem linha corrente — o estado "turma terminou"');

select is(
  (select format('%s linha(s), corrente %s',
                 count(*),
                 case when bool_and(l.modulo_corrente_id is null) then 'nulo'
                      else 'preenchido' end)
     from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.turma_nome = 'Eletricista 2026.1'),
  '1 linha(s), corrente nulo',
  'e ela CONTINUA na lotacao, com o corrente nulo: "terminou" nao e "sumiu"');

update public.turma_modular_modulo set concluido = false
 where turma_id = (select id from turma_id where nome = 'Eletricista 2026.1')
   and modulo_id <> (select tm.modulo_id from public.turma_modular_modulo tm
                       join public.modulo m on m.id = tm.modulo_id
                      where tm.turma_id = (select id from turma_id
                                            where nome = 'Eletricista 2026.1')
                      order by m.ordem limit 1);

-- ===========================================================================
-- 3. v_turma_modular_aluno — o inativo fica, e o motivo com ele
-- ===========================================================================
select is(
  (select format('%s (%s), desde %s', v.aluno_nome, v.codigo_sgf,
                 to_char(v.data_entrada, 'DD/MM'))
     from public.v_turma_modular_aluno v
    where v.turma_id = (select id from turma_id where nome = 'Eletricista 2026.1')
      and v.ativo),
  format('Eduarda Lima (3005), desde %s',
         to_char(public.fn_hoje() - 60, 'DD/MM')),
  'a view resolve nome, codigo e data de entrada — turma_modular_aluno so tem o id');

-- Sai pela FUNÇÃO do card 7.2, e na pele de quem tem `turmas.alocar`: como
-- `postgres` a função morre em `SEM_PERMISSAO` (`tem_permissao` sem `auth.uid()`
-- é falso). Os ids são resolvidos ANTES de autenticar, porque `tests.unidade`
-- não é alcançável por `authenticated` — o mesmo desenho de `pg_temp.receber`
-- no `062`.
create or replace function pg_temp.remover_da_turma(
  p_turma text, p_email text, p_motivo text)
returns void
language plpgsql
as $$
declare
  v_role  text := current_user;
  v_turma uuid;
  v_aluno uuid;
begin
  select t.id into v_turma from public.turma_modular t
   where t.nome = p_turma and t.unidade_id = tests.unidade('ESCOLA_A');
  -- `order by` completo: `limit` sem ordem é sorteio (§11).
  select ta.aluno_id into v_aluno from public.turma_modular_aluno ta
   where ta.turma_id = v_turma and ta.ativo
   order by ta.criado_em, ta.id
   limit 1;

  perform tests.autenticar(tests.uid(p_email));
  perform public.fn_turma_modular_remover(v_turma, v_aluno, p_motivo);
  execute format('set local role %I', v_role);
  perform set_config('request.jwt.claims', null, true);
end $$;

select lives_ok(
  $$select pg_temp.remover_da_turma('Eletricista 2026.1',
                                    'secretaria@escola-a.test',
                                    'mudou de cidade')$$,
  'a saida da turma passa pela funcao do card 7.2, com o motivo');

-- `%s` de boolean imprime `t`/`f` (o output do tipo), e não `true`/`false`: o
-- `::text` das asserções acima é o que produz a outra forma.
select is(
  (select format('%s: ativo=%s, motivo=%s',
                 v.aluno_nome, v.ativo::text, v.motivo_saida)
     from public.v_turma_modular_aluno v
    where v.turma_id = (select id from turma_id where nome = 'Eletricista 2026.1')
      and v.aluno_nome = 'Eduarda Lima'),
  'Eduarda Lima: ativo=false, motivo=mudou de cidade',
  'quem saiu CONTINUA na view com o motivo: e a unica leitura que responde por que');

select is(
  (select l.alocados from public.v_turma_modular_lotacao l
    where l.unidade_id = tests.unidade('ESCOLA_A')
      and l.turma_nome = 'Eletricista 2026.1'),
  0,
  'mas ele NAO conta na lotacao: quem ocupa vaga e so o ativo, e a conta e a mesma do trigger');

-- Devolve Eduarda à turma: a seção 4 precisa de uma turma com aluno ATIVO para
-- provar que a lotação conta gente que a lista não mostra — sem isso a asserção
-- do `EstadoSemAcesso` por região compararia zero com zero. Contexto de rotina
-- pela mesma razão da seção 1 (o trigger de admissão dispara em `new.ativo`).
select set_config('app.rotina', 'on', true);
select set_config('app.rotina_unidade', tests.unidade('ESCOLA_A')::text, true);

update public.turma_modular_aluno
   set ativo = true, motivo_saida = null
 where turma_id = (select id from turma_id where nome = 'Eletricista 2026.1');

select set_config('app.rotina', 'off', true);

-- ===========================================================================
-- 4. Paridade por perfil, zero para quem não pode e isolamento de unidade
-- ===========================================================================
-- Um perfil com o conjunto EXATO da rota da tela 5 e SEM `alunos.ler`: é o que
-- separa as três views, e o único jeito de provar que o join interno de
-- `v_turma_modular_aluno` é escolha.
insert into public.perfil (unidade_id, codigo, nome)
values (tests.unidade('ESCOLA_A'), 'MOD_SALUNOS', 'Rota da tela 5 sem alunos.ler (teste 072)');

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select tests.unidade('ESCOLA_A'), pe.id, pm.id
  from public.perfil pe, public.permissao pm
 where pe.unidade_id = tests.unidade('ESCOLA_A')
   and pm.unidade_id = tests.unidade('ESCOLA_A')
   and pe.codigo = 'MOD_SALUNOS'
   and pm.codigo in ('turmas.ler', 'salas.ler', 'materiais.ler');

select tests.criar_usuario('modsalunos@escola-a.test', 'MOD_SALUNOS');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_turma_modular_lotacao'),
  '>', 0::bigint,
  'a direcao ve turma: sem isso toda paridade abaixo comparava zero com zero');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e),
                             'select 1 from public.v_turma_modular_lotacao') as n
       from (values ('direcao@escola-a.test'), ('pedagogico@escola-a.test'),
                    ('secretaria@escola-a.test'), ('monitor@escola-a.test')) as u(e)
   ) t)::bigint,
  1::bigint,
  'paridade: os quatro perfis da rota leem a MESMA contagem de turmas');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e),
                             'select 1 from public.v_turma_modular_cronograma') as n
       from (values ('direcao@escola-a.test'), ('pedagogico@escola-a.test'),
                    ('secretaria@escola-a.test'), ('monitor@escola-a.test')) as u(e)
   ) t)::bigint,
  1::bigint,
  'paridade: e a MESMA contagem de linhas de cronograma');

-- As três views reagindo de forma DIFERENTE à mesma falta de permissão.
select cmp_ok(
  tests.conta_como(tests.uid('modsalunos@escola-a.test'),
                   'select 1 from public.v_turma_modular_lotacao'),
  '>', 0::bigint,
  'sem alunos.ler a LOTACAO vem cheia: ela nao junta aluno nenhum');

select cmp_ok(
  tests.conta_como(tests.uid('modsalunos@escola-a.test'),
                   'select 1 from public.v_turma_modular_cronograma'),
  '>', 0::bigint,
  'e o CRONOGRAMA tambem: ele junta modulo, e a rota ja exige materiais.ler');

select is(
  tests.conta_como(tests.uid('modsalunos@escola-a.test'),
                   'select 1 from public.v_turma_modular_aluno'),
  0::bigint,
  'mas a lista de ALUNOS vem VAZIA: join interno em aluno, e a rota nao pede alunos.ler');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select 1 from public.v_turma_modular_aluno'),
  '>', 0::bigint,
  'contraprova: com alunos.ler os alunos VEM — senao a assercao acima passaria de graca');

-- ⚠️ O NÚMERO QUE A TELA MOSTRA AO LADO DA LISTA VAZIA. Sem `alunos.ler` a
--    lotação diz "1/15" e a lista vem sem ninguém: é a redução silenciosa do
--    card 2.3 §3.4 na forma mais enganosa, e é por isso que a região da tela
--    declara a permissão faltante em vez de listar vazio.
select cmp_ok(
  tests.conta_como(tests.uid('modsalunos@escola-a.test'),
                   'select 1 from public.v_turma_modular_lotacao where alocados > 0'),
  '>', 0::bigint,
  'a lotacao continua contando alunos que a lista nao mostra — o motivo do EstadoSemAcesso por regiao');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.v_turma_modular_lotacao'),
  0::bigint,
  'sem perfil nenhum a tela 5 e vazia — e vazia por RLS, que a view nao pode esconder');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_turma_modular_lotacao where unidade_id = ' ||
                   quote_literal(tests.unidade('ESCOLA_A')::text) || '::uuid'),
  0::bigint,
  'a direcao da Escola B nao ve turma da Escola A: security_invoker + RLS por unidade');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_turma_modular_lotacao'),
  '>', 0::bigint,
  'contraprova: ela ve as turmas da PROPRIA unidade, e o isolamento nao e "view quebrada"');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select 1 from public.v_turma_modular_aluno where unidade_id = ' ||
                   quote_literal(tests.unidade('ESCOLA_A')::text) || '::uuid'),
  0::bigint,
  'e a lista de alunos tambem isola por unidade');

select * from finish();
rollback;
