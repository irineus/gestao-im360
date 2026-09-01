-- =============================================================================
-- Infraestrutura de teste. Aplicada APENAS por `supabase db reset` (local/CI).
--
-- ⚠️ NUNCA mover nada deste arquivo para supabase/migrations/: migração é o que
--    o CI empurra para produção, e extensão de teste em prod é superfície de
--    ataque sem uso (card 2.8, ajuste #5).
-- ⚠️ `supabase db reset --linked` fica PROIBIDO: aplicaria isto no banco remoto.
--    O repositório nega o comando em .claude/settings.json.
--
-- O bootstrap (pgTAP + schema `tests`) nasceu no card 3.3, para que a suíte de
-- catálogo escrita lá tivesse onde rodar. Os HELPERS e a ESCOLA-FIXTURE são
-- deste card (3.4.5): dependem de usuario_perfil (3.3) e de tem_permissao (3.4).
--
-- Não confundir com o seed do card 3.6 (unidade real da escola, 50 permissões,
-- matriz inicial, parâmetros e primeiro usuário de direção): aquele É migração,
-- porque precisa existir em produção. Este aqui nunca sai da máquina de quem
-- testa.
--
-- Ordem de aplicação em `supabase db reset`: migrations/ → este arquivo. Logo,
-- tudo aqui pode contar com as tabelas e funções já criadas pelas migrações.
-- =============================================================================

create extension if not exists pgtap with schema extensions;

create schema if not exists tests;

-- Fail-closed, como toda a superfície deste projeto: `authenticated` não tem
-- USAGE no schema, então nenhuma função daqui é alcançável pelo PostgREST nem
-- por um teste que já trocou de papel.
--
-- Consequência prática que precisa estar na cabeça de quem escreve teste:
-- DEPOIS de `tests.autenticar(...)` a sessão está em `authenticated` e NÃO
-- consegue mais chamar `tests.*`. Para trocar de usuário, use `reset role;`
-- (comando SQL, sempre disponível) e autentique de novo. Errar isso dá
-- "permission denied for schema tests" — erro alto, não silêncio.
revoke all on schema tests from public, anon, authenticated;

-- =============================================================================
-- 1. Registro das camadas da fixture — o antídoto contra o esquecimento
-- =============================================================================
-- A escola-fixture do card 2.8 §4.2 descreve salas, PCs, blocos, materiais e
-- 12 alunos. NENHUMA dessas tabelas existe hoje: elas nascem nos cards 4.1, 4.2,
-- 4.3, 5.1 e 6.1. Escrevê-las agora faria `supabase db reset` falhar no primeiro
-- `insert`, e comentá-las produziria exatamente o que o card 2.8 combate — um
-- artefato que existe no papel e não exercita nada.
--
-- Em vez disso, cada camada futura fica DECLARADA aqui com a condição que a
-- torna devida. `tests/030_fixture_escola.sql` reprova a suíte no dia em que a
-- condição passar a valer e a camada continuar sem ser escrita. Ou seja: o card
-- 4.1 não fecha verde sem trazer a camada de catálogo junto.
create table tests.fixture_camada (
  camada    text primary key,
  ordem     smallint not null,
  card      text    not null,
  devida_se text    not null,   -- expressão booleana avaliada por fixture_camadas_devidas()
  aplicada  boolean not null default false,
  nota      text    not null
);

comment on table tests.fixture_camada is
  'Camadas da escola-fixture (card 2.8 §4.2). Camada não aplicada cuja condição devida_se já vale reprova o teste 030 — é assim que a fixture acompanha o schema em vez de ficar para trás.';

insert into tests.fixture_camada (camada, ordem, card, devida_se, aplicada, nota) values
  ('acesso', 10, '3.4.5',
   $$to_regclass('public.usuario_perfil') is not null$$, true,
   'Duas unidades, cinco perfis, catálogo e matriz das permissões citadas pelas políticas, oito usuários.'),

  ('acesso_seed_real', 20, '3.6',
   $$exists (select 1
               from public.permissao p
               join public.unidade u on u.id = p.unidade_id
              where u.codigo not in ('ESCOLA_A','ESCOLA_B'))$$, false,
   'O seed do card 3.6 passa a ser a fonte do catálogo, da matriz e dos parâmetros. A fixture deve consumir a MESMA fonte para ESCOLA_A/ESCOLA_B, senão o teste de paridade compara a tela real com uma matriz de mentira e passa.'),

  ('catalogo_curricular', 30, '4.1',
   $$to_regclass('public.material') is not null$$, false,
   'Seis materiais em três métodos, com os saldos 0/0/1/n/n/n do card 2.8 §4.2. Saldo depende de movimento_estoque (6.1); até lá, só o catálogo.'),

  ('alunos', 40, '4.2',
   $$to_regclass('public.aluno') is not null$$, false,
   'Doze alunos cobrindo os quatro degraus da cascata da projeção, um em FIM e um em STANDBY antigo. Datas SEMPRE relativas a fn_hoje().'),

  ('infra_fisica', 50, '4.3',
   $$to_regclass('public.pc') is not null$$, false,
   'Uma sala com 10 PCs (capacidade real do laboratório) e uma com 6. A borda 10/11 é o teste de lotação do card 5.3.'),

  ('turmas', 60, '5.1',
   $$to_regclass('public.bloco_aluno') is not null$$, false,
   'Três blocos, com 0, 9 e 10 alunos — o de 9 aceita o décimo, o de 10 recusa o décimo primeiro, sem depender de ordem de execução. Mais um aluno com débito REP na borda do critério do card 2.5.'),

  ('trilha_estoque', 70, '6.1',
   $$to_regclass('public.movimento_estoque') is not null$$, false,
   'Trilha dos doze alunos e os movimentos que produzem os saldos 0/0/1/n/n/n. Saldo 1 é o teste de concorrência (card 2.8 §7); saldo 0 é o REORDENADA e o BLOQUEADA_SEM_ESTOQUE.');

-- Devolve as camadas cuja condição já vale e que ainda não foram escritas.
-- Vazio = a fixture está em dia com o schema.
create or replace function tests.fixture_camadas_devidas()
returns table (camada text, card text, nota text)
language plpgsql
set search_path = public, pg_temp
as $$
declare
  r        record;
  v_devida boolean;
begin
  for r in select * from tests.fixture_camada where not aplicada order by ordem loop
    execute 'select (' || r.devida_se || ')' into v_devida;
    if coalesce(v_devida, false) then
      camada := r.camada;
      card   := r.card;
      nota   := r.nota;
      return next;
    end if;
  end loop;
end $$;

-- =============================================================================
-- 2. Helpers — o contexto que o PostgREST monta (card 2.8 §4.1, Apêndice A)
-- =============================================================================
-- Um teste que roda como `postgres` passa sem testar nada: `postgres` tem
-- BYPASSRLS (achado do card 3.3), então nenhuma política é exercitada. O que
-- prova alguma coisa é o papel `authenticated` com `request.jwt.claims` — que é
-- literalmente o que o PostgREST monta a cada requisição.

-- Cria usuário em auth.users + usuario + usuario_perfil.
-- security definer: auth.users pertence a supabase_auth_admin e usuario tem RLS
-- forçada. O dono (postgres) tem BYPASSRLS, então a montagem passa.
--
-- Idempotente por e-mail: reexecutar o seed não duplica, e o `on conflict` em
-- `usuario` sobrevive ao trigger de espelhamento auth.users → usuario do card
-- 3.5 — que desde 01/09/2026 existe de fato e cria a linha antes de este insert
-- chegar nela. O `do update` é o que faz `p_ativo => false` valer: o espelho
-- sempre cria a linha ativa, porque `ativo` é dado do app e não do Auth.
create or replace function tests.criar_usuario(
  p_email   text,
  p_perfil  text,
  p_unidade uuid    default null,
  p_ativo   boolean default true
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid;
  v_unidade uuid := coalesce(p_unidade, (select id from unidade where codigo = 'ESCOLA_A'));
begin
  select id into v_uid from usuario where email = p_email;

  if v_uid is null then
    v_uid := gen_random_uuid();

    -- raw_user_meta_data com a unidade: é o metadado do convite, e desde o card
    -- 3.5 o trigger tg_auth_usuario_criado o lê para criar a linha de `usuario`.
    -- Sem ele o helper quebraria — a fixture tem DUAS unidades ativas, e o
    -- fallback "única unidade ativa" do espelho recusa a ambiguidade com
    -- USUARIO_SEM_UNIDADE. Passar o metadado aqui não é contornar o trigger: é
    -- exercitar o mesmo caminho que o convite de verdade percorre.
    -- instance_id, raw_app_meta_data e uma senha de verdade: sem os três, a linha
    -- serve para teste SQL e mais nada — o GoTrue filtra por `instance_id` e
    -- responde "user not found" (medido no card 3.5). Com eles, os oito usuários
    -- da fixture LOGAM no stack local, que é o que o card 3.7 precisa para
    -- exercitar a tela de login sem inventar usuário à mão.
    --
    -- ⚠️ A senha abaixo é de fixture e só existe no stack local: este arquivo
    -- nunca vai para migrations/ e `supabase db reset --linked` é proibido
    -- (card 2.8, ajuste 5). Não é credencial de ninguém e não abre nada — não
    -- confundir com a política do card 2.9.
    -- Os seis campos de token vão como '' e não como null: o GoTrue lê essas
    -- colunas em `string` e morre com "converting NULL to string is unsupported"
    -- — erro 500 no login, sem relação aparente com a linha que o causou.
    insert into auth.users (id, instance_id, email, aud, role, encrypted_password,
                            email_confirmed_at, created_at, updated_at,
                            raw_app_meta_data, raw_user_meta_data,
                            confirmation_token, recovery_token,
                            email_change, email_change_token_new,
                            email_change_token_current, reauthentication_token)
    values (v_uid, '00000000-0000-0000-0000-000000000000',
            p_email, 'authenticated', 'authenticated',
            extensions.crypt('fixture-local-123', extensions.gen_salt('bf')),
            now(), now(), now(),
            jsonb_build_object('provider', 'email', 'providers', array['email']),
            jsonb_build_object('unidade_id', v_unidade::text, 'nome', p_email),
            '', '', '', '', '', '');
  end if;

  insert into usuario (id, unidade_id, nome, email, ativo)
  values (v_uid, v_unidade, p_email, p_email, p_ativo)
  on conflict (id) do update
     set unidade_id = excluded.unidade_id,
         nome       = excluded.nome,
         ativo      = excluded.ativo;

  if p_perfil is not null then
    insert into usuario_perfil (usuario_id, perfil_id, unidade_id)
    select v_uid, p.id, v_unidade
      from perfil p
     where p.unidade_id = v_unidade
       and p.codigo     = p_perfil
    on conflict (usuario_id, perfil_id) do nothing;
  end if;

  return v_uid;
end $$;

-- Busca por chave natural. security definer porque `usuario` e `unidade` têm
-- RLS: sem isso o helper devolveria null justamente quando chamado no meio de
-- um teste já autenticado.
create or replace function tests.uid(p_email text) returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select id from usuario where email = p_email $$;

create or replace function tests.unidade(p_codigo text) returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select id from unidade where codigo = p_codigo $$;

-- Reproduz o contexto de um usuário logado.
-- Claims ANTES do set role; is_local = true para o efeito morrer no rollback do
-- arquivo de teste — sem o `true`, um teste vaza identidade para o seguinte.
--
-- Verificado em 01/09/2026 (card 3.4): `set local role` dentro de função com
-- cláusula `set search_path` PERSISTE depois da saída — a cláusula SET salva e
-- restaura só as variáveis que nomeia, não o nível de GUC inteiro. É por isso
-- que estas quatro funções NÃO podem ser security definer: ali `set role` dá
-- erro explícito ("cannot set parameter role within security-definer function").
create or replace function tests.autenticar(p_usuario uuid) returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_usuario::text, 'role', 'authenticated')::text,
    true);
  set local role authenticated;
