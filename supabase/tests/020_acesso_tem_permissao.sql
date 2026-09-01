-- =============================================================================
-- Suíte de acesso — card 3.4 (mapa suíte → card, docs/estrategia-testes.md §17)
--
-- Testa comportamento, não catálogo: tem_permissao, fn_unidade_atual,
-- fn_minhas_permissoes, fn_param_int/txt, fn_exige_permissao, o contexto de
-- rotina e as políticas das sete tabelas do card 3.3.
--
-- Reescrito no card 3.4.5 para consumir a escola-fixture e os helpers tests.*
-- de supabase/seed.sql. Antes montava a própria fixture, com as mesmas duas
-- unidades — e a partir do 3.4.5 isso deixou de ser só duplicação: `ESCOLA_A`
-- passou a existir no seed, e `unidade_codigo_uk` derrubaria este arquivo no
-- primeiro insert.
--
-- Regra de ouro dos helpers: `tests.*` só é alcançável a partir do papel
-- `postgres`. Depois de `tests.autenticar(...)` a sessão está em
-- `authenticated`, que não tem USAGE no schema `tests` — para trocar de usuário,
-- `reset role;` primeiro.
--
-- O setup roda como `postgres`, que tem BYPASSRLS (achado do card 3.3): a RLS
-- não atrapalha a leitura da fixture. Tudo dentro de begin/rollback.
-- =============================================================================

begin;
select plan(32);

-- ===========================================================================
-- 1. tem_permissao — quem tem, quem não tem, e os três estados que negam
-- ===========================================================================
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select ok(public.tem_permissao('unidades.ler'),
  'direcao tem unidades.ler');

reset role;
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select ok(not public.tem_permissao('admin.ler'),
  'monitor NAO tem admin.ler');

reset role;
select tests.autenticar(tests.uid('semperfil@escola-a.test'));

select ok(not public.tem_permissao('unidades.ler'),
  'usuario sem perfil nao tem permissao nenhuma');

reset role;
select tests.autenticar(tests.uid('desativado@escola-a.test'));

select ok(not public.tem_permissao('unidades.ler'),
  'usuario DESATIVADO nao tem permissao, mesmo com perfil de direcao');

select is(public.fn_unidade_atual(), null::uuid,
  'usuario desativado nao tem unidade — e unidade null nega toda politica');

reset role;
select tests.autenticar(tests.uid('arquivado@escola-a.test'));

select ok(not public.tem_permissao('unidades.ler'),
  'perfil DESATIVADO nao concede, mesmo com a linha de perfil_permissao intacta');

-- ===========================================================================
-- 2. fn_unidade_atual e fn_minhas_permissoes
-- ===========================================================================
reset role;
select tests.autenticar(tests.uid('direcao@escola-a.test'));

-- Comparação com SQL puro: a direção enxerga exatamente uma unidade, a sua.
select is(public.fn_unidade_atual(), (select id from public.unidade),
  'fn_unidade_atual devolve a unidade do usuario autenticado');

reset role;
select tests.autenticar(tests.uid('monitor@escola-a.test'));

-- A lista literal, e não a contagem: é a camada de sessão do card 3.7 que vive
-- disto, e uma permissão a mais aqui é um botão a mais na tela do monitor.
-- `collate "C"` para a ordenação não depender do locale do cluster.
select is(
  (select string_agg(c, ',' order by c collate "C") from public.fn_minhas_permissoes() c),
  'alunos.ler,certificados.criar,certificados.ler,certificados.marcar_financeiro,'
  'estoque.lancar_saida,estoque.ler,materiais.ler,pendencias.ler,professores.ler,'
  'salas.acessar_credencial,salas.ler,salas.registrar_manutencao,turmas.ler,unidades.ler',
  'fn_minhas_permissoes devolve exatamente as 14 permissoes do monitor (card 2.4 §5 + 2.9)');

reset role;
select tests.autenticar(tests.uid('semperfil@escola-a.test'));

select is(
  (select count(*) from public.fn_minhas_permissoes())::bigint, 0::bigint,
  'fn_minhas_permissoes devolve vazio para usuario sem perfil');

-- ===========================================================================
-- 3. Políticas de select — inclusive a redução silenciosa, que é o modo de
--    falha que o card 2.3 §3.4 documentou
-- ===========================================================================
reset role;
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select is((select count(*) from public.unidade)::bigint, 1::bigint,
  'direcao de A ve apenas a propria unidade');

select is((select count(*) from public.permissao)::bigint, 50::bigint,
  'direcao ve o catalogo de 50 permissoes da propria unidade, e so o dela');

