-- =============================================================================
-- Suíte de catálogo — convenções (C2, C3, C6, C7, C8, C9 do card 2.8, §5.1)
-- Nasce no card 3.3 e cresce a cada migração.
-- =============================================================================

begin;
select plan(12);

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
-- C6 — nenhum current_date em corpo de função, default de PARÂMETRO, definição
--      de view ou default de coluna (card 2.3 (c) — o bug das 21h: o Postgres do
--      Supabase roda em UTC)
--
--      A quarta origem entrou no card 5.2, com a primeira função do projeto a ter
--      parâmetro de data com default (`fn_capacidade_efetiva(p_bloco_id, p_data
--      date default fn_hoje())`, e o §4.1 do card 2.2 a escrevia com
--      `current_date`). O default de parâmetro mora em `proargdefaults`, NÃO em
--      `prosrc`: as três origens originais o deixariam passar em silêncio — e a
--      função afetada seria justamente a que decide a lotação da grade, cujo
--      erro apareceria só depois das 21h, deslocado em um dia.
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(origem, '; ' order by origem), '')
     from (
       select 'funcao ' || proname as origem
         from f_projeto where prosrc ~* '\mcurrent_date\M'
       union all
       select 'default de parametro em ' || proname
         from f_projeto
        where pg_get_function_arguments(oid) ~* '\mcurrent_date\M'
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
--      A lista cresce card a card.
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(proname, ', ' order by proname), '')
     from f_projeto
    where prosecdef
      and proname not in (
            -- card 3.4 — as quatro primeiras precisam ignorar a RLS de
            -- usuario/usuario_perfil (senão recursam na própria política) e
            -- fn_param_txt/int precisam ler `parametro` sem exigir
            -- `parametros.ler`, que só a direção tem. TODAS filtram unidade no
            -- corpo, direta ou indiretamente por fn_unidade_atual().
            'fn_unidade_atual', 'tem_permissao', 'fn_minhas_permissoes',
            'fn_param_txt', 'fn_param_int',
            -- card 3.5 — as três do espelho auth.users → usuario. As duas
            -- primeiras escrevem em `usuario` (RLS forçada) a mando do
            -- supabase_auth_admin, que não é usuário do sistema e não tem
            -- política nenhuma a favor; a terceira precisa LER auth.users, que
            -- nenhum papel do app alcança. Nenhuma devolve dado ao chamador:
            -- duas gravam a partir do que o Auth já tem e a terceira compara e
            -- recusa — por isso não carregam filtro de unidade no corpo.
            'fn_usuario_espelhar', 'fn_usuario_email_sincronizar',
            'fn_usuario_espelho_coerente',
            -- card 3.6 — o trigger do bootstrap da direção. Dispara DENTRO da
            -- transação do espelho, que é do supabase_auth_admin: precisa ler
            -- `parametro` e escrever `usuario_perfil`, as duas com RLS forçada e
            -- nenhuma política a favor de quem convida. Filtra unidade no corpo
            -- (`new.unidade_id`), como manda a correção do card 2.3. As seis
            -- fn_seed_* NÃO são definer: rodam na migração, como `postgres`.
            'fn_usuario_direcao_inicial',
            -- card 4.3 — as três das credenciais de PC. As duas de aplicação
            -- precisam alcançar `vault` (que nenhum papel do app enxerga) e
            -- escrever o log em pc_credencial_acesso; a do trigger precisa
            -- apagar o segredo do Vault junto com o PC. As três filtram a
            -- unidade no corpo (as de aplicação) ou operam sobre a linha que o
            -- trigger recebe — como manda a correção do card 2.3.
            --
            -- fn_pc_exclusao_valida NÃO está aqui, de propósito: ela só conta
            -- linhas de tabelas que o próprio chamador pode ler, e entrar na
            -- lista sem necessidade gasta a revisão consciente que a lista
            -- existe para provocar (card 3.4 (a)).
            'fn_pc_credencial_ler', 'fn_pc_credencial_gravar',
            'fn_pc_credencial_apagar',
            -- card 4.7.5 — o trigger que escreve perfil_permissao_hist. Dispara
            -- na transação de quem marcou ou desmarcou a caixa (admin.gerir_perfis),
            -- e a tabela de histórico não tem política de insert para ninguém —
            -- de propósito, senão um POST direto gravaria uma remoção que não
            -- aconteceu. Não devolve dado ao chamador e grava a unidade da
            -- própria linha que mudou; por isso não carrega filtro no corpo.
            'fn_perfil_permissao_historico',
            -- card 4.7,7 — quem ainda não aceitou o convite. Precisa LER
            -- auth.users (email_confirmed_at), que nenhum papel do app alcança —
            -- mesma justificativa de fn_usuario_espelho_coerente. Esta DEVOLVE
            -- dado, então filtra unidade no corpo (fn_unidade_atual) e exige
            -- admin.ler, a mesma permissão da política usuario_sel: não sai
            -- daqui nada que o chamador já não pudesse ver na lista.
            'fn_convites_pendentes',
            -- card 5.2 — as duas que alimentam a grade semanal. `salas.ler`
            -- guarda `pc` e `turmas.ler` guarda `bloco_aluno`: como invoker, um
            -- leitor sem a primeira contaria zero PCs e veria a grade inteira
            -- LOTADA, e um sem a segunda veria ocupação zero num bloco cheio —
            -- os dois erros silenciosos, porque a RLS nega linha e não devolve
            -- erro (card 2.3 §3.4 e §10 #3). Número derivado exibido em tela não
            -- pode depender do que o leitor enxerga. As duas filtram unidade no
            -- corpo (`b.unidade_id = fn_unidade_atual()`) e devolvem NULO, não
            -- zero, para bloco de outra unidade.
            --
            -- fn_vagas_livres NÃO está aqui, de propósito: ela não lê tabela
            -- nenhuma, só compõe estas duas — mesma decisão de
            -- fn_pc_exclusao_valida no card 4.3.
            'fn_capacidade_efetiva', 'fn_ocupacao_bloco',
            -- card 5.5 — as duas que escrevem em `pendencia`. Elas são chamadas
            -- como EFEITO COLATERAL, na transação de outro ator (hoje
            -- fn_rep_virar_continuo, com `turmas.alocar`; amanhã
            -- fn_registrar_entrega, com o monitor, e fn_revalidar_blocos_sala).
            -- Como `invoker` elas encontram a RLS de quem chamou, e a RLS NEGA
            -- LINHA em vez de devolver erro: fn_pendencia_resolver devolveria
            -- "0 fechadas" e fn_pendencia_abrir nenhuma linha, sem nada
            -- denunciar — e o sintoma seria a central sugerindo todo dia uma
            -- virada REP que já aconteceu, indistinguível de "a rotina não
            -- rodou". Com a matriz INICIAL nada disso aparece (`turmas.alocar` e
            -- `pendencias.resolver` estão nos mesmos três perfis), e é o card
            -- 4.2 que deixou escrito que isso não é argumento. As duas filtram
            -- unidade no corpo e tratam unidade nula como ERRO.
            --
            -- fn_pendencia_resolver_id, o fechamento HUMANO, NÃO está aqui de
            -- propósito: é `invoker` e exige `pendencias.resolver`, que é onde o
            -- controle importa. fn_pendencias_fechar_ausentes também não: ela é
            -- `invoker` e só as rt_* a chamam.
            'fn_pendencia_abrir', 'fn_pendencia_resolver',
            -- card 5.4 — as três da manutenção de PC. As duas de trigger são
            -- definer por PRIVILÉGIO e por RLS: elas chamam funções sem grant
            -- para authenticated (o `invoker` morreria com "permission denied
            -- for function"), e são elas que atravessam a política de `update`
            -- de `pc`, que exige `salas.editar` — quem registra manutenção é o
            -- MONITOR, que não a tem, e como invoker o update afetaria ZERO
            -- linhas sem erro nenhum, deixando o PC OPERACIONAL na ficha
            -- enquanto estivesse quebrado. `fn_revalidar_blocos_sala` lê `pc` e
            -- `bloco_horario` (`salas.ler`, `turmas.ler`) e escreve pendência:
            -- como invoker percorreria zero blocos e a pendência não abriria.
            -- Todas filtram unidade no corpo e tratam unidade nula como ERRO.
            --
            -- fn_pc_status_sincronizar NÃO está aqui, e a ausência custou uma
            -- contraprova VERDE para ser descoberta: ela nasceu definer com a
            -- justificativa da RLS, e a sabotagem que devia prová-la passou —
            -- quem já atravessa a RLS é o trigger que a chama. Virou invoker,
            -- pelo precedente de fn_pendencias_fechar_ausentes (card 5.5): só
            -- quem roda como o dono a chama.
            'fn_revalidar_blocos_sala',
            'fn_pc_manutencao_status', 'fn_pc_revalida_blocos',
            -- card 5.5 — as três rotinas. `pg_cron` roda como `postgres` sem
            -- auth.uid(), e o contexto de rotina do card 2.2 §2.2 só existe
            -- porque elas são definer e não têm `grant` para authenticated
            -- (C9): um cliente não tem como entrar nesse contexto.
            'rt_diaria', 'rt_pendencias_diaria', 'rt_rep_avaliar',
            -- card 5.4 — as duas rotinas novas, pelo mesmo motivo das três de
            -- cima: `pg_cron` roda como `postgres` sem auth.uid(), e o contexto
            -- de rotina só se sustenta porque elas são definer e não têm grant
            -- para authenticated (C9).
            'rt_pcs_normaliza', 'rt_capacidades',
            -- card 6.5 — o trigger que fecha ESTOQUE_ZERO e COMPRA_SEM_ESTOQUE
            -- quando a compra chega. Ele dispara na transação de quem RECEBE
            -- (`compras.receber`) e precisa ler `pendencia` (`pendencias.ler`) e
            -- `aluno_material` (`alunos.ler`) — duas permissões que quem recebe
            -- pode não ter. Como invoker ele percorreria zero linhas e a
            -- pendência ficaria aberta com o material já na prateleira, sem nada
            -- denunciando: a redução silenciosa do card 2.3 §3.4 na tabela que a
            -- central do 5.8 lê. Com a matriz INICIAL nada disso aparece, e o
            -- card 4.2 já deixou escrito que isso não é argumento. Filtra a
            -- unidade no corpo, e ela vem da LINHA que o trigger recebe
            -- (`new.unidade_id`), como fn_perfil_permissao_historico.
            --
            -- As cinco funções de aplicação do card (fn_pedido_criar,
            -- fn_pedido_enviar, fn_pedido_cancelar, fn_pedido_receber e
            -- fn_ajustar_estoque) NÃO estão aqui, e é o ponto: definer as tiraria
            -- da política `insert` POR TIPO de movimento_estoque, que é a única
            -- coisa que impede uma ENTRADA inventada (achado 9 do card 2.4 §7).
            -- fn_movimento_valida_sinal e fn_pedido_item_recebimento_valido
            -- também não: as duas só leem linha que o próprio chamador já pode
            -- ler, e falham FECHADO quando não podem.
            'fn_movimento_resolve_pendencia'
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

-- ---------------------------------------------------------------------------
-- C8 (premissa) — o dono das funções `security definer` tem BYPASSRLS.
--
-- Não é curiosidade de plataforma: com `force row level security` em toda
-- tabela (card 2.1 (b)), `security definer` sozinho NÃO livra o dono da RLS —
-- e tem_permissao, que lê usuario_perfil, cairia na política de usuario_perfil,
-- que chama tem_permissao. O Postgres corta isso com "infinite recursion
-- detected in policy", e o sistema inteiro para na primeira consulta.
--
-- O card 3.3 verificou o atributo em EntrelaresProdDB e deixou a reconferência
-- em aberto para os projetos GestaoIM360. Esta asserção transforma a premissa em
-- portão: se um dia o Supabase deixar de conceder BYPASSRLS ao dono, a suíte
-- reprova aqui, com o motivo escrito, em vez de o app quebrar em produção com
-- um erro de recursão que não se parece com o que é.
-- ---------------------------------------------------------------------------
select ok(
  (select bool_and(r.rolbypassrls)
     from f_projeto f
     join pg_proc p on p.oid = f.oid
     join pg_roles r on r.oid = p.proowner
    where f.prosecdef),
  'C8: o dono de toda funcao security definer tem BYPASSRLS (premissa do card 3.3)'
);

-- ---------------------------------------------------------------------------
-- C14 — nenhuma coluna de `public` guarda segredo (card 2.9 §10)
--
-- A política do card 2.9 é que a senha do PC viva CIFRADA no Vault e que `pc`
-- guarde só o ponteiro. Nada no schema impõe isso: uma coluna
-- `credencial_senha text` acrescentada numa migração futura passaria por toda
-- a suíte — RLS, auditoria, políticas — sem uma linha vermelha, e a senha
-- voltaria ao pg_dump semanal em texto puro.
--
-- A exceção é uma só e é nominal: `credencial_secret_id`, que é o ponteiro.
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(c.relname || '.' || a.attname, ', '
                              order by c.relname, a.attname), '')
     from pg_attribute a
     join pg_class c on c.oid = a.attrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r'
      and a.attnum > 0
      and not a.attisdropped
      and a.attname ~ '(senha|password|pwd|secret)'
      and a.attname <> 'credencial_secret_id'),
  '',
  'C14: nenhuma coluna de tabela do schema public guarda segredo em claro'
);

