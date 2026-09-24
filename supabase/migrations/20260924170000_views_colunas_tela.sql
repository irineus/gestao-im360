-- =============================================================================
-- Views: o fuso de dias_aberta e as colunas que as telas 5 e 8 esperam
-- (card 9.2,7)
--
-- Quatro itens registrados e não feitos, numa migração só. Todas as views são
-- `create or replace` SEM mexer em nome, tipo ou posição das colunas que já
-- existem (precedente do card 8.2): as novas entram no FIM. Cada uma parte da
-- última definição aplicada.
--
--   (1) DEFEITO — v_pendencias_abertas.dias_aberta no fuso da escola;
--   (2) metodo_codigo / metodo_nome em v_projecao_material_mes (tela 8);
--   (3) data_inicio em v_turma_modular_lotacao (tela 5);
--   (4) modular_sem_cronograma em v_projecao_aluno_detalhe (drill-down da 8).
-- =============================================================================

create or replace view public.v_pendencias_abertas with (security_invoker = on) as
select p.unidade_id,
       p.id          as pendencia_id,
       p.tipo,
       p.severidade,
       (case p.severidade when 'ALTA' then 1 when 'MEDIA' then 2 else 3 end)::smallint
                     as ordem_severidade,
       p.descricao,
       p.chave_dedup,
       p.criado_em,
       -- Card 9.2,7: no fuso da ESCOLA. `criado_em::date` usa o da sessão
       -- (UTC no Supabase), e a pendência aberta entre 21h e meia-noite de São
       -- Paulo saía com −1 dia. O C6 procura só o texto current_date e não
       -- pegava. A forma é a de v_pedido_compra.data_referencia (card 6.8).
       (public.fn_hoje() - (p.criado_em at time zone 'America/Sao_Paulo')::date)::integer
                     as dias_aberta,
       p.aluno_id,    al.nome as aluno_nome, al.codigo_sgf, al.status as aluno_status,
       p.bloco_id,    bh.dia_semana, bh.hora_inicio, sl.nome as bloco_sala_nome,
       p.material_id, mt.codigo as material_codigo, mt.nome as material_nome,
       p.pc_id,       pcs.identificador as pc_identificador
  from public.pendencia p
  left join public.aluno         al  on al.id  = p.aluno_id
  left join public.bloco_horario bh  on bh.id  = p.bloco_id
  left join public.sala          sl  on sl.id  = bh.sala_id
  left join public.material      mt  on mt.id  = p.material_id
  left join public.pc            pcs on pcs.id = p.pc_id
 where p.resolvida_em is null;

create or replace view public.v_projecao_material_mes with (security_invoker = on) as
select dp.unidade_id,
       dp.material_id,
       m.metodo_id,
       m.codigo,
       m.nome,
       m.categoria,
       dp.mes,
       dp.quantidade,
       dp.regra,
       dp.calculado_em,
       -- Card 9.2,7 (item E1 do 9.2,5; wireframes §17 div. 70): o rótulo do
       -- método na própria linha. Sem ele a tela 8 dependia do catálogo em
       -- memória para dizer de que método é a linha — e, com o catálogo sem
       -- ler, a coluna inteira virava "não lido".
       me.codigo as metodo_codigo,
       me.nome   as metodo_nome
  from public.v_demanda_projetada dp
  join public.material m on m.id = dp.material_id
  join public.metodo  me on me.id = m.metodo_id;

create or replace view public.v_turma_modular_lotacao with (security_invoker = on) as
select t.unidade_id,
       t.id        as turma_id,
       t.nome      as turma_nome,
       t.curso_id,
       c.nome      as curso_nome,
       t.sala_id,
       s.nome      as sala_nome,
       t.capacidade,
       (select count(*) from public.turma_modular_aluno ta
         where ta.turma_id = t.id and ta.ativo)::integer as alocados,
       greatest(t.capacidade
                - (select count(*) from public.turma_modular_aluno ta
                    where ta.turma_id = t.id and ta.ativo), 0)::integer as vagas_livres,
       mc.modulo_id      as modulo_corrente_id,
       mo.nome           as modulo_corrente_nome,
       mo.ordem          as modulo_corrente_ordem,
       mc.data_inicio    as modulo_corrente_inicio,
       mc.prev_conclusao as modulo_corrente_prev_conclusao,
       (mc.prev_conclusao is not null and mc.prev_conclusao < public.fn_hoje()) as modulo_atrasado,
       -- Card 9.2,7 (wireframes §17 div. 41): o início da TURMA — dado que o
       -- importador traz e a projeção Modular lê — ficava invisível depois de
       -- criada a turma, e por isso não podia ser corrigido na tela 5.
       t.data_inicio
  from public.turma_modular t
  join public.curso c on c.id = t.curso_id
  join public.sala  s on s.id = t.sala_id
  left join lateral (
         select tm.modulo_id, tm.data_inicio, tm.prev_conclusao
           from public.turma_modular_modulo tm
           join public.modulo m2 on m2.id = tm.modulo_id
          where tm.turma_id = t.id and not tm.concluido
          order by m2.ordem
          limit 1
       ) mc on true
  left join public.modulo mo on mo.id = mc.modulo_id
 where t.ativo;

create or replace view public.v_projecao_aluno_detalhe with (security_invoker = on) as
select pa.unidade_id,
       pa.aluno_id,
       a.nome       as aluno_nome,
       a.codigo_sgf,
       a.status     as aluno_status,
       pa.material_id,
       m.metodo_id,
       m.codigo,
       m.nome       as material_nome,
       date_trunc('month', pa.data_prevista)::date as mes,
       pa.data_prevista,
       pa.regra,
       pa.ritmo_dias,
       pa.k,
       pa.pendentes,
       -- Card 9.2,7 (projecao-demanda §13 item 5): aluno do MODULAR projetado por
       -- outro degrau que não MODULAR — a turma dele não tem cronograma futuro
       -- datado (ou ele não tem turma), e a data saiu da previsão de curso ou da
       -- média do método. A pendência TURMA_MODULAR_SEM_CRONOGRAMA avisa por
       -- turma; esta coluna diz, no drill-down, QUAIS alunos estão nessa conta.
       (me.codigo = 'MODULAR' and pa.regra <> 'MODULAR') as modular_sem_cronograma
  from public.v_projecao_aluno pa
  join public.aluno a    on a.id = pa.aluno_id
  join public.material m on m.id = pa.material_id
  join public.metodo  me on me.id = m.metodo_id;