select is((select count(*) from public.usuario)::bigint, 7::bigint,
  'direcao ve os sete usuarios da unidade A, e nenhum da B');

reset role;
select tests.autenticar(tests.uid('direcao@escola-b.test'));

select is((select string_agg(codigo, ',') from public.unidade), 'ESCOLA_B',
  'direcao de B ve apenas a unidade B — isolamento por unidade');

reset role;
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select is((select count(*) from public.permissao)::bigint, 0::bigint,
  'monitor sem admin.ler le ZERO linhas de permissao — a RLS reduz, nao acusa');

select is((select count(*) from public.usuario)::bigint, 1::bigint,
  'monitor le a propria linha de usuario, e so ela (camada de sessao do 3.7)');

select is((select count(*) from public.parametro)::bigint, 0::bigint,
  'monitor sem parametros.ler nao le a tabela parametro');

-- ===========================================================================
-- 4. Políticas de escrita
-- ===========================================================================
-- O id da unidade alheia vai para uma GUC enquanto a sessão ainda é `postgres`:
-- a direção de A **não enxerga** a linha de B, então um subselect dentro do
-- insert não acharia nada e o teste passaria pelo motivo errado.
reset role;
select set_config('tests.unidade_b', tests.unidade('ESCOLA_B')::text, true);
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select throws_ok(
  $$ insert into public.parametro (unidade_id, chave, valor, tipo)
     select id, 'hack', '1', 'INTEIRO' from public.unidade $$,
  '42501', null,
  'monitor sem parametros.gerir nao insere parametro');

reset role;
select tests.autenticar(tests.uid('direcao@escola-a.test'));

-- Chave que o seed NÃO cria: desde o card 3.6 as 15 chaves das regras já estão
-- na tabela, e reinserir uma delas bateria em parametro_chave_uk antes de a RLS
-- opinar — o teste passaria a medir a unique, não a política.
select lives_ok(
  $$ insert into public.parametro (unidade_id, chave, valor, tipo)
     select id, 'parametro_criado_na_tela', '1', 'INTEIRO' from public.unidade $$,
  'direcao com parametros.gerir insere parametro');

select throws_ok(
  $$ insert into public.parametro (unidade_id, chave, valor, tipo)
     values (current_setting('tests.unidade_b')::uuid, 'invasao', '1', 'INTEIRO') $$,
  '42501', null,
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
reset role;
select tests.autenticar(tests.uid('monitor@escola-a.test'));

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

reset role;

select is(
  tests.codigo_do_erro($$ select public.fn_param_int('inexistente') $$,
                       tests.uid('monitor@escola-a.test')),
  'PARAMETRO_AUSENTE',
  'e o codigo estavel no DETAIL e PARAMETRO_AUSENTE');

-- ===========================================================================
-- 6. fn_exige_permissao
-- ===========================================================================
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select throws_ok(
  $$ select public.fn_exige_permissao('admin.ler') $$,
  'PT403', null,
  'fn_exige_permissao levanta PT403 para quem nao tem o codigo');

reset role;

select is(
  tests.codigo_do_erro($$ select public.fn_exige_permissao('admin.ler') $$,
                       tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'e o codigo estavel no DETAIL e SEM_PERMISSAO');

select tests.autenticar(tests.uid('monitor@escola-a.test'));

select lives_ok(
  $$ select public.fn_exige_permissao('unidades.ler') $$,
  'fn_exige_permissao passa em silencio para quem tem o codigo');

-- ===========================================================================
-- 7. Anônimo não vê nada: toda política é `to authenticated`
-- ===========================================================================
reset role;
select tests.como_anonimo();

select is((select count(*) from public.unidade)::bigint, 0::bigint,
  'anon nao le unidade — nenhuma politica e concedida a anon');

reset role;

-- ===========================================================================
-- 8. Contexto de rotina (card 2.2 §2.2)
-- ===========================================================================
select tests.como_rotina(tests.unidade('ESCOLA_A'));

select ok(public.tem_permissao('qualquer.codigo_que_nao_existe'),
  'em contexto de rotina tem_permissao e sempre verdadeira');

select is(public.fn_unidade_atual(), tests.unidade('ESCOLA_A'),
  'em contexto de rotina fn_unidade_atual vem da GUC, nao de auth.uid()');

select tests.encerrar_sessao();

-- ===========================================================================
-- 9. fn_hoje() não depende do fuso da sessão (card 2.3 §3.3)
-- ===========================================================================
set local timezone = 'UTC';

select is(public.fn_hoje(), (now() at time zone 'America/Sao_Paulo')::date,
  'fn_hoje devolve o dia em Sao Paulo mesmo com a sessao em UTC');

select * from finish();
rollback;
