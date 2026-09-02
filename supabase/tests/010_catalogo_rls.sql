-- =============================================================================
-- Suíte de catálogo — RLS (C1 e C4 do card 2.8, §5.1)
-- Nasce no card 3.3 e cresce a cada migração.
--
-- Roda com `supabase test db` (stack local). Não executa regra de negócio
-- nenhuma: só interroga o catálogo do Postgres.
-- =============================================================================

begin;
select plan(6);

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
  ('parametro','r'),        ('parametro','a'),        ('parametro','w'),
  -- card 4.1 — catálogo curricular. `metodo` é a única sem delete: as três
  -- linhas são enumeração do produto (check na coluna) e apagá-las levaria
  -- junto todo o catálogo pendurado nelas; fora de uso é `ativo = false`.
  ('metodo','r'),           ('metodo','a'),           ('metodo','w'),
  ('material','r'),         ('material','a'),         ('material','w'),         ('material','d'),
  ('curso','r'),            ('curso','a'),            ('curso','w'),            ('curso','d'),
  ('curso_material','r'),   ('curso_material','a'),   ('curso_material','w'),   ('curso_material','d'),
  ('modulo','r'),           ('modulo','a'),           ('modulo','w'),           ('modulo','d'),
  ('combo','r'),            ('combo','a'),            ('combo','w'),            ('combo','d'),
  ('combo_curso','r'),      ('combo_curso','a'),      ('combo_curso','w'),      ('combo_curso','d'),
  -- card 4.2 — alunos. `aluno` não tem DELETE porque aluno não some, vira
  -- CANCELADO (por isso o catálogo do card 2.4 não tem `alunos.excluir`), e
  -- `aluno_status_hist` não tem update nem delete: é histórico imutável, e a
  -- imutabilidade aqui É a ausência de política. As três linhas que faltam neste
  -- bloco são a decisão escrita.
  ('aluno','r'),            ('aluno','a'),            ('aluno','w'),
  ('aluno_status_hist','r'), ('aluno_status_hist','a'),
  -- card 4.3 — infraestrutura física. Três ausências, três decisões:
  -- `pc_manutencao` sem DELETE (manutenção registrada é histórico), `professor`
  -- sem DELETE (sai por ativo = false, senão a grade histórica perde o nome de
  -- quem deu a aula) e `pc_credencial_acesso` sem update NEM delete — a
  -- imutabilidade do log de credencial É esta ausência (card 2.9 §6).
  ('sala','r'),             ('sala','a'),             ('sala','w'),             ('sala','d'),
  ('pc','r'),               ('pc','a'),               ('pc','w'),               ('pc','d'),
  ('pc_manutencao','r'),    ('pc_manutencao','a'),    ('pc_manutencao','w'),
  ('professor','r'),        ('professor','a'),        ('professor','w'),
  ('pc_credencial_acesso','r'), ('pc_credencial_acesso','a');

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
-- Este par (espelho literal) já pagava sozinho: um `admin.gerir_perfil` no
-- singular dentro de uma política não dá erro nenhum — a política simplesmente
-- nega para sempre, e o sintoma é uma tela vazia que ninguém liga à digitação.
-- A versão CHEIA, contra a tabela `permissao` populada, vem logo abaixo: ela é
-- do card 3.6, porque só passou a existir catálogo em 01/09/2026.
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
  ('parametros.ler'), ('parametros.gerir'),
  -- card 4.1 — os quatro do domínio `materiais` (card 2.4 §3.3). As sete tabelas
  -- do catálogo curricular usam exatamente estes, e a composição
  -- (curso_material, combo_curso) grava com `materiais.editar` e não com
  -- `materiais.criar`: montar a sequência de um curso é editar o curso.
  ('materiais.ler'), ('materiais.criar'), ('materiais.editar'), ('materiais.excluir'),
  -- card 4.2 — o domínio `alunos` MENOS os dois códigos que nenhuma política
  -- cita, e essa ausência é o ponto: `alunos.editar_trilha` só aparece quando
  -- `aluno_material` nascer (card 6.1), e `alunos.formar_sem_certificado` nunca
  -- aparece em política nenhuma — ele é o gate de fn_aluno_pode_formar, dentro
  -- de um trigger. Pôr qualquer um dos dois aqui reprovaria por "catalogado e
  -- não usado", que é exatamente o que esta lista existe para dizer.
  ('alunos.ler'), ('alunos.criar'), ('alunos.editar'),
  ('alunos.alterar_status'), ('alunos.reverter_status'),
  -- card 4.3 — os cinco do domínio `salas`, os três de `professores` e o 50º
  -- código, `salas.acessar_credencial` (card 2.9), que aqui aparece pela
  -- primeira vez em política: as duas de `pc_credencial_acesso`.
  -- `salas.registrar_manutencao` é separado de `salas.editar` porque tem
  -- consequência que editar não tem — manutenção sem substituto derruba a
  -- capacidade do bloco (card 2.4 §3.3).
  ('salas.ler'), ('salas.criar'), ('salas.editar'), ('salas.excluir'),
  ('salas.registrar_manutencao'), ('salas.acessar_credencial'),
  ('professores.ler'), ('professores.criar'), ('professores.editar');

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

-- ---------------------------------------------------------------------------
-- C11 (cheia, card 3.6) — todo código citado numa política EXISTE no catálogo
-- que o seed grava. É a versão que o card 2.8 §5.1 deixou reservada para quando
-- houvesse seed.
--
-- O par acima compara política contra uma lista escrita à mão neste arquivo; se
-- os dois errarem o mesmo código, ele passa. Este compara contra o que a
-- migração de fato gravou no banco — a mesma tabela que `tem_permissao` lê em
-- produção. Um código citado em política e ausente do catálogo nega para sempre,
-- em silêncio, e é justamente o modo de falha que o card 2.4 (a) descreve.
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(u.codigo, ', ' order by u.codigo), '')
     from p_codigo_usado u
    where not exists (
          select 1 from public.permissao p
           where p.codigo = u.codigo
             and p.unidade_id = (select id from public.unidade where codigo = 'MATRIZ'))),
  '',
  'C11: todo codigo citado em politica existe no catalogo gravado pelo seed do card 3.6'
);

select * from finish();
rollback;
