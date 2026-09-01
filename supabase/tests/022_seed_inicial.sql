-- =============================================================================
-- Suíte do card 3.6 — seed inicial (unidade, catálogo, matriz, parâmetros e o
-- primeiro usuário de direção).
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Testa COMPORTAMENTO, não catálogo do Postgres: o que a migração gravou, o que
-- ela NÃO desfaz quando roda de novo, e as duas metades do bootstrap da direção.
--
-- A parte que mais paga é a de idempotência. O seed vai rodar em toda promoção
-- para produção, e o erro que ele pode cometer não aparece no dia em que é
-- escrito: é a direção desmarcar uma permissão na tela de Administração, o
-- próximo deploy devolvê-la, e ninguém ligar uma coisa à outra.
--
-- Roda como `postgres`, com begin/rollback.
-- =============================================================================

begin;
select plan(22);

create temporary view u_real as
  select id from public.unidade where codigo = 'MATRIZ';

-- ===========================================================================
-- 1. O que o seed gravou
-- ===========================================================================
select is(
  (select nome from public.unidade where codigo = 'MATRIZ'),
  'Instituto Mix Charqueadas',
  'a unidade real existe, com o codigo estavel do card 3.3 como chave');

select is(
  (select count(*)::bigint from public.permissao where unidade_id = (select id from u_real)),
  50::bigint,
  'catalogo com os 49 codigos do card 2.4 §3 mais salas.acessar_credencial (card 2.9)');

-- `dominio` é derivado do próprio código na função de seed; a asserção existe
-- para o dia em que alguém acrescentar a coluna à mão numa linha nova.
select is(
  (select coalesce(string_agg(codigo, ', ' order by codigo), '')
     from public.permissao
    where unidade_id = (select id from u_real)
      and dominio <> split_part(codigo, '.', 1)),
  '',
  'dominio e sempre o prefixo do codigo, no plural (card 2.4, convencao 2)');

select is(
  (select count(*)::bigint from public.permissao
    where unidade_id = (select id from u_real) and not ativo),
  0::bigint,
  'nenhum codigo nasce inativo — codigo sem consumidor nao entra, nao entra desligado');

select is(
  (select string_agg(codigo, ',' order by codigo collate "C") from public.perfil
    where unidade_id = (select id from u_real)),
  'DIRECAO,MONITOR,PEDAGOGICO,SECRETARIA',
  'os quatro perfis do plano, e so eles');

-- ===========================================================================
-- 2. A matriz — os totais de docs/permissoes-matriz.md §5
-- ===========================================================================
-- Contagem por perfil e não a matriz inteira: a matriz inteira já está escrita
-- na migração, e reescrevê-la aqui seria copiar o gabarito. O total é o que
-- muda quando alguém acrescenta ou tira uma linha sem reparar.
select is(
  (select string_agg(pe.codigo || '=' || cnt, ',' order by pe.codigo collate "C")
     from public.perfil pe
     cross join lateral (
       select count(*) as cnt from public.perfil_permissao pp where pp.perfil_id = pe.id
     ) c
    where pe.unidade_id = (select id from u_real)),
  'DIRECAO=50,MONITOR=14,PEDAGOGICO=22,SECRETARIA=37',
  'totais da matriz inicial: direcao 50, monitor 14, pedagogico 22, secretaria 37');

-- Os três pontos que Irineu confirmou em 01/09/2026 (card 2.4 §9). Escritos como
-- asserção porque são decisão do dono do produto, não consequência de nada: se
-- mudarem, tem de ser por decisão nova e não por um `join` que passou a casar
-- diferente.
select ok(
  exists (select 1 from public.perfil_permissao pp
            join public.perfil    pe on pe.id = pp.perfil_id
            join public.permissao pm on pm.id = pp.permissao_id
           where pe.unidade_id = (select id from u_real)
             and pe.codigo = 'SECRETARIA' and pm.codigo = 'salas.criar'),
  'confirmado por Irineu: a secretaria cadastra infraestrutura');

select ok(
  exists (select 1 from public.perfil_permissao pp
            join public.perfil    pe on pe.id = pp.perfil_id
            join public.permissao pm on pm.id = pp.permissao_id
           where pe.unidade_id = (select id from u_real)
             and pe.codigo = 'MONITOR' and pm.codigo = 'salas.registrar_manutencao'),
  'confirmado por Irineu: o monitor abre manutencao de PC');