-- ---------------------------------------------------------------------------
-- C15 — o Vault fica fora do alcance dos papéis do app (card 2.9 §3 e §10)
--
-- `vault` não está nos `schemas` expostos do PostgREST, mas isso é
-- configuração — e configuração se muda num clique, sem passar por revisão de
-- código. O que sustenta a política é o PRIVILÉGIO, e é ele que se asserta.
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(x.d, '; ' order by x.d), '')
     from (
       select 'authenticated tem usage em vault' as d
        where has_schema_privilege('authenticated', 'vault', 'usage')
       union all
       select 'anon tem usage em vault'
        where has_schema_privilege('anon', 'vault', 'usage')
       union all
       select 'authenticated le vault.decrypted_secrets'
        where has_table_privilege('authenticated', 'vault.decrypted_secrets', 'select')
       union all
       select 'anon le vault.decrypted_secrets'
        where has_table_privilege('anon', 'vault.decrypted_secrets', 'select')
     ) x),
  '',
  'C15: authenticated e anon nao alcancam o schema vault nem a view de decifra'
);

-- ---------------------------------------------------------------------------
-- C5 — toda view tem `security_invoker = on`, e não existe materialized view
--      (card 2.3 §2.1 e §2.2). Nasce no card 5.5, com a primeira view do
--      projeto (v_pendencias_abertas), e cresce a cada view nova.
--
--      View sem `security_invoker` roda com a identidade do DONO: é a porta dos
--      fundos que `force row level security` fechou na porta da frente. E
--      `materialized view` não respeita RLS de jeito nenhum — é um instantâneo
--      com a visibilidade de quem deu o `refresh`, e devolveria todas as
--      unidades para qualquer leitor. As duas falhas são silenciosas: a view
--      responde, e responde LINHAS A MAIS.
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(c.relname, ', ' order by c.relname), '')
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'v'
      and not coalesce(c.reloptions, '{}') @> array['security_invoker=on']),
  '',
  'C5: toda view do schema public tem security_invoker = on'
);

