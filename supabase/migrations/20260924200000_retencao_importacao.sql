-- =============================================================================
-- Retenção do arquivo bruto das importações (card 11.5,5, 24/09/2026)
--
-- `importacao.dados` guarda o ARQUIVO INTEIRO de cada lote em jsonb — a escola
-- inteira, com nome e código de cada aluno, uma cópia por reimportação no
-- dry-run e mais uma na virada. Depois de APLICADO e conferido (o prazo é o
-- tempo de comparar com a planilha, card 9.4), o que a auditoria precisa é o
-- relatório: `totais`, as ocorrências e os carimbos — e eles FICAM. Sai só o
-- arquivo: `dados` vira '{}' e `dados_limpos_em` diz quando.
--
-- Escopo fechado com Irineu em 24/09/2026: SÓ esta limpeza. O resto do card
-- (demanda_projetada_hist, importacao_ocorrencia, pendência resolvida) espera
-- a medição do tamanho das tabelas em produção — card 11.5.
--
-- ⚠️ ESTA MIGRAÇÃO MUDA O QUE RODA SOZINHO. `rt_diaria` ganha um sexto passo,
--    `rt_importacao_retencao`, e o `cron.schedule('gi_rotina_diaria', …)` segue
--    o mesmo (03:10): a partir da primeira madrugada depois da promoção, todo
--    lote APLICADO há `importacao_retencao_dias` dias ou mais tem o arquivo
--    bruto APAGADO, sem volta. Em produção isso alcança o lote da virada (card
--    9.7) 30 dias depois dela.
--
-- O prazo mora em `parametro` (`importacao_retencao_dias`, valor inicial 30),
-- SEM default embutido na função (precedente do card 8.4): parâmetro ausente é
-- PARAMETRO_AUSENTE, a rotina cai no bloco de exceção de rt_diaria e vira
-- pendência ROTINA_FALHOU — nada se apaga por um default que ninguém escolheu.
-- Configuração, não dado de negócio: `parametro` está na lista do portão.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Quando o arquivo saiu
-- -----------------------------------------------------------------------------
alter table public.importacao add column dados_limpos_em timestamptz;
alter table public.importacao add constraint importacao_dados_limpos_ck
  check (dados_limpos_em is null or (status = 'APLICADA' and dados = '{}'::jsonb));

comment on column public.importacao.dados_limpos_em is
  'Card 11.5,5: quando rt_importacao_retencao limpou o arquivo bruto (dados = ''{}'') deste lote APLICADO, importacao_retencao_dias depois da aplicação. totais, ocorrências e carimbos continuam — é o que a auditoria precisa. NULL = o arquivo ainda está aqui.';

-- -----------------------------------------------------------------------------
-- 2. O parâmetro — para toda unidade que existe e para as que vierem
-- -----------------------------------------------------------------------------
create or replace function public.fn_seed_parametros(p_unidade_id uuid)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n integer;
begin
  insert into public.parametro (unidade_id, chave, valor, tipo, descricao)
  select p_unidade_id, p.chave, p.valor, 'INTEIRO', p.descricao
    from (values
      -- decisão de 31/08/2026 (card 2.1 §5)
      ('projecao_horizonte_dias',      '60',  'Horizonte da projeção de demanda, em dias'),
      ('standby_alerta_dias',          '30',  'Dias em STANDBY até gerar pendência'),
      -- card 2.5 (docs/regra-virada-rep.md §4)
      ('rep_prazo_dias',               '30',  'Prazo, em dias corridos da aula perdida, para repor sem virar REP contínuo'),
      ('rep_capacidade_semanal',       '1',   'Reposições por semana que o aluno consegue fazer além dos encontros regulares'),
      ('rep_faltas_max',               '2',   'Faltas a reposições agendadas, na janela do prazo, que sugerem a virada'),
      ('rep_janela_volta_dias',        '30',  'Carência sem débito e sem falta para sugerir a volta a REP pontual'),
      -- card de Ordem 5 (docs/projecao-demanda.md §3)
      ('ritmo_padrao_dias_INTERATIVO', '30',  'Dias por apostila no degrau MEDIA_METODO do método Interativo'),
      ('ritmo_padrao_dias_INGLES',     '30',  'Dias por apostila no degrau MEDIA_METODO do método Inglês'),
      ('ritmo_padrao_dias_MODULAR',    '45',  'Dias por módulo no Modular, quando a turma não tem cronograma'),
      ('ritmo_padrao_dias_PADRAO',     '30',  'Último recurso, quando falta a chave do método'),
      ('ritmo_janela_entregas',        '4',   'Entregas recentes que entram na média de ritmo do aluno (4 entregas = 3 intervalos)'),
      ('ritmo_intervalo_min_dias',     '7',   'Piso: intervalo menor que isto é entrega em lote, não ritmo'),
      ('ritmo_intervalo_max_dias',     '120', 'Teto: intervalo maior que isto é interrupção, não ritmo'),
      ('projecao_acelerar_pct',        '50',  'Percentual do ritmo do método aplicado ao aluno ACELERAR'),
      ('ritmo_calibracao_dias',        '180', 'Janela da mediana observada por método na recalibração'),
      -- card 11.5,5 (retenção do arquivo bruto das importações)
      ('importacao_retencao_dias',     '30',  'Dias depois de APLICADO em que o arquivo bruto do lote de importação é limpo (o relatório fica)')
    ) as p(chave, valor, descricao)
  on conflict (unidade_id, chave) do nothing;

  select count(*) into v_n from public.parametro where unidade_id = p_unidade_id;
  return v_n;
