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
   'Duas unidades, cinco perfis (quatro do seed real mais ARQUIVADO) e oito usuários. Catálogo, matriz e parâmetros vêm da camada acesso_seed_real.'),

  ('acesso_seed_real', 20, '3.6',
   $$exists (select 1
               from public.permissao p
               join public.unidade u on u.id = p.unidade_id
              where u.codigo not in ('ESCOLA_A','ESCOLA_B'))$$, true,
   'APLICADA no card 3.6: as duas unidades da fixture chamam public.fn_seed_acesso(), a mesma função que a migração chama para a unidade real. Nada de catálogo nem de matriz é escrito na fixture — se fosse, o teste de paridade compararia a tela real com uma matriz de mentira e passaria.'),

  ('catalogo_curricular', 30, '4.1',
   $$to_regclass('public.material') is not null$$, true,
   'APLICADA no card 4.1: os três métodos vêm de public.fn_seed_metodos() — a mesma função da migração —, mais seis materiais, quatro cursos, três módulos e três combos por unidade. Os saldos 0/0/1/n/n/n do card 2.8 §4.2 dependem de movimento_estoque e ficam com a camada trilha_estoque (6.1); aqui vai o catálogo, e o estoque_minimo já distingue os seis.'),

  ('alunos', 40, '4.2',
   $$to_regclass('public.aluno') is not null$$, true,
   'APLICADA no card 4.2: doze alunos por unidade, um por caso que alguma decisão criou — os quatro degraus da cascata da projeção, previsão vencida, STANDBY antigo, os dois terminais (FORMADO e CANCELADO), TRANCADO, ACELERAR e um sem combo. Datas SEMPRE relativas a fn_hoje(). O "em FIM" e o "com débito REP na borda" do card 2.8 §4.2 dependem de aluno_material e bloco_aluno: ficam com as camadas trilha_estoque (6.1) e turmas (5.1), e os alunos que os receberão já nascem aqui.'),

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

-- Catálogo, perfis, matriz e parâmetros NÃO são escritos aqui. As duas unidades
-- da fixture chamam `public.fn_seed_acesso()` — exatamente a função que a
-- migração do card 3.6 chama para a unidade real: 50 permissões, os quatro
-- perfis do plano, a matriz de docs/permissoes-matriz.md §5 e os 15 parâmetros.
--
-- É o ponto inteiro da camada `acesso_seed_real`. Enquanto o seed real não
-- existia, esta seção declarava um catálogo mínimo próprio (as sete permissões
-- citadas pelas políticas das migrações 3.3/3.4); mantê-lo agora seria uma
-- segunda matriz ao lado da real, parecida com ela e livre para divergir — e o
-- teste de paridade do card 2.8 §6.3, que compara contagem entre perfis,
-- passaria comparando a tela contra a mentira.
--
-- As duas unidades recebem o mesmo seed: é o que torna a asserção de isolamento
-- comparável (mesmos números dos dois lados, e mesmo assim zero vazamento).
select public.fn_seed_acesso(tests.unidade('ESCOLA_A'));
select public.fn_seed_acesso(tests.unidade('ESCOLA_B'));

-- O quinto perfil de A é da fixture, não do seed: ARQUIVADO, desativado e com a
-- mesma permissão de leitura que a matriz dá a todos. Sem ele nada prova o
-- filtro `perfil.ativo` que o card 3.4 acrescentou a tem_permissao, e desativar
-- um perfil na tela de Administração voltaria a ser uma ação sem efeito nenhum.
insert into public.perfil (unidade_id, codigo, nome, ativo)
values (tests.unidade('ESCOLA_A'), 'ARQUIVADO', 'Perfil desativado', false)
on conflict (unidade_id, codigo) do nothing;

insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
select pe.unidade_id, pe.id, pm.id
  from public.perfil    pe
  join public.permissao pm on pm.unidade_id = pe.unidade_id
                          and pm.codigo     = 'unidades.ler'
 where pe.unidade_id = tests.unidade('ESCOLA_A')
   and pe.codigo     = 'ARQUIVADO'
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

