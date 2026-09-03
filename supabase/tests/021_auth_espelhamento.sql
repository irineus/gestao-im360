-- =============================================================================
-- Suíte do espelho auth.users → usuario — card 3.5
--
-- O que este arquivo protege, em uma frase: `usuario` é espelho de `auth.users`,
-- e as duas formas de esse espelho quebrar em silêncio são pessoa que entra e
-- não tem linha, e linha que existe com e-mail diferente do de acesso.
--
-- Convite de verdade = `insert into auth.users` feito pelo GoTrue. Aqui o insert
-- é escrito à mão, como faz tests.criar_usuario (seed.sql), porque o que se
-- testa é o trigger, não o GoTrue.
--
-- Regra de ouro dos helpers (card 3.4.5): `tests.*` só é alcançável a partir do
-- papel `postgres` — depois de tests.autenticar(...) é preciso `reset role;`.
-- Tudo dentro de begin/rollback.
-- =============================================================================

begin;
select plan(22);

-- ===========================================================================
-- 0. Os triggers estão instalados onde precisam estar
-- ===========================================================================
select has_trigger('auth'::name, 'users'::name, 'tg_auth_usuario_criado'::name,
  'tg_auth_usuario_criado existe em auth.users');

select has_trigger('auth'::name, 'users'::name, 'tg_auth_usuario_email'::name,
  'tg_auth_usuario_email existe em auth.users');

select has_trigger('public'::name, 'usuario'::name, 'tg_usuario_espelho_coerente'::name,
  'tg_usuario_espelho_coerente existe em public.usuario');

-- ===========================================================================
-- 1. Convite com metadado completo — o caminho do card 4.7
-- ===========================================================================
insert into auth.users (id, email, aud, role, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        raw_user_meta_data)
values ('11111111-1111-4111-8111-111111111111', 'convidada@escola-a.test',
        'authenticated', 'authenticated', '', now(), now(), now(),
        jsonb_build_object('unidade_id', tests.unidade('ESCOLA_A')::text,
                           'nome', 'Débora Convidada'));

select is(
  (select nome from public.usuario where id = '11111111-1111-4111-8111-111111111111'),
  'Débora Convidada',
  'espelho copia o nome do metadado do convite');

select is(
  (select unidade_id from public.usuario where id = '11111111-1111-4111-8111-111111111111'),
  tests.unidade('ESCOLA_A'),
  'espelho copia a unidade do metadado do convite');

select ok(
  (select ativo from public.usuario where id = '11111111-1111-4111-8111-111111111111'),
  'usuario espelhado nasce ativo — `ativo` e dado do app, o Auth nao opina');

-- ===========================================================================
-- 2. Convite pelo painel do Supabase — só o e-mail, sem metadado nenhum
-- ===========================================================================
-- É o fluxo da v1 (docs/acesso-autenticacao.md §3). O nome vira a parte local do
-- e-mail, obviamente provisório, e a direção corrige na tela de Administração.
-- Precisa de UMA unidade ativa. O banco tem três: as duas da fixture e a
-- unidade real, que a migração do card 3.6 passou a criar — e é justamente por
-- ela que o fallback funciona em dev e em produção, onde MATRIZ é a única. Aqui
-- todas as outras saem de cena.
update public.unidade set ativo = false where codigo <> 'ESCOLA_A';

