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
  ('pc_credencial_acesso','r'), ('pc_credencial_acesso','a'),
  -- card 4.7.5 — histórico da matriz. Só leitura: quem escreve é o trigger
  -- (security definer) em perfil_permissao, e a imutabilidade é a ausência de
  -- update e delete, como em aluno_status_hist e pc_credencial_acesso. Sem
  -- insert de propósito: um POST direto gravaria "REMOVIDA" de uma permissão
  -- que continua valendo — histórico que mente é pior que histórico ausente.
  ('perfil_permissao_hist','r'),
  -- card 5.1 — blocos e alocação. `bloco_horario` segue o padrão de quatro;
  -- `bloco_aluno` e `bloco_aluno_reposicao` não têm DELETE, e a ausência é a
  -- decisão: alocação encerrada é `ativo = false` e reposição desmarcada é
  -- `status = 'CANCELADA'` — apagar a linha tiraria da grade histórica quem
  -- esteve na turma. O que a ausência de política NÃO alcançava era a cascata de
  -- `bloco_aluno.bloco_id`, e é o que tg_bloco_exclusao_valida fecha.
  ('bloco_horario','r'),         ('bloco_horario','a'),         ('bloco_horario','w'), ('bloco_horario','d'),
  ('bloco_aluno','r'),           ('bloco_aluno','a'),           ('bloco_aluno','w'),
  ('bloco_aluno_reposicao','r'), ('bloco_aluno_reposicao','a'), ('bloco_aluno_reposicao','w'),
  -- card 5.5 — pendências. Duas particularidades, as duas decisão do card 2.4 §4:
  -- o `insert` é a ÚNICA política do projeto que não exige permissão de domínio
  -- nenhuma (pendência é anotação do sistema, aberta por quase toda função de
  -- aplicação, e enumerar os autores num `or` daria uma lista que cresce a cada
  -- card e cujo esquecimento vira erro opaco de RLS numa tela que não fala de
  -- pendência); e não há DELETE, porque pendência encerrada é `resolvida_em`
  -- preenchida — apagar a linha tiraria da história justamente o que se quer
  -- olhar depois, quantas vezes este bloco já estourou a capacidade.
  ('pendencia','r'),        ('pendencia','a'),        ('pendencia','w'),
  -- card 6.1 — trilha e estoque. Quatro ausências, quatro decisões:
  -- `aluno_material_hist` sem update nem delete (histórico imutável, como
  -- aluno_status_hist); `movimento_estoque` sem update NEM delete, que É a
  -- imutabilidade do movimento — e o `insert` dele é o único do projeto
  -- condicionado ao valor de uma COLUNA (`tipo`), porque um `estoque.criar`
  -- genérico deixaria o monitor `POST`ar uma ENTRADA de 500 unidades sem passar
  -- por fn_pedido_receber; e `pedido_compra` sem delete, porque pedido enviado
  -- vira CANCELADO — o histórico de compra é o que explica um saldo três meses
  -- depois. `pedido_item` é o único dos cinco com o padrão de quatro.
  ('aluno_material','r'),      ('aluno_material','a'),      ('aluno_material','w'), ('aluno_material','d'),
  ('aluno_material_hist','r'), ('aluno_material_hist','a'),
  ('movimento_estoque','r'),   ('movimento_estoque','a'),
  ('pedido_compra','r'),       ('pedido_compra','a'),       ('pedido_compra','w'),
  ('pedido_item','r'),         ('pedido_item','a'),         ('pedido_item','w'),    ('pedido_item','d'),
  -- card 7.1 — turmas Modular. `turma_modular` segue o padrão de quatro;
  -- `turma_modular_modulo` também tem os quatro, mas o INSERT dele exige
  -- `turmas.editar` e não `turmas.criar` (o cronograma é conteúdo da turma, como
  -- curso_material é do curso no card 4.1) — a asserção por comando não vê essa
  -- diferença, quem a vê é o C11 do par abaixo e o teste 070. E
  -- `turma_modular_aluno` não tem DELETE, exatamente como `bloco_aluno`: saída
  -- da turma é `ativo = false`, e apagar a linha tiraria da turma o registro de
  -- quem esteve nela. O que a ausência de política NÃO alcançava era a cascata
  -- de `turma_modular_aluno.turma_id`, e é o que tg_turma_modular_exclusao_valida
  -- fecha.
  ('turma_modular','r'),        ('turma_modular','a'),        ('turma_modular','w'),        ('turma_modular','d'),
  ('turma_modular_modulo','r'), ('turma_modular_modulo','a'), ('turma_modular_modulo','w'), ('turma_modular_modulo','d'),
  ('turma_modular_aluno','r'),  ('turma_modular_aluno','a'),  ('turma_modular_aluno','w'),
  -- card 8.1 — projeção de demanda, e as duas tabelas estão FORA do padrão de
  -- quatro políticas por decisão, não por esquecimento (docs/projecao-demanda.md
  -- §7.1): NINGUÉM escreve nelas pela tela. O `insert` e o `delete` de
  -- `demanda_projetada` exigem `fn_contexto_rotina()` — não permissão de domínio
  -- —, e são as únicas políticas do projeto assim; com uma política por
  -- permissão, a tela de Compras poderia GRAVAR projeção via PostgREST. Sem
  -- `update` nas duas: a rotina apaga e regrava (contrato do card 2.3), e a foto
  -- mensal é imutável. `demanda_projetada_hist` também não tem `delete`, pela
  -- mesma razão de aluno_status_hist — a imutabilidade AQUI é a ausência.
  ('demanda_projetada','r'),      ('demanda_projetada','a'),      ('demanda_projetada','d'),
  ('demanda_projetada_hist','r'), ('demanda_projetada_hist','a'),
  -- card 8.3 — o checklist do certificado. Sem DELETE, e a ausência é a decisão
  -- (card 2.4 §4): checklist que a secretaria já trabalhou não some. O único
  -- apagamento legítimo — o estorno que tira o aluno do FIM antes de qualquer
  -- item marcado — é fn_certificado_reavaliar_estorno, `security definer`, e é
  -- PRECISAMENTE porque não há política que ela precisa ser definer.
  -- O `update` aceita o `or` de TRÊS permissões, e esta asserção não vê essa
  -- diferença: quem a vê é o C11 abaixo e a guarda de coluna, medida no 081 §4.
  ('certificado_checklist','r'), ('certificado_checklist','a'), ('certificado_checklist','w');

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
  -- card 4.2 — o domínio `alunos` MENOS o código que nenhuma política cita, e
  -- essa ausência é o ponto: `alunos.formar_sem_certificado` nunca aparece em
  -- política nenhuma — ele é o gate de fn_aluno_pode_formar, dentro de um
  -- trigger. Pô-lo aqui reprovaria por "catalogado e não usado", que é
  -- exatamente o que esta lista existe para dizer.
  --
  -- ⚠️ `alunos.editar_trilha` ENTROU em 04/09/2026, com o card 6.1: até ele a
  --    ausência era a decisão ("só aparece quando aluno_material nascer"), e
  --    agora as quatro políticas de aluno_material e as duas de
  --    aluno_material_hist o citam. Mover a linha é a metade da simetria que se
  --    esquece — sem isso o par reprovaria por "citado e fora do catálogo".
  ('alunos.ler'), ('alunos.criar'), ('alunos.editar'),
  ('alunos.alterar_status'), ('alunos.reverter_status'),
  ('alunos.editar_trilha'),
  -- card 4.3 — os cinco do domínio `salas`, os três de `professores` e o 50º
  -- código, `salas.acessar_credencial` (card 2.9), que aqui aparece pela
  -- primeira vez em política: as duas de `pc_credencial_acesso`.
  -- `salas.registrar_manutencao` é separado de `salas.editar` porque tem
  -- consequência que editar não tem — manutenção sem substituto derruba a
  -- capacidade do bloco (card 2.4 §3.3).
  ('salas.ler'), ('salas.criar'), ('salas.editar'), ('salas.excluir'),
  ('salas.registrar_manutencao'), ('salas.acessar_credencial'),
  ('professores.ler'), ('professores.criar'), ('professores.editar'),
  -- card 5.1 — cinco dos seis do domínio `turmas`. O sexto,
  -- `turmas.lancar_reposicao_retroativa`, fica DE FORA e a ausência é o ponto:
  -- ele não guarda tabela nenhuma, guarda uma condição dentro de
  -- tg_reposicao_admissao (card 5.3). Pô-lo aqui reprovaria por "catalogado e
  -- não usado", que é exatamente o que esta lista existe para dizer.
  ('turmas.ler'), ('turmas.criar'), ('turmas.editar'), ('turmas.excluir'),
  ('turmas.alocar'),
  -- card 5.5 — os dois do domínio `pendencias`. `pendencias.ler` guarda a
  -- leitura e `pendencias.resolver` guarda o UPDATE; o insert de `pendencia` não
  -- cita permissão nenhuma (card 2.4 §4), e é por isso que este par é o
  -- conjunto completo do domínio.
  ('pendencias.ler'), ('pendencias.resolver'),
  -- card 6.1 — os quatro do domínio `estoque` e CINCO dos seis de `compras`. O
  -- sexto, `compras.receber_excedente`, fica DE FORA e a ausência é o ponto,
  -- como a de `turmas.lancar_reposicao_retroativa`: ele não guarda tabela
  -- nenhuma, guarda uma condição dentro de fn_pedido_receber (card 6.5).
  --
  -- `compras.receber` aparece em TRÊS tabelas e uma delas surpreende: o insert de
  -- ENTRADA em movimento_estoque. É deliberado — quem faz estoque entrar é quem
  -- recebe compra, e um `estoque.criar` genérico seria a porta aberta que o
  -- achado 9 do card 2.4 §7 descreve.
  ('estoque.ler'), ('estoque.lancar_saida'), ('estoque.estornar'), ('estoque.ajustar'),
  ('compras.ler'), ('compras.criar'), ('compras.editar'), ('compras.excluir'),
  ('compras.receber'),
  -- card 8.3 — os CINCO do domínio `certificados`, e aqui o domínio inteiro
  -- aparece em política, sem a ausência deliberada que `alunos`, `turmas`,
  -- `compras` e `estoque` têm. Não é acaso: as três de marcar guardam GRUPOS DE
  -- COLUNA da mesma tabela, então as três precisam estar na `using` do mesmo
  -- update — é justamente por isso que o achado 8 do card 2.4 §7 exige a guarda
  -- de coluna, e é ela que devolve a cada código o sentido que o `or` dissolve.
  ('certificados.ler'), ('certificados.criar'),
  ('certificados.marcar_pedagogico'), ('certificados.marcar_financeiro'),
  ('certificados.alterar_status');

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
