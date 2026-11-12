-- =============================================================================
-- O próximo livro do aluno Modular segue os MÓDULOS dele — card 9.2,886, item 1
-- (docs/turma-rodizio.md §10.8)
--
-- O defeito: a trilha de livros nasce na ordem do curso (livro 1, livro 2), e
-- o "próximo livro" era a menor `ordem` ainda não entregue. Em turma em rodízio
-- o aluno entra em qualquer módulo; quem entra num módulo do SEGUNDO livro
-- precisa dele primeiro — e o sistema apontava o primeiro. Quatro lugares liam
-- "próximo" assim, cada um escrevendo a regra de novo:
--
--   1. fn_trilha_proximo_material — o livro que a entrega sem material escolhido
--      entrega (fn_registrar_entrega);
--   2. v_aluno_trilha.proximo     — o "► próxima" da aba Trilha e o "Próximo
--      livro" do cabeçalho da ficha e da lista de alunos;
--   3. v_demanda_imediata_aluno   — a coluna DEMANDA (compra imediata);
--   4. v_projecao_aluno, `k`      — k = 1 é a demanda imediata e fica de fora.
--
-- A decisão (Irineu, 12/11/2026, recomendação (b) do card): NÃO reordenar a
-- trilha. Reordenar na admissão criaria uma segunda fonte da ordem, gravada,
-- que sai de sincronia no primeiro módulo perdido ou na primeira exceção à mão.
-- A ordem passa a ser DERIVADA, numa view só, e os quatro leem dela:
--
--   v_aluno_material_sequencia — os itens pendentes de cada aluno, numerados
--   (`seq`) pela primeira posição, na agenda do aluno (v_aluno_modular_agenda),
--   do módulo que usa aquele livro; e, empatado ou sem módulo (aluno sem turma
--   Modular, livro de outro curso do combo, métodos Interativo e Inglês), pela
--   `ordem` da trilha — exatamente a regra de antes.
--
-- Para quem não está em turma Modular NADA muda: a agenda dele é vazia e a
-- sequência é a `ordem`. O teste 109 mede os dois lados.
--
-- O que este arquivo NÃO muda: a reordenação por falta de estoque dentro de
-- fn_registrar_entrega (o substituto continua sendo escolhido pela `ordem`
-- entre os que têm saldo — no Modular de dois livros só há um outro) e a
-- `ordem` gravada, que continua sendo a da trilha.
--
-- Esta migração NÃO grava dado: uma view nova, uma função e três views
-- recriadas com as MESMAS colunas, na mesma ordem.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. A sequência efetiva — a regra, em UM lugar
-- -----------------------------------------------------------------------------
-- `security_invoker`: lê aluno_material (alunos.ler) e a agenda (turmas.ler).
-- Sem turmas.ler a agenda vem vazia e a sequência cai na `ordem` — o mesmo
-- "próximo" de antes deste card, e não um próximo errado.
create view public.v_aluno_material_sequencia with (security_invoker = on) as
with livro_modulo as (
  -- em que posição da agenda DO ALUNO a turma dá o primeiro módulo que usa
  -- cada livro (só os módulos que ainda lhe faltam)
  select ag.aluno_id,
         ag.material_id,
         min(ag.posicao) as posicao_modulo
    from public.v_aluno_modular_agenda ag
   group by ag.aluno_id, ag.material_id
)
select am.unidade_id,
       am.aluno_id,
       am.id                 as aluno_material_id,
       am.material_id,
       am.ordem,
       lm.posicao_modulo,
       (row_number() over (partition by am.aluno_id
                           order by lm.posicao_modulo nulls last, am.ordem,
                                    am.material_id))::integer as seq
  from public.aluno_material am
  left join livro_modulo lm on lm.aluno_id = am.aluno_id
                           and lm.material_id = am.material_id
 where not am.entregue;

comment on view public.v_aluno_material_sequencia is
  'A ordem EFETIVA dos livros que faltam a cada aluno (card 9.2,886): `seq` = 1 é o próximo livro. Para o aluno em turma Modular, pela primeira posição, na agenda dele, do módulo que usa o livro; empatado ou sem módulo, pela `ordem` da trilha — para quem não está em turma Modular é exatamente a regra antiga. É a ÚNICA definição de "próximo livro": fn_trilha_proximo_material, v_aluno_trilha.proximo, v_demanda_imediata_aluno e o `k` de v_projecao_aluno leem daqui. Só itens NÃO entregues. Derivada — nada aqui é guardado.';

comment on column public.v_aluno_material_sequencia.posicao_modulo is
  'Posição, na agenda do aluno, do primeiro módulo que usa este livro. NULO para quem não está em turma Modular, ou para livro que nenhum módulo que lhe falta usa.';

revoke all   on public.v_aluno_material_sequencia from public;
revoke all   on public.v_aluno_material_sequencia from anon;
grant select on public.v_aluno_material_sequencia to authenticated;

-- -----------------------------------------------------------------------------
-- 2. fn_trilha_proximo_material lê a sequência
-- -----------------------------------------------------------------------------
-- Continua `stable` e `invoker` (card 6.2): quem não pode ler a trilha de um
-- aluno não pode saber qual é o próximo livro dele. fn_trilha_atual é sinônimo
-- e muda junto, sem ser tocada.
create or replace function public.fn_trilha_proximo_material(p_aluno_id uuid)
returns uuid
language sql
stable
set search_path = public, pg_temp
as $$
  select s.material_id
    from public.v_aluno_material_sequencia s
   where s.aluno_id = p_aluno_id
     and s.seq = 1;