end $$;

create or replace function tests.como_anonimo() returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  perform set_config('request.jwt.claims', null, true);
  set local role anon;
end $$;

-- Contexto de rotina do card 2.2 §2.2: sem auth.uid(), a unidade vem da GUC.
-- Dentro dele tem_permissao() é sempre verdadeira — é o que faz o pg_cron
-- enxergar linha com `force row level security` ligado.
create or replace function tests.como_rotina(p_unidade uuid) returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  perform set_config('request.jwt.claims', null, true);
  perform set_config('app.rotina', 'on', true);
  perform set_config('app.rotina_unidade', p_unidade::text, true);
end $$;

create or replace function tests.encerrar_sessao() returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  reset role;
  perform set_config('request.jwt.claims', null, true);
  perform set_config('app.rotina', '', true);
  perform set_config('app.rotina_unidade', '', true);
end $$;

-- Conta linhas de um SELECT na pele de um usuário — base do teste de paridade
-- (card 2.8 §6.3), que é o único formato que prova alguma coisa quando a RLS
-- reduz linhas em silêncio. Chamar sempre a partir do papel `postgres`.
--
-- ⚠️ O Apêndice A do card 2.8 fechava esta função com `perform
-- tests.encerrar_sessao()`, e ela NÃO funcionaria: nessa altura a sessão já está
-- em `authenticated`, que não tem USAGE no schema `tests` — a chamada morre com
-- "permission denied for schema tests" e derruba toda paridade. A volta ao papel
-- do chamador é feita aqui dentro, com SQL puro, sem passar por tests.*.
create or replace function tests.conta_como(p_usuario uuid, p_sql text)
returns bigint
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n    bigint;
  v_role text := current_user;
