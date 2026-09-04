-- =============================================================================
-- Card 5.7 — Os alunos do bloco no banco (v_bloco_alunos + fn_bloco_alunos)
-- Fonte: docs/views-leitura.md §12.1 (v_bloco_alunos é view de tela DESTE card)
--          e §2/§3 (princípios de view),
--        docs/wireframes.md §7.2 (a lista de alunos do bloco), §6.4 (a aba
--          Turmas da ficha), §6.1 (a coluna Turmas e o ⚠ da lista) e §17 #3
--          (a view precisa expor a ORIGEM da reposição pontual),
--        docs/regras-negocio-funcoes.md §4.3/§4.4 (as funções de admissão e
--          reposição do card 5.3, que aqui NÃO se reimplementam),
--        docs/estrategia-testes.md §13 (obrigação de card de View).
--
-- ⚠️ ESTE ARQUIVO NÃO GRAVA NADA. Uma view, uma função e a substituição de
--    `rt_pendencias_diaria`. O portão do card 4.0,5 segue as chamadas
--    transitivamente: `rt_pendencias_diaria` escreve em `pendencia`, mas é
--    apenas DEFINIDA aqui e nunca chamada — quem a chama é o `pg_cron`, em
--    tempo de execução, com o dado de cada ambiente.
--
-- O QUE ESTE CARD NÃO RECRIA, e onde está escrito que não é esquecimento:
-- `fn_bloco_admitir`, `fn_bloco_remover`, `fn_reposicao_agendar/registrar/
-- cancelar`, `tg_bloco_aluno_admissao` e `bloco_aluno.motivo_saida` são do card
-- 5.3; `fn_capacidade_efetiva`/`fn_ocupacao_bloco`/`fn_vagas_livres` são do 5.2;
-- `fn_rep_situacao` é do 5.3. A tela ORQUESTRA essas funções — a validação de
-- vaga, o advisory lock e o `BLOCO_LOTADO` já estão no banco.
--
-- DUAS PEÇAS, E A DIVISÃO NÃO É ARBITRÁRIA. A alocação em `bloco_aluno` vale
-- toda semana; a reposição em `bloco_aluno_reposicao` vale só no dia (card 2.1
-- §8). Então:
--   • `v_bloco_alunos` é a metade PERMANENTE — quem está alocado em que bloco —,
--     e por isso é view: não depende de data nenhuma. Ela responde às duas
--     perguntas que o app faz fora do painel do bloco (a aba Turmas da ficha e a
--     coluna Turmas da lista de alunos) e é a definição única de "o aluno está
--     em turma", que `rt_pendencias_diaria` passa a consumir;
--   • `fn_bloco_alunos(bloco, data)` é a LOTAÇÃO DAQUELA DATA — as alocações da
--     view mais as reposições PREVISTAS do dia —, e por isso é função: view não
--     recebe parâmetro, e o painel do §7.2 abre a partir de uma célula da grade,
--     que é um bloco NUMA DATA.
-- A função é escrita EM CIMA da view, como o card 5.6 escreveu a view em cima da
-- função e pela mesma razão: uma segunda implementação de "quem está alocado
-- aqui" divergiria em silêncio, com os dois números continuando plausíveis.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. v_bloco_alunos — a alocação, do lado do bloco e do lado do aluno
-- -----------------------------------------------------------------------------
-- `security_invoker = on` sem exceção (card 2.3 §2.1, asserido por C5).
--
-- ⚠️ `bloco_ativo` é COLUNA e não filtro, e é a decisão que fecha o ajuste que o
--    card 5.6 deixou escrito para cá: *desativar um bloco NÃO desaloca ninguém*
--    — os alunos seguem com `bloco_aluno.ativo = true` apontando para um bloco
--    fora da grade, e `rt_pendencias_diaria` contava alocação ativa sem olhar se
--    o bloco estava ativo, de modo que nem `ALUNO_SEM_TURMA` acusava. Uma turma
--    inteira sumia do horário e o sistema não dizia nada.
--
--    Filtrar `b.ativo` aqui dentro resolveria a pendência e criaria outra: a
--    alocação órfã ficaria INVISÍVEL para a ficha do aluno, que é a única tela
--    de onde alguém a desfaria — o aluno apareceria com ⚠ "sem turma" e a aba
--    Turmas mostraria vazio, sem nada a remover. Com a coluna, cada consumidor
--    decide: a pendência e o ⚠ olham `bloco_ativo`, a ficha mostra tudo e marca
--    o que está fora da grade.
--
-- ⚠️ Os dois `join` são INTERNOS e cada um tem consequência própria quando falta
--    permissão, as duas viradas em asserção no teste 043: sem `turmas.ler` a
--    view vem VAZIA (RLS de `bloco_horario`/`bloco_aluno`) e sem `alunos.ler`
--    também — e vazia aqui não é "o bloco está vazio", é "não deu para ver".
--    É por isso que `fn_bloco_alunos` exige as duas explicitamente em vez de
--    devolver zero linhas, e é por isso que a coluna Turmas da lista de alunos
--    só é renderizada para quem tem `turmas.ler` (card 2.6 decisão 1).
--
-- Nenhum `join` em `metodo`, `sala` ou `professor`, ao contrário de
-- `v_bloco_vagas_semana`: a view devolve os ids e quem resolve o nome é o
-- catálogo que a tela já carregou (a decisão (f) do card 4.6). Cada `join`
-- interno a mais é mais um modo de vir vazia por permissão que a tela não pede.
create view public.v_bloco_alunos with (security_invoker = on) as
select ba.unidade_id,
       ba.id                  as alocacao_id,
       ba.bloco_id,
       b.dia_semana,
       b.hora_inicio,
       b.metodo_id,
       b.sala_id,
       b.ativo                as bloco_ativo,
       ba.aluno_id,
       a.nome                 as aluno_nome,
       a.codigo_sgf,
       a.status               as aluno_status,
       ba.tipo,
       ba.tipo_desde,
       ba.data_inicio_prevista
  from public.bloco_aluno ba
  join public.bloco_horario b on b.id = ba.bloco_id
  join public.aluno         a on a.id = ba.aluno_id
 where ba.ativo;

