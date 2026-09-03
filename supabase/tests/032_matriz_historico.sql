-- =============================================================================
-- Histórico da matriz de permissões — card 4.7.5
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- O card é de "Função/regra" (trigger), então o §13 cobra: caminho feliz com
-- EFEITO conferido, o teste de camada 2 (o caminho que contorna — aqui, o POST
-- direto na tabela de histórico e a cascata de FK) e o negativo de permissão
-- (quem não tem admin.ler lê zero linhas). Mais o que este card muda no seed do
-- 3.6: o caso residual "tirado de todos volta" deixa de existir.
--
-- Roda com begin/rollback. Os ids da fixture ficam numa tabela temporária,
-- porque depois de tests.autenticar() a sessão está em `authenticated` e não
-- alcança mais o schema tests (card 3.4.5) — e pg_temp continua acessível
-- depois de trocar de papel (verificado no card 3.4).
-- =============================================================================

begin;
select plan(19);

create temporary table t_ctx as
  select tests.uid('direcao@escola-a.test')  as direcao_a,
         tests.uid('monitor@escola-a.test')  as monitor_a,
         tests.uid('direcao@escola-b.test')  as direcao_b,
         tests.unidade('ESCOLA_A')           as unidade_a,
         tests.unidade('ESCOLA_B')           as unidade_b;

-- ===========================================================================
-- 1. O seed também deixa rastro — e o rastro é distinguível do de uma pessoa
-- ===========================================================================
-- Toda linha que o seed pôs na matriz tem uma CONCEDIDA no histórico, com
-- criado_por nulo: é assim que a tela mostra "sistema" em vez de um nome.
select is(
  (select count(*)::bigint from public.perfil_permissao_hist h
    where h.unidade_id = (select unidade_a from t_ctx)),
  (select count(*)::bigint from public.perfil_permissao pp
    where pp.unidade_id = (select unidade_a from t_ctx)),
  'cada linha da matriz da unidade A tem exatamente uma linha de historico');

select is(
  (select coalesce(string_agg(distinct h.acao || ':' || coalesce(h.criado_por::text, 'seed'), ','), '')
     from public.perfil_permissao_hist h
    where h.unidade_id = (select unidade_a from t_ctx)),
  'CONCEDIDA:seed',
  'antes de qualquer pessoa mexer, o historico so tem CONCEDIDA do seed (criado_por nulo)');

-- ===========================================================================
-- 2. Caminho feliz: marcar e desmarcar pela tela ficam registrados, com quem
-- ===========================================================================
select tests.autenticar((select direcao_a from t_ctx));

select lives_ok(
  $$insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
    select pe.unidade_id, pe.id, pm.id
      from public.perfil pe
      join public.permissao pm on pm.unidade_id = pe.unidade_id and pm.codigo = 'compras.ler'
     where pe.codigo = 'MONITOR' and pe.unidade_id = public.fn_unidade_atual()$$,
  'a direcao marca compras.ler para o MONITOR (insert em perfil_permissao)');

reset role;

select is(
  (select h.acao || '/' || h.perfil_codigo || '/' || h.permissao_codigo || '/' || h.criado_por::text
     from public.perfil_permissao_hist h
    where h.unidade_id = (select unidade_a from t_ctx)
      and h.perfil_codigo = 'MONITOR' and h.permissao_codigo = 'compras.ler'),
  'CONCEDIDA/MONITOR/compras.ler/' || (select direcao_a::text from t_ctx),
  'o historico registra CONCEDIDA, os dois codigos em texto e QUEM concedeu');

select tests.autenticar((select direcao_a from t_ctx));

select lives_ok(
  $$delete from public.perfil_permissao pp
     using public.perfil pe, public.permissao pm
     where pp.perfil_id = pe.id and pp.permissao_id = pm.id
       and pe.codigo = 'MONITOR' and pm.codigo = 'compras.ler'
       and pp.unidade_id = public.fn_unidade_atual()$$,
  'a direcao desmarca a mesma caixa (delete em perfil_permissao)');

reset role;

select is(
  (select string_agg(h.acao, ',' order by h.criado_em, h.acao)
     from public.perfil_permissao_hist h
    where h.unidade_id = (select unidade_a from t_ctx)
      and h.perfil_codigo = 'MONITOR' and h.permissao_codigo = 'compras.ler'),
  'CONCEDIDA,REMOVIDA',
  'a remocao NAO apaga a concessao: as duas transicoes ficam, na ordem');

select is(
  (select h.criado_por from public.perfil_permissao_hist h
    where h.unidade_id = (select unidade_a from t_ctx)
      and h.perfil_codigo = 'MONITOR' and h.permissao_codigo = 'compras.ler'
      and h.acao = 'REMOVIDA'),
  (select direcao_a from t_ctx),
  'a REMOVIDA carrega quem desmarcou — e o carimbo mora numa linha que nao some');

-- ===========================================================================
-- 3. Camada 2 — o caminho que contorna
-- ===========================================================================
-- (a) POST direto na tabela de histórico: sem política de insert, o PostgREST
-- recusa. É o que impede alguém de gravar "REMOVIDA" de uma permissão que
-- continua valendo — histórico que mente é pior que histórico ausente (4.2).
select tests.autenticar((select direcao_a from t_ctx));