select is(
  (select coalesce(string_agg(c.relname, ', ' order by c.relname), '')
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'm'),
  '',
  'C5: nenhuma materialized view no schema public — matview nao respeita RLS'
);

-- ---------------------------------------------------------------------------
-- C10 — todo tipo passado a fn_pendencia_abrir está no `check` de
--       `pendencia.tipo`, e toda severidade citada está no `check` de
--       `severidade` (card 2.8 §5.1). Nasce no card 5.5, com a tabela.
--
--       O erro que ele pega é o mais barato de cometer e o mais caro de
--       descobrir: um tipo com uma letra fora derruba a chamada no `check` — e,
--       dentro do `exception when others` de rt_diaria, isso vira ROTINA_FALHOU
--       todo dia, com a causa a três funções de distância.
--
--       Depende da convenção do §5.2 do card 2.8: constante de contrato aparece
--       sempre como LITERAL na chamada. A primeira metade da asserção é a
--       espelho que impede a convenção de se perder — no dia em que alguém
--       escrever `fn_pendencia_abrir(v_tipo, …)` este teste cegaria em silêncio,
--       então ele reprova antes de cegar.
--
--       `prosrc` inclui os comentários do corpo, e este arquivo está cheio de
--       comentários que citam tipos de pendência: daí o regexp_replace, a mesma
--       lição que custou uma sessão no card 5.3.
-- ---------------------------------------------------------------------------
create temporary view p_check as
  select conname, pg_get_constraintdef(oid) as def
    from pg_constraint
   where conrelid = 'public.pendencia'::regclass and contype = 'c';

