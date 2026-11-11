-- =============================================================================
-- Card 9.2,89 — Turma em rodízio: a projeção MODULAR segue a sequência do aluno
--
-- Fonte: docs/turma-rodizio.md §6 e docs/projecao-demanda.md §5.4.
--
-- Até aqui a regra MODULAR dizia: o livro é necessário quando A TURMA entra no
-- primeiro módulo daquele livro. Em rodízio a turma dá a volta, e cada aluno
-- está numa altura diferente dela. A regra passa a dizer:
--
--   o livro é necessário quando a turma entra no PRIMEIRO MÓDULO, DOS QUE
--   FALTAM AO ALUNO, daquele livro.
--
-- É a "urgência" que o dono do produto pediu (06/11/2026): dois alunos da mesma
-- turma, o mesmo livro, meses diferentes — quem entrou em Massas e Molhos
-- precisa do livro Panificação na próxima troca; quem entrou em Garde Manger, só
-- quatro módulos depois.
--
-- Entregável:
--   1. `v_aluno_modular_agenda` — os módulos que faltam a cada aluno, cada um na
--      primeira vez em que a turma lho dará;
--   2. `v_projecao_aluno` com a CTE `modular` POR ALUNO, lida dessa view.
--   3. `fn_turma_modular_agenda` volta a ser `invoker` (seção 0) — correção do
--      card 9.2,88, achada pelos testes deste.
--
-- ⚠️ Fecha o aviso do card 9.2,88: a view lia `turma_modular_modulo` sem
--    conhecer `ciclo`, e a turma que já abrira o segundo ciclo tinha cada módulo
--    em duas linhas. Agora a view não lê o cronograma — lê a agenda, que é a
--    ÚNICA definição de quando a turma dará cada módulo (card 9.2,88 §5), e a
--    extrapolação (gaps-and-islands) deixa de existir aqui.
--
-- O que este arquivo NÃO faz:
--   • não muda a cascata nem os outros três degraus;
--   • não muda a disjunção `k >= 2` com a demanda imediata, nem a contagem por
--     item PENDENTE da trilha — quem já tem o livro continua não contando;
--   • não muda `rt_projecao_demanda` nem TURMA_MODULAR_SEM_CRONOGRAMA: turma sem
--     data nenhuma continua derrubando o aluno para MEDIA_METODO;
--   • não grava dado: a tabela `demanda_projetada` é regravada pela rotina.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. fn_turma_modular_agenda deixa de ser `security definer`
-- -----------------------------------------------------------------------------
-- ⚠️ ACHADO DESTE CARD, e é correção do card 9.2,88. A agenda nasceu `definer`
--    com o argumento de sempre — "decisão derivada lida sob RLS nega linha" —,
--    mas o corpo exigia `turmas.ler` e filtrava a unidade: exatamente o que a
--    RLS de `turma_modular` já faz para um `invoker`. O `definer` não comprava
--    NADA, e custava uma coisa: sem `auth.uid()` nem contexto de rotina a
--    função devolvia vazio. Foi assim que apareceu — o teste 080 lê
--    `v_projecao_aluno` como dono, sem contexto, e a aluna Modular caiu de
--    MODULAR para MEDIA_METODO sem erro nenhum. É a mesma família de falha
--    calada que o argumento do `definer` dizia evitar.
--
--    Como `invoker`, sem `turmas.ler` ou em turma de outra unidade a agenda
--    continua vindo VAZIA (teste 105 §1) — agora pela RLS, que é uma barreira a
--    menos para manter. Sai da lista fechada do C8 (teste 011).
--
-- O corpo é o do card 9.2,88, palavra por palavra, sem o bloco do contexto.
create or replace function public.fn_turma_modular_agenda(p_turma_id uuid)
returns table (
  posicao       integer,
  modulo_id     uuid,
  modulo_nome   text,
  modulo_ordem  integer,
  material_id   uuid,
  ciclo         integer,
  cronograma_id uuid,
  data_inicio   date,
  data_fim      date
)
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_curso   uuid;
  v_inicio_turma date;
  v_n       integer;
  v_i0      integer;   -- índice (1..N) do módulo corrente na ordem do catálogo
  v_c0      integer;   -- ciclo do módulo corrente
  v_passo   integer;
  v_ant_fim date;
  r         record;
  v_ini     date;
  v_fim     date;
