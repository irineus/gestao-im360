-- =============================================================================
-- v_projecao_acuracia — o instrumento da recalibração, antes dos três meses
-- (card 11.1,5, 24/09/2026)
--
-- Fonte: docs/projecao-demanda.md §9.2 (critério) e §9.3 (a view), escrita para
-- o card 11.2. O 11.2 tem duas metades: construir a view e recalibrar com ela
-- depois de três meses de uso. Só a segunda depende de uso real — construída
-- agora, os três meses passam a ser LIDOS desde o primeiro, em vez de a view
-- ser descoberta com defeito no dia da recalibração.
--
-- Duas divergências do texto do §9.3, as duas de CORREÇÃO (registradas lá):
--
-- 1. O previsto é UMA linha por (unidade, material, mês), com as regras numa
--    lista. O §9.3 agrupava também por `regra`, e `regra` faz parte da unique
--    de `demanda_projetada_hist`: material previsto por duas regras no mesmo
--    mês viraria duas linhas de previsto, e o `full join` casaria o realizado
--    com AS DUAS — a mesma entrega contada duas vezes no Σ realizado, que é o
--    denominador do viés do §9.2(b). Coberto pelo `098`.
--
-- 2. Só entram MESES MEDIDOS: aqueles para os quais existe a foto do mês
--    anterior na unidade. Sem isso, toda entrega de antes da primeira foto — a
--    começar pelo histórico que o importador traz na virada — apareceria como
--    "entregue sem previsão", e o viés do §9.2(b) sairia perto de −100% sem
--    ninguém ter previsto nada errado. Limite assumido: foto tirada com a
--    projeção VAZIA (nenhuma linha) não marca o mês como medido.
--
-- Leitura (§10): `estoque.ler` + `alunos.ler`. Sem `estoque.ler` a view vem
-- VAZIA (não há mês medido); sem `alunos.ler` o realizado some e o previsto
-- aparece inteiro como sobra — é o número menor com cara de certo que o §10
-- descreve, e por isso a permissão é declarada.
--
-- ⚠️ Nenhuma linha de dado. Nada passa a rodar sozinho: é uma view.
-- =============================================================================

create view public.v_projecao_acuracia with (security_invoker = on) as
with medidos as (
  -- O mês M é medido quando a foto de M − 1 existe (a foto é tirada no dia 1).
  select distinct h.unidade_id, (h.snapshot_em + interval '1 month')::date as mes
    from public.demanda_projetada_hist h
),
previsto as (
  select h.unidade_id, h.material_id, h.mes,
         array_agg(distinct h.regra order by h.regra) as regras,
         sum(h.quantidade)::integer as qtd_projetada
    from public.demanda_projetada_hist h
   where h.snapshot_em = (h.mes - interval '1 month')::date   -- a foto de um mês antes
   group by h.unidade_id, h.material_id, h.mes
),
realizado as (
  select am.unidade_id,
         am.material_id,
         date_trunc('month', am.data_entrega)::date as mes,
         count(*)::integer as qtd_realizada
    from public.aluno_material am
   where am.entregue and am.data_entrega is not null
   group by am.unidade_id, am.material_id, date_trunc('month', am.data_entrega)::date
)
select coalesce(p.unidade_id, r.unidade_id)   as unidade_id,
       coalesce(p.material_id, r.material_id) as material_id,
       coalesce(p.mes, r.mes)                 as mes,
       p.regras,
       coalesce(p.qtd_projetada, 0)           as qtd_projetada,
       coalesce(r.qtd_realizada, 0)           as qtd_realizada,
       coalesce(p.qtd_projetada, 0) - coalesce(r.qtd_realizada, 0) as erro
  from previsto p
  full join realizado r
    on r.unidade_id = p.unidade_id and r.material_id = p.material_id and r.mes = p.mes
  join medidos md
    on md.unidade_id = coalesce(p.unidade_id, r.unidade_id)
   and md.mes = coalesce(p.mes, r.mes)
 where coalesce(p.mes, r.mes) < date_trunc('month', public.fn_hoje())::date;   -- só mês fechado

comment on view public.v_projecao_acuracia is
  'Previsto (foto de um mês antes, demanda_projetada_hist) × realizado (entregas de aluno_material), por unidade, material e mês fechado e medido — docs/projecao-demanda.md §9.3, card 11.1,5. Full join: o entregue sem previsão (qtd_projetada = 0) é o lado do erro que falta material. Insumo do viés do §9.2(b), card 11.2. Leitura: estoque.ler + alunos.ler.';

revoke all   on public.v_projecao_acuracia from public;
revoke all   on public.v_projecao_acuracia from anon;
grant select on public.v_projecao_acuracia to authenticated;