begin
  perform tests.autenticar(p_usuario);
  execute format('select count(*) from (%s) t', p_sql) into v_n;
  execute format('set local role %I', v_role);
  perform set_config('request.jwt.claims', null, true);
  return v_n;
end $$;

-- Devolve o `codigo` estável do DETAIL de um erro — o contrato que o Flutter lê
-- (card 2.2 §1.2; catálogo de 21 códigos conferido no card 2.8 §10). O par
-- canônico de asserção é `throws_ok` para o SQLSTATE e este helper para o
-- código: o texto da mensagem nunca é contrato.
--
-- Chamar a partir do papel `postgres`, passando p_usuario quando o erro só
-- acontece na pele de alguém.
create or replace function tests.codigo_do_erro(p_sql text, p_usuario uuid default null)
returns text
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_detail text;
  v_role   text := current_user;
begin
  if p_usuario is not null then
    perform tests.autenticar(p_usuario);
  end if;

  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
  end;

  -- Mesma razão de tests.conta_como: aqui a sessão pode estar em
  -- `authenticated`, e de lá tests.* é inalcançável.
  execute format('set local role %I', v_role);
  perform set_config('request.jwt.claims', null, true);

  -- DETAIL vazio devolve null, não erro de cast: um erro sem `codigo` é uma
  -- falha de contrato do card 2.2 §1.2, e quem tem de acusá-la é a asserção do
  -- teste, não uma exceção dentro do helper.
  return nullif(v_detail, '')::json ->> 'codigo';
