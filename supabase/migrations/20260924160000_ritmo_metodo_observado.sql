-- =============================================================================
-- fn_ritmo_metodo_observado — o ritmo observado de um MÉTODO (card 9.2,69)
--
-- É a parte (a) do card 9.5 — a única de código —, feita antes do dry-run para
-- sair do caminho crítico da virada. As partes (b) rodar sobre o histórico
-- migrado em homolog e (c) gravar o resultado em `ritmo_padrao_dias_<METODO>`
-- pela tela de Parâmetros continuam no 9.5, e dependem do 9.4.
--
-- Especificação: docs/projecao-demanda.md §9.1. O que muda em relação ao texto
-- de lá, e por quê:
--
--   • SEM default embutido nos parâmetros (`fn_param_int(chave)` e não
--     `fn_param_int(chave, 7)`): as três chaves existem por configuração em toda
--     unidade (card 3.6), e um default no código esconderia justamente o
--     PARAMETRO_AUSENTE que deve aparecer (precedente do card 8.4);
--   • plpgsql, e não sql, para exigir `parametros.ler` — a calibração é feita
--     na tela de Parâmetros, e o número agrega entregas de todos os alunos do
--     método, que a função lê como definer (sem a RLS de quem chama);
--   • a mediana é ARREDONDADA para inteiro (`round`), e não truncada pelo cast:
--     com número par de intervalos a mediana pode ser x,5.
--
-- O resto é o do §9.1:
--   • MEDIANA, não média — a distribuição dos intervalos tem cauda longa à
--     direita (paradas, férias, atrasos), e a média compraria tarde demais;
--   • os mesmos filtros do ritmo individual (`v_ritmo_aluno`): intervalo entre
--     entregas consecutivas do mesmo aluno, entre ritmo_intervalo_min_dias e
--     ritmo_intervalo_max_dias;
--   • janela de `p_dias` (ou ritmo_calibracao_dias) contada da entrega mais
--     recente do par para trás, a partir de fn_hoje();
--   • devolve também QUANTOS intervalos entraram, para o 9.5 aplicar o gate de
--     ≥ 30 do §9.2;
--   • método SEM entrega datada (Inglês e Modular, TRILHA_SEM_DATA do 9.2)
--     devolve ritmo NULO e 0 intervalos — "sem base", nunca zero, que seria um
--     ritmo instantâneo.
-- =============================================================================

create function public.fn_ritmo_metodo_observado(p_metodo_id uuid,
                                                 p_dias integer default null)
returns table (ritmo_mediana integer, intervalos integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid := public.fn_unidade_atual();
  v_min     integer;
  v_max     integer;
  v_janela  integer;
begin
  perform public.fn_exige_permissao('parametros.ler');
  if v_unidade is null then
    raise exception using
      errcode = 'PT403',
      message = 'Você não tem permissão para executar esta ação.',
      detail  = json_build_object('codigo', 'SEM_PERMISSAO',
                                  'permissao', 'parametros.ler')::text;
  end if;

  v_min    := public.fn_param_int('ritmo_intervalo_min_dias');
  v_max    := public.fn_param_int('ritmo_intervalo_max_dias');
  v_janela := coalesce(p_dias, public.fn_param_int('ritmo_calibracao_dias'));

  return query
  with i as (
    select (am.data_entrega
            - lag(am.data_entrega) over (partition by am.aluno_id
                                             order by am.data_entrega, am.ordem)) as dias,
           am.data_entrega
      from public.aluno_material am
      join public.aluno a on a.id = am.aluno_id
     where am.entregue
       and am.data_entrega is not null
       and a.metodo_id = p_metodo_id
       -- O filtro de unidade no CORPO (C8): a função é definer e não passa pela
       -- RLS de quem chama.
       and am.unidade_id = v_unidade
       and a.unidade_id  = v_unidade
  )
  select round(percentile_cont(0.5) within group (order by i.dias))::integer,
         count(*)::integer
    from i
   where i.dias between v_min and v_max
     and i.data_entrega >= public.fn_hoje() - v_janela;
end $$;

comment on function public.fn_ritmo_metodo_observado(uuid, integer) is
  'Card 9.2,69 (parte (a) do 9.5; docs/projecao-demanda.md §9.1): MEDIANA dos intervalos entre entregas consecutivas dos alunos do método na unidade de quem chama, com os filtros do ritmo individual (ritmo_intervalo_min/max_dias) e a janela de p_dias ou ritmo_calibracao_dias. Devolve também quantos intervalos entraram (gate de ≥ 30 do §9.2). Sem entrega datada: ritmo NULO e 0 — sem base, nunca zero. Exige parametros.ler; sem default embutido nos parâmetros.';

revoke execute on function public.fn_ritmo_metodo_observado(uuid, integer) from public;
revoke execute on function public.fn_ritmo_metodo_observado(uuid, integer) from anon;
grant  execute on function public.fn_ritmo_metodo_observado(uuid, integer) to authenticated;
