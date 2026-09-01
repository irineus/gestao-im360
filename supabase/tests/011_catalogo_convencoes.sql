-- =============================================================================
-- Suíte de catálogo — convenções (C2, C3, C6, C7, C8, C9 do card 2.8, §5.1)
-- Nasce no card 3.3 e cresce a cada migração.
-- =============================================================================

begin;
select plan(6);

create temporary view t_negocio as
  select c.oid, c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relkind = 'r'
     and c.relname not like 'pg\_%';

-- Funções escritas por nós: schema public, fora de extensão.
create temporary view f_projeto as
  select p.oid, p.proname, p.prosrc, p.proconfig, p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and not exists (
           select 1 from pg_depend d
            where d.objid = p.oid and d.classid = 'pg_proc'::regclass
              and d.deptype = 'e');

-- ---------------------------------------------------------------------------
-- C2 — unidade_id e as quatro colunas de auditoria em toda tabela de negócio
--      (CLAUDE.md; card 2.1). Exceção fechada: `unidade`, que É a unidade.
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(format('%s(%s)', t.relname, falta), '; ' order by t.relname), '')
     from t_negocio t
     cross join lateral (
       select string_agg(col, ',') as falta
         from unnest(array['unidade_id','criado_em','criado_por',
                           'atualizado_em','atualizado_por']) as col
        where not exists (
              select 1 from pg_attribute a
               where a.attrelid = t.oid and a.attname = col
                 and a.attnum > 0 and not a.attisdropped)
          and not (col = 'unidade_id' and t.relname = 'unidade')
     ) f
    where f.falta is not null),
  '',
  'C2: toda tabela de negocio tem unidade_id e as quatro colunas de auditoria'
);

-- ---------------------------------------------------------------------------
-- C3 — toda tabela de negócio tem trigger de auditoria chamando fn_auditoria
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(t.relname, ', ' order by t.relname), '')
     from t_negocio t
    where not exists (
          select 1
            from pg_trigger tg
            join pg_proc p on p.oid = tg.tgfoid
           where tg.tgrelid = t.oid
             and not tg.tgisinternal
             and p.proname = 'fn_auditoria')),
  '',
  'C3: toda tabela de negocio tem trigger de auditoria'
);

-- ---------------------------------------------------------------------------
-- C6 — nenhum current_date em corpo de função, definição de view ou default de
--      coluna (card 2.3 (c) — o bug das 21h: o Postgres do Supabase roda em UTC)
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(origem, '; ' order by origem), '')
     from (
       select 'funcao ' || proname as origem
         from f_projeto where prosrc ~* '\mcurrent_date\M'
       union all
       select 'view ' || c.relname
         from pg_class c
         join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public' and c.relkind in ('v','m')
          and pg_get_viewdef(c.oid) ~* '\mcurrent_date\M'
       union all
       select 'default ' || c.relname || '.' || a.attname
         from pg_attrdef d
         join pg_class c on c.oid = d.adrelid
         join pg_namespace n on n.oid = c.relnamespace
         join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
        where n.nspname = 'public'
          and pg_get_expr(d.adbin, d.adrelid) ~* '\mcurrent_date\M'
     ) x),
  '',
  'C6: nenhum current_date em funcao, view ou default — usar fn_hoje()'
);

-- ---------------------------------------------------------------------------
-- C7 — toda função do projeto tem search_path fixo em proconfig (card 2.2 §1.1)
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(proname, ', ' order by proname), '')
     from f_projeto
    where proconfig is null
       or not exists (select 1 from unnest(proconfig) c where c like 'search\_path=%')),
  '',
  'C7: toda funcao do projeto tem search_path fixo'
);

-- ---------------------------------------------------------------------------
-- C8 — toda função `security definer` está na lista fechada versionada aqui.
--      Definer novo tem de passar por revisão consciente: dentro de uma função
--      definer de propriedade do papel `postgres` a RLS é ignorada por inteiro
--      (o papel tem BYPASSRLS), então o filtro de unidade tem de estar no corpo.
--      A lista cresce card a card — hoje o card 3.3 não cria nenhuma.
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(proname, ', ' order by proname), '')
     from f_projeto
    where prosecdef
      and proname not in (
            -- card 3.4:  'fn_unidade_atual', 'tem_permissao',
            --            'fn_param_int', 'fn_param_txt', 'fn_hoje'
            -- card 5.2:  'fn_capacidade_efetiva', 'fn_ocupacao_bloco'
            -- card 4.3:  'fn_pc_credencial_ler', 'fn_pc_credencial_gravar'
            ''
          )),
  '',
  'C8: nenhuma funcao security definer fora da lista fechada'
);

-- ---------------------------------------------------------------------------
-- C9 — nenhuma função com execute para public ou anon; nenhuma rt_* com
--      execute para authenticated (card 2.2 §1.1 e §11)
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(origem, '; ' order by origem), '')
     from (
       select proname || ' -> public' as origem from f_projeto
        where has_function_privilege('public', oid, 'EXECUTE')
       union all
       select proname || ' -> anon' from f_projeto
        where has_function_privilege('anon', oid, 'EXECUTE')
       union all
       select proname || ' -> authenticated' from f_projeto
        where proname like 'rt\_%'
          and has_function_privilege('authenticated', oid, 'EXECUTE')
     ) x),
  '',
  'C9: nenhum execute para public/anon, e nenhuma rt_* para authenticated'
);

select * from finish();
rollback;