$$;

comment on function public.fn_trilha_proximo_material(uuid) is
  'Próximo livro da trilha: o primeiro da sequência EFETIVA (v_aluno_material_sequencia, card 9.2,886) — no aluno em turma Modular, o livro do próximo módulo que lhe falta; nos outros, a menor `ordem` ainda não entregue. NULO = trilha em FIM (ou aluno sem trilha). Derivado a cada consulta — o card 2.2 (e) proíbe a coluna que o guardaria.';

-- -----------------------------------------------------------------------------
-- 3. v_aluno_trilha — o "► próxima" lê a sequência
-- -----------------------------------------------------------------------------
-- A partir da única definição (20260904233000_view_aluno_trilha.sql), palavra
-- por palavra, com a coluna `proximo` trocada. Mesmas colunas, mesma ordem.
create or replace view public.v_aluno_trilha with (security_invoker = on) as
select am.unidade_id,
       am.aluno_id,
       am.id                                        as item_id,
       am.material_id,
       am.ordem,
       -- Posição na lista, 1..n. NÃO é `ordem`: `ordem` nasce de 10 em 10 (card
       -- 6.2 §5.1) para a inserção caber entre dois itens sem renumerar, então
       -- mostrá-la ao usuário exibiria "10, 20, 25, 30" na coluna `#`.
       row_number() over (partition by am.aluno_id order by am.ordem)::integer
                                                    as posicao,
       am.origem,
       am.entregue,
       am.data_entrega,
       am.movimento_estoque_id,
       m.metodo_id,
       m.codigo                                     as material_codigo,
       m.nome                                       as material_nome,
       m.categoria                                  as material_categoria,
       -- O "► próxima" da aba (wireframe §6.3). Card 9.2,886: é o primeiro da
       -- sequência EFETIVA (v_aluno_material_sequencia) — para o aluno em turma
       -- Modular, o livro do próximo módulo que lhe falta; para os outros, a
       -- menor `ordem` pendente, como sempre foi. Item entregue não está na
       -- sequência e sai `false` pelo coalesce.
       coalesce(sq.seq = 1, false)                  as proximo,
       public.fn_saldo_material(am.material_id)     as saldo
  from public.aluno_material am
  join public.material m on m.id = am.material_id
  left join public.v_aluno_material_sequencia sq on sq.aluno_material_id = am.id;

-- -----------------------------------------------------------------------------
-- 4. v_demanda_imediata_aluno — a demanda imediata lê a sequência
-- -----------------------------------------------------------------------------
-- A partir da única definição (20260904180000_views_estoque_demanda.sql), com o
-- `distinct on … order by ordem` trocado por `seq = 1`. Mesmas colunas.
create or replace view public.v_demanda_imediata_aluno with (security_invoker = on) as
select am.unidade_id,
       am.aluno_id,
       a.nome        as aluno_nome,
       a.codigo_sgf,
       a.status      as aluno_status,
       a.metodo_id,
       am.material_id,
       am.id         as aluno_material_id,
       am.ordem,
       (select count(*) from public.aluno_material p
         where p.aluno_id = am.aluno_id and not p.entregue)::integer as itens_pendentes
  from public.v_aluno_material_sequencia s
  join public.aluno_material am on am.id = s.aluno_material_id
  join public.aluno a on a.id = am.aluno_id
 where s.seq = 1
   and a.status in ('ATIVO','ACELERAR');

-- -----------------------------------------------------------------------------
-- 5. v_projecao_aluno — `k` é a sequência efetiva
-- -----------------------------------------------------------------------------
-- A partir da última definição (20261111180000_projecao_rodizio.sql), palavra
-- por palavra, com a CTE `pendente` lendo a sequência. Mesmas colunas.
create or replace view public.v_projecao_aluno with (security_invoker = on) as
with p as (
  select public.fn_hoje()                                    as hoje,
         public.fn_param_int('ritmo_padrao_dias_PADRAO', 30)  as ritmo_padrao,
         public.fn_param_int('projecao_acelerar_pct', 50)     as acelerar_pct,
         public.fn_param_int('ritmo_padrao_dias_MODULAR', 45) as passo_modular_padrao
),
-- itens pendentes dos alunos ativos, numerados: k = 1 é o próximo livro, que é
-- demanda IMEDIATA e não entra aqui. Card 9.2,886: `k` é a sequência EFETIVA
-- (v_aluno_material_sequencia) e não mais a `ordem` crua — a mesma que
-- v_demanda_imediata_aluno usa, ou a disjunção entre as duas se quebraria.
pendente as (
  select s.unidade_id,
         s.aluno_id,
         s.material_id,
         a.metodo_id,
         a.status,
         a.data_inicio,
         a.prev_conclusao_curso,
         s.seq                                                    as k,
         (count(*) over (partition by s.aluno_id))::integer       as pendentes
    from public.v_aluno_material_sequencia s
    join public.aluno a on a.id = s.aluno_id
   where a.status in ('ATIVO','ACELERAR')
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
