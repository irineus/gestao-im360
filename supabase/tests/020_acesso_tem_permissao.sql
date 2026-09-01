-- =============================================================================
-- Suíte de acesso — card 3.4 (mapa suíte → card, docs/estrategia-testes.md §17)
--
-- Testa comportamento, não catálogo: tem_permissao, fn_unidade_atual,
-- fn_minhas_permissoes, fn_param_int/txt, fn_exige_permissao, o contexto de
-- rotina e as políticas das sete tabelas do card 3.3.
--
-- ⚠️ Esta suíte monta a PRÓPRIA fixture e faz a troca de papel no topo do
-- script, sem os helpers tests.* do Apêndice A do card 2.8 — eles são do card
-- 3.4.5 e ainda não existem. Ver o achado registrado na subpágina deste card:
-- `set local role` dentro de uma função que carrega cláusula `set search_path`
-- é desfeito na saída da função (o Postgres restaura o nível de GUC inteiro),
-- então `tests.autenticar` como está escrito no apêndice provavelmente não
-- persiste o papel — a verificar no 3.4.5, num stack local.
--
-- O setup roda como `postgres`, que tem BYPASSRLS (achado do card 3.3): a RLS
-- não atrapalha a montagem da fixture. Tudo dentro de begin/rollback.
-- =============================================================================

begin;
select plan(32);

-- ---------------------------------------------------------------------------
-- Fixture — duas unidades; a segunda existe só para provar isolamento.
-- UUIDs fixos para que as claims JWT possam ser literais no script.
-- ---------------------------------------------------------------------------
insert into public.unidade (id, codigo, nome) values
  ('11111111-1111-4111-8111-111111111111', 'ESCOLA_A', 'Escola A'),
  ('22222222-2222-4222-8222-222222222222', 'ESCOLA_B', 'Escola B');

insert into public.permissao (unidade_id, codigo, descricao, dominio) values
  ('11111111-1111-4111-8111-111111111111', 'admin.ler',        'Ler administração', 'admin'),
  ('11111111-1111-4111-8111-111111111111', 'unidades.ler',     'Ler unidade',       'unidades'),
  ('11111111-1111-4111-8111-111111111111', 'parametros.ler',   'Ler parâmetros',    'parametros'),
  ('11111111-1111-4111-8111-111111111111', 'parametros.gerir', 'Gerir parâmetros',  'parametros'),
  ('22222222-2222-4222-8222-222222222222', 'unidades.ler',     'Ler unidade',       'unidades');

insert into public.perfil (id, unidade_id, codigo, nome, ativo) values
  ('aaaa0000-0000-4000-8000-00000000000a', '11111111-1111-4111-8111-111111111111',
   'DIRECAO',   'Direção',  true),
  ('aaaa0000-0000-4000-8000-00000000000b', '11111111-1111-4111-8111-111111111111',
   'MONITOR',   'Monitor',  true),
  ('aaaa0000-0000-4000-8000-00000000000c', '11111111-1111-4111-8111-111111111111',
   'ARQUIVADO', 'Perfil desativado', false),
  ('aaaa0000-0000-4000-8000-00000000000d', '22222222-2222-4222-8222-222222222222',
   'DIRECAO',   'Direção',  true);

-- direção da unidade A: as quatro permissões de A.
insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
  select '11111111-1111-4111-8111-111111111111',
         'aaaa0000-0000-4000-8000-00000000000a', p.id
    from public.permissao p
   where p.unidade_id = '11111111-1111-4111-8111-111111111111';

-- monitor: só unidades.ler. Sem admin.ler e sem parametros.ler — é dele que sai
-- a prova de que fn_param_int funciona mesmo assim.
insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
  select '11111111-1111-4111-8111-111111111111',
         'aaaa0000-0000-4000-8000-00000000000b', p.id
    from public.permissao p
   where p.unidade_id = '11111111-1111-4111-8111-111111111111'
     and p.codigo = 'unidades.ler';