begin
  -- Card 9.2,89: INVOKER. Quem recorta unidade e permissão é a RLS de
  -- turma_modular — sem turmas.ler, ou em turma de outra unidade, a linha não
  -- vem e a agenda sai vazia.
  select t.curso_id, t.data_inicio into v_curso, v_inicio_turma
    from public.turma_modular t
   where t.id = p_turma_id;
  if v_curso is null then
    return;
  end if;

  select count(*) into v_n from public.modulo m where m.curso_id = v_curso;

  -- o corrente: a MESMA ordem de fn_turma_modular_modulo_corrente
  select x.idx, x.ciclo into v_i0, v_c0
    from (select tm.ciclo, m.ordem, tm.modulo_id,
                 (select count(*) from public.modulo m2
                   where m2.curso_id = v_curso
                     and (m2.ordem, m2.id) <= (m.ordem, m.id))::integer as idx
            from public.turma_modular_modulo tm
            join public.modulo m on m.id = tm.modulo_id
           where tm.turma_id = p_turma_id and not tm.concluido
           order by tm.ciclo, m.ordem, tm.modulo_id
           limit 1) x;
  if v_i0 is null then
    return;
  end if;

  -- o passo: a duração média dos módulos datados da turma, em qualquer ciclo
  select round(avg(tm.prev_conclusao - tm.data_inicio + 1))::integer into v_passo
    from public.turma_modular_modulo tm
   where tm.turma_id = p_turma_id
     and tm.data_inicio is not null and tm.prev_conclusao is not null;
  if v_passo is null or v_passo < 1 then
    v_passo := public.fn_param_int('ritmo_padrao_dias_MODULAR', 45);
  end if;

  -- o fim do último módulo CONCLUÍDO: é de onde o corrente parte quando não
  -- tem início informado
  select tm.prev_conclusao into v_ant_fim
    from public.turma_modular_modulo tm
    join public.modulo m on m.id = tm.modulo_id
   where tm.turma_id = p_turma_id and tm.concluido and tm.prev_conclusao is not null
   order by tm.ciclo desc, m.ordem desc, tm.modulo_id desc
   limit 1;

  for r in
    select g.p as posicao, mo.id as modulo_id, mo.nome, mo.ordem, mo.material_id,
           (v_c0 + (v_i0 - 1 + g.p - 1) / v_n) as ciclo,
           tm.id as cronograma_id, tm.data_inicio, tm.prev_conclusao
      from generate_series(1, v_n + 1) g(p)
      join (select m.id, m.nome, m.ordem, m.material_id,
                   row_number() over (order by m.ordem, m.id)::integer as idx
              from public.modulo m where m.curso_id = v_curso) mo
        on mo.idx = ((v_i0 - 1 + g.p - 1) % v_n) + 1
      left join public.turma_modular_modulo tm
        on tm.turma_id = p_turma_id and tm.modulo_id = mo.id
       and tm.ciclo = v_c0 + (v_i0 - 1 + g.p - 1) / v_n
     order by g.p
  loop
    v_ini := coalesce(r.data_inicio,
                      v_ant_fim + 1,
                      -- a turma inteira sem data nenhuma não tem o que extrapolar
                      case when r.posicao = 1 and r.prev_conclusao is not null
                           then r.prev_conclusao - v_passo + 1 end);
    v_fim := coalesce(r.prev_conclusao, v_ini + v_passo - 1);
    v_ant_fim := v_fim;

    posicao       := r.posicao;
    modulo_id     := r.modulo_id;
    modulo_nome   := r.nome;
    modulo_ordem  := r.ordem;
    material_id   := r.material_id;
    ciclo         := r.ciclo;
    cronograma_id := r.cronograma_id;
    data_inicio   := v_ini;
    data_fim      := v_fim;
    return next;
  end loop;