end $$;

comment on function public.fn_seed_parametros(uuid) is
  'Os 16 parâmetros lidos pelas regras já especificadas (cards 2.1, 2.5, Ordem 5 e 11.5,5). do nothing: valor ajustado na tela não volta ao default no deploy seguinte.';

revoke execute on function public.fn_seed_parametros(uuid) from public, anon, authenticated;

-- As unidades que já existem (em produção, a real). `do nothing` dentro da
-- função: nenhum valor ajustado volta ao default.
select public.fn_seed_parametros(u.id) from public.unidade u;

-- -----------------------------------------------------------------------------
-- 3. A rotina
-- -----------------------------------------------------------------------------
create function public.rt_importacao_retencao()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_dias    integer;
  v_n       integer;
begin
  v_unidade := public.fn_unidade_atual();

  if v_unidade is null then
    raise exception
      'rt_importacao_retencao: sem unidade no contexto. Chamar de rt_diaria, ou entrar no contexto de rotina antes (card 2.2 §2.2).';
  end if;

  -- Sem default: parâmetro ausente é PARAMETRO_AUSENTE (card 8.4).
  v_dias := public.fn_param_int('importacao_retencao_dias');
  if v_dias < 1 then
    raise exception
      'rt_importacao_retencao: importacao_retencao_dias = % — o prazo tem de ser de pelo menos 1 dia.', v_dias;
  end if;

  -- O dia da aplicação é o da escola (fn_hoje), não o de UTC.
  update public.importacao
     set dados = '{}'::jsonb,
         dados_limpos_em = now()
   where unidade_id = v_unidade
     and status = 'APLICADA'
     and dados_limpos_em is null
     and aplicado_em is not null
     and (aplicado_em at time zone 'America/Sao_Paulo')::date <= public.fn_hoje() - v_dias;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

comment on function public.rt_importacao_retencao() is
  'Card 11.5,5: na unidade do contexto de rotina, limpa o arquivo bruto (dados = ''{}'', dados_limpos_em = now()) dos lotes APLICADOS há importacao_retencao_dias dias ou mais. Só APLICADA: lote VALIDADA/REPROVADA/FALHOU guarda o arquivo (ainda pode ser conferido ou reenviado). Sem default no parâmetro. Devolve quantos lotes limpou. Chamada por rt_diaria.';

revoke execute on function public.rt_importacao_retencao() from public;
revoke execute on function public.rt_importacao_retencao() from anon;
revoke execute on function public.rt_importacao_retencao() from authenticated;

-- -----------------------------------------------------------------------------
-- 4. rt_diaria com o sexto passo (o resto é o do card 9.2,66, sem mudança)
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

    -- Card 11.5,5: a retenção do arquivo bruto das importações. Por último de
    -- propósito: não mexe em nada que as cinco de cima leem.
    begin
      perform public.rt_importacao_retencao();
      perform public.fn_pendencia_resolver('ROTINA_FALHOU:rt_importacao_retencao');
    exception when others then
      v_falhou := true;
      perform public.fn_pendencia_abrir(
        'ROTINA_FALHOU', 'ROTINA_FALHOU:rt_importacao_retencao',
        format('A rotina rt_importacao_retencao falhou: %s (SQLSTATE %s). O arquivo bruto das importações antigas desta unidade continua guardado — nada se perdeu, só não foi limpo.',
               sqlerrm, sqlstate),
        'MEDIA');
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
  'Rotina diária única (card 2.2 §11): itera as unidades ativas (ou só p_unidade, na execução sob demanda do card 9.2,65), entra no contexto de rotina em cada uma e chama, nesta ordem, rt_pcs_normaliza, rt_capacidades, rt_pendencias_diaria, rt_rep_avaliar, rt_projecao_demanda e rt_importacao_retencao (card 11.5,5) — cada uma isolada num bloco de exceção que registra a falha como pendência ROTINA_FALHOU (ALTA) e segue. Uma execução por unidade de cada vez (pg_try_advisory_xact_lock): a unidade já em execução noutra sessão é pulada, com NOTICE. Na execução completa (sem argumento), carimba rotina_execucao da unidade em que nada falhou (card 9.2,66).';
