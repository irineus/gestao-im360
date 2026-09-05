-- =============================================================================
-- Checklist de certificado e sugestão de FORMADO — card 8.3
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Card de "Função/regra", então o §13 cobra o caminho feliz com efeito conferido,
-- UM `throws_ok` por `codigo` que as funções levantam, um negativo de permissão
-- por perfil, e a camada 2 exercitada POR FORA das funções de aplicação — um
-- teste que só chama `fn_certificado_marcar` nunca descobre que a guarda de
-- coluna não existe, e a guarda é o achado 8 do card 2.4 §7 (alta).
--
-- O arquivo prova, nesta ordem:
--   • a camada `certificados` da fixture: um checklist, os itens em estados
--     diferentes, e os pares "quem/quando" preenchidos em três e vazios no quarto;
--   • o achado 3 do card 2.4 §7, contra o SEED e não contra a intenção: todo
--     perfil que pode lançar saída pode abrir checklist — sem isso a entrega que
--     fecha a trilha morre em SEM_PERMISSAO no passo 9;
--   • fn_certificado_abrir: idempotência, a data que ela deriva, e os dois erros;
--   • a GUARDA DE COLUNA atacada por `update` direto, perfil a perfil — é onde
--     "RLS não é por coluna" deixa de ser observação e vira asserção;
--   • os pares quem/quando: preenchidos pelo trigger na mudança, e NÃO
--     falsificáveis por PATCH que não muda o item;
--   • os códigos de fn_certificado_marcar e fn_certificado_status;
--   • tg_certificado_sugere_formado nos DOIS lados, e a prova de que ele SUGERE:
--     o aluno continua ATIVO depois da pendência;
--   • o fechamento das duas pendências quando o aluno vira FORMADO — a metade que
--     o §10.1 sempre prometeu e nenhum código fazia;
--   • fn_certificado_reavaliar_estorno nos dois desfechos (APAGADO e
--     MANTIDO_INCONSISTENTE), o primeiro pela chamada direta e o segundo pelo
--     caminho REAL, fn_estornar_entrega;
--   • paridade de leitura entre os quatro perfis, zero para quem não pode, e
--     isolamento entre as duas unidades.
--
-- O gate de FORMADO (a condição (1), que este card completou) mora no `030`, ao
-- lado do resto do gate; aqui só se mede o que é do domínio do certificado.
--
-- ⚠️ Disciplina de papel, a mesma do 071: DEPOIS de `tests.autenticar` a sessão
--    está em `authenticated` e NÃO alcança mais o schema `tests`. Todo bloco que
--    volta a usar `tests.*` é precedido de `reset role;`.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(40);

-- Ids colhidos como `postgres`, ANTES de qualquer autenticação — a RLS de
-- ESCOLA_A esconderia os da B, e é o mesmo recurso do 070 e do 071.
create temporary table t_ids as
select tests.unidade('ESCOLA_A') as unidade_a,
       tests.unidade('ESCOLA_B') as unidade_b,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'João Pedro Martins') as joao,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Carla Menezes') as carla,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Diego Alves') as diego,
       (select a.id from public.aluno a
         where a.unidade_id = tests.unidade('ESCOLA_B') and a.nome = 'João Pedro Martins') as joao_b,
       -- Colhido aqui e não dentro da asserção da seção 5: sob a RLS de `usuario`
       -- (que exige `admin.ler`), o pedagógico não enxerga a linha da direção, e
       -- um `select id from usuario where email = …` ali devolveria NULO. A
       -- falsificação tem de tentar um id REAL de outra pessoa, senão a
       -- sabotagem apaga a autoria em vez de trocá-la, e a asserção passaria a
       -- medir outra coisa.
       tests.uid('direcao@escola-a.test') as direcao_uid;

grant select on t_ids to authenticated;

-- ===========================================================================
-- 1. A camada `certificados` da fixture
-- ===========================================================================
select is(
  (select count(*)::bigint from public.certificado_checklist),
  2::bigint,
  'um checklist por unidade — o de Joao Pedro, o unico aluno em FIM da fixture');

-- Os estados DIFERENTES não são enfeite: `formatura = false` é o que mantém a
-- fixture sem pendência SUGERIR_FORMADO (seção 7) e o que dá ao par
-- formatura_por/_em — o par novo do ajuste 3 do §14 — o lado VAZIO.
select is(
  (select format('%s/%s/%s/%s', cc.pedagogico_ok, cc.financeiro_ok, cc.formatura,
                 cc.certificado_status)
     from public.certificado_checklist cc
    where cc.aluno_id = (select joao from t_ids)),
  't/t/f/ENTREGUE',
  'pedagogico e financeiro marcados, formatura NAO, certificado ENTREGUE');