end $$;

comment on function public.fn_turma_modular_agenda(uuid) is
  'A agenda da turma Modular em rodízio (card 9.2,88, docs/turma-rodizio.md §5.1): os próximos N + 1 módulos a partir do corrente (N = módulos do curso) — uma volta inteira mais o corrente outra vez, no ciclo seguinte, que é o último módulo de quem entrou para começar no próximo —, com início e fim planejados: a data informada; senão o fim do anterior + 1; senão a extrapolação pelo passo médio da turma (ou ritmo_padrao_dias_MODULAR). É a ÚNICA definição de quando a turma dará cada módulo. INVOKER desde o card 9.2,89: quem recorta unidade e permissão é a RLS de turma_modular, e sem turmas.ler a agenda vem vazia. Datas NULAS quando a turma não tem data nenhuma.';

-- -----------------------------------------------------------------------------
-- 1. v_aluno_modular_agenda — a sequência que FALTA ao aluno, com datas
-- -----------------------------------------------------------------------------
-- Uma linha por (alocação ativa em turma ativa, módulo que falta). Para cada
-- módulo, a PRIMEIRA posição da agenda em que a turma o dará ÀQUELE aluno: quem
-- entrou para começar no próximo módulo não conta a posição 1 — o corrente de
-- hoje só volta na outra volta (card 9.2,88, a posição N + 1).
--
-- A condição de "aguardando a entrada" é a MESMA de fn_turma_modular_avancar e
-- de v_aluno_modular_progresso; o teste 107 §4 compara as duas views aluno a
-- aluno, para que a terceira escrita não fique livre para divergir.
create view public.v_aluno_modular_agenda with (security_invoker = on) as
select ta.unidade_id,
       ta.id          as alocacao_id,
       ta.turma_id,
       ta.aluno_id,
       x.modulo_id,
       x.modulo_nome,
       x.modulo_ordem,
       x.material_id,
       x.posicao,
       x.ciclo,
       x.data_inicio,
       x.data_fim
  from public.turma_modular_aluno ta
  join public.turma_modular t on t.id = ta.turma_id
  cross join lateral (
         select (ta.modulo_entrada_id is not null
                 and ta.modulo_entrada_id is distinct from
                     public.fn_turma_modular_modulo_corrente(ta.turma_id)
                 and not exists (select 1
                                   from public.aluno_modulo am0
                                   join public.modulo m0 on m0.id = am0.modulo_id
                                  where am0.aluno_id = ta.aluno_id
                                    and m0.curso_id = t.curso_id)) as aguardando
       ) esp
  cross join lateral (
         select distinct on (ag.modulo_id)
                ag.modulo_id, ag.modulo_nome, ag.modulo_ordem, ag.material_id,
                ag.posicao, ag.ciclo, ag.data_inicio, ag.data_fim
           from public.fn_turma_modular_agenda(ta.turma_id) ag
          where not exists (select 1 from public.aluno_modulo am
                             where am.aluno_id = ta.aluno_id
                               and am.modulo_id = ag.modulo_id)
            and (ag.posicao > 1 or not esp.aguardando)
          order by ag.modulo_id, ag.posicao
       ) x
 where ta.ativo and t.ativo;

comment on view public.v_aluno_modular_agenda is
  'Os módulos que FALTAM a cada aluno de turma Modular em rodízio, cada um na PRIMEIRA vez em que a turma o dará a ele, com as datas planejadas (card 9.2,89, docs/turma-rodizio.md §6). Uma linha por alocação ativa × módulo que falta. Derivada de fn_turma_modular_agenda e de aluno_modulo — nada aqui é guardado. É de onde a regra MODULAR da projeção tira a data de cada livro, por aluno. Exige turmas.ler (a agenda) e alunos.ler ou turmas.editar (aluno_modulo).';

revoke all   on public.v_aluno_modular_agenda from public;
revoke all   on public.v_aluno_modular_agenda from anon;
grant select on public.v_aluno_modular_agenda to authenticated;