-- Nenhum parâmetro escrito aqui: os 15 vêm de `fn_seed_parametros()`, chamada
-- acima. `projecao_horizonte_dias` continua sendo o que prova que fn_param_int
-- lê para quem NÃO tem `parametros.ler` (ajuste bloqueante do card 2.4 #4) — a
-- diferença é que agora ele vale 60 pela mesma linha que fará valer 60 em
-- produção.

-- =============================================================================
-- 4. Escola-fixture — camada `catalogo_curricular` (card 4.1)
-- =============================================================================
-- Os três métodos NÃO são escritos aqui: vêm de `public.fn_seed_metodos()`, a
-- mesma função que a migração do card 4.1 chama para a unidade real. É a lição
-- da camada `acesso_seed_real` aplicada de novo — enumeração declarada duas
-- vezes é enumeração livre para divergir, e a divergência não acusa nada.
--
-- O catálogo em si (materiais, cursos, módulos, combos) é da fixture e só dela:
-- o catálogo REAL é dado de planilha, entra pelo importador do card 9.1 no
-- ambiente dev e nunca aparece numa migração (decisão de 02/09/2026). Os números
-- aqui são escolhidos para exercitar bordas, não para parecer com a escola.
--
-- Duas escolhas que valem explicação:
--
--   (a) os códigos de material SE REPETEM entre métodos ('01' existe em
--       INTERATIVO, em INGLES e em MODULAR). É de propósito: é assim na planilha
--       — cada catálogo tem a sua numeração — e é o que faz a fixture exercitar
--       `material_codigo_uk (unidade_id, metodo_id, codigo)` em vez de passar
--       igual se a unique estivesse errada em (unidade_id, codigo). Consequência
--       para quem escrever teste daqui em diante: material se acha pelo PAR
--       (método, código), nunca pelo código sozinho.
--
--   (b) o combo de Informática tem DOIS cursos, com ordens 1 e 2. Um combo de
--       curso único não exercita `combo_curso_ordem_uk` nem a ordem da trilha
--       que o card 6.2 gera a partir do combo — e a trilha resultante (01, 02,
--       03, sem repetição) é justamente o que o 6.2 precisa ter contra o que
--       comparar.
--
-- Saldos de estoque (0/0/1/n/n/n do card 2.8 §4.2) NÃO entram aqui: dependem de
-- `movimento_estoque`, que nasce no card 6.1 com a camada `trilha_estoque`. O
-- que este catálogo já traz é o `estoque_minimo` diferente por material, que é o
-- que o pedido sugerido do card 2.3 soma.

create or replace function tests.seed_catalogo(p_unidade uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_interativo uuid;
  v_ingles     uuid;
  v_modular    uuid;
begin
  perform public.fn_seed_metodos(p_unidade);

  select id into v_interativo from metodo where unidade_id = p_unidade and codigo = 'INTERATIVO';
  select id into v_ingles     from metodo where unidade_id = p_unidade and codigo = 'INGLES';
  select id into v_modular    from metodo where unidade_id = p_unidade and codigo = 'MODULAR';

  -- Seis materiais. `estoque_minimo` distinto por material: um valor único em
  -- todos faria o pedido sugerido do card 2.3 passar com a parcela do mínimo
  -- somada errado (ou não somada) sem que a conta mudasse.
  insert into material (unidade_id, metodo_id, codigo, nome, categoria, estoque_minimo)
  values
    (p_unidade, v_interativo, '01', 'Informática Essencial 1', 'APOSTILA', 2),
    (p_unidade, v_interativo, '02', 'Informática Essencial 2', 'APOSTILA', 1),
    (p_unidade, v_interativo, '03', 'Informática Avançada 1',  'APOSTILA', 1),
    (p_unidade, v_ingles,     '01', 'English Book 1',          'APOSTILA', 1),
    (p_unidade, v_ingles,     '02', 'English Book 2',          'APOSTILA', 2),
    (p_unidade, v_modular,    '01', 'Eletricista Instalador',  'LIVRO',    1)
  on conflict (unidade_id, metodo_id, codigo) do nothing;

  insert into curso (unidade_id, metodo_id, nome)
  values
    (p_unidade, v_interativo, 'Informática Essencial'),
    (p_unidade, v_interativo, 'Informática Avançada'),
    (p_unidade, v_ingles,     'Inglês Kids'),
    (p_unidade, v_modular,    'Eletricista Instalador')
  on conflict (unidade_id, metodo_id, nome) do nothing;

  -- Sequência de cada curso. O join por chave natural (método + código do
  -- material, nome do curso) é o que mantém isto legível e sem UUID literal —
  -- convenção do card 2.8 §A.
  insert into curso_material (unidade_id, curso_id, material_id, ordem)
  select p_unidade, c.id, m.id, s.ordem
    from (values
      ('Informática Essencial',  'INTERATIVO', '01', 1),
      ('Informática Essencial',  'INTERATIVO', '02', 2),
      ('Informática Avançada',   'INTERATIVO', '03', 1),
      ('Inglês Kids',            'INGLES',     '01', 1),
      ('Inglês Kids',            'INGLES',     '02', 2),
      -- No Modular o curso tem UM livro; o que avança é o módulo (abaixo).
      ('Eletricista Instalador', 'MODULAR',    '01', 1)
    ) as s(curso, metodo, material, ordem)
    join metodo   me on me.unidade_id = p_unidade and me.codigo = s.metodo
    join curso    c  on c.unidade_id  = p_unidade and c.metodo_id = me.id and c.nome = s.curso
    join material m  on m.unidade_id  = p_unidade and m.metodo_id = me.id and m.codigo = s.material
  on conflict (curso_id, material_id) do nothing;

  -- Três módulos sobre o MESMO livro: é a forma do Modular (card 7.2), e uma
  -- fixture com um módulo por material não exercitaria isso.
  insert into modulo (unidade_id, curso_id, material_id, nome, ordem)
  select p_unidade, c.id, m.id, s.nome, s.ordem
    from (values
      ('Módulo 1 — Comandos elétricos', 1),
      ('Módulo 2 — Instalações prediais', 2),
      ('Módulo 3 — Projetos', 3)
    ) as s(nome, ordem)
    join metodo   me on me.unidade_id = p_unidade and me.codigo = 'MODULAR'
    join curso    c  on c.unidade_id  = p_unidade and c.metodo_id = me.id
                    and c.nome = 'Eletricista Instalador'
    join material m  on m.unidade_id  = p_unidade and m.metodo_id = me.id and m.codigo = '01'
   where not exists (select 1 from modulo x where x.curso_id = c.id and x.ordem = s.ordem);

  insert into combo (unidade_id, metodo_id, nome)
  values
    (p_unidade, v_interativo, 'Informática Completo'),
    (p_unidade, v_ingles,     'Inglês Kids Completo'),
    (p_unidade, v_modular,    'Eletricista Completo')
  on conflict (unidade_id, nome) do nothing;

  insert into combo_curso (unidade_id, combo_id, curso_id, ordem)
  select p_unidade, cb.id, c.id, s.ordem
    from (values
      ('Informática Completo', 'Informática Essencial',  1),
      ('Informática Completo', 'Informática Avançada',   2),
      ('Inglês Kids Completo', 'Inglês Kids',            1),
      ('Eletricista Completo', 'Eletricista Instalador', 1)
    ) as s(combo, curso, ordem)
    join combo cb on cb.unidade_id = p_unidade and cb.nome = s.combo
    join curso c  on c.unidade_id  = p_unidade and c.nome  = s.curso
  on conflict (combo_id, curso_id) do nothing;
end $$;

-- As duas unidades recebem o mesmo catálogo, pela mesma razão da camada
-- `acesso`: números iguais dos dois lados é o que torna a asserção de isolamento
-- comparável — mesmo conteúdo, e ainda assim zero vazamento entre elas.
select tests.seed_catalogo(tests.unidade('ESCOLA_A'));
select tests.seed_catalogo(tests.unidade('ESCOLA_B'));

-- =============================================================================
-- 5. Escola-fixture — camada `alunos` (card 4.2)
-- =============================================================================
-- Doze alunos, um por caso que alguma decisão do projeto criou — não uma amostra
-- da planilha. O quadro do card 2.8 §4.2 pede "12 alunos cobrindo os 4 degraus
-- da cascata da projeção, 1 em FIM, 1 em STANDBY antigo, 1 com débito REP na
-- borda"; duas dessas três marcas dependem de tabelas que ainda não existem
-- (`aluno_material` no card 6.1, `bloco_aluno` no 5.1), e o que se pode fazer
-- agora — e é o que interessa — é já nascer o ALUNO que vai recebê-las, para que
-- as camadas seguintes só acrescentem linhas, sem mexer nesta.
--
-- Três escolhas que valem explicação:
--
--   (a) DUAS datas por aluno, sempre relativas a fn_hoje(). `data_inicio` é
--       quando a matrícula começou; `status_desde` é quando o status atual
--       passou a valer, e num aluno recém-inserido os dois NÃO coincidem —
--       Gabriela está em STANDBY há 45 dias e matriculada há 200. É essa
--       diferença que o alerta de STANDBY prolongado (30 dias, card 5.5) lê, e
--       uma fixture que igualasse as duas passaria sem exercitar nada.
--
--   (b) `codigo_sgf` fica NULO em três dos doze, de propósito. O índice é
--       parcial (`where codigo_sgf is not null`) justamente porque a planilha
--       tem aluno sem código, e três nulos são o que prova que nulos não colidem
--       entre si — com um só, a asserção passaria igual se o índice estivesse
--       escrito errado, sem o `where`.
--
--   (c) os dois status TERMINAIS estão presentes (Isabela CANCELADO, João Pedro
--       FORMADO). São a única entrada possível para fn_aluno_reverter_status, e
--       sem eles o teste da reversão teria de criar o próprio aluno — que é o
--       caminho para um teste que passa porque montou o cenário que queria.
create or replace function tests.seed_alunos(p_unidade uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  insert into aluno (unidade_id, codigo_sgf, nome, metodo_id, combo_id, status,
                     status_desde, prev_conclusao_curso, data_inicio)
  select p_unidade, s.codigo_sgf, s.nome, me.id, cb.id, s.status,
         fn_hoje() - s.status_ha,
         case when s.prev_em is null then null else fn_hoje() + s.prev_em end,
         fn_hoje() - s.inicio_ha
    from (values
      -- nome, codigo_sgf, metodo, combo, status, dias desde o status,
      -- prev_conclusao (dias a partir de hoje; negativo = vencida), dias de matrícula
      ('Ana Paula Ribeiro',  '3001', 'INTERATIVO', 'Informática Completo', 'ATIVO',     180, null, 180),
      ('Bruno Carvalho',     '3002', 'INTERATIVO', 'Informática Completo', 'ATIVO',      90,   90,  90),
      ('Carla Menezes',      '3003', 'INTERATIVO', 'Informática Completo', 'ATIVO',      10, null,  10),
      ('Diego Alves',        '3004', 'INTERATIVO', 'Informática Completo', 'ATIVO',     120,  -15, 120),
      ('Eduarda Lima',       '3005', 'MODULAR',    'Eletricista Completo', 'ATIVO',      60, null,  60),
      ('Felipe Nunes',       '3006', 'INGLES',     'Inglês Kids Completo', 'ACELERAR',   30,   60, 150),
      ('Gabriela Souza',     '3007', 'INGLES',     'Inglês Kids Completo', 'STANDBY',    45, null, 200),
      ('Henrique Dias',      '3008', 'INTERATIVO', 'Informática Completo', 'TRANCADO',   75, null, 300),
      ('Isabela Rocha',      null,   'INTERATIVO', 'Informática Completo', 'CANCELADO',  20, null, 100),
      ('João Pedro Martins', '3010', 'INTERATIVO', 'Informática Completo', 'FORMADO',     5, null, 400),
      ('Karina Bastos',      null,   'INTERATIVO', null,                   'ATIVO',      15, null,  15),
      ('Lucas Ferreira',     null,   'INTERATIVO', 'Informática Completo', 'ATIVO',      50, null,  50)
    ) as s(nome, codigo_sgf, metodo, combo, status, status_ha, prev_em, inicio_ha)
    join metodo me on me.unidade_id = p_unidade and me.codigo = s.metodo
    -- `left join` e não `join`: Karina não tem combo, e um join interno a
    -- deixaria de fora em silêncio — a fixture ficaria com onze alunos e o teste
    -- de contagem acusaria em outro lugar, longe da causa.
    left join combo cb on cb.unidade_id = p_unidade and cb.nome = s.combo
   where not exists (select 1 from aluno a
                      where a.unidade_id = p_unidade and a.nome = s.nome);
end $$;

-- Os alunos de A e de B são os mesmos, com os mesmos códigos SGF: é o que faz a
-- asserção de isolamento significar alguma coisa. `codigo_sgf` é único por
-- UNIDADE (card 2.1 §7), então repetir entre unidades é exatamente o caso que a
-- unique precisa aceitar — e recusaria se estivesse escrita sem o unidade_id.
select tests.seed_alunos(tests.unidade('ESCOLA_A'));
select tests.seed_alunos(tests.unidade('ESCOLA_B'));

-- =============================================================================
-- 6. Fecho: nada em `tests` alcançável por quem não é `postgres`
-- =============================================================================
-- `create function` concede EXECUTE a PUBLIC por padrão. A revogação do USAGE no
-- schema já bastaria, mas as duas juntas sobrevivem a alguém conceder o schema
-- sem pensar.
revoke all on all functions in schema tests from public, anon, authenticated;
revoke all on all tables    in schema tests from public, anon, authenticated;
