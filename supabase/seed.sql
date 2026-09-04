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
   $$to_regclass('public.pc') is not null$$, true,
   'APLICADA no card 4.3: uma sala com 10 PCs (capacidade real do laboratório) e uma com 6, mais uma sala modular sem PC. A borda 10/11 é o teste de lotação do card 5.3. Os seis PCs da segunda sala NÃO estão todos operacionais de propósito: capacidade nominal (6), total de PCs (6) e PCs operacionais (4) são três números distintos, e é isso que faz fn_capacidade_efetiva (card 5.2) reprovar se somar a coluna errada. Duas manutenções (uma aberta sem substituto, uma fechada) e três professores, um inativo. Nenhuma credencial: senha de fixture no repositório é o que o card 2.9 §9 recusa, e os testes de credencial gravam a sua dentro da própria transação. Desde o card 5.4 a camada roda em CONTEXTO DE ROTINA (os triggers de manutenção exigem unidade no contexto) e, por consequência, a fixture nasce com uma pendência PC_SEM_SUBSTITUTO por unidade — a do LAB2-05, GERADA pelo trigger e não semeada.'),

  ('turmas', 60, '5.1',
   $$to_regclass('public.bloco_aluno') is not null$$, true,
   'APLICADA no card 5.1: três blocos no Laboratório 1 (0, 9 e 10 alunos), os três SEM capacidade_override, para a capacidade efetiva do card 5.2 ter de sair dos 10 PCs operacionais. Os dois blocos cheios têm alunos disjuntos — reaproveitá-los faria nove alunos ATIVO ficarem com dois blocos, que é a definição de aceleração —, e por isso a camada traz treze alunos de lotação próprios, com codigo_sgf na faixa 9xxx para não mexer nas asserções do card 4.2. Lucas Ferreira fica com débito REP EXATAMENTE na borda do card 2.5, escolhida onde ceil e floor divergem; as reposições dele ficam no bloco vazio, que assim passa a ter ocupação 1 no dia da PREVISTA.'),

  ('trilha_estoque', 70, '6.1',
   $$to_regclass('public.movimento_estoque') is not null$$, true,
   'APLICADA no card 6.1: trilha dos doze alunos (menos Karina, que não tem combo) derivada do combo, três pedidos de compra — um por estado que muda alguma conta — e os movimentos que produzem os saldos 0/0/1/n/n/n do card 2.8 §4.2. Saldo 1 é o material que é o PRÓXIMO de dois alunos, que é o teste de concorrência do card 6.3; os dois saldos zero são diferentes de propósito (um com item pendente adiante = REORDENADA, um sem = BLOQUEADA_SEM_ESTOQUE). João Pedro fica em FIM, fechando a última marca do quadro §4.2 que ainda não tinha casa. Os quatro tipos de movimento aparecem, incluindo o único ESTORNO da fixture.'),

  -- Declarada aqui e não no card 7.1 porque o portão do teste 001 precisa de uma
  -- camada AINDA NÃO aplicada para vigiar: com `trilha_estoque` aplicada, ele
  -- ficaria sem sentinela e a prova por construção viraria decoração — que é
  -- exatamente a crítica do card 2.8. A nota do 001 já escrevia isso: «quando ela
  -- for aplicada, esta asserção precisa de uma camada NOVA para vigiar, e não de
  -- uma sentinela nova».
  ('modular', 80, '7.1',
   $$to_regclass('public.turma_modular_aluno') is not null$$, false,
   'Turma Modular de Eletricista com o cronograma dos três módulos e Eduarda Lima dentro. A fixture já tem o método, o curso, os três módulos (card 4.1) e a aluna (4.2) — falta a turma, que é o que torna fn_aluno_status_desaloca capaz de citar turma_modular_aluno (portão do teste 040 §10).');

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
-- 6. Escola-fixture — camada `infra_fisica` (card 4.3)
-- =============================================================================
-- Três salas e dezesseis PCs, escolhidos para exercitar bordas — não para
-- parecer com a escola. Quatro escolhas que valem explicação:
--
--   (a) o laboratório tem EXATAMENTE 10 PCs operacionais, que é a capacidade
--       real do laboratório (Decisões vigentes, 31/08/2026). A borda 10/11 é o
--       teste de lotação do card 5.3: o 11º aluno tem de bater em BLOCO_LOTADO,
--       e uma fixture com 9 ou com 12 PCs passaria sem exercitar isso.
--
--   (b) na segunda sala, capacidade nominal (6), total de PCs (6) e PCs
--       OPERACIONAIS (4) são TRÊS NÚMEROS DISTINTOS. É o que faz
--       `fn_capacidade_efetiva` (card 5.2) reprovar quando somar a coluna
--       errada — com os três iguais, a função passaria contando qualquer coisa.
--       Um PC em MANUTENCAO e um DESATIVADO: os dois saem da conta, e são
--       estados diferentes que o card 5.4 trata de forma diferente.
--
--   (c) as duas manutenções são de tipos opostos de propósito: uma ABERTA
--       (`data_fim` nulo) e sem substituto — o caso que derruba a capacidade e
--       abre a pendência do card 5.4 — e uma FECHADA, que é histórico e não
--       muda capacidade nenhuma. Uma fixture só com manutenção aberta faria
--       "manutenção" e "PC parado" parecerem a mesma coisa.
--
--   (d) NENHUMA credencial é gravada aqui. Senha de fixture no repositório é
--       exatamente o que o card 2.9 recusa, e o varredor de segredos do card
--       3.11 já reprovou este projeto duas vezes por linhas que apenas PARECEM
--       uma senha. Os testes de credencial gravam a sua com
--       `fn_pc_credencial_gravar` dentro da própria transação, e ela morre no
--       rollback.
--
-- Os PCs dos dois laboratórios TÊM histórico (manutenção), e é isso que dá ao
-- teste da guarda de exclusão do card 4.3 os dois lados: um PC que recusa ser
-- apagado e um que aceita.
--
-- ⚠️ ESTA CAMADA PASSOU A RODAR EM CONTEXTO DE ROTINA NO CARD 5.4, pelo mesmo
--    motivo e com a mesma escolha da camada `turmas` (ver a nota da seção 7): o
--    `insert` em `pc_manutencao` dispara `tg_pc_manutencao_status` e
--    `tg_pc_revalida_blocos`, e os dois acabam em funções que exigem unidade no
--    contexto. O seed roda como `postgres`, sem `auth.uid()`: sem o contexto,
--    `fn_unidade_atual()` é nula e o `supabase db reset` inteiro morre no
--    primeiro PC. A saída RECUSADA foi tratar unidade nula como "não faz nada"
--    dentro das funções — isso seria um contorno permanente em produção,
--    escrito para acomodar um arquivo de teste (card 5.3).
--
--    CONSEQUÊNCIA QUE VALE ESCREVER, porque muda uma asserção do teste 090: a
--    fixture passa a NASCER com uma pendência `PC_SEM_SUBSTITUTO` por unidade —
--    a do LAB2-05, que está em manutenção aberta e sem substituto por desenho
--    (nota (c) acima). Ela não é semeada: é GERADA pelo trigger do card 5.4, a
--    partir do dado que a fixture escreve, e é exatamente o que a regra manda
--    acontecer. Uma fixture com esse PC parado e sem pendência nenhuma diria que
--    a regra não vale.
create or replace function tests.seed_infra_fisica(p_unidade uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_lab      uuid;
  v_lab2     uuid;
  v_pc_manut uuid;
  v_pc_ok    uuid;
begin
  -- Contexto de rotina (ver a nota ⚠️ acima). `is_local => true`: morre no fim
  -- da transação mesmo se o `insert` falhar no meio.
  perform set_config('app.rotina', 'on', true);
  perform set_config('app.rotina_unidade', p_unidade::text, true);

  insert into sala (unidade_id, nome, tipo, capacidade_nominal)
  select p_unidade, s.nome, s.tipo, s.cap
    from (values
      ('Laboratório 1',      'LABORATORIO',  10),
      ('Laboratório 2',      'LABORATORIO',   6),
      ('Sala Eletricista',   'SALA_MODULAR', 15)
    ) as s(nome, tipo, cap)
   where not exists (select 1 from sala x
                      where x.unidade_id = p_unidade and x.nome = s.nome);

  select id into v_lab  from sala where unidade_id = p_unidade and nome = 'Laboratório 1';
  select id into v_lab2 from sala where unidade_id = p_unidade and nome = 'Laboratório 2';

  -- Laboratório 1: dez PCs, todos operacionais. LAB1-01 .. LAB1-10.
  insert into pc (unidade_id, sala_id, identificador, status)
  select p_unidade, v_lab, format('LAB1-%s', lpad(i::text, 2, '0')), 'OPERACIONAL'
    from generate_series(1, 10) as i
   where not exists (select 1 from pc x
                      where x.unidade_id = p_unidade
                        and x.identificador = format('LAB1-%s', lpad(i::text, 2, '0')));

  -- Laboratório 2: seis PCs, quatro operacionais.
  insert into pc (unidade_id, sala_id, identificador, status)
  select p_unidade, v_lab2, p.identificador, p.status
    from (values
      ('LAB2-01', 'OPERACIONAL'),
      ('LAB2-02', 'OPERACIONAL'),
      ('LAB2-03', 'OPERACIONAL'),
      ('LAB2-04', 'OPERACIONAL'),
      ('LAB2-05', 'MANUTENCAO'),
      ('LAB2-06', 'DESATIVADO')
    ) as p(identificador, status)
   where not exists (select 1 from pc x
                      where x.unidade_id = p_unidade and x.identificador = p.identificador);

  select id into v_pc_manut from pc where unidade_id = p_unidade and identificador = 'LAB2-05';
  select id into v_pc_ok    from pc where unidade_id = p_unidade and identificador = 'LAB1-01';

  -- Aberta e sem substituto: é a que derruba a capacidade efetiva do bloco.
  insert into pc_manutencao (unidade_id, pc_id, tipo, data_inicio, descricao)
  select p_unidade, v_pc_manut, 'CORRETIVA', fn_hoje() - 3, 'fonte queimada'
   where not exists (select 1 from pc_manutencao m where m.pc_id = v_pc_manut);

  -- Fechada: histórico, não muda capacidade nenhuma.
  insert into pc_manutencao (unidade_id, pc_id, tipo, data_inicio, data_fim, descricao)
  select p_unidade, v_pc_ok, 'PREVENTIVA', fn_hoje() - 60, fn_hoje() - 59, 'limpeza e atualização'
   where not exists (select 1 from pc_manutencao m where m.pc_id = v_pc_ok);

  -- Três professores, um inativo — o inativo é o que prova que a grade do card
  -- 5.6 filtra por `ativo` em vez de listar todo mundo que já deu aula.
  insert into professor (unidade_id, nome, ativo)
  select p_unidade, pr.nome, pr.ativo
    from (values
      ('Marcos Vieira',  true),
      ('Renata Alves',   true),
      ('Otávio Pacheco', false)
    ) as pr(nome, ativo)
   where not exists (select 1 from professor x
                      where x.unidade_id = p_unidade and x.nome = pr.nome);

  perform set_config('app.rotina', '', true);
  perform set_config('app.rotina_unidade', '', true);
end $$;

-- As duas unidades recebem a mesma infraestrutura, com os MESMOS
-- identificadores de PC: `pc_identificador_uk` é único por UNIDADE, então
-- repetir entre unidades é exatamente o caso que a unique precisa aceitar — e
-- recusaria se estivesse escrita sem o unidade_id.
select tests.seed_infra_fisica(tests.unidade('ESCOLA_A'));
select tests.seed_infra_fisica(tests.unidade('ESCOLA_B'));

-- =============================================================================
-- 7. Escola-fixture — camada `turmas` (card 5.1)
-- =============================================================================
-- Três blocos com 0, 9 e 10 alunos (card 2.8 §4.2), os três no Laboratório 1,
-- que tem exatamente 10 PCs OPERACIONAIS — a capacidade efetiva sai dos PCs
-- (card 5.2) e não de `capacidade_override`, que fica nulo de propósito nos
-- três: um override aqui esconderia justamente a conta que o 5.2 precisa provar.
--
-- Cinco escolhas que valem explicação:
--
--   (a) os dois blocos cheios têm alunos DISJUNTOS, e é por isso que a camada
--       traz treze alunos próprios. Reaproveitar os mesmos alunos nos dois
--       custaria zero linhas e faria nove alunos ATIVO ficarem com dois blocos
--       — que pela decisão de 31/08/2026 é a definição de ACELERAÇÃO. A fixture
--       passaria a afirmar, sem querer, que nove alunos estão acelerando, e a
--       rotina do card 5.5 leria isso como verdade.
--
--   (b) o de 9 aceita o décimo e o de 10 recusa o décimo primeiro SEM DEPENDER
--       DE ORDEM: são dois blocos distintos na mesma unidade, então o teste de
--       lotação do card 5.3 não precisa admitir alguém para depois testar o
--       estouro — teste que monta o próprio cenário é teste que passa porque
--       montou o cenário que queria.
--
--   (c) os treze alunos de lotação têm `codigo_sgf` na faixa 9xxx e NENHUM
--       nulo, de propósito: as asserções do card 4.2 sobre os três alunos sem
--       código continuam valendo palavra por palavra, e a única asserção do
--       teste 030 que precisou mudar foi a contagem total, que passou a dizer a
--       soma das duas camadas.
--
--   (d) as reposições de Lucas Ferreira ficam no bloco VAZIO, não no dele. Duas
--       coisas de graça: o bloco de 0 alunos passa a ter ocupação 1 no dia da
--       reposição PREVISTA, que é a asserção que reprova uma `fn_ocupacao_bloco`
--       (card 5.2) que somou só `bloco_aluno` e esqueceu a metade pontual do
--       REP; e a lotação dos outros dois blocos não se mexe.
--
--   (e) o débito de Lucas fica EXATAMENTE na borda do critério do card 2.5, e a
--       borda foi escolhida onde `ceil` e `floor` divergem. Três aulas perdidas
--       em aberto (FALTOU, CANCELADA e PREVISTA — as três contam, §3.2), a mais
--       antiga em `fn_hoje() - 10`: prazo_final = hoje + 20, semanas_uteis =
--       ceil(20/7) = 3, limite = rep_capacidade_semanal × 3 = 3, e 3 > 3 é
--       falso — VIÁVEL. Uma quarta aula perdida vira o veredito, que é a borda
--       que o card 5.3 vai testar nos dois sentidos. Com `floor` daria 2 e o
--       mesmo cenário reprovaria: a fixture distingue as duas implementações em
--       vez de passar nas duas. A quarta linha é REALIZADA e mais ANTIGA que
--       todas (origem em hoje - 20): aula quitada não conta, então uma
--       implementação que tome `min(data_origem)` sem filtrar as quitadas acha
--       prazo vencido e sugere a virada — e a fixture a reprova.
--
-- ⚠️ PARA O CARD 5.3, e é bloqueante lá: três destas reposições têm `data` no
--    PASSADO (FALTOU e CANCELADA não têm como não ter), e o seed roda como
--    `postgres`, sem `auth.uid()` e fora do contexto de rotina — `tem_permissao`
--    devolve falso. O `tg_reposicao_admissao` do card 2.2 §4.3 exige
--    `turmas.lancar_reposicao_retroativa` para data no passado: escrito sem uma
--    saída para esse contexto, ele derruba o `supabase db reset` inteiro, e o
--    sintoma aparece longe da causa.
--
--    ✅ RESOLVIDO NO CARD 5.3 (03/09/2026), e a escolha importa: a saída NÃO foi
--    uma exceção dentro do trigger para "quando não há sessão" — isso seria um
--    contorno permanente em produção, escrito para acomodar um arquivo de teste.
--    Foi esta camada passar a rodar no CONTEXTO DE ROTINA (card 2.2 §2.2), que é
--    o mesmo que `tests.como_rotina` dá aos testes e o mesmo em que
--    fn_revalidar_blocos_sala (5.4) e rt_pendencias_diaria (5.5) vão escrever.
--    Duas consequências, as duas boas: `tem_permissao` responde verdadeiro e a
--    reposição retroativa passa; e `fn_unidade_atual()` deixa de ser nula, de
--    modo que fn_capacidade_efetiva enxerga o bloco e **a fixture passa a ser
--    validada pelas regras de verdade** — os dez alunos do bloco cheio entram
--    porque cabem, e um décimo primeiro na fixture reprovaria o `db reset` em
--    voz alta, em vez de criar 11 alunos em 10 PCs para os testes do 5.2 e do
--    5.3 medirem.
create or replace function tests.seed_turmas(p_unidade uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_lab     uuid;
  v_metodo  uuid;
  v_combo   uuid;
  v_vazio   uuid;
  v_quase   uuid;
  v_cheio   uuid;
  v_lucas   uuid;
begin
  -- Contexto de rotina (ver a nota ⚠️ acima). `is_local => true`: morre no fim
  -- da transação mesmo se o `insert` falhar no meio, e o `reset` do fim existe
  -- para o caso de o seed inteiro rodar numa transação só.
  perform set_config('app.rotina', 'on', true);
  perform set_config('app.rotina_unidade', p_unidade::text, true);

  select id into v_lab    from sala   where unidade_id = p_unidade and nome = 'Laboratório 1';
  select id into v_metodo from metodo where unidade_id = p_unidade and codigo = 'INTERATIVO';
  select id into v_combo  from combo  where unidade_id = p_unidade and nome = 'Informática Completo';

  -- Treze alunos que existem só para ocupar vaga. Nomeados pelo que são: um
  -- "Aluno de Lotação" não é um caso de negócio disfarçado, e quem ler a fixture
  -- daqui a três meses não vai procurar qual decisão o criou.
  insert into aluno (unidade_id, codigo_sgf, nome, metodo_id, combo_id, status,
                     status_desde, data_inicio)
  select p_unidade, format('9%s', lpad(i::text, 3, '0')),
         format('Aluno de Lotação %s', lpad(i::text, 2, '0')),
         v_metodo, v_combo, 'ATIVO', fn_hoje() - 30, fn_hoje() - 30
    from generate_series(1, 13) as i
   where not exists (select 1 from aluno a
                      where a.unidade_id = p_unidade
                        and a.codigo_sgf = format('9%s', lpad(i::text, 3, '0')));

  -- Os três blocos. O de 10 fica SEM professor de propósito: `professor_id` é
  -- opcional e a grade do card 5.6 o lê por `left join` — um bloco sem
  -- professor é o que reprova a grade que usa join interno e some com a linha.
  insert into bloco_horario (unidade_id, dia_semana, hora_inicio, metodo_id,
                             professor_id, sala_id)
  select p_unidade, b.dia, b.hora, v_metodo,
         (select id from professor where unidade_id = p_unidade and nome = b.professor),
         v_lab
    from (values
      (1, time '08:00', 'Marcos Vieira'),
      (2, time '08:00', 'Renata Alves'),
      (3, time '08:00', null)
    ) as b(dia, hora, professor)
   where not exists (select 1 from bloco_horario x
                      where x.unidade_id = p_unidade and x.sala_id = v_lab
                        and x.dia_semana = b.dia and x.hora_inicio = b.hora);

  select id into v_vazio from bloco_horario
   where unidade_id = p_unidade and sala_id = v_lab and dia_semana = 1;
  select id into v_quase from bloco_horario
   where unidade_id = p_unidade and sala_id = v_lab and dia_semana = 2;
  select id into v_cheio from bloco_horario
   where unidade_id = p_unidade and sala_id = v_lab and dia_semana = 3;

  -- Bloco CHEIO (10/10): os seis alunos ATIVO de método INTERATIVO da camada
  -- `alunos` mais quatro de lotação. Os de caso entram aqui, e não no de 9,
  -- porque é deles que o card 5.3 precisa para exercitar
  -- `tg_aluno_status_desaloca`: mudar o status de um aluno que TEM alocação.
  insert into bloco_aluno (unidade_id, bloco_id, aluno_id, tipo, data_inicio_prevista,
                           tipo_desde)
  select p_unidade, v_cheio, a.id, x.tipo,
         case when x.tipo = 'NOVO' then fn_hoje() + 7 end,
         fn_hoje() - 30
    from (values
      ('Ana Paula Ribeiro',    'REM'),
      ('Bruno Carvalho',       'REM'),
      ('Carla Menezes',        'REM'),
      ('Diego Alves',          'PRE'),
      ('Karina Bastos',        'NOVO'),
      ('Lucas Ferreira',       'REM'),
      ('Aluno de Lotação 01',  'REM'),
      ('Aluno de Lotação 02',  'REM'),
      ('Aluno de Lotação 03',  'REM'),
      ('Aluno de Lotação 04',  'REM')
    ) as x(nome, tipo)
    join aluno a on a.unidade_id = p_unidade and a.nome = x.nome
   where not exists (select 1 from bloco_aluno ba
                      where ba.bloco_id = v_cheio and ba.aluno_id = a.id);

  -- Bloco QUASE CHEIO (9/10): nove de lotação, um deles em REP CONTÍNUO com o
  -- relógio já fora da carência de volta (rep_janela_volta_dias = 30). É o único
  -- aluno da fixture com `tipo = 'REP'`, e serve a dois testes opostos: a
  -- contagem de aceleração do card 5.5, que precisa FILTRAR tipo <> 'REP'
  -- (ajuste 4 do card 2.5), e o `fn_rep_voltar_pontual` do 5.3, que sem a
  -- carência vencida não teria como devolver "pode voltar".
  insert into bloco_aluno (unidade_id, bloco_id, aluno_id, tipo, tipo_desde)
  select p_unidade, v_quase, a.id, x.tipo, fn_hoje() - x.desde_ha
    from (values
      ('Aluno de Lotação 05',  'REM', 30),
      ('Aluno de Lotação 06',  'REM', 30),
      ('Aluno de Lotação 07',  'REM', 30),
      ('Aluno de Lotação 08',  'REM', 30),
      ('Aluno de Lotação 09',  'PRE', 30),
      ('Aluno de Lotação 10',  'REM', 30),
      ('Aluno de Lotação 11',  'REM', 30),
      ('Aluno de Lotação 12',  'REM', 30),
      ('Aluno de Lotação 13',  'REP', 40)
    ) as x(nome, tipo, desde_ha)
    join aluno a on a.unidade_id = p_unidade and a.nome = x.nome
   where not exists (select 1 from bloco_aluno ba
                      where ba.bloco_id = v_quase and ba.aluno_id = a.id);

  -- Lucas Ferreira, débito na borda — ver a nota (e) acima.
  select id into v_lucas from aluno where unidade_id = p_unidade and nome = 'Lucas Ferreira';

  insert into bloco_aluno_reposicao (unidade_id, bloco_id, aluno_id, data,
                                     bloco_origem_id, data_origem, status, observacao)
  select p_unidade, v_vazio, v_lucas, fn_hoje() + r.data_em,
         v_cheio, fn_hoje() + r.origem_em, r.status, r.observacao
    from (values
      (-16, -20, 'REALIZADA', 'aula quitada: NAO entra no debito nem na aula mais antiga'),
      ( -9, -10, 'FALTOU',    'em aberto, e a mais antiga: e ela que define o prazo'),
      ( -5,  -6, 'CANCELADA', 'em aberto: desmarcada e nao remarcada (card 2.5 §3.2)'),
      (  3,  -2, 'PREVISTA',  'em aberto, e a unica que ocupa vaga — no bloco vazio')
    ) as r(data_em, origem_em, status, observacao)
   where not exists (select 1 from bloco_aluno_reposicao br
                      where br.bloco_id = v_vazio and br.aluno_id = v_lucas
                        and br.data = fn_hoje() + r.data_em);

  perform set_config('app.rotina', '', true);
  perform set_config('app.rotina_unidade', '', true);
end $$;

-- As duas unidades recebem os mesmos blocos, no mesmo dia e horário e com os
-- mesmos códigos SGF de lotação: `bloco_horario_uk` e `aluno_codigo_sgf_uk` são
-- únicos por UNIDADE, então repetir entre unidades é exatamente o caso que as
-- duas uniques precisam aceitar — e recusariam se estivessem escritas sem o
-- unidade_id.
select tests.seed_turmas(tests.unidade('ESCOLA_A'));
select tests.seed_turmas(tests.unidade('ESCOLA_B'));

-- =============================================================================
-- 8. Escola-fixture — camada `trilha_estoque` (card 6.1)
-- =============================================================================
-- Fecha o quadro do card 2.8 §4.2: os seis materiais ganham os saldos
-- **0, 0, 1, n, n, n** e os doze alunos ganham trilha — inclusive o "1 em FIM",
-- que era a última marca do quadro ainda sem casa (as outras duas foram para as
-- camadas `alunos` e `turmas`).
--
-- Cinco escolhas que valem explicação:
--
--   (a) OS SALDOS SÃO DERIVADOS, não escritos. Cada saldo é a soma dos
--       movimentos que o produziram — entradas de pedido, entradas manuais,
--       saídas de entrega, um ajuste e um estorno. Escrever "saldo = 1" numa
--       coluna seria testar uma coluna que o projeto decidiu não ter; o que se
--       quer provar é que `sum(quantidade)` dá o número certo.
--
--   (b) O SALDO 1 É DE `INTERATIVO 03`, E ELE É O PRÓXIMO DE DOIS ALUNOS (Ana
--       Paula e Bruno, os dois com 01 e 02 entregues). É exatamente o cenário do
--       teste de concorrência do card 6.3: duas sessões disputando o último
--       exemplar, uma ENTREGUE e a outra REORDENADA — e ele não existe se o
--       último exemplar for o próximo de uma pessoa só.
--
--   (c) OS DOIS SALDOS ZERO SÃO DIFERENTES DE PROPÓSITO. `INTERATIVO 02` é o
--       próximo de Diego e de Lucas, que TÊM outro item pendente adiante (o 03):
--       é o caso `REORDENADA`. `INGLES 02` é o próximo de Felipe e é o ÚNICO
--       item pendente dele: é o caso `BLOQUEADA_SEM_ESTOQUE`. Dois zeros iguais
--       exercitariam um ramo só, e o outro passaria sem nunca ter rodado.
--
--   (d) OS QUATRO TIPOS DE MOVIMENTO APARECEM. ENTRADA e SAIDA sozinhas
--       deixariam `movimento_sinal_ck` e `movimento_estorno_ck` sem contraprova,
--       e `movimento_estorno_uk` sem nenhuma linha para vigiar. O AJUSTE negativo
--       (extravio de `INGLES 02`) é o que faz um saldo cair sem entrega nenhuma;
--       o ESTORNO devolve ao estoque a entrega de Eduarda, que por isso volta a
--       ter o livro dela PENDENTE — o par saída-estorno é o estado que o card 6.3
--       precisa encontrar já pronto.
--
--   (e) UM PEDIDO POR ESTADO QUE MUDA ALGUMA CONTA: RECEBIDO (com a ENTRADA
--       vinculada ao item, que é o vínculo compra ↔ estoque que a planilha não
--       tinha), ENVIADO (a parcela "já pedida" que o pedido sugerido do card 2.3
--       §6 (d) abate) e RASCUNHO (que NÃO abate, e é também o único item que a
--       guarda de exclusão da seção 10.2 da migração deixa remover). Sem os três,
--       a view do card 6.4 passaria somando o RASCUNHO ou deixando de somar o
--       ENVIADO, que é o mesmo erro nas duas direções.
--
-- ⚠️ Os quatro degraus da cascata da projeção (card 8.1) precisam de intervalos
--    entre entregas, e é por isso que as datas de entrega aqui são escalonadas e
--    relativas a fn_hoje(). O que a camada NÃO faz é afirmar qual degrau cada
--    aluno cai: isso depende de parâmetros e de v_ritmo_aluno, que são do card
--    8.1 — e é lá que esta camada cresce, se precisar.

create or replace function tests.seed_trilha_estoque(p_unidade uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  r         record;
  v_item    uuid;
  v_mov     uuid;
  v_saida   uuid;
begin
  -- -------------------------------------------------------------------------
  -- 8.1 Pedidos de compra — um por estado que muda alguma conta
  -- -------------------------------------------------------------------------
  insert into pedido_compra (unidade_id, numero, status, data_envio, fornecedor)
  select p_unidade, s.numero, s.status,
         case when s.envio_ha is null then null else fn_hoje() - s.envio_ha end,
         s.fornecedor
    from (values
      ('2026-001', 'RECEBIDO', 120, 'Editora Interativa'),
      ('2026-002', 'ENVIADO',   10, 'Editora Interativa'),
      ('2026-003', 'RASCUNHO', null, null)
    ) as s(numero, status, envio_ha, fornecedor)
   where not exists (select 1 from pedido_compra p
                      where p.unidade_id = p_unidade and p.numero = s.numero);

  insert into pedido_item (unidade_id, pedido_id, material_id, qtd_pedida, qtd_recebida)
  select p_unidade, pc.id, m.id, s.pedida, s.recebida
    from (values
      ('2026-001', 'INTERATIVO', '01', 26, 26),
      ('2026-002', 'INTERATIVO', '02', 10,  0),
      ('2026-002', 'INGLES',     '02',  5,  0),
      ('2026-003', 'INTERATIVO', '03',  5,  0)
    ) as s(numero, metodo, material, pedida, recebida)
    join pedido_compra pc on pc.unidade_id = p_unidade and pc.numero = s.numero
    join metodo   me on me.unidade_id = p_unidade and me.codigo = s.metodo
    join material m  on m.unidade_id  = p_unidade and m.metodo_id = me.id
                    and m.codigo = s.material
   where not exists (select 1 from pedido_item pi
                      where pi.pedido_id = pc.id and pi.material_id = m.id);

  -- -------------------------------------------------------------------------
  -- 8.2 Entradas de estoque
  -- -------------------------------------------------------------------------
  -- A primeira vem de um pedido e carrega `pedido_item_id`; as outras são
  -- entrada manual, que é um caso real (card 6.7) e o único jeito de o estoque
  -- inicial existir antes de haver pedido nenhum.
  select pi.id into v_item
    from pedido_item pi
    join pedido_compra pc on pc.id = pi.pedido_id
    join material m on m.id = pi.material_id
   where pc.unidade_id = p_unidade and pc.numero = '2026-001';

  insert into movimento_estoque (unidade_id, material_id, tipo, quantidade,
                                 ocorrido_em, pedido_item_id, observacao)
  select p_unidade, m.id, 'ENTRADA', s.qtd, now() - (s.dias || ' days')::interval,
         case when s.do_pedido then v_item else null end,
         s.observacao
    from (values
      ('INTERATIVO', '01', 26, 120, true,  'chegada do pedido 2026-001'),
      ('INTERATIVO', '02',  3, 118, false, 'entrada manual: sobra de remessa antiga'),
      ('INTERATIVO', '03',  2, 118, false, 'entrada manual: o ultimo exemplar mora aqui'),
      ('INGLES',     '01', 11, 115, false, 'entrada manual'),
      ('INGLES',     '02',  5, 115, false, 'entrada manual'),
      ('MODULAR',    '01', 10, 115, false, 'entrada manual')
    ) as s(metodo, material, qtd, dias, do_pedido, observacao)
    join metodo   me on me.unidade_id = p_unidade and me.codigo = s.metodo
    join material m  on m.unidade_id  = p_unidade and m.metodo_id = me.id
                    and m.codigo = s.material
   where not exists (select 1 from movimento_estoque mv
                      where mv.unidade_id = p_unidade and mv.material_id = m.id
                        and mv.tipo = 'ENTRADA');

  -- Extravio de `INGLES 02`: é o AJUSTE negativo, e é ele que leva o saldo a
  -- zero SEM nenhuma entrega — o caso que uma fixture só com saídas não teria.
  insert into movimento_estoque (unidade_id, material_id, tipo, quantidade,
                                 ocorrido_em, observacao)
  select p_unidade, m.id, 'AJUSTE', -5, now() - interval '100 days',
         'conferencia de prateleira: cinco exemplares extraviados'
    from metodo   me
    join material m on m.unidade_id = p_unidade and m.metodo_id = me.id and m.codigo = '02'
   where me.unidade_id = p_unidade and me.codigo = 'INGLES'
     and not exists (select 1 from movimento_estoque mv
                      where mv.unidade_id = p_unidade and mv.material_id = m.id
                        and mv.tipo = 'AJUSTE');

  -- -------------------------------------------------------------------------
  -- 8.3 A trilha inteira, derivada do combo
  -- -------------------------------------------------------------------------
  -- A `ordem` sai de combo_curso.ordem × curso_material.ordem, que é a mesma
  -- cadeia que a função do card 6.2 vai percorrer — e é por isso que ela é
  -- calculada e não digitada: uma trilha escrita à mão aqui deixaria o 6.2 sem
  -- nada contra o que comparar o resultado dele.
  --
  -- ⚠️ O `row_number()` sobre as DUAS ordens é a parte que não pode simplificar:
  --    `curso_material.ordem` é a posição dentro do CURSO, então o combo de
  --    Informática (dois cursos) tem duas apostilas com `cm.ordem = 1`, e usá-la
  --    direto derrubaria a inserção em `aluno_material_ordem_uk` — ou, pior num
  --    combo de um curso só, passaria e deixaria a fixture com a ordem errada
  --    sem nada acusando.
  --
  -- Karina Bastos NÃO ganha trilha, e é a decisão: ela é a aluna sem combo da
  -- camada `alunos`, e aluno ATIVO sem trilha é exatamente o que a pendência do
  -- card 6.2 existe para acusar.
  --
  -- Os treze `Aluno de Lotação` da camada `turmas` GANHAM trilha, e isso não é
  -- efeito colateral aceito de má vontade: eles são ATIVO e têm combo, então um
  -- deles sem trilha seria uma pendência FALSA na fixture — a mesma que a
  -- pendência do card 6.2 vai abrir. O preço é conhecido e está escrito: a
  -- demanda imediata de `INTERATIVO 01` (card 6.4) conta treze alunos a mais do
  -- que a leitura ingênua "doze alunos na fixture" sugere.
  insert into aluno_material (unidade_id, aluno_id, material_id, ordem, origem)
  select p_unidade, a.id, cm.material_id,
         row_number() over (partition by a.id order by cc.ordem, cm.ordem),
         'COMBO'
    from aluno a
    join combo_curso cc on cc.combo_id = a.combo_id and cc.unidade_id = p_unidade
    join curso_material cm on cm.curso_id = cc.curso_id and cm.unidade_id = p_unidade
   where a.unidade_id = p_unidade
     and not exists (select 1 from aluno_material am
                      where am.aluno_id = a.id and am.material_id = cm.material_id);

  -- -------------------------------------------------------------------------
  -- 8.4 As entregas: uma SAIDA por item entregue, e o vínculo na trilha
  -- -------------------------------------------------------------------------
  -- As datas são escalonadas porque a projeção do card 8.1 mede INTERVALO entre
  -- entregas: uma fixture com todas as entregas no mesmo dia daria ritmo zero
  -- para todo mundo e o degrau RITMO_ALUNO passaria sem nunca ser exercitado.
  for r in
    select a.id as aluno_id, m.id as material_id, s.dias
      from (values
        ('Ana Paula Ribeiro',  'INTERATIVO', '01', 150),
        ('Ana Paula Ribeiro',  'INTERATIVO', '02',  90),
        ('Bruno Carvalho',     'INTERATIVO', '01',  80),
        ('Bruno Carvalho',     'INTERATIVO', '02',  20),
        ('Diego Alves',        'INTERATIVO', '01', 100),
        ('Henrique Dias',      'INTERATIVO', '01', 280),
        ('João Pedro Martins', 'INTERATIVO', '01', 380),
        ('João Pedro Martins', 'INTERATIVO', '02', 300),
        ('João Pedro Martins', 'INTERATIVO', '03', 200),
        ('Lucas Ferreira',     'INTERATIVO', '01',  40),
        ('Felipe Nunes',       'INGLES',     '01', 100)
      ) as s(aluno, metodo, material, dias)
      join aluno    a  on a.unidade_id  = p_unidade and a.nome = s.aluno
      join metodo   me on me.unidade_id = p_unidade and me.codigo = s.metodo
      join material m  on m.unidade_id  = p_unidade and m.metodo_id = me.id
                      and m.codigo = s.material
     where exists (select 1 from aluno_material am
                    where am.aluno_id = a.id and am.material_id = m.id
                      and not am.entregue)
  loop
    insert into movimento_estoque (unidade_id, material_id, tipo, quantidade,
                                   ocorrido_em, aluno_id, observacao)
    values (p_unidade, r.material_id, 'SAIDA', -1,
            now() - (r.dias || ' days')::interval, r.aluno_id,
            'entrega ao aluno')
    returning id into v_mov;

    -- O UPDATE toca só as três colunas da ENTREGA, que são exatamente as que
    -- tg_aluno_material_colunas_permitidas deixa fora da lista guardada — a
    -- fixture percorre o mesmo caminho que fn_registrar_entrega (card 6.3)
    -- percorrerá, e não um atalho que o sistema real não tem.
    update aluno_material
       set entregue = true,
           data_entrega = fn_hoje() - r.dias,
           movimento_estoque_id = v_mov
     where aluno_id = r.aluno_id and material_id = r.material_id;
  end loop;

  -- -------------------------------------------------------------------------
  -- 8.5 O par saída + estorno de Eduarda (Modular)
  -- -------------------------------------------------------------------------
  -- A entrega aconteceu e foi desfeita: o livro voltou ao estoque, a trilha
  -- voltou a PENDENTE e as DUAS linhas de movimento continuam lá. É o contrato
  -- do estorno (card 2.2 §6.3) já materializado — e a única linha da fixture com
  -- `estorno_de_id`, que é o que dá a `movimento_estorno_uk` algo para vigiar.
  select mv.id into v_saida
    from movimento_estoque mv
    join material m on m.id = mv.material_id
    join metodo me on me.id = m.metodo_id and me.codigo = 'MODULAR'
   where mv.unidade_id = p_unidade and mv.tipo = 'SAIDA' and m.codigo = '01';

  if v_saida is null then
    insert into movimento_estoque (unidade_id, material_id, tipo, quantidade,
                                   ocorrido_em, aluno_id, observacao)
    select p_unidade, m.id, 'SAIDA', -1, now() - interval '50 days', a.id,
           'entrega ao aluno (desfeita 5 dias depois)'
      from metodo me
      join material m on m.unidade_id = p_unidade and m.metodo_id = me.id and m.codigo = '01'
      join aluno a on a.unidade_id = p_unidade and a.nome = 'Eduarda Lima'
     where me.unidade_id = p_unidade and me.codigo = 'MODULAR'
    returning id into v_saida;

    insert into movimento_estoque (unidade_id, material_id, tipo, quantidade,
                                   ocorrido_em, aluno_id, estorno_de_id, observacao)
    select p_unidade, mv.material_id, 'ESTORNO', 1,
           now() - interval '45 days', mv.aluno_id, mv.id,
           'estorno: livro entregue por engano'
      from movimento_estoque mv where mv.id = v_saida;
  end if;
end $$;

comment on function tests.seed_trilha_estoque(uuid) is
  'Camada `trilha_estoque` da escola-fixture (card 6.1): trilha dos doze alunos e os movimentos que produzem os saldos 0/0/1/n/n/n do card 2.8 §4.2.';

-- As duas unidades recebem a mesma trilha e o mesmo estoque: números iguais dos
-- dois lados é o que torna a asserção de isolamento comparável — e
-- `pedido_compra_numero_uk` é única por UNIDADE, então repetir `2026-001` entre
-- elas é exatamente o caso que a unique precisa aceitar.
select tests.seed_trilha_estoque(tests.unidade('ESCOLA_A'));
select tests.seed_trilha_estoque(tests.unidade('ESCOLA_B'));

-- =============================================================================
-- 9. Fecho: nada em `tests` alcançável por quem não é `postgres`
-- =============================================================================
-- `create function` concede EXECUTE a PUBLIC por padrão. A revogação do USAGE no
-- schema já bastaria, mas as duas juntas sobrevivem a alguém conceder o schema
-- sem pensar.
revoke all on all functions in schema tests from public, anon, authenticated;
revoke all on all tables    in schema tests from public, anon, authenticated;
