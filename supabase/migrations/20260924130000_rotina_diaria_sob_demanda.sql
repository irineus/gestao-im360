-- =============================================================================
-- Card 9.2,65 — a rotina diária sob demanda, e a trava contra duas ao mesmo tempo
-- Fonte: nota do card 9.2,65 (medido em 24/09/2026), card 2.2 §11 (a rotina
--        única), 20260905150000_projecao_demanda.sql (a ÚLTIMA definição de
--        rt_diaria, de onde este corpo parte — o card 5.7 ensinou que
--        substituir função inteira a partir de outra versão apaga decisão).
--
-- Entrega: rt_diaria(p_unidade uuid default null) — o MESMO corpo, com dois
--          acréscimos (o filtro opcional de unidade e a trava) —, e
--          fn_rotina_diaria_executar(), a execução sob demanda da direção.
--          Nenhuma linha de dado. O job `gi_rotina_diaria` continua chamando
--          `select public.rt_diaria();`, que resolve para esta versão pelo
--          default do parâmetro.
--
-- =============================================================================
-- O PROBLEMA
-- =============================================================================
-- Depois de um `db reset` — e, no mundo real, depois de uma IMPORTAÇÃO no
-- dry-run do 9.4 e na virada do 9.7 — Compras diz "a projeção ainda não foi
-- calculada" e a central de pendências fica quase vazia até as 03:10 do dia
-- seguinte, quando `gi_rotina_diaria` roda. A direção importa a escola e só vê
-- projeção, pedido sugerido e pendências no dia seguinte.
--
-- =============================================================================
-- AS DECISÕES
-- =============================================================================
-- (a) A permissão é `parametros.gerir` (hoje só da direção) — decisão de Irineu
--     de 24/09/2026. NENHUM código novo: o catálogo fica em 50 (critério 1 do
--     marco 4.8).
-- (b) A execução sob demanda roda SÓ a unidade de quem chama. Rodar todas a
--     partir de uma direção seria atravessar unidade — a mesma regra de todo
--     `security definer` deste projeto (filtro de unidade no corpo, C8).
-- (c) A TRAVA é por unidade: `pg_try_advisory_xact_lock` com a chave
--     (hashtext('rt_diaria'), hashtext(unidade)). Sem ela, uma chamada manual
--     simultânea ao cron disputava o `delete`+`insert` de `demanda_projetada` e
--     o "if not exists … insert" do histórico mensal. `try` e não a espera:
--     quem chega em segundo recebe `JA_EM_EXECUCAO` na hora — status legível,
--     não erro, e não uma tela presa por minutos. O cron que encontra a
--     unidade travada a PULA (quem está rodando está fazendo o mesmo trabalho)
--     e diz isso com um NOTICE.
--     O advisory lock é reentrante na mesma sessão: a função sob demanda pega
--     a trava ANTES de chamar rt_diaria, e rt_diaria a pega de novo sem
--     esperar.
-- =============================================================================

drop function public.rt_diaria();

