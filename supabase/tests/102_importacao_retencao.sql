-- =============================================================================
-- Retenção do arquivo bruto das importações — rt_importacao_retencao (card 11.5,5)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Seis lotes escritos à mão (como dono, na transação), aplicados ao meio-dia
-- de São Paulo em dias contados de fn_hoje(), com o prazo de 30 dias:
--
--   A_31   Escola A, APLICADA há 31 dias      → limpa
--   A_30   Escola A, APLICADA há 30 dias      → limpa (o prazo é "30 ou mais")
--   A_29   Escola A, APLICADA há 29 dias      → fica
--   A_VAL  Escola A, VALIDADA de 90 dias      → fica (só APLICADA se limpa)
--   A_FAL  Escola A, FALHOU de 90 dias        → fica
--   A_FALC Escola A, FALHOU de 90 dias COM aplicado_em → fica. Hoje a falha não
--          carimba aplicado_em; o lote existe para o dia em que carimbar — sem
--          ele, tirar o filtro de status da rotina passava VERDE (contraprova
--          vista em 24/09/2026)
--   B_31   Escola B, APLICADA há 31 dias      → fica quando quem roda é a A
--
-- O caminho exercitado é o de verdade: a direção chama
-- fn_rotina_diaria_executar() na pele dela, que roda rt_diaria só da unidade
-- dela — o mesmo corpo do cron.
-- =============================================================================

begin;
select plan(15);

create temporary table t_lote (caso text primary key, id uuid);

create function pg_temp.lote(p_caso text, p_unidade text, p_status text, p_dias integer)
returns void language plpgsql as $$
declare v_id uuid;
begin
  insert into public.importacao (unidade_id, arquivo, snapshot_em, status, dados, totais, aplicado_em)
  values (tests.unidade(p_unidade), p_caso || '.json', public.fn_hoje() - p_dias, p_status,
          jsonb_build_object('aluno', jsonb_build_array(jsonb_build_object('codigo', '1', 'nome', 'Fulano'))),
          jsonb_build_object('aluno', jsonb_build_object('arquivo', 1, 'aplicadas', 1)),
          case when p_status = 'APLICADA' or p_caso = 'A_FALC'
               then ((public.fn_hoje() - p_dias)::timestamp + time '12:00') at time zone 'America/Sao_Paulo'
          end)
  returning id into v_id;
  insert into public.importacao_ocorrencia (unidade_id, importacao_id, severidade, entidade, codigo, mensagem)
  values (tests.unidade(p_unidade), v_id, 'AVISO', 'aluno', 'TESTE', 'ocorrência do lote ' || p_caso);
  insert into t_lote values (p_caso, v_id);
end $$;

select pg_temp.lote('A_31',  'ESCOLA_A', 'APLICADA', 31);
select pg_temp.lote('A_30',  'ESCOLA_A', 'APLICADA', 30);
select pg_temp.lote('A_29',  'ESCOLA_A', 'APLICADA', 29);
select pg_temp.lote('A_VAL', 'ESCOLA_A', 'VALIDADA', 90);
select pg_temp.lote('A_FAL', 'ESCOLA_A', 'FALHOU',   90);
select pg_temp.lote('A_FALC', 'ESCOLA_A', 'FALHOU',  90);
select pg_temp.lote('B_31',  'ESCOLA_B', 'APLICADA', 31);

create function pg_temp.limpos() returns text language sql stable as $$
  select coalesce(string_agg(t.caso, ',' order by t.caso), '')
    from t_lote t join public.importacao i on i.id = t.id
   where i.dados_limpos_em is not null
$$;

-- ===========================================================================
-- 1. O parâmetro existe, com o valor inicial, em toda unidade
-- ===========================================================================
select is(
  (select string_agg(distinct p.valor, ',') from public.parametro p
    where p.chave = 'importacao_retencao_dias'),
  '30', 'importacao_retencao_dias = 30 (valor inicial decidido em 24/09/2026)');
select is(
  (select count(*)::integer from public.unidade u
    where not exists (select 1 from public.parametro p
                       where p.unidade_id = u.id and p.chave = 'importacao_retencao_dias')),
  0, 'nenhuma unidade sem o parametro — nem as que existiam antes da migracao');