select is(
  (select format('%s/%s/%s/%s',
                 cc.pedagogico_por is not null, cc.financeiro_por is not null,
                 cc.formatura_por  is not null, cc.certificado_por is not null)
     from public.certificado_checklist cc
    where cc.aluno_id = (select joao from t_ids)),
  't/t/f/t',
  'os tres itens marcados tem quem/quando; o nao marcado nao tem — o par nao e default');

select is(
  (select cc.data_fim_curso from public.certificado_checklist cc
    where cc.aluno_id = (select joao from t_ids)),
  (select max(am.data_entrega) from public.aluno_material am
    where am.aluno_id = (select joao from t_ids) and am.entregue),
  'data_fim_curso e a data da ULTIMA entrega da trilha, nao o dia do db reset');

-- ===========================================================================
-- 2. O achado 3 do card 2.4 §7, medido contra o SEED
-- ===========================================================================
-- `fn_certificado_abrir` roda DENTRO da transação de `fn_registrar_entrega`. Se
-- algum perfil puder lançar saída e não puder abrir checklist, a entrega que
-- fecha a trilha morre em SEM_PERMISSAO — e o modo de falha é péssimo: só
-- acontece com o ÚLTIMO livro do aluno, meses depois de a matriz ter sido
-- editada, numa tela que fala de apostila e não de certificado.
--
-- A asserção é sobre a matriz que o seed do card 3.6 grava, e não sobre a
-- intenção escrita no documento: é o mesmo desenho do C11 cheio no `010`.
select is(
  (select coalesce(string_agg(distinct pf.codigo, ',' order by pf.codigo), '')
     from public.perfil pf
     join public.perfil_permissao pp on pp.perfil_id = pf.id
     join public.permissao pm on pm.id = pp.permissao_id
    where pf.unidade_id = (select id from public.unidade where codigo = 'MATRIZ')
      and pm.codigo = 'estoque.lancar_saida'
      and not exists (
            select 1 from public.perfil_permissao pp2
              join public.permissao pm2 on pm2.id = pp2.permissao_id
             where pp2.perfil_id = pf.id and pm2.codigo = 'certificados.criar')),
  '',
  'todo perfil com estoque.lancar_saida tem certificados.criar — achado 3 do card 2.4 §7');

-- ===========================================================================
-- 3. fn_certificado_abrir
-- ===========================================================================
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

-- Idempotência: a entrega chama isto toda vez que a trilha fecha, e o estorno
-- seguido de nova entrega passaria por aqui de novo. Duas chamadas, um checklist.
select is(
  public.fn_certificado_abrir((select carla from t_ids)),
  public.fn_certificado_abrir((select carla from t_ids)),
  'fn_certificado_abrir chamada duas vezes devolve o MESMO id, sem duplicar');

-- Carla não tem entrega nenhuma (camada `alunos`): o `coalesce` cai em fn_hoje().
-- É a metade do default que a fixture não exercita, e ela existe porque a tela do
-- card 8.6 vai abrir checklist à mão para quem terminou o curso fora do sistema.
select is(
  (select cc.data_fim_curso from public.certificado_checklist cc
    where cc.aluno_id = (select carla from t_ids)),
  public.fn_hoje(),
  'sem entrega na trilha, data_fim_curso cai em fn_hoje() — nao em nulo, que a coluna recusa');

reset role;

select is(
  tests.codigo_do_erro(
    $$select public.fn_certificado_abrir((select joao_b from t_ids))$$,
    tests.uid('secretaria@escola-a.test')),
  'ALUNO_INEXISTENTE',
  'aluno de OUTRA unidade e indistinguivel de inexistente — quem nao pode ver nao descobre');