comment on view public.v_bloco_alunos is
  'Alocações ATIVAS, com o bloco e o aluno resolvidos (card 5.7). Metade permanente da lotação: a reposição pontual, que vale só no dia, entra por fn_bloco_alunos. bloco_ativo é coluna e não filtro — a pendência e o ⚠ da lista olham para ela, a ficha do aluno mostra também a alocação em bloco desativado, que é a única de onde alguém a desfaz.';

revoke all   on public.v_bloco_alunos from public;
revoke all   on public.v_bloco_alunos from anon;
grant select on public.v_bloco_alunos to authenticated;

-- -----------------------------------------------------------------------------
-- 2. fn_bloco_alunos — a lotação de um bloco NUMA DATA
-- -----------------------------------------------------------------------------
-- É a lista do wireframe §7.2, e ela tem de somar exatamente o que a célula da
-- grade mostra: `count(*) = fn_ocupacao_bloco(bloco, data)`. Uma lista com nove
-- linhas embaixo de um cabeçalho que diz 10/10 é o tipo de divergência que
-- ninguém reporta como defeito — reporta como "o sistema está estranho". O
-- teste 043 assere a igualdade nos dois estados da fixture.
--
-- `security invoker` (o default), pela razão do card 5.6 (a): esta função
-- devolve LINHAS, que devem depender do que o leitor enxerga, e não um número
-- derivado como as três do card 5.2. Como `definer`, ela entregaria a turma
-- inteira a quem a RLS acabou de negar.
--
-- ⚠️ ...e é justamente por ser `invoker` que as duas exigências explícitas
--    existem. Sem `turmas.ler` ou sem `alunos.ler` a RLS não levanta erro: ela
--    NEGA LINHA (card 2.3 §3.4), e o painel abriria dizendo que a turma de dez
--    alunos está vazia. É a mesma decisão, com a mesma justificativa escrita,
--    que `fn_rep_situacao` tomou no card 5.3 — erro alto no lugar de resposta
--    plausível. As duas permissões são dos quatro perfis na matriz inicial
--    (card 2.4), então isto não fecha porta de ninguém hoje; fecha a porta que
--    um perfil enxuto criado na tela do card 4.7 abriria amanhã.
--
-- ⚠️ A reposição traz o BLOCO DE ORIGEM da falta — apontamento #3 do §17 do card
--    2.6, que este card fecha. Sem `bloco_origem_dia`/`bloco_origem_hora` o
--    rótulo "reposição de Qua 27/08" do wireframe não teria de onde sair, e a
--    linha diria só "reposição", que é a informação que já se vê pela marca.
--    `left join` no bloco de origem porque `bloco_origem_id` é nulo de propósito
--    (card 2.5 §3.1): a escola nem sempre sabe qual encontro foi perdido.
create or replace function public.fn_bloco_alunos(
  p_bloco_id uuid,
  p_data     date default public.fn_hoje()
)
returns table (
  origem               text,
  registro_id          uuid,
  aluno_id             uuid,
  aluno_nome           text,
  codigo_sgf           text,
  aluno_status         text,
  tipo                 text,
  tipo_desde           date,
  data_inicio_prevista date,
  bloco_ativo          boolean,
  data                 date,
  bloco_origem_id      uuid,
  bloco_origem_dia     smallint,
  bloco_origem_hora    time,
  data_origem          date,
  observacao           text
)
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  perform public.fn_exige_permissao('turmas.ler');
  perform public.fn_exige_permissao('alunos.ler');

  return query
    select 'ALOCACAO'::text,
           t.alocacao_id,
           t.aluno_id,
           t.aluno_nome,
           t.codigo_sgf,
           t.aluno_status,
           t.tipo,
           t.tipo_desde,
           t.data_inicio_prevista,
           t.bloco_ativo,
           null::date,
           null::uuid,
           null::smallint,
           null::time,
           null::date,
           null::text
      from public.v_bloco_alunos t
     where t.bloco_id = p_bloco_id
    union all
    select 'REPOSICAO'::text,
           br.id,
           br.aluno_id,
           a.nome,
           a.codigo_sgf,
           a.status,
           'REP'::text,
           null::date,
           null::date,
           b.ativo,
           br.data,
           br.bloco_origem_id,
           o.dia_semana,
           o.hora_inicio,
           br.data_origem,
           br.observacao
      from public.bloco_aluno_reposicao br
      join public.aluno         a on a.id = br.aluno_id
      join public.bloco_horario b on b.id = br.bloco_id
      left join public.bloco_horario o on o.id = br.bloco_origem_id
     where br.bloco_id = p_bloco_id
       and br.data     = p_data
       and br.status   = 'PREVISTA'
     order by 1, 4, 3;