-- -----------------------------------------------------------------------------
-- 2. v_projecao_aluno — a CTE `modular` passa a ser POR ALUNO
-- -----------------------------------------------------------------------------
-- `create or replace` a partir da última definição aplicada (card 8.5,
-- 20260906010000_views_projecao_tela.sql), palavra por palavra, com três
-- mudanças: as cinco CTEs que extrapolavam o cronograma da turma dão lugar a
-- uma, que lê `v_aluno_modular_agenda`; e os dois pontos que casavam `modular`
-- por TURMA passam a casar por ALUNO. Mesmas colunas, na mesma ordem.
create or replace view public.v_projecao_aluno with (security_invoker = on) as
with p as (
  select public.fn_hoje()                                    as hoje,
         public.fn_param_int('ritmo_padrao_dias_PADRAO', 30)  as ritmo_padrao,
         public.fn_param_int('projecao_acelerar_pct', 50)     as acelerar_pct,
         public.fn_param_int('ritmo_padrao_dias_MODULAR', 45) as passo_modular_padrao
),
-- itens pendentes dos alunos ativos, numerados: k = 1 é o próximo livro, que é
-- demanda IMEDIATA e não entra aqui
pendente as (
  select am.unidade_id,
         am.aluno_id,
         am.material_id,
         a.metodo_id,
         a.status,
         a.data_inicio,
         a.prev_conclusao_curso,
         (row_number() over (partition by am.aluno_id order by am.ordem))::integer as k,
         (count(*)    over (partition by am.aluno_id))::integer                    as pendentes
    from public.aluno_material am
    join public.aluno a on a.id = am.aluno_id
   where not am.entregue
     and a.status in ('ATIVO','ACELERAR')
),
-- turma Modular ativa do aluno (o índice único do card 7.1 garante no máximo uma)
turma_aluno as (
  select tma.aluno_id, tma.turma_id
    from public.turma_modular_aluno tma
    join public.turma_modular tm on tm.id = tma.turma_id and tm.ativo
   where tma.ativo
),
-- Card 9.2,89: a data em que a turma entra no PRIMEIRO módulo, DOS QUE FALTAM
-- AO ALUNO, de cada material. Por aluno, e não mais por turma: em rodízio cada
-- aluno está numa altura diferente da volta. A extrapolação do cronograma, que
-- vivia aqui em cinco CTEs, é agora da agenda da turma (card 9.2,88) — a única
-- definição de quando a turma dará cada módulo.
modular as (
  select ag.aluno_id,
         ag.material_id,
         min(ag.data_inicio) as data_prevista
    from public.v_aluno_modular_agenda ag
   where ag.data_inicio is not null
   group by ag.aluno_id, ag.material_id
),
-- degrau escolhido, UMA vez por aluno (§2.2). O aluno Modular não usa
-- RITMO_ALUNO: no Modular a turma avança em conjunto, então a data em que ele
-- recebe o próximo livro é decidida pelo cronograma, não pela velocidade dele —
-- o histórico individual de um aluno modular mede o passado da TURMA.
aluno_regra as (
  select distinct
         pe.aluno_id,
         pe.metodo_id,
         me.codigo as metodo_codigo,
         pe.status,
         pe.data_inicio,
         pe.prev_conclusao_curso,
         ta.turma_id,
         ra.ritmo_dias,
         ra.ultima_entrega,
         case
           when me.codigo = 'MODULAR'
                and exists (select 1 from modular m where m.aluno_id = pe.aluno_id)
             then 'MODULAR'
           when me.codigo <> 'MODULAR' and ra.ritmo_dias is not null
             then 'RITMO_ALUNO'
           when pe.prev_conclusao_curso > p.hoje
             then 'PREVISAO_CURSO'
           else 'MEDIA_METODO'
         end as regra
    from pendente pe
    cross join p
    join public.metodo me on me.id = pe.metodo_id
    left join turma_aluno ta on ta.aluno_id = pe.aluno_id
    left join public.v_ritmo_aluno ra on ra.aluno_id = pe.aluno_id
),
-- ritmo efetivo dos degraus que trabalham com ritmo. O fator de aceleração vale
-- SÓ em MEDIA_METODO: em RITMO_ALUNO a aceleração já está medida (o aluno em
-- dois blocos entrega mais rápido, e a média mostra isso), em PREVISAO_CURSO a
-- data foi declarada por uma pessoa que sabe se o aluno acelerou, e em MODULAR
-- quem manda é a turma. Aplicá-lo nos quatro degraus contaria a aceleração duas
-- vezes.
ritmo_efetivo as (
  select ar.aluno_id,
         ar.regra,
         case ar.regra
           when 'RITMO_ALUNO' then ar.ritmo_dias
           when 'MEDIA_METODO' then
             case when ar.status = 'ACELERAR'
                  then greatest(round(public.fn_param_int('ritmo_padrao_dias_' || ar.metodo_codigo,
                                                          p.ritmo_padrao)
                                      * p.acelerar_pct / 100.0), 1)::integer
                  else public.fn_param_int('ritmo_padrao_dias_' || ar.metodo_codigo, p.ritmo_padrao)
             end
           else null
         end as ritmo,
         -- o `hoje − 400` contém data de entrega absurda vinda da migração; o
         -- limite que IMPORTA (`hoje − ritmo`) está aplicado na projeção, onde o
         -- ritmo já é conhecido. Sem ele, o aluno atrasado teria os próximos
         -- livros com data no passado, todos despejados no mês corrente — a
         -- projeção transformaria atraso em pico de compra.
         greatest(coalesce(ar.ultima_entrega, ar.data_inicio), p.hoje - 400) as ancora_bruta
    from aluno_regra ar
    cross join p
)
select pe.unidade_id,
       pe.aluno_id,
       pe.material_id,
       ar.regra,
       case ar.regra
         when 'MODULAR' then mo.data_prevista
         when 'PREVISAO_CURSO'
           then p.hoje + round(pe.k * (ar.prev_conclusao_curso - p.hoje)::numeric
                                    / pe.pendentes)::integer
         else greatest(re.ancora_bruta, p.hoje - re.ritmo) + pe.k * re.ritmo
       end as data_prevista,
       pe.k,
       pe.pendentes,
       -- A coluna nova do card 8.5. Sai da MESMA CTE que produziu a data acima.
       re.ritmo as ritmo_dias
  from pendente pe
  cross join p
  join aluno_regra   ar on ar.aluno_id = pe.aluno_id
  join ritmo_efetivo re on re.aluno_id = pe.aluno_id
  left join modular  mo on mo.aluno_id = pe.aluno_id and mo.material_id = pe.material_id
 where pe.k >= 2
   and (ar.regra <> 'MODULAR' or mo.data_prevista is not null);