end $$;

-- =============================================================================
-- 3. Escola-fixture — camada `acesso` (card 2.8 §4.2)
-- =============================================================================
-- Uma escola pequena e FIXA, com números escolhidos para exercitar bordas — não
-- uma cópia da planilha. A planilha entra no dry-run do card 9.4, com dados
-- reais; aqui o que se quer é determinismo.
--
-- Datas relativas a fn_hoje(), nunca absolutas: fixture com '2026-09-01' começa
-- a falhar sozinha meses depois. Esta camada não tem nenhuma data de negócio —
-- só carimbos de auditoria, preenchidos por fn_auditoria().
--
-- Toda a camada é idempotente: reexecutar o seed não duplica nada.

insert into public.unidade (codigo, nome) values
  ('ESCOLA_A', 'Escola A (fixture)'),
  ('ESCOLA_B', 'Escola B (fixture)')
on conflict (codigo) do nothing;

-- Catálogo de permissões — as SETE citadas pelas políticas das migrações
-- 3.3/3.4, nem uma a mais. Código sem consumidor não entra (card 2.4 (a)), e um
-- catálogo inventado aqui viraria uma segunda fonte da verdade que ninguém
-- reconcilia. As outras 43 chegam com a camada `acesso_seed_real` (card 3.6).
--
-- As duas unidades recebem o mesmo catálogo: é o que torna a asserção de
-- isolamento comparável (mesmos números dos dois lados, e mesmo assim zero
-- vazamento).
insert into public.permissao (unidade_id, codigo, descricao, dominio)
select u.id, c.codigo, c.descricao, c.dominio
  from public.unidade u
 cross join (values
    ('admin.ler',            'Ler usuario, perfil, permissao, perfil_permissao, usuario_perfil', 'admin'),
    ('admin.gerir_usuarios', 'Criar/editar usuario; atribuir e remover perfis',                  'admin'),
    ('admin.gerir_perfis',   'Criar/editar perfil; marcar e desmarcar a matriz',                 'admin'),
    ('unidades.ler',         'Ler unidade',                                                      'unidades'),
    ('unidades.gerir',       'Criar/editar unidade',                                             'unidades'),
    ('parametros.ler',       'Ler parametro na tela de Administracao',                           'parametros'),
    ('parametros.gerir',     'Criar/editar parametro',                                           'parametros')
 ) as c(codigo, descricao, dominio)
 where u.codigo in ('ESCOLA_A', 'ESCOLA_B')