-- perfil desativado com a MESMA permissão da direção: se `pe.ativo` não fosse
-- filtrado, o usuário abaixo passaria em tudo.
insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
  select '11111111-1111-4111-8111-111111111111',
         'aaaa0000-0000-4000-8000-00000000000c', p.id
    from public.permissao p
   where p.unidade_id = '11111111-1111-4111-8111-111111111111'
     and p.codigo = 'unidades.ler';

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
  select '22222222-2222-4222-8222-222222222222',
         'aaaa0000-0000-4000-8000-00000000000d', p.id
    from public.permissao p
   where p.unidade_id = '22222222-2222-4222-8222-222222222222';

insert into auth.users (id, email, aud, role, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values
  ('cccc0000-0000-4000-8000-000000000001', 'direcao@ex.com',   'authenticated', 'authenticated', '', now(), now(), now()),
  ('cccc0000-0000-4000-8000-000000000002', 'monitor@ex.com',   'authenticated', 'authenticated', '', now(), now(), now()),
  ('cccc0000-0000-4000-8000-000000000003', 'semperfil@ex.com', 'authenticated', 'authenticated', '', now(), now(), now()),
  ('cccc0000-0000-4000-8000-000000000004', 'inativo@ex.com',   'authenticated', 'authenticated', '', now(), now(), now()),
  ('cccc0000-0000-4000-8000-000000000005', 'arquivado@ex.com', 'authenticated', 'authenticated', '', now(), now(), now()),
  ('cccc0000-0000-4000-8000-000000000006', 'direcaob@ex.com',  'authenticated', 'authenticated', '', now(), now(), now());

insert into public.usuario (id, unidade_id, nome, email, ativo) values
  ('cccc0000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'Direção A',   'direcao@ex.com',   true),
  ('cccc0000-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'Monitor A',   'monitor@ex.com',   true),
  ('cccc0000-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', 'Sem perfil',  'semperfil@ex.com', true),
  ('cccc0000-0000-4000-8000-000000000004', '11111111-1111-4111-8111-111111111111', 'Desativado',  'inativo@ex.com',   false),
  ('cccc0000-0000-4000-8000-000000000005', '11111111-1111-4111-8111-111111111111', 'Arquivado',   'arquivado@ex.com', true),
  ('cccc0000-0000-4000-8000-000000000006', '22222222-2222-4222-8222-222222222222', 'Direção B',   'direcaob@ex.com',  true);

insert into public.usuario_perfil (unidade_id, usuario_id, perfil_id) values
  ('11111111-1111-4111-8111-111111111111', 'cccc0000-0000-4000-8000-000000000001', 'aaaa0000-0000-4000-8000-00000000000a'),
  ('11111111-1111-4111-8111-111111111111', 'cccc0000-0000-4000-8000-000000000002', 'aaaa0000-0000-4000-8000-00000000000b'),
  -- desativado, mas com o perfil de direção intacto
  ('11111111-1111-4111-8111-111111111111', 'cccc0000-0000-4000-8000-000000000004', 'aaaa0000-0000-4000-8000-00000000000a'),
  -- ativo, mas o perfil é que está desativado
  ('11111111-1111-4111-8111-111111111111', 'cccc0000-0000-4000-8000-000000000005', 'aaaa0000-0000-4000-8000-00000000000c'),
  ('22222222-2222-4222-8222-222222222222', 'cccc0000-0000-4000-8000-000000000006', 'aaaa0000-0000-4000-8000-00000000000d');

insert into public.parametro (unidade_id, chave, valor, tipo, descricao) values
  ('11111111-1111-4111-8111-111111111111', 'projecao_horizonte_dias', '60', 'INTEIRO',
   'Horizonte da projeção de demanda, em dias');

-- Captura o `codigo` do DETAIL de um erro — o contrato que o Flutter lê
-- (card 2.2 §1.2). Substituído por tests.ultimo_erro_detail() no card 3.4.5.
create function pg_temp.codigo_do_erro(p_sql text) returns text
language plpgsql as $$
declare v_detail text;
begin
  execute p_sql;
  return null;
exception when others then
  get stacked diagnostics v_detail = pg_exception_detail;
  return v_detail::json ->> 'codigo';
end $$;

-- ===========================================================================
-- 1. tem_permissao — quem tem, quem não tem, e os três estados que negam
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select ok(public.tem_permissao('unidades.ler'),
  'direcao tem unidades.ler');

select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select ok(not public.tem_permissao('admin.ler'),
  'monitor NAO tem admin.ler');

select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select ok(not public.tem_permissao('unidades.ler'),
  'usuario sem perfil nao tem permissao nenhuma');

select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000004","role":"authenticated"}', true);

select ok(not public.tem_permissao('unidades.ler'),
  'usuario DESATIVADO nao tem permissao, mesmo com perfil de direcao');

select is(public.fn_unidade_atual(), null::uuid,
  'usuario desativado nao tem unidade — e unidade null nega toda politica');

select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000005","role":"authenticated"}', true);

select ok(not public.tem_permissao('unidades.ler'),
  'perfil DESATIVADO nao concede, mesmo com a linha de perfil_permissao intacta');

-- ===========================================================================
-- 2. fn_unidade_atual e fn_minhas_permissoes
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select is(public.fn_unidade_atual(),
  '11111111-1111-4111-8111-111111111111'::uuid,
  'fn_unidade_atual devolve a unidade do usuario autenticado');

select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select is(
  (select string_agg(c, ',' order by c) from public.fn_minhas_permissoes() c),
  'unidades.ler',
  'fn_minhas_permissoes devolve exatamente as permissoes do monitor');

select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select is(
  (select count(*) from public.fn_minhas_permissoes())::bigint, 0::bigint,
  'fn_minhas_permissoes devolve vazio para usuario sem perfil');

-- ===========================================================================
-- 3. Políticas de select — inclusive a redução silenciosa, que é o modo de
--    falha que o card 2.3 §3.4 documentou
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select is((select count(*) from public.unidade)::bigint, 1::bigint,
  'direcao de A ve apenas a propria unidade');

select is((select count(*) from public.permissao)::bigint, 4::bigint,
  'direcao ve o catalogo de permissoes da propria unidade');

select is((select count(*) from public.usuario)::bigint, 5::bigint,
  'direcao ve os cinco usuarios da unidade A, e nenhum da B');

select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000006","role":"authenticated"}', true);

select is((select string_agg(codigo, ',') from public.unidade), 'ESCOLA_B',
  'direcao de B ve apenas a unidade B — isolamento por unidade');

select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select is((select count(*) from public.permissao)::bigint, 0::bigint,
  'monitor sem admin.ler le ZERO linhas de permissao — a RLS reduz, nao acusa');

select is((select count(*) from public.usuario)::bigint, 1::bigint,
  'monitor le a propria linha de usuario, e so ela (camada de sessao do 3.7)');

select is((select count(*) from public.parametro)::bigint, 0::bigint,
  'monitor sem parametros.ler nao le a tabela parametro');

-- ===========================================================================
-- 4. Políticas de escrita
-- ===========================================================================
select throws_ok(
  $$ insert into public.parametro (unidade_id, chave, valor, tipo)
     values ('11111111-1111-4111-8111-111111111111', 'hack', '1', 'INTEIRO') $$,
  '42501', null,
  'monitor sem parametros.gerir nao insere parametro');

select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$ insert into public.parametro (unidade_id, chave, valor, tipo)
     values ('11111111-1111-4111-8111-111111111111', 'standby_alerta_dias', '30', 'INTEIRO') $$,
  'direcao com parametros.gerir insere parametro');

select throws_ok(
  $$ insert into public.parametro (unidade_id, chave, valor, tipo)
     values ('22222222-2222-4222-8222-222222222222', 'invasao', '1', 'INTEIRO') $$,
  '42501',  null,
  'ninguem escreve na unidade alheia, mesmo com a permissao do proprio dominio');

-- `permissao` não tem política de update: o catálogo só muda por migração
-- (card 2.4 (e)). Sem política, o Postgres NÃO levanta erro — ele simplesmente
-- não encontra linha para atualizar. É exatamente a falha opaca que
-- fn_exige_permissao existe para traduzir nas funções de aplicação.
with u as (
  update public.permissao set descricao = 'alterada pela tela' where true returning 1
)
select is((select count(*) from u)::bigint, 0::bigint,
  'permissao sem politica de update: zero linhas afetadas, sem erro');

-- ===========================================================================
-- 5. fn_param_* — o ajuste BLOQUEANTE do card 2.4 (#4) / Ordem 5 (§11)
-- ===========================================================================
select set_config('request.jwt.claims',
  '{"sub":"cccc0000-0000-4000-8000-000000000002","role":"authenticated"}', true);

-- O monitor acabou de ler ZERO linhas de `parametro` (asserção acima). Se
-- fn_param_int fosse security invoker, esta chamada devolveria
-- PARAMETRO_AUSENTE — e a tela de projeção erraria para tres dos quatro perfis.
select is(public.fn_param_int('projecao_horizonte_dias'), 60,
  'fn_param_int le o parametro para quem NAO tem parametros.ler (security definer)');

select is(public.fn_param_txt('projecao_horizonte_dias'), '60',
  'fn_param_txt le o mesmo parametro como texto');

select is(public.fn_param_int('inexistente', 7), 7,
  'fn_param_int usa o default quando a chave nao existe');

select throws_ok(
  $$ select public.fn_param_int('inexistente') $$,
  'PT422', null,
  'fn_param_int sem valor nem default levanta PT422');

-- `reset role` antes de chamar o helper: o schema temporário pertence ao usuário
-- da sessão (postgres) e não concede USAGE a authenticated. O veredito não muda
-- com o papel — fn_param_int e fn_exige_permissao decidem por auth.uid(), que
-- continua sendo o do monitor, e não pela RLS.
reset role;

select is(
  pg_temp.codigo_do_erro($$ select public.fn_param_int('inexistente') $$),
  'PARAMETRO_AUSENTE',
  'e o codigo estavel no DETAIL e PARAMETRO_AUSENTE');

set local role authenticated;

-- ===========================================================================
-- 6. fn_exige_permissao
-- ===========================================================================
select throws_ok(
  $$ select public.fn_exige_permissao('admin.ler') $$,
  'PT403', null,
  'fn_exige_permissao levanta PT403 para quem nao tem o codigo');

reset role;

select is(
  pg_temp.codigo_do_erro($$ select public.fn_exige_permissao('admin.ler') $$),
  'SEM_PERMISSAO',
  'e o codigo estavel no DETAIL e SEM_PERMISSAO');

set local role authenticated;

select lives_ok(
  $$ select public.fn_exige_permissao('unidades.ler') $$,
  'fn_exige_permissao passa em silencio para quem tem o codigo');

-- ===========================================================================
-- 7. Anônimo não vê nada: toda política é `to authenticated`
-- ===========================================================================
select set_config('request.jwt.claims', null, true);
set local role anon;

select is((select count(*) from public.unidade)::bigint, 0::bigint,
  'anon nao le unidade — nenhuma politica e concedida a anon');

reset role;

-- ===========================================================================
-- 8. Contexto de rotina (card 2.2 §2.2)
-- ===========================================================================
select set_config('request.jwt.claims', null, true);
select set_config('app.rotina', 'on', true);
select set_config('app.rotina_unidade',
  '11111111-1111-4111-8111-111111111111', true);

select ok(public.tem_permissao('qualquer.codigo_que_nao_existe'),
  'em contexto de rotina tem_permissao e sempre verdadeira');

select is(public.fn_unidade_atual(),
  '11111111-1111-4111-8111-111111111111'::uuid,
  'em contexto de rotina fn_unidade_atual vem da GUC, nao de auth.uid()');

select set_config('app.rotina', '', true);

-- ===========================================================================
-- 9. fn_hoje() não depende do fuso da sessão (card 2.3 §3.3)
-- ===========================================================================
set local timezone = 'UTC';

select is(public.fn_hoje(), (now() at time zone 'America/Sao_Paulo')::date,
  'fn_hoje devolve o dia em Sao Paulo mesmo com a sessao em UTC');

select * from finish();
rollback;