create temporary view p_tipo_citado as
  select f.proname,
         btrim((regexp_matches(regexp_replace(f.prosrc, '--[^\n]*', '', 'g'),
                               'fn_pendencia_abrir\s*\(\s*([^,]*),', 'g'))[1]) as tipo
    from f_projeto f;

select is(
  (select coalesce(string_agg(distinct format('%s -> %s', t.proname, t.tipo), '; '), '')
     from p_tipo_citado t
    where t.tipo !~ '^''[A-Z0-9_]+''$'
       or not exists (select 1 from p_check k
                       where k.def like '%tipo%' and position(t.tipo in k.def) > 0)),
  '',
  'C10: todo tipo passado a fn_pendencia_abrir e literal e esta no check de pendencia.tipo'
);

-- A outra metade do C10 — "toda severidade usada está no `check`" — NÃO está
-- aqui, e a decisão vale ser escrita: a severidade é o QUARTO argumento
-- posicional, e o segundo e o terceiro são expressões com vírgulas dentro
-- (`format(…)`, concatenação). Uma expressão regular que os atravesse acerta
-- hoje e passa a mentir no primeiro `format` novo — e o modo de falha é o pior
-- possível, um teste estático que cega em silêncio (§5.2 do card 2.8).
--
-- O que substitui: uma asserção de RUNTIME no teste 090, depois de a rotina ter
-- rodado — «nenhuma severidade fora do check do DDL». Ela mede o que foi
-- ESCRITO em vez do que foi digitado, e é a mesma razão pela qual este projeto
-- prefere contraprova a leitura. O caso que o card 2.3 nomeia (INFO, que o
-- catálogo do 2.2 usava e o DDL não aceita) reprova nas duas.

select * from finish();
rollback;