create function public.rt_diaria(p_unidade uuid default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  u record;
begin
  -- Sem argumento (o cron), todas as unidades ativas; com argumento (a execução
  -- sob demanda do card 9.2,65), só aquela.
  for u in select id from public.unidade
            where ativo and (p_unidade is null or id = p_unidade)
            order by id
  loop
    -- A trava do card 9.2,65: uma execução por unidade de cada vez.
    if not pg_try_advisory_xact_lock(hashtext('rt_diaria'), hashtext(u.id::text)) then
      raise notice 'rt_diaria: unidade % já está em execução noutra sessão — pulada.', u.id;
      continue;
    end if;

    -- `is_local => true`: o contexto morre no `commit` mesmo se a rotina falhar
    -- no meio, e não vaza de uma unidade para a seguinte (card 2.2 §2.2).
    perform set_config('app.rotina', 'on', true);
    perform set_config('app.rotina_unidade', u.id::text, true);

    begin
      perform public.rt_pcs_normaliza();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_pcs_normaliza');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_pcs_normaliza',
        format('A rotina rt_pcs_normaliza falhou: %s (SQLSTATE %s). O status dos PCs desta unidade pode estar desatualizado.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

    begin
      perform public.rt_capacidades();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_capacidades');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_capacidades',
        format('A rotina rt_capacidades falhou: %s (SQLSTATE %s). Os blocos acima da capacidade desta unidade podem não estar na central.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

    begin
      perform public.rt_pendencias_diaria();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_pendencias_diaria');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_pendencias_diaria',
        format('A rotina rt_pendencias_diaria falhou: %s (SQLSTATE %s). A lista de pendências desta unidade pode estar desatualizada.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

    begin
      perform public.rt_rep_avaliar();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_rep_avaliar');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_rep_avaliar',
        format('A rotina rt_rep_avaliar falhou: %s (SQLSTATE %s). As sugestões de virada REP desta unidade podem estar desatualizadas.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

    begin
      perform public.rt_projecao_demanda();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_projecao_demanda');
    exception when others then
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_projecao_demanda',
        format('A rotina rt_projecao_demanda falhou: %s (SQLSTATE %s). A projeção de demanda desta unidade está com os números da última execução bem-sucedida.',
               sqlerrm, sqlstate),
        'ALTA');
    end;
  end loop;

  perform set_config('app.rotina', '', true);
  perform set_config('app.rotina_unidade', '', true);
end $$;

comment on function public.rt_diaria(uuid) is
  'Rotina diária única (card 2.2 §11): itera as unidades ativas (ou só p_unidade, na execução sob demanda do card 9.2,65), entra no contexto de rotina em cada uma e chama, nesta ordem, rt_pcs_normaliza, rt_capacidades, rt_pendencias_diaria, rt_rep_avaliar e rt_projecao_demanda — cada uma isolada num bloco de exceção que registra a falha como pendência ROTINA_FALHOU (ALTA) e segue. Uma execução por unidade de cada vez (pg_try_advisory_xact_lock): a unidade já em execução noutra sessão é pulada, com NOTICE.';

revoke execute on function public.rt_diaria(uuid) from public;
revoke execute on function public.rt_diaria(uuid) from anon;
revoke execute on function public.rt_diaria(uuid) from authenticated;

-- -----------------------------------------------------------------------------
-- fn_rotina_diaria_executar — o botão "Recalcular agora"
-- -----------------------------------------------------------------------------
-- `security definer` porque chama rt_diaria, que ninguém além do postgres
-- executa. O filtro de unidade está no corpo (fn_unidade_atual()), como exige o
-- C8, e a permissão é conferida ANTES de qualquer coisa, com o token de quem
-- chama.
create function public.fn_rotina_diaria_executar()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid := public.fn_unidade_atual();
begin
  perform public.fn_exige_permissao('parametros.gerir');

  if v_unidade is null then
    raise exception using
      errcode = 'PT403',
      message = 'Você não tem permissão para executar esta ação.',
      detail  = json_build_object('codigo', 'SEM_PERMISSAO',
                                  'permissao', 'parametros.gerir')::text;
  end if;

  if not pg_try_advisory_xact_lock(hashtext('rt_diaria'), hashtext(v_unidade::text)) then
    return 'JA_EM_EXECUCAO';
  end if;

  perform public.rt_diaria(v_unidade);
  return 'EXECUTADA';
end $$;

comment on function public.fn_rotina_diaria_executar() is
  'Executa agora a rotina diária da unidade de quem chama (card 9.2,65) — o que o cron faz às 03:10. Exige parametros.gerir. Devolve EXECUTADA, ou JA_EM_EXECUCAO quando outra sessão (o cron ou outra pessoa) já está rodando a rotina desta unidade — status, não erro.';

revoke execute on function public.fn_rotina_diaria_executar() from public;
revoke execute on function public.fn_rotina_diaria_executar() from anon;
grant  execute on function public.fn_rotina_diaria_executar() to authenticated;