end $$;

comment on function public.fn_bloco_alunos(uuid, date) is
  'A lotação do bloco NAQUELA data (card 5.7, wireframe §7.2): as alocações ativas de v_bloco_alunos mais as reposições PREVISTAS do dia, cada linha marcada em origem. A contagem é a mesma de fn_ocupacao_bloco(bloco, data) — a lista e o cabeçalho da célula não podem discordar. security invoker, com turmas.ler e alunos.ler exigidos explicitamente: sem elas a RLS devolveria uma turma cheia como vazia, sem erro.';

revoke execute on function public.fn_bloco_alunos(uuid, date) from public;
revoke execute on function public.fn_bloco_alunos(uuid, date) from anon;
grant  execute on function public.fn_bloco_alunos(uuid, date) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. rt_pendencias_diaria — "em turma" passa a significar "em turma que existe"
-- -----------------------------------------------------------------------------
-- Substituição de `create or replace`; a base é o corpo que o card **5.4**
-- deixou — DUAS seções, sem `BLOCO_ACIMA_CAPACIDADE`, que voltou ao dono do
-- catálogo §10.1 (`fn_revalidar_blocos_sala`, chamada todo dia por
-- `rt_capacidades`). O que muda são as duas contagens de alocação, que passam a
-- ler `v_bloco_alunos` com `bloco_ativo`:
--
--   (1) ALUNO_SEM_TURMA — fecha o ajuste que o card 5.6 registrou. Um bloco
--       desativado tira a turma da grade e deixa as alocações de pé; até aqui a
--       rotina contava essas alocações e concluía que o aluno tinha turma. O
--       sintoma era o pior possível: **nada**. Nenhuma pendência, nenhum ⚠, e a
--       turma inteira fora do horário.
--
--   (2) ACELERAR_SEM_2O_BLOCO — pela mesma razão e no mesmo movimento: dois
--       blocos por semana é aceleração, e um bloco desativado não é aula. Sem a
--       correção aqui, desativar um dos dois blocos de um aluno ACELERAR o
--       deixaria com um só e sem aviso nenhum.
--
-- POR QUE A VIEW E NÃO A MESMA CONSULTA COM `and b.ativo`: seria a segunda cópia
-- da mesma comparação, exatamente o que o card 5.4 (4) recusou ao devolver
-- `BLOCO_ACIMA_CAPACIDADE` a um dono só — o ⚠ da lista de alunos é o MESMO fato
-- desta pendência, e as duas leituras precisam sair da mesma definição. Com a
-- view, quem mudar "o que conta como turma" muda num lugar e os dois caminhos
-- acompanham.
--
-- ⚠️ A função é `security definer` e a view é `security_invoker`: dentro dela o
--    invoker é o DONO, `postgres`, que tem BYPASSRLS (card 3.3), então a view
--    aqui enxerga todas as unidades. Não há vazamento porque as duas consultas
--    correlacionam por `t.aluno_id = a.id` e `a` já está limitado a
--    `v_unidade` — mas está escrito, porque é o mesmo mecanismo que o card 5.4
--    mediu e é fácil de esquecer na próxima consulta que alguém acrescentar
--    aqui.
--
-- ⚠️ PORTÃO DO CARD 7.1, no teste 090: `turma_modular_aluno` ainda não existe,
--    então "sem turma" hoje continua sendo "sem alocação em bloco ativo".
--
-- ⚠️ LIÇÃO DE MÉTODO, e ela custou uma rodada de CI: a primeira versão deste
--    arquivo copiou o corpo do card **5.5** em vez do do **5.4**, e com isso
--    reintroduziu a seção de `BLOCO_ACIMA_CAPACIDADE` que o 5.4 tinha removido —
--    um `create or replace` desfaz uma decisão sem que nada no diff pareça
--    errado, porque o texto reintroduzido É código legítimo, só de outra época.
--    Quem pegou foi a asserção que o próprio card 5.4 escreveu no teste 090
--    ("rt_pendencias_diaria NÃO abre mais BLOCO_ACIMA_CAPACIDADE"), e o registro
--    fica: **substituir função inteira exige partir da ÚLTIMA definição
--    aplicada, não da que criou a função** — é a mesma família do defeito que o
--    portão do card 4.0,5 teve em 02/09/2026, e a razão de a asserção existir.
create or replace function public.rt_pendencias_diaria()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_chaves  text[];
  r         record;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'rt_pendencias_diaria: sem unidade no contexto. Chamar de rt_diaria, ou entrar no contexto de rotina antes (card 2.2 §2.2).';
  end if;

  -- ---------------------------------------------------------------------------
  -- ALUNO_SEM_TURMA (ALTA) — ATIVO/ACELERAR sem bloco nem turma modular
  -- ---------------------------------------------------------------------------
  -- Alocação de tipo REP CONTA aqui, ao contrário do que acontece na aceleração:
  -- o aluno está num bloco de verdade, ocupando vaga de verdade (card 2.5 §7 #2).
  v_chaves := '{}';

  for r in select a.id,
                  format('%s (%s) está %s e não está em nenhuma turma.',
                         a.nome, coalesce(a.codigo_sgf, 'sem código SGF'), a.status)
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status in ('ATIVO', 'ACELERAR')
              and not exists (select 1
                                from public.v_bloco_alunos t
                               where t.aluno_id = a.id and t.bloco_ativo)
            order by a.nome, a.id
  loop
    v_chaves := v_chaves || ('ALUNO_SEM_TURMA:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'ALUNO_SEM_TURMA', 'ALUNO_SEM_TURMA:' || r.id::text, r.descricao,
      'ALTA', p_aluno_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('ALUNO_SEM_TURMA', v_chaves);

  -- ---------------------------------------------------------------------------
  -- ACELERAR_SEM_2O_BLOCO (BAIXA) — ajuste 4 do §8 do card 2.5
  -- ---------------------------------------------------------------------------
  -- ⚠️ `tipo <> 'REP'` é o ajuste, e ele muda o resultado: "dois blocos por
  --    semana = aceleração" é regra do plano, e uma alocação de REP contínuo é
  --    reposição, não aceleração. Sem o filtro, um aluno ACELERAR com um bloco
  --    normal e uma alocação REP contaria dois e a pendência NÃO abriria — o
  --    aluno ficaria sem o segundo bloco de verdade e ninguém saberia. A
  --    contraprova está no teste 090, montada exatamente nesse cenário.
  --
  -- Severidade BAIXA e não INFO: ajuste 4 do §10 do card 2.3 (o `check` do DDL
  -- não tem INFO). É informativa, e a severidade é o que a central usa para
  -- ordenar (v_pendencias_abertas.ordem_severidade).
  v_chaves := '{}';

  for r in select a.id,
                  format('%s (%s) está em ACELERAR com %s bloco(s) de aula por semana — a aceleração pressupõe dois.',
                         a.nome, coalesce(a.codigo_sgf, 'sem código SGF'),
                         (select count(*)
                            from public.v_bloco_alunos t
                           where t.aluno_id = a.id and t.bloco_ativo and t.tipo <> 'REP'))
                    as descricao
             from public.aluno a
            where a.unidade_id = v_unidade
              and a.status = 'ACELERAR'
              and (select count(*)
                     from public.v_bloco_alunos t
                    where t.aluno_id = a.id and t.bloco_ativo and t.tipo <> 'REP') < 2
            order by a.nome, a.id
  loop
    v_chaves := v_chaves || ('ACELERAR:' || r.id::text);
    perform public.fn_pendencia_abrir(
      'ACELERAR_SEM_2O_BLOCO', 'ACELERAR:' || r.id::text, r.descricao,
      'BAIXA', p_aluno_id => r.id);
  end loop;

  perform public.fn_pendencias_fechar_ausentes('ACELERAR_SEM_2O_BLOCO', v_chaves);

  -- ---------------------------------------------------------------------------
  -- BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4, e continua fora
  -- ---------------------------------------------------------------------------
  -- O dono é fn_revalidar_blocos_sala, como o catálogo §10.1 sempre disse, e
  -- quem a chama todo dia é rt_capacidades — que rt_diaria executa ANTES desta
  -- rotina. Manter a cópia aqui seria manter duas implementações da mesma
  -- comparação, livres para divergir na primeira vez que alguém mexer numa só.
end $$;

comment on function public.rt_pendencias_diaria() is
  'Abre E fecha, na unidade do contexto corrente, ALUNO_SEM_TURMA e ACELERAR_SEM_2O_BLOCO (contando só blocos de tipo <> REP). BLOCO_ACIMA_CAPACIDADE saiu daqui no card 5.4 e é de fn_revalidar_blocos_sala. Desde o card 5.7 as duas contagens leem v_bloco_alunos com bloco_ativo: alocação em bloco desativado não é turma, e antes disso desativar um bloco tirava a turma da grade sem abrir pendência nenhuma.';

revoke execute on function public.rt_pendencias_diaria() from public;
revoke execute on function public.rt_pendencias_diaria() from anon;
revoke execute on function public.rt_pendencias_diaria() from authenticated;
