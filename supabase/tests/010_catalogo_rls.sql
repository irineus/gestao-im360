-- =============================================================================
-- Suíte de catálogo — RLS (C1 e C4 do card 2.8, §5.1)
-- Nasce no card 3.3 e cresce a cada migração.
--
-- Roda com `supabase test db` (stack local). Não executa regra de negócio
-- nenhuma: só interroga o catálogo do Postgres.
-- =============================================================================

begin;
select plan(5);

-- A lista de tabelas de negócio é derivada do catálogo, não escrita à mão: é o
-- que faz a suíte crescer sozinha quando uma migração nova cria tabela.
create temporary view t_negocio as
  select c.oid, c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'r'
     and c.relname not like 'pg\_%';

-- ---------------------------------------------------------------------------
-- Guarda da própria suíte: catálogo vazio faz toda asserção agregada passar.
-- ---------------------------------------------------------------------------
select cmp_ok(
  (select count(*) from t_negocio)::bigint, '>=', 7::bigint,
  'ha ao menos as 7 tabelas do card 3.3 no schema public'
);

-- ---------------------------------------------------------------------------
-- C1 — toda tabela de negócio tem RLS habilitada E forçada (card 2.1 (b))
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(t.relname, ', ' order by t.relname), '')
     from t_negocio t
     join pg_class c on c.oid = t.oid
    where not c.relrowsecurity or not c.relforcerowsecurity),
  '',
  'C1: toda tabela de negocio tem relrowsecurity e relforcerowsecurity'
);

-- ---------------------------------------------------------------------------
-- C4 — nenhuma tabela de negócio sem política, exceto a lista fechada de
--      ausências intencionais (card 2.1 (b), card 2.4 (c) e (e)).
--
-- A lista nasceu no card 3.3 com as sete tabelas daquele card, porque lá nenhuma
-- tinha política ainda. O card 3.4 criou as políticas e a esvaziou. As ausências
-- permanentes previstas — movimento_estoque (sem update/delete) e permissao (sem
-- escrita) — são ausências de COMANDO, não de tabela: quem as asserta é o teste
-- por comando logo abaixo.
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(t.relname, ', ' order by t.relname), '')
     from t_negocio t
    where not exists (select 1 from pg_policy p where p.polrelid = t.oid)
      and t.relname not in (
            ''   -- nenhuma exceção em aberto
          )),
  '',
  'C4: nenhuma tabela de negocio sem politica fora da lista fechada de excecoes'
);

-- ---------------------------------------------------------------------------
-- C4 (por comando) — o conjunto (tabela, comando) tem de ser EXATAMENTE o do
-- card 2.4 §4. A asserção é simétrica de propósito: política que falta deixa uma
-- tela sem funcionar, e política a mais é uma porta aberta que ninguém pediu.
--
-- É aqui que "sem política = sem acesso" deixa de ser convenção e vira contrato:
-- `permissao` sem escrita (card 2.4 (e)) e `unidade`/`usuario`/`perfil`/
-- `parametro` sem delete não são esquecimento, e a única forma de provar isso é
-- escrever a ausência.
--
-- A lista cresce a cada migração. polcmd: r=select, a=insert, w=update, d=delete.
-- ---------------------------------------------------------------------------
create temporary view p_esperada (tabela, cmd) as values
  ('unidade','r'),          ('unidade','a'),          ('unidade','w'),
  ('usuario','r'),          ('usuario','a'),          ('usuario','w'),
  ('perfil','r'),           ('perfil','a'),           ('perfil','w'),
  ('permissao','r'),
  ('perfil_permissao','r'), ('perfil_permissao','a'), ('perfil_permissao','d'),
  ('usuario_perfil','r'),   ('usuario_perfil','a'),   ('usuario_perfil','d'),
  ('parametro','r'),        ('parametro','a'),        ('parametro','w');

create temporary view p_real (tabela, cmd) as
  select t.relname, p.polcmd::text
    from t_negocio t
    join pg_policy p on p.polrelid = t.oid;

select is(
  (select coalesce(string_agg(msg, '; ' order by msg), '')
     from (
       select format('FALTA %s %s', tabela, cmd) as msg
         from (select tabela, cmd from p_esperada
               except
               select tabela, cmd from p_real) f
       union all
       select format('SOBRA %s %s', tabela, cmd)
         from (select tabela, cmd from p_real
               except
               select tabela, cmd from p_esperada) s
     ) x),
  '',
  'C4: conjunto (tabela, comando) identico ao do card 2.4 §4'
);

-- ---------------------------------------------------------------------------
-- C11 (parcial) — todo código de permissão citado numa política é um código do
-- catálogo do card 2.4, e todo código que o catálogo prevê para estas tabelas
-- está de fato citado.
--
-- Parcial porque a versão cheia (contra a tabela `permissao` populada) depende
-- do seed e é do card 3.6. Esta já paga: um `admin.gerir_perfil` no singular
-- dentro de uma política não dá erro nenhum — a política simplesmente nega para
-- sempre, e o sintoma é uma tela vazia que ninguém liga à digitação.
-- ---------------------------------------------------------------------------
create temporary view p_codigo_usado as
  select distinct (regexp_matches(
           coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' ||
           coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''),
           'tem_permissao\(''([a-z_]+\.[a-z_]+)''', 'g'))[1] as codigo
    from pg_policy p
    join t_negocio t on t.oid = p.polrelid;

create temporary view p_codigo_catalogo (codigo) as values
  ('admin.ler'), ('admin.gerir_usuarios'), ('admin.gerir_perfis'),
  ('unidades.ler'), ('unidades.gerir'),
  ('parametros.ler'), ('parametros.gerir');

select is(
  (select coalesce(string_agg(msg, '; ' order by msg), '')
     from (
       select 'fora do catalogo: ' || codigo as msg
         from (select codigo from p_codigo_usado
               except
               select codigo from p_codigo_catalogo) a
       union all
       select 'catalogado e nao usado: ' || codigo
         from (select codigo from p_codigo_catalogo
               except
               select codigo from p_codigo_usado) b
     ) x),
  '',
  'C11: codigos de permissao das politicas batem com o catalogo do card 2.4'
);

select * from finish();
rollback;
