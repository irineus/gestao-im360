-- =============================================================================
-- Vigiar a rotina diária — saber que o pg_cron rodou (card 9.2,66)
--
-- O ACHADO (varredura do banco, 24/09/2026): ninguém conferia que o job
-- `gi_rotina_diaria` existe ou rodou. `ROTINA_FALHOU` cobre a falha DENTRO da
-- rotina; não cobre a rotina que não roda — job apagado, extensão desligada,
-- migração que substituiu `rt_diaria` errado. O sintoma seria uma central de
-- pendências e uma projeção paradas no último dia bom, SEM ERRO NENHUM.
--
-- A DECISÃO (Irineu, 24/09/2026 — aprovada NESTE formato e só nele):
--   • `rt_diaria` grava o carimbo da última execução bem-sucedida numa linha
--     de configuração — aqui, `rotina_execucao`, uma linha por unidade;
--   • `fn_rotina_diaria_ultima_execucao()` devolve SÓ essa data ao `anon` —
--     nenhum dado de aluno, nenhum id, nenhum nome de unidade;
--   • o vigia (worker-vigia), que já consulta o banco como anon, reprova
--     quando ela passa de 36 h.
-- Qualquer coisa além da data volta a ser decisão.
--
-- Por que uma tabela própria, e não uma chave em `parametro`: a aba
-- Parâmetros da Administração lista e deixa editar TODA linha de `parametro`
-- da unidade. O carimbo apareceria ali como um parâmetro qualquer — e editável,
-- o que deixaria qualquer um "consertar" o vigia à mão.
--
-- O que conta como execução bem-sucedida, e por quê:
--   (a) só a execução COMPLETA — `rt_diaria()` sem argumento, que é a do cron.
--       A execução sob demanda da direção (card 9.2,65) não carimba: se
--       carimbasse, uma direção que clica todo dia esconderia um cron morto,
--       que é exatamente o que este card existe para achar;
--   (b) só a unidade em que as CINCO `rt_*` passaram. Uma unidade cuja rotina
--       falha todo dia fica com o carimbo envelhecendo, e o vigia avisa por
--       e-mail o que a pendência ROTINA_FALHOU só avisa a quem abre o app;
--   (c) a unidade pulada pela trava (outra execução em curso) não carimba —
--       quem carimba é a execução que de fato rodou.
--
-- A função devolve a data MAIS VELHA entre as unidades ativas, e NULL se
-- alguma unidade ativa nunca foi carimbada: o vigia pergunta "todas rodaram?",
-- e a resposta é a da pior.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. A linha de configuração
-- -----------------------------------------------------------------------------
create table public.rotina_execucao (
  id             uuid primary key default gen_random_uuid(),
  unidade_id     uuid not null references public.unidade(id),
  executada_em   timestamptz not null,
  criado_em      timestamptz not null default now(),
  criado_por     uuid,
  atualizado_em  timestamptz,
  atualizado_por uuid,
  constraint rotina_execucao_unidade_uk unique (unidade_id)
);

comment on table public.rotina_execucao is
  'Carimbo da última execução COMPLETA e bem-sucedida da rotina diária, por unidade (card 9.2,66). Só rt_diaria() escreve; o vigia lê a data mais velha por fn_rotina_diaria_ultima_execucao(). Não é parâmetro: a aba Parâmetros deixaria editar.';

create trigger tg_auditoria_rotina_execucao
  before insert or update on public.rotina_execucao
  for each row execute function public.fn_auditoria();

alter table public.rotina_execucao enable row level security;
alter table public.rotina_execucao force  row level security;

-- Leitura para quem já lê parâmetros da unidade — a mesma pergunta ("quando a
-- rotina rodou?") que a Administração pode vir a responder. Escrita: NENHUMA
-- política. Quem grava é `rt_diaria`, definer, cujo dono tem BYPASSRLS
-- (premissa do C8); sem política de insert/update ninguém de fora a imita.
create policy rotina_execucao_sel on public.rotina_execucao
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('parametros.ler'));