comment on view public.v_projecao_aluno is
  'Detalhe da projeção: uma linha por aluno × material × data prevista × regra, a PARTIR do segundo item pendente da trilha (docs/projecao-demanda.md §6). É a mesma expressão que rt_projecao_demanda agrega para produzir o total — o drill-down da tela 8.5 lê daqui, e não de uma segunda implementação. Desde o card 9.2,89 o degrau MODULAR é POR ALUNO: o livro é necessário quando a turma em rodízio entra no primeiro módulo, dos que faltam àquele aluno, daquele livro (v_aluno_modular_agenda). Leitura exige alunos.ler, materiais.ler e turmas.ler: o join em metodo é INTERNO e obrigatório, então sem materiais.ler a projeção vem VAZIA, não errada.';

comment on column public.v_projecao_aluno.regra is
  'Degrau da cascata, escolhido UMA vez por aluno (nunca por item): MODULAR (o aluno está em turma com agenda datada — por aluno desde o card 9.2,89) → RITMO_ALUNO (método ≠ MODULAR e ritmo mensurável) → PREVISAO_CURSO (prev_conclusao_curso informada e FUTURA) → MEDIA_METODO (o degrau que não pode falhar). Previsão vencida não serve de base: passo negativo despejaria a trilha inteira no mês corrente.';