select ok(
  not exists (select 1 from public.perfil_permissao pp
                join public.perfil    pe on pe.id = pp.perfil_id
                join public.permissao pm on pm.id = pp.permissao_id
               where pe.unidade_id = (select id from u_real)
                 and pe.codigo = 'PEDAGOGICO' and pm.codigo = 'compras.ler'),
  'confirmado por Irineu: o pedagogico NAO enxerga compras');

-- ===========================================================================
-- 3. Parâmetros — o contrato literal, chave por chave
-- ===========================================================================
-- Aqui o gabarito é copiado de propósito: parâmetro ausente é PARAMETRO_AUSENTE
-- (card 2.2 §2.3) e parâmetro com valor errado é pior — a projeção e a virada
-- REP rodam, com número errado e cara de certo. Os valores vêm de
-- docs/regra-virada-rep.md §4 e docs/projecao-demanda.md §3.
select is(
  (select string_agg(chave || '=' || valor, ',' order by chave collate "C")
     from public.parametro
    where unidade_id = (select id from u_real) and tipo = 'INTEIRO'),
  'projecao_acelerar_pct=50,projecao_horizonte_dias=60,'
  'rep_capacidade_semanal=1,rep_faltas_max=2,rep_janela_volta_dias=30,rep_prazo_dias=30,'
  'ritmo_calibracao_dias=180,ritmo_intervalo_max_dias=120,ritmo_intervalo_min_dias=7,'
  'ritmo_janela_entregas=4,ritmo_padrao_dias_INGLES=30,ritmo_padrao_dias_INTERATIVO=30,'
  'ritmo_padrao_dias_MODULAR=45,ritmo_padrao_dias_PADRAO=30,standby_alerta_dias=30',
  'os 15 parametros das regras ja especificadas, com os valores dos cards 2.1, 2.5 e Ordem 5');

-- fn_param_int lê pela unidade corrente; em contexto de rotina a unidade vem da
-- GUC (card 2.2 §2.2). É a leitura que a projeção e a virada REP fazem de
-- verdade — a asserção acima olha a tabela, esta olha pela porta do consumidor.
select tests.como_rotina((select id from u_real));

select is(public.fn_param_int('rep_prazo_dias'), 30,
  'fn_param_int enxerga o parametro do seed pelo mesmo caminho que a rotina diaria usa');

select tests.encerrar_sessao();

-- ===========================================================================
-- 4. Idempotência — o que o seed NÃO pode desfazer
-- ===========================================================================
-- A direção desmarca uma permissão na tela de Administração. O deploy seguinte
-- roda o seed de novo. Se a linha voltar, a tela de Administração é decorativa e
-- ninguém descobre isso olhando o código do seed.
delete from public.perfil_permissao pp
 using public.perfil pe, public.permissao pm
 where pp.perfil_id = pe.id and pp.permissao_id = pm.id
   and pe.unidade_id = (select id from u_real)
   and pe.codigo = 'SECRETARIA' and pm.codigo = 'compras.receber';

update public.parametro
   set valor = '90'
 where unidade_id = (select id from u_real) and chave = 'projecao_horizonte_dias';

update public.permissao
   set descricao = 'descricao adulterada'
 where unidade_id = (select id from u_real) and codigo = 'estoque.ajustar';

select public.fn_seed_acesso((select id from u_real));

select ok(
  not exists (select 1 from public.perfil_permissao pp
                join public.perfil    pe on pe.id = pp.perfil_id
                join public.permissao pm on pm.id = pp.permissao_id
               where pe.unidade_id = (select id from u_real)
                 and pe.codigo = 'SECRETARIA' and pm.codigo = 'compras.receber'),
  'permissao DESMARCADA na tela nao volta quando o seed roda de novo');

select is(
  (select valor from public.parametro
    where unidade_id = (select id from u_real) and chave = 'projecao_horizonte_dias'),
  '90',
  'parametro ajustado pela escola nao volta ao default no deploy seguinte');

-- O catálogo é a exceção, e de propósito: `permissao` não tem política de
-- escrita nenhuma (card 2.4 (e)), então a única forma de a descrição estar
-- errada é a migração; corrigi-la é para valer no deploy.
select is(
  (select descricao from public.permissao
    where unidade_id = (select id from u_real) and codigo = 'estoque.ajustar'),
  'Ajustar o saldo com motivo obrigatório',
  'a descricao do catalogo VOLTA: catalogo e codigo, e so muda por migracao');