-- -----------------------------------------------------------------------------
-- 2. rt_diaria carimba — parte da definição do card 9.2,65
--    (20260924130000_rotina_diaria_sob_demanda.sql), a última aplicada.
-- -----------------------------------------------------------------------------
create or replace function public.rt_diaria(p_unidade uuid default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  u record;
  -- Card 9.2,66: alguma rt_* desta unidade caiu no bloco de exceção?
  v_falhou boolean;
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

    v_falhou := false;

    -- `is_local => true`: o contexto morre no `commit` mesmo se a rotina falhar
    -- no meio, e não vaza de uma unidade para a seguinte (card 2.2 §2.2).
    perform set_config('app.rotina', 'on', true);
    perform set_config('app.rotina_unidade', u.id::text, true);

    begin
      perform public.rt_pcs_normaliza();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_pcs_normaliza');
    exception when others then
      v_falhou := true;
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
      v_falhou := true;
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
      v_falhou := true;
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
      v_falhou := true;
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
      v_falhou := true;
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_projecao_demanda',
        format('A rotina rt_projecao_demanda falhou: %s (SQLSTATE %s). A projeção de demanda desta unidade está com os números da última execução bem-sucedida.',
               sqlerrm, sqlstate),
        'ALTA');
    end;

    -- Card 9.2,66: o carimbo que o vigia lê. Só a execução completa (a do
    -- cron) e só a unidade em que nada falhou — ver o cabeçalho da migração.
    if p_unidade is null and not v_falhou then
      insert into public.rotina_execucao (unidade_id, executada_em)
      values (u.id, now())
      on conflict (unidade_id) do update set executada_em = excluded.executada_em;
    end if;
  end loop;

  perform set_config('app.rotina', '', true);
  perform set_config('app.rotina_unidade', '', true);
end $$;

comment on function public.rt_diaria(uuid) is
  'Rotina diária única (card 2.2 §11): itera as unidades ativas (ou só p_unidade, na execução sob demanda do card 9.2,65), entra no contexto de rotina em cada uma e chama, nesta ordem, rt_pcs_normaliza, rt_capacidades, rt_pendencias_diaria, rt_rep_avaliar e rt_projecao_demanda — cada uma isolada num bloco de exceção que registra a falha como pendência ROTINA_FALHOU (ALTA) e segue. Uma execução por unidade de cada vez (pg_try_advisory_xact_lock): a unidade já em execução noutra sessão é pulada, com NOTICE. Na execução completa (sem argumento), carimba rotina_execucao da unidade em que nada falhou (card 9.2,66).';

-- -----------------------------------------------------------------------------
-- 3. A única coisa que o anon lê: uma data
-- -----------------------------------------------------------------------------
-- ⚠️ EXCEÇÃO NOMINAL a duas convenções, autorizada por Irineu em 24/09/2026:
--   • C9 (nenhuma função com execute para anon): o vigia só tem a chave
--     publicável. A função não recebe parâmetro e devolve um `timestamptz` —
--     nem linha, nem id, nem nome;
--   • filtro de unidade no corpo: o anon não tem unidade, e a pergunta é da
--     instalação ("todas as unidades rodaram?"). O agregado atravessa as
--     unidades de propósito e devolve só a data mais velha.
create function public.fn_rotina_diaria_ultima_execucao()
returns timestamptz
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- NULL quando alguma unidade ativa nunca foi carimbada: "nunca rodou" não
  -- pode se esconder atrás da data de outra unidade.
  select case when count(r.id) < count(*) then null
              else min(r.executada_em) end
    from public.unidade u
    left join public.rotina_execucao r on r.unidade_id = u.id
   where u.ativo
$$;

comment on function public.fn_rotina_diaria_ultima_execucao() is
  'Card 9.2,66: a data da última execução completa e bem-sucedida da rotina diária — a MAIS VELHA entre as unidades ativas; NULL se alguma nunca rodou. Única função aberta ao anon (exceção nominal ao C9, autorizada em 24/09/2026): é o que o worker-vigia consulta para reprovar acima de 36 h. Devolve só a data.';

revoke execute on function public.fn_rotina_diaria_ultima_execucao() from public;
revoke execute on function public.fn_rotina_diaria_ultima_execucao() from authenticated;
grant  execute on function public.fn_rotina_diaria_ultima_execucao() to anon;