insert into auth.users (id, email, aud, role, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('22222222-2222-4222-8222-222222222222', 'caio.souza@escola-a.test',
        'authenticated', 'authenticated', '', now(), now(), now());

select is(
  (select nome || '|' || unidade_id::text from public.usuario
    where id = '22222222-2222-4222-8222-222222222222'),
  'caio.souza|' || tests.unidade('ESCOLA_A')::text,
  'sem metadado: nome e a parte local do e-mail e a unidade e a unica ativa');

update public.unidade set ativo = true where codigo <> 'ESCOLA_A';

-- ===========================================================================
-- 3. As três formas de o espelho não saber em que unidade pôr a pessoa
-- ===========================================================================
-- Todas recusam o convite inteiro, em vez de criar um auth.users sem espelho —
-- que seria alguém capaz de autenticar e ver todas as telas vazias, sem erro.
--
-- A recusa por ambiguidade é o fallback da v1 se fechando sozinho: aqui há três
-- unidades ativas, como a escola terá mais de uma na Fase 11.
select is(
  tests.codigo_do_erro($$
    insert into auth.users (id, email, aud, role, encrypted_password,
                            email_confirmed_at, created_at, updated_at)
    values ('33333333-3333-4333-8333-333333333333', 'ambigua@escola-a.test',
            'authenticated', 'authenticated', '', now(), now(), now())
  $$),
  'USUARIO_SEM_UNIDADE',
  'duas unidades ativas e nenhum metadado: convite recusado, nao adivinhado');

select is(
  tests.codigo_do_erro($$
    insert into auth.users (id, email, aud, role, encrypted_password,
                            email_confirmed_at, created_at, updated_at,
                            raw_user_meta_data)
    values ('44444444-4444-4444-8444-444444444444', 'lixo@escola-a.test',
            'authenticated', 'authenticated', '', now(), now(), now(),
            jsonb_build_object('unidade_id', 'ESCOLA_A'))
  $$),
  'USUARIO_SEM_UNIDADE',
  'metadado de unidade que nao e uuid: erro com codigo, nao 22P02 cru');

select is(
  tests.codigo_do_erro($$
    insert into auth.users (id, email, aud, role, encrypted_password,
                            email_confirmed_at, created_at, updated_at,
                            raw_user_meta_data)
    values ('55555555-5555-4555-8555-555555555555', 'fantasma@escola-a.test',
            'authenticated', 'authenticated', '', now(), now(), now(),
            jsonb_build_object('unidade_id', '99999999-9999-4999-8999-999999999999'))
  $$),
  'USUARIO_SEM_UNIDADE',
  'unidade inexistente no metadado: convite recusado');

select is(
  tests.codigo_do_erro($$
    insert into auth.users (id, email, aud, role, encrypted_password,
                            email_confirmed_at, created_at, updated_at,
                            raw_user_meta_data)
    values ('66666666-6666-4666-8666-666666666666', null,
            'authenticated', 'authenticated', '', now(), now(), now(),
            jsonb_build_object('unidade_id', tests.unidade('ESCOLA_A')::text))
  $$),
  'USUARIO_SEM_EMAIL',
  'auth.users sem e-mail: recusado com codigo, e nao com not-null violation');

-- ===========================================================================
-- 4. Troca de e-mail no Auth: o espelho segue — e só o e-mail segue
-- ===========================================================================
-- O dado que a direção corrigiu na tela não pode ser desfeito por uma mexida no
-- Auth: se o espelho reescrevesse nome/unidade a cada update, a correção duraria
-- até a próxima troca de senha.
update public.usuario
   set nome = 'Débora Ramos', ativo = false
 where id = '11111111-1111-4111-8111-111111111111';

update auth.users
   set email = 'debora.ramos@escola-a.test',
       raw_user_meta_data = jsonb_build_object('nome', 'Nome Antigo do Convite')
 where id = '11111111-1111-4111-8111-111111111111';

select is(
  (select email from public.usuario where id = '11111111-1111-4111-8111-111111111111'),
  'debora.ramos@escola-a.test',
  'troca de e-mail no Auth propaga para o espelho');

select is(
  (select nome from public.usuario where id = '11111111-1111-4111-8111-111111111111'),
  'Débora Ramos',
  'troca no Auth NAO desfaz o nome corrigido na tela de Administracao');

select ok(
  (select not ativo from public.usuario where id = '11111111-1111-4111-8111-111111111111'),
  'troca no Auth NAO reativa usuario desativado pela direcao');

-- ===========================================================================
-- 5. O outro lado: o app não faz o espelho divergir
-- ===========================================================================
-- Sem este trigger o PATCH passaria pela RLS sem reclamar (a direção tem
-- admin.gerir_usuarios) e a tela passaria a mostrar um e-mail com o qual
-- ninguém consegue entrar. Par canônico do card 2.8 §6.2: SQLSTATE por
-- throws_ok, `codigo` pelo helper.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select throws_ok(
  $$update public.usuario
       set email = 'outro@escola-a.test'
     where id = '11111111-1111-4111-8111-111111111111'$$,
  'PT409',
  null,
  'PATCH de email em usuario levanta PT409 (PostgREST devolve 409)');

reset role;

select is(
  tests.codigo_do_erro(
    $$update public.usuario
         set email = 'outro@escola-a.test'
       where id = '11111111-1111-4111-8111-111111111111'$$,
    tests.uid('direcao@escola-a.test')),
  'EMAIL_IMUTAVEL',
  'PATCH de email em usuario devolve o codigo EMAIL_IMUTAVEL');

-- Criar usuário pela tabela, em vez de convidar, esbarra na FK — e é ela quem
-- deve falar: "não existe no Auth" não é divergência de e-mail, é ausência de
-- identidade, e a restrição diz isso com precisão (card 2.2 §1).
select throws_ok(
  $$insert into public.usuario (id, unidade_id, nome, email)
    select '77777777-7777-4777-8777-777777777777',
           tests.unidade('ESCOLA_A'), 'Sem Auth', 'inventado@escola-a.test'$$,
  '23503',
  null,
  'insert em usuario sem auth.users correspondente e barrado pela FK');

-- ===========================================================================
-- 6. Apagar a pessoa no Auth é recusado enquanto houver espelho
-- ===========================================================================
-- FK `on delete restrict` (card 3.3). Quem entregou apostila e lançou estoque
-- está em criado_por/atualizado_por de milhares de linhas: usuário sai com
-- `ativo = false`, nunca por delete.
select throws_ok(
  $$delete from auth.users where id = '11111111-1111-4111-8111-111111111111'$$,
  '23503',
  null,
  'delete em auth.users e barrado pela FK enquanto o espelho existir');

-- ===========================================================================
-- 7. fn_convites_pendentes() — quem ainda não aceitou (card 4.7,7)
-- ===========================================================================
-- O que a função responde não é "quem parece novo": é "para quem convidar de
-- novo REENVIA em vez de recusar com email_exists", e o pivô do GoTrue para
-- isso é `email_confirmed_at`. Daí os dois lados serem asserção: o convidado
-- que ainda não abriu o link aparece, e quem já definiu senha (os oito da
-- fixture, criados confirmados) não aparece — oferecer o reenvio a esse último
-- seria oferecer um botão que só sabe falhar.
--
-- Os inserts abaixo são o convite de verdade: sem `email_confirmed_at`, que é
-- exatamente como o GoTrue grava a linha do convidado.
insert into auth.users (id, email, aud, role, encrypted_password,
                        created_at, updated_at, raw_user_meta_data)
values ('88888888-8888-4888-8888-888888888888', 'pendente@escola-a.test',
        'authenticated', 'authenticated', '', now(), now(),
        jsonb_build_object('unidade_id', tests.unidade('ESCOLA_A')::text,
                           'nome', 'Pendente da Silva'));

insert into auth.users (id, email, aud, role, encrypted_password,
                        created_at, updated_at, raw_user_meta_data)
values ('99999999-9999-4999-8999-999999999999', 'pendente@escola-b.test',
        'authenticated', 'authenticated', '', now(), now(),
        jsonb_build_object('unidade_id', tests.unidade('ESCOLA_B')::text,
                           'nome', 'Pendente de Outra Unidade'));

select tests.autenticar(tests.uid('direcao@escola-a.test'));

select ok(
  exists (select 1 from public.fn_convites_pendentes() x
           where x = '88888888-8888-4888-8888-888888888888'),
  'convidado sem email_confirmed_at aparece em fn_convites_pendentes');

-- Pelo e-mail, e não por tests.uid(): depois de tests.autenticar a sessão é
-- `authenticated` e o schema `tests` fica fora de alcance (regra de ouro do
-- card 3.4.5). `public.usuario` a direção lê, que é justamente o ponto.
select ok(
  not exists (select 1
                from public.usuario u
                join public.fn_convites_pendentes() x on x = u.id
               where u.email = 'secretaria@escola-a.test'),
  'quem ja aceitou o convite NAO aparece em fn_convites_pendentes');

-- A função é security definer e o dono tem BYPASSRLS: sem o filtro no corpo,
-- a direção da ESCOLA_A veria o convidado da ESCOLA_B (correção do card 2.3).
select ok(
  not exists (select 1 from public.fn_convites_pendentes() x
               where x = '99999999-9999-4999-8999-999999999999'),
  'convidado de OUTRA unidade NAO aparece em fn_convites_pendentes');

reset role;

-- `admin.ler` é o portão, o mesmo da política usuario_sel: quem não enxerga a
-- lista não recebe o estado das linhas dela. O monitor não tem admin.ler na
-- matriz inicial (card 2.4).
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select is(
  (select count(*)::int from public.fn_convites_pendentes()),
  0,
  'sem admin.ler fn_convites_pendentes devolve vazio');

reset role;

select * from finish();
rollback;