on conflict (unidade_id, codigo) do nothing;

-- Cinco perfis em A. Os quatro do plano, mais ARQUIVADO — desativado, e com a
-- MESMA permissão do monitor. Sem ele nada prova o filtro `perfil.ativo` que o
-- card 3.4 acrescentou a tem_permissao, e desativar um perfil na tela de
-- Administração voltaria a ser uma ação sem efeito nenhum.
insert into public.perfil (unidade_id, codigo, nome, ativo)
select tests.unidade('ESCOLA_A'), p.codigo, p.nome, p.ativo
  from (values
    ('DIRECAO',    'Direção',           true),
    ('PEDAGOGICO', 'Pedagógico',        true),
    ('SECRETARIA', 'Secretaria',        true),
    ('MONITOR',    'Monitor',           true),
    ('ARQUIVADO',  'Perfil desativado', false)
 ) as p(codigo, nome, ativo)
on conflict (unidade_id, codigo) do nothing;

insert into public.perfil (unidade_id, codigo, nome, ativo)
values (tests.unidade('ESCOLA_B'), 'DIRECAO', 'Direção', true)
on conflict (unidade_id, codigo) do nothing;

-- Matriz inicial, copiada de docs/permissoes-matriz.md §5 para os sete códigos
-- desta camada: direção tem os sete; os outros três perfis têm só
-- `unidades.ler`, que a matriz abre para todos porque sem ela ninguém lê o nome
-- da própria escola no cabeçalho.
insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select pe.unidade_id, pe.id, pm.id
  from public.perfil    pe
  join public.permissao pm on pm.unidade_id = pe.unidade_id
 where pe.codigo = 'DIRECAO'
on conflict (perfil_id, permissao_id) do nothing;

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select pe.unidade_id, pe.id, pm.id
  from public.perfil    pe
  join public.permissao pm on pm.unidade_id = pe.unidade_id
                          and pm.codigo     = 'unidades.ler'
 where pe.codigo in ('PEDAGOGICO', 'SECRETARIA', 'MONITOR', 'ARQUIVADO')
on conflict (perfil_id, permissao_id) do nothing;

-- Oito usuários. Os cinco do card 2.8 §4.2 (um por perfil + um sem perfil
-- nenhum, que é o teste de "sem política = sem acesso") mais três que as
-- asserções do card 3.4 tornaram necessários: o desativado com perfil de
-- direção intacto, o de perfil arquivado, e a direção da segunda unidade.
select tests.criar_usuario('direcao@escola-a.test',    'DIRECAO');
select tests.criar_usuario('pedagogico@escola-a.test', 'PEDAGOGICO');
select tests.criar_usuario('secretaria@escola-a.test', 'SECRETARIA');
select tests.criar_usuario('monitor@escola-a.test',    'MONITOR');
select tests.criar_usuario('semperfil@escola-a.test',  null);
select tests.criar_usuario('desativado@escola-a.test', 'DIRECAO',   null, false);
select tests.criar_usuario('arquivado@escola-a.test',  'ARQUIVADO');
select tests.criar_usuario('direcao@escola-b.test',    'DIRECAO', tests.unidade('ESCOLA_B'));

-- Um parâmetro só: o suficiente para provar que fn_param_int/txt leem para quem
-- NÃO tem `parametros.ler` (o ajuste bloqueante do card 2.4 #4). Os outros
-- chegam com a camada `acesso_seed_real`, junto do seed do card 3.6, que é a
-- fonte de verdade deles.
insert into public.parametro (unidade_id, chave, valor, tipo, descricao)
values (tests.unidade('ESCOLA_A'), 'projecao_horizonte_dias', '60', 'INTEIRO',
        'Horizonte da projeção de demanda, em dias')
on conflict (unidade_id, chave) do nothing;

-- =============================================================================
-- 4. Fecho: nada em `tests` alcançável por quem não é `postgres`
-- =============================================================================
-- `create function` concede EXECUTE a PUBLIC por padrão. A revogação do USAGE no
-- schema já bastaria, mas as duas juntas sobrevivem a alguém conceder o schema
-- sem pensar.
revoke all on all functions in schema tests from public, anon, authenticated;
revoke all on all tables    in schema tests from public, anon, authenticated;