-- O pedagógico NÃO tem `certificados.criar` na matriz inicial: ele confere o
-- checklist, não o abre.
select is(
  tests.codigo_do_erro(
    $$select public.fn_certificado_abrir((select diego from t_ids))$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'sem certificados.criar, abrir checklist e recusado COM O CODIGO — nao com um 42501 cru');

-- ===========================================================================
-- 4. A guarda de coluna, atacada por UPDATE direto (camada 2)
-- ===========================================================================
-- É aqui que "RLS não é por coluna" vira asserção. A política de update aceita o
-- `or` de três permissões: sem o trigger, o monitor — que tem só
-- `certificados.marcar_financeiro` — passaria a linha inteira por um PATCH.
select is(
  tests.codigo_do_erro(
    $$update public.certificado_checklist set pedagogico_ok = false
       where aluno_id = (select joao from t_ids)$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor NAO reescreve pedagogico_ok por update direto — a guarda pega o que a RLS deixa passar');

select is(
  tests.codigo_do_erro(
    $$update public.certificado_checklist set certificado_status = 'NAO_PEDIDO'
       where aluno_id = (select joao from t_ids)$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'nem o status do certificado, que e da secretaria');

-- A contraprova: o que ele PODE, ele faz — senão a asserção acima passaria com um
-- trigger que recusa tudo.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select lives_ok(
  $$update public.certificado_checklist set financeiro_ok = false
     where aluno_id = (select joao from t_ids)$$,
  'e o financeiro, que e dele, passa — a guarda distingue quem pode o que');

reset role;

select is(
  tests.codigo_do_erro(
    $$update public.certificado_checklist set financeiro_ok = true
       where aluno_id = (select joao from t_ids)$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'o pedagogico nao marca o financeiro — a separacao vale nos dois sentidos');

-- Identidade do checklist: reescrever a data em que o curso acabou é abrir OUTRO
-- checklist por cima deste, e quem abre precisa de `certificados.criar`.
select is(
  tests.codigo_do_erro(
    $$update public.certificado_checklist set data_fim_curso = public.fn_hoje()
       where aluno_id = (select joao from t_ids)$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'mudar data_fim_curso exige certificados.criar — nao e "marcar item", e abrir');

-- ===========================================================================
-- 5. Os pares quem/quando
-- ===========================================================================
select tests.autenticar(tests.uid('pedagogico@escola-a.test'));

select lives_ok(
  $$select public.fn_certificado_marcar((select joao from t_ids), 'FORMATURA', true)$$,
  'o pedagogico marca a formatura — e o item que ainda estava vazio na fixture');

select is(
  (select format('%s/%s', cc.formatura_por = auth.uid(), cc.formatura_em is not null)
     from public.certificado_checklist cc
    where cc.aluno_id = (select joao from t_ids)),
  't/t',
  'o par formatura_por/_em foi preenchido pelo trigger, com QUEM marcou e QUANDO');

-- A metade que se esquece: um PATCH que NÃO muda o item não pode reescrever o
-- par. Sem o `else` do trigger, a autoria seria falsificável — e por quem tem
-- permissão de marcar OUTRO item.
select lives_ok(
  $$update public.certificado_checklist
       set formatura_por = (select direcao_uid from t_ids)
     where aluno_id = (select joao from t_ids)$$,
  'o PATCH que tenta forjar a autoria e ACEITO pela RLS (e o ponto: nao e ela que barra)');

select is(
  (select cc.formatura_por = auth.uid() from public.certificado_checklist cc
    where cc.aluno_id = (select joao from t_ids)),
  true,
  'mas o trigger reescreveu o par com o valor antigo — a autoria nao se forja');

reset role;

-- ===========================================================================
-- 6. Os códigos de fn_certificado_marcar e fn_certificado_status
-- ===========================================================================
select is(
  tests.codigo_do_erro(
    $$select public.fn_certificado_marcar((select joao from t_ids), 'JURIDICO', true)$$,
    tests.uid('pedagogico@escola-a.test')),
  'ITEM_CERTIFICADO_INVALIDO',
  'item fora dos tres devolve o codigo do catalogo, nao um erro de case');

select is(
  tests.codigo_do_erro(
    $$select public.fn_certificado_status((select joao from t_ids), 'EMITIDO')$$,
    tests.uid('secretaria@escola-a.test')),
  'STATUS_CERTIFICADO_INVALIDO',
  'status fora dos tres devolve o codigo — nao o 23514 do check da coluna');

select is(
  tests.codigo_do_erro(
    $$select public.fn_certificado_marcar((select diego from t_ids), 'PEDAGOGICO', true)$$,
    tests.uid('pedagogico@escola-a.test')),
  'CERTIFICADO_INEXISTENTE',
  'marcar item de aluno sem checklist e 404 com codigo, nao um update de zero linhas');

select is(
  tests.codigo_do_erro(
    $$select public.fn_certificado_status((select diego from t_ids), 'PEDIDO')$$,
    tests.uid('secretaria@escola-a.test')),
  'CERTIFICADO_INEXISTENTE',
  'idem no status — as duas funcoes distinguem "nao existe" de "nada mudou"');

select is(
  tests.codigo_do_erro(
    $$select public.fn_certificado_marcar((select joao from t_ids), 'FINANCEIRO', true)$$,
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'a permissao POR ITEM tambem vale na funcao, e nao so no trigger');

select is(
  tests.codigo_do_erro(
    $$select public.fn_certificado_status((select joao from t_ids), 'PEDIDO')$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor nao altera o status do certificado');

-- ===========================================================================
-- 7. tg_certificado_sugere_formado — os dois lados
-- ===========================================================================
-- O lado NEGATIVO é permanente e vem da fixture: com `formatura = false` a
-- condição dos três itens não fecha, e é por isso que o `db reset` não nasce com
-- uma pendência SUGERIR_FORMADO (as contagens do teste 090 dependem disso).
--
-- ⚠️ A seção 5 acima marcou a formatura de João Pedro, então a pendência DELE
--    existe agora — a asserção olha Carla, cujo checklist ainda está virgem.
select is(
  (select count(*)::bigint from public.pendencia p
    where p.tipo = 'SUGERIR_FORMADO'
      and p.chave_dedup = 'FORMADO:' || (select carla from t_ids)::text),
  0::bigint,
  'checklist incompleto NAO sugere formatura — o lado negativo do gatilho');

select tests.autenticar(tests.uid('direcao@escola-a.test'));

-- A direção tem as três de marcar mais a de status: é o único perfil que fecha o
-- checklist sozinho, e é por isso que ela serve para medir o gatilho.
select public.fn_certificado_marcar((select carla from t_ids), 'PEDAGOGICO', true);
select public.fn_certificado_marcar((select carla from t_ids), 'FINANCEIRO', true);
select public.fn_certificado_marcar((select carla from t_ids), 'FORMATURA',  true);
select public.fn_certificado_status((select carla from t_ids), 'ENTREGUE');

select is(
  (select format('%s/%s', p.tipo, p.severidade) from public.pendencia p
    where p.chave_dedup = 'FORMADO:' || (select carla from t_ids)::text
      and p.resolvida_em is null),
  'SUGERIR_FORMADO/BAIXA',
  'checklist completo e certificado ENTREGUE abrem SUGERIR_FORMADO, severidade BAIXA');

-- SUGERE, não automatiza: formar o aluno desalocaria de todo bloco e turma
-- (tg_aluno_status_desaloca), e isso não pode ser efeito colateral de marcar uma
-- caixa. Quem forma é uma pessoa.
select is(
  (select a.status from public.aluno a where a.id = (select carla from t_ids)),
  'ATIVO',
  'e o aluno continua ATIVO — a pendencia SUGERE, nao forma');

reset role;

-- ===========================================================================
-- 8. Formar o aluno FECHA as duas pendências
-- ===========================================================================
-- O §10.1 do card 2.2 sempre disse «fechada por: formatura» para
-- ALUNO_ULTIMO_LIVRO e SUGERIR_FORMADO. Do primeiro só existia a metade do
-- estorno (card 6.3); do segundo, nada. Sem isto, a central do card 5.8 sugere
-- para sempre que se forme quem já está FORMADO.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

select public.fn_pendencia_abrir(
  'ALUNO_ULTIMO_LIVRO',
  'ULTIMO_LIVRO:' || (select carla from t_ids)::text,
  'aberta pelo teste para medir o fechamento na formatura',
  'BAIXA',
  (select carla from t_ids));

select tests.encerrar_sessao();
reset role;

select tests.autenticar(tests.uid('direcao@escola-a.test'));

select lives_ok(
  $$select public.fn_aluno_alterar_status((select carla from t_ids), 'FORMADO', null)$$,
  'a direcao forma a aluna — o gate passa pelo certificado ENTREGUE');

reset role;

select is(
  (select count(*)::bigint from public.pendencia p
    where p.chave_dedup in ('ULTIMO_LIVRO:' || (select carla from t_ids)::text,
                            'FORMADO:'      || (select carla from t_ids)::text)
      and p.resolvida_em is null),
  0::bigint,
  'formado o aluno, as DUAS pendencias fecham — a metade que o §10.1 prometia');

select is(
  (select coalesce(string_agg(distinct p.resolucao, ','), '') from public.pendencia p
    where p.chave_dedup in ('ULTIMO_LIVRO:' || (select carla from t_ids)::text,
                            'FORMADO:'      || (select carla from t_ids)::text)),
  'RESOLVIDA',
  'e fecham como RESOLVIDA com resolvida_por nulo — foi o sistema, nao uma pessoa');

-- ===========================================================================
-- 9. fn_certificado_reavaliar_estorno — os dois desfechos
-- ===========================================================================
-- Caminho REAL primeiro: o estorno da última entrega de João Pedro o tira do FIM,
-- e o checklist dele tem item marcado (a fixture marcou dois, e a seção 5 marcou
-- a formatura). Mantém e abre CERTIFICADO_INCONSISTENTE — apagar um checklist que
-- a secretaria já trabalhou é perda de informação.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select lives_ok(
  $$select public.fn_estornar_entrega(
      (select am.movimento_estoque_id from public.aluno_material am
        where am.aluno_id = (select joao from t_ids) and am.entregue
        order by am.data_entrega desc limit 1),
      'estorno do teste 081')$$,
  'o estorno da ultima entrega tira Joao Pedro do FIM');

reset role;

select is(
  (select count(*)::bigint from public.certificado_checklist cc
    where cc.aluno_id = (select joao from t_ids)),
  1::bigint,
  'o checklist com item marcado NAO e apagado pelo estorno');

select is(
  (select format('%s/%s', p.tipo, p.severidade) from public.pendencia p
    where p.chave_dedup = 'CERT_INCONS:' || (select joao from t_ids)::text
      and p.resolvida_em is null),
  'CERTIFICADO_INCONSISTENTE/MEDIA',
  'e a pendencia avisa que ha o que conferir antes de emitir');

-- O outro desfecho: checklist VIRGEM some.
--
-- ⚠️ NA PELE DA DIREÇÃO, e não em contexto de rotina — esta escolha custou uma
--    contraprova VERDE para ser descoberta (05/09/2026). A primeira versão
--    desmarcava os itens e chamava a função dentro de `tests.como_rotina`, que
--    mantém a sessão como `postgres`: com BYPASSRLS, o `delete` funcionaria mesmo
--    com a função `invoker`, e a sabotagem que devia provar o `security definer`
--    passou verde. Quem estorna de verdade é uma pessoa com `estoque.estornar`
--    (direção ou secretaria), e é na pele dela que o `delete` encontra a ausência
--    de política — a redução silenciosa que o definer existe para evitar.
--
--    Desmarcar pelas FUNÇÕES, e não por `update` direto, é o mesmo cuidado: a
--    direção é o único perfil com as três de marcar mais a de status, então o
--    caminho é o real do começo ao fim.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

select public.fn_certificado_marcar((select joao from t_ids), 'PEDAGOGICO', false);
select public.fn_certificado_marcar((select joao from t_ids), 'FINANCEIRO', false);
select public.fn_certificado_marcar((select joao from t_ids), 'FORMATURA',  false);
select public.fn_certificado_status((select joao from t_ids), 'NAO_PEDIDO');

select is(
  public.fn_certificado_reavaliar_estorno((select joao from t_ids)),
  'APAGADO',
  'checklist virgem e apagado pelo estorno que tira o aluno do FIM');

select is(
  (select count(*)::bigint from public.certificado_checklist cc
    where cc.aluno_id = (select joao from t_ids)),
  0::bigint,
  'e a linha sumiu DE VERDADE — como invoker o delete afetaria zero linhas, sem erro nenhum');

select is(
  public.fn_certificado_reavaliar_estorno((select joao from t_ids)),
  'NENHUM',
  'e sem checklist nenhum ela devolve NENHUM, sem erro — o estorno comum passa por aqui');

reset role;

-- ===========================================================================
-- 10. Paridade de leitura e isolamento
-- ===========================================================================
-- A seção 9 apagou o checklist de João Pedro e a 3 criou o de Carla: sobra UM em
-- ESCOLA_A. O número não importa — importa que os quatro perfis leiam o MESMO.
select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select id from public.certificado_checklist') as n
       from (values ('direcao@escola-a.test'), ('pedagogico@escola-a.test'),
                    ('secretaria@escola-a.test'), ('monitor@escola-a.test')) as u(e)
   ) t)::bigint,
  1::bigint,
  'paridade: os quatro perfis com certificados.ler leem a MESMA contagem');

select cmp_ok(
  tests.conta_como(tests.uid('direcao@escola-a.test'),
                   'select id from public.certificado_checklist'),
  '>', 0::bigint,
  'e a contagem de referencia e maior que zero — paridade em zero nao prova nada');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select id from public.certificado_checklist'),
  0::bigint,
  'quem nao tem certificados.ler le ZERO');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select id from public.certificado_checklist'),
  1::bigint,
  'a unidade B ve o checklist DELA e so o dela — o de Joao Pedro da B, intocado por este arquivo');

select * from finish();
rollback;