select throws_ok(
  $$insert into public.perfil_permissao_hist
      (unidade_id, perfil_id, perfil_codigo, permissao_id, permissao_codigo, acao)
    select pe.unidade_id, pe.id, pe.codigo, pm.id, pm.codigo, 'REMOVIDA'
      from public.perfil pe
      join public.permissao pm on pm.unidade_id = pe.unidade_id and pm.codigo = 'admin.ler'
     where pe.codigo = 'DIRECAO' and pe.unidade_id = public.fn_unidade_atual()$$,
  '42501',
  null,
  'insert direto no historico e recusado pela RLS (sem politica = sem acesso), mesmo para a direcao');

-- (b) update e delete: sem política, o Postgres devolve zero linhas e nenhum
-- erro (card 3.4 (d)) — a imutabilidade é asserida pela contagem.
with u as (
  update public.perfil_permissao_hist set acao = 'CONCEDIDA'
   where acao = 'REMOVIDA' returning 1)
select is((select count(*) from u)::bigint, 0::bigint,
  'update no historico afeta zero linhas, mesmo para a direcao');

with d as (
  delete from public.perfil_permissao_hist returning 1)
select is((select count(*) from d)::bigint, 0::bigint,
  'delete no historico afeta zero linhas, mesmo para a direcao');

reset role;

-- (c) a cascata de FK. perfil → perfil_permissao é `on delete cascade`, e o
-- card 4.3 mediu que a cascata não passa pela RLS. Aqui a decisão é outra: o
-- histórico referencia o perfil com `on delete restrict`, então um perfil com
-- histórico NÃO se apaga — nem por quem tem BYPASSRLS. Perfil sai por
-- ativo = false (card 3.4), e a prova de quem mexeu na matriz dele fica.
select throws_ok(
  $$delete from public.perfil
     where codigo = 'ARQUIVADO' and unidade_id = (select unidade_a from t_ctx)$$,
  '23503',
  null,
  'perfil com historico nao se apaga: a FK do historico e restrict, nao cascade');

-- ===========================================================================
-- 4. Leitura: admin.ler, e só a própria unidade (paridade do card 2.8 §6.3)
-- ===========================================================================
select cmp_ok(
  tests.conta_como((select direcao_a from t_ctx),
    'select id from public.perfil_permissao_hist'),
  '>', 0::bigint,
  'a direcao le o historico da propria unidade');

select is(
  tests.conta_como((select monitor_a from t_ctx),
    'select id from public.perfil_permissao_hist'),
  0::bigint,
  'sem admin.ler o historico e invisivel (zero linhas, nao erro)');

select is(
  tests.conta_como((select direcao_b from t_ctx),
    $$select id from public.perfil_permissao_hist
       where perfil_codigo = 'MONITOR' and permissao_codigo = 'compras.ler'$$),
  0::bigint,
  'a direcao da unidade B nao ve a transicao feita na unidade A');

-- ===========================================================================
-- 5. O seed deixa de devolver o que alguém tirou de todos
-- ===========================================================================
-- Era o caso residual assumido no card 3.6 (docs/seed-inicial.md §2.1):
-- compras.receber_excedente só a direção tem; desmarcado dela, o código não
-- tinha linha nenhuma na unidade e o deploy seguinte o devolvia — sem erro, sem
-- log. Com o histórico, a REMOVIDA distingue "tirado de todos" de "nunca dado".
delete from public.perfil_permissao pp
 using public.permissao pm
 where pp.permissao_id = pm.id
   and pm.unidade_id = (select unidade_a from t_ctx)
   and pm.codigo = 'compras.receber_excedente';

select is(
  (select count(*)::bigint from public.perfil_permissao_hist h
    where h.unidade_id = (select unidade_a from t_ctx)
      and h.permissao_codigo = 'compras.receber_excedente' and h.acao = 'REMOVIDA'),
  1::bigint,
  'a remocao feita como postgres (sem auth.uid) tambem fica no historico');

select public.fn_seed_acesso((select unidade_a from t_ctx));

select ok(
  not exists (select 1 from public.perfil_permissao pp
                join public.permissao pm on pm.id = pp.permissao_id
               where pm.unidade_id = (select unidade_a from t_ctx)
                 and pm.codigo = 'compras.receber_excedente'),
  'codigo tirado de TODOS os perfis NAO volta quando o seed roda de novo (fecha o caso residual do card 3.6)');

-- O outro lado continua valendo: código sem linha E sem histórico é código novo,
-- e chega no primeiro deploy. Simulado apagando o histórico daquele código
-- (como postgres — pela tela isso é impossível, e é o ponto).
delete from public.perfil_permissao_hist h
 where h.unidade_id = (select unidade_a from t_ctx)
   and h.permissao_codigo = 'compras.receber_excedente';

select public.fn_seed_acesso((select unidade_a from t_ctx));

select ok(
  exists (select 1 from public.perfil_permissao pp
            join public.perfil    pe on pe.id = pp.perfil_id
            join public.permissao pm on pm.id = pp.permissao_id
           where pm.unidade_id = (select unidade_a from t_ctx)
             and pe.codigo = 'DIRECAO' and pm.codigo = 'compras.receber_excedente'),
  'codigo sem linha e sem historico E distribuido — e assim que codigo novo chega');

-- ===========================================================================
-- 6. A função do trigger não é um botão na API
-- ===========================================================================
select ok(
  not has_function_privilege('authenticated', 'public.fn_perfil_permissao_historico()', 'EXECUTE'),
  'fn_perfil_permissao_historico nao tem execute para authenticated');

select ok(
  exists (select 1 from pg_trigger tg
            join pg_class c on c.oid = tg.tgrelid
           where c.relname = 'perfil_permissao'
             and tg.tgname = 'tg_perfil_permissao_historico'
             and not tg.tgisinternal),
  'o trigger esta em perfil_permissao');

select * from finish();
rollback;