-- ===========================================================================
-- 2. A direção executa a rotina da unidade dela
-- ===========================================================================
select tests.autenticar(tests.uid('direcao@escola-a.test'));
select is(public.fn_rotina_diaria_executar(), 'EXECUTADA', 'direcao: EXECUTADA');
reset role;
select set_config('request.jwt.claims', null, true);

select is(pg_temp.limpos(), 'A_30,A_31',
  'limpos: so os APLICADOS da Escola A com 30 dias ou mais');

select is(
  (select i.dados from public.importacao i join t_lote t on t.id = i.id where t.caso = 'A_31'),
  '{}'::jsonb, 'o arquivo bruto sai: dados = {}');

select is(
  (select format('%s/%s/%s', i.status, i.totais -> 'aluno' ->> 'aplicadas', i.aplicado_em is not null)
     from public.importacao i join t_lote t on t.id = i.id where t.caso = 'A_31'),
  'APLICADA/1/t', 'o relatorio fica: status, totais e o carimbo da aplicacao');

select is(
  (select count(*)::integer from public.importacao_ocorrencia o join t_lote t on t.id = o.importacao_id
    where t.caso = 'A_31'),
  1, 'e as ocorrencias do lote continuam — e o que a auditoria precisa');

select is(
  (select i.dados -> 'aluno' -> 0 ->> 'nome' from public.importacao i join t_lote t on t.id = i.id
    where t.caso = 'A_VAL'),
  'Fulano', 'lote VALIDADA antigo guarda o arquivo: ainda pode ser conferido e aplicado');

select is(
  (select i.dados -> 'aluno' -> 0 ->> 'nome' from public.importacao i join t_lote t on t.id = i.id
    where t.caso = 'A_FALC'),
  'Fulano', 'lote FALHOU guarda o arquivo mesmo com aplicado_em: so APLICADA se limpa');

select is(
  (select i.dados -> 'aluno' -> 0 ->> 'nome' from public.importacao i join t_lote t on t.id = i.id
    where t.caso = 'B_31'),
  'Fulano', 'o lote da Escola B nao se mexe quando quem roda e a Escola A');

-- ===========================================================================
-- 3. Não limpa duas vezes
-- ===========================================================================
update public.importacao set dados_limpos_em = '2026-01-01 00:00:00+00'
 where id = (select id from t_lote where caso = 'A_31');
select tests.autenticar(tests.uid('direcao@escola-a.test'));
select is(public.fn_rotina_diaria_executar(), 'EXECUTADA', 'direcao: EXECUTADA de novo');
reset role;
select set_config('request.jwt.claims', null, true);
select is(
  (select i.dados_limpos_em from public.importacao i join t_lote t on t.id = i.id where t.caso = 'A_31'),
  '2026-01-01 00:00:00+00'::timestamptz, 'o lote ja limpo nao e carimbado de novo');

-- ===========================================================================
-- 4. Sem o parâmetro, nada se apaga — e a falha vira pendência
-- ===========================================================================
delete from public.parametro
 where unidade_id = tests.unidade('ESCOLA_B') and chave = 'importacao_retencao_dias';
select tests.autenticar(tests.uid('direcao@escola-b.test'));
select is(public.fn_rotina_diaria_executar(), 'EXECUTADA',
  'direcao da B: a rotina diaria segue — a retencao cai no bloco de excecao dela');
reset role;
select set_config('request.jwt.claims', null, true);
select is(
  (select i.dados_limpos_em is null from public.importacao i join t_lote t on t.id = i.id where t.caso = 'B_31'),
  true, 'sem importacao_retencao_dias o lote de 31 dias da B NAO e limpo: nao ha default embutido');
select is(
  (select count(*)::integer from public.pendencia p
    where p.unidade_id = tests.unidade('ESCOLA_B')
      and p.chave_dedup = 'ROTINA_FALHOU:rt_importacao_retencao' and p.resolvida_em is null),
  1, 'e a falha abre ROTINA_FALHOU:rt_importacao_retencao na Escola B');

select * from finish();
rollback;
