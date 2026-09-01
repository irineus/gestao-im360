-- =============================================================================
-- Suíte de catálogo — RLS (C1 e C4 do card 2.8, §5.1)
-- Nasce no card 3.3 e cresce a cada migração.
--
-- Roda com `supabase test db` (stack local). Não executa regra de negócio
-- nenhuma: só interroga o catálogo do Postgres.
-- =============================================================================

begin;
select plan(3);

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
-- No card 3.3 NENHUMA tabela tem política ainda: as políticas são do card 3.4.
-- Por isso a lista de exceções abaixo é, hoje, a lista das sete tabelas deste
-- card. O card 3.4 esvazia essa lista e deixa só as ausências permanentes:
--   movimento_estoque (sem update/delete) e permissao (sem escrita).
-- Deixar a asserção aqui, com a exceção explícita e datada, é o que impede que
-- ela seja simplesmente esquecida quando as políticas chegarem.
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(t.relname, ', ' order by t.relname), '')
     from t_negocio t
    where not exists (select 1 from pg_policy p where p.polrelid = t.oid)
      and t.relname not in (
            -- exceções temporárias — saem no card 3.4, que cria as políticas
            'unidade', 'usuario', 'perfil', 'permissao',
            'perfil_permissao', 'usuario_perfil', 'parametro'
          )),
  '',
  'C4: nenhuma tabela de negocio sem politica fora da lista fechada de excecoes'
);

select * from finish();
rollback;