select is(
  (select count(*)::bigint from public.permissao where unidade_id = (select id from u_real)),
  50::bigint,
  'reexecutar o seed nao duplica o catalogo');

-- O outro lado do mesmo guarda: código que ainda não foi distribuído a ninguém
-- CONTINUA chegando quando o seed roda. É o que faz uma migração futura poder
-- acrescentar um código ao catálogo e à matriz sem `insert` avulso — e é também
-- o caso residual assumido na migração: desmarcar de TODOS os perfis é
-- indistinguível de "nunca foi dado" enquanto não houver o histórico do card
-- 4.7.5.
delete from public.perfil_permissao pp
 using public.permissao pm
 where pp.permissao_id = pm.id
   and pm.unidade_id = (select id from u_real)
   and pm.codigo = 'compras.receber_excedente';

select public.fn_seed_acesso((select id from u_real));

select ok(
  exists (select 1 from public.perfil_permissao pp
            join public.perfil    pe on pe.id = pp.perfil_id
            join public.permissao pm on pm.id = pp.permissao_id
           where pe.unidade_id = (select id from u_real)
             and pe.codigo = 'DIRECAO' and pm.codigo = 'compras.receber_excedente'),
  'codigo sem linha nenhuma na unidade E distribuido — e assim que codigo novo chega');

-- ===========================================================================
-- 5. Bootstrap do primeiro usuário de direção — as duas metades
-- ===========================================================================
-- Metade (b), o caso normal: a migração já rodou e o convite chega depois. Sem
-- o trigger, o seed de produção não encontraria ninguém e não faria nada — e a
-- pessoa entraria no app com fn_minhas_permissoes() vazia, vendo todas as telas
-- ocultas, sem erro nenhum.
--
-- O e-mail vai em caixa diferente da do parâmetro de propósito: quem digita um
-- convite não pensa em maiúscula, e o GoTrue guarda o que recebe.
select tests.criar_usuario('IRINEUS@gmail.com', null, (select id from u_real));

select ok(
  exists (select 1 from public.usuario_perfil up
            join public.perfil pe on pe.id = up.perfil_id
           where up.usuario_id = tests.uid('IRINEUS@gmail.com')
             and pe.codigo = 'DIRECAO'),
  'convite DEPOIS do deploy: o trigger liga o e-mail do parametro ao perfil DIRECAO');

select tests.criar_usuario('outra.pessoa@escola.test', null, (select id from u_real));

select is(
  (select count(*)::bigint from public.usuario_perfil
    where usuario_id = tests.uid('outra.pessoa@escola.test')),
  0::bigint,
  'qualquer outro e-mail entra sem perfil nenhum — o bootstrap e de um so');

-- Metade (a): o convite já tinha acontecido quando o deploy chegou. Simulada
-- tirando a atribuição e chamando a função que a migração chama no fim.
delete from public.usuario_perfil where usuario_id = tests.uid('IRINEUS@gmail.com');

select ok(
  public.fn_seed_direcao_inicial((select id from u_real)),
  'convite ANTES do deploy: fn_seed_direcao_inicial encontra o usuario e atribui DIRECAO');

select ok(
  exists (select 1 from public.usuario_perfil up
            join public.perfil pe on pe.id = up.perfil_id
           where up.usuario_id = tests.uid('IRINEUS@gmail.com')
             and pe.codigo = 'DIRECAO'),
  'e a atribuicao esta la depois da chamada');

-- Unidade sem o parâmetro: devolve false em silêncio, sem PARAMETRO_AUSENTE. A
-- leitura é direta em `parametro` e não por fn_param_txt justamente por isto —
-- as duas unidades da escola-fixture não têm direção inicial, e uma exceção aqui
-- derrubaria a criação de todo usuário de teste.
select ok(
  not public.fn_seed_direcao_inicial(tests.unidade('ESCOLA_A')),
  'unidade sem direcao_inicial_email devolve false, sem levantar PARAMETRO_AUSENTE');

-- ===========================================================================
-- 6. As funções de seed não são um botão na API
-- ===========================================================================
-- C9 (teste 011) cobre `public` e `anon`. `authenticated` é o papel que o
-- PostgREST usa, e é dele que estas seis precisam ficar fora: publicá-las seria
-- oferecer pela API uma ação que não existe em tela nenhuma.
select is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'fn\_seed\_%'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  '',
  'nenhuma funcao de seed executavel por authenticated');

select * from finish();
rollback;
