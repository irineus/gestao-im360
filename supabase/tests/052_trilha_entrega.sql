-- =============================================================================
-- Entrega de apostila e estorno — card 6.3
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- ⚠️ O NÚMERO DO ARQUIVO É 052, e não 051: a geração da trilha vem antes da
--    entrega, o `050` já era do card 6.1 e o `051` ficou com o 6.2. É o mesmo
--    deslocamento que levou o `040` do card 5.3 a virar `042`. Divergência já
--    registrada no §17 da estratégia de testes.
--
-- Card de "Função/regra", então o §13 cobra quatro coisas: caminho feliz com
-- EFEITO conferido, um `throws_ok`/`codigo_do_erro` por código que as funções
-- podem levantar, um negativo de permissão e a camada 2 quando houver trigger.
-- As quatro estão aqui.
--
-- Fora da obrigação, o arquivo mede as decisões do card 2.2 que sem ele são
-- frase em documento (docs/estrategia-testes.md §14):
--   • falha que precisa deixar rastro é STATUS DE RETORNO, não exceção (2.2 b):
--     BLOQUEADA_SEM_ESTOQUE devolve valor E a pendência COMPRA_SEM_ESTOQUE
--     sobrevive — um `raise` a levaria no rollback;
--   • "livro atual"/"próximo" são DERIVADOS (2.2 e): a entrega muda o próximo sem
--     `update` em coluna nenhuma;
--   • movimento IMUTÁVEL, correção por estorno (CLAUDE.md): o original continua
--     idêntico e o saldo volta;
--   • o advisory lock não sumiu (C13) — o guarda-chuva barato do
--     `tests_concorrencia/entrega_ultimo_exemplar.sh`, que é quem prova de fato;
--   • a exceção NOMEADA da guarda do card 6.1 §9 é estreita: vale só para
--     `ordem`, só dentro do contexto de entrega, e a GUC tem um escritor só.
--
-- ⚠️ A ORDEM DAS SEÇÕES 1 A 4 IMPORTA, e não é estética: `INTERATIVO 03` tem
--    saldo 1 na fixture (card 2.8 §4.2) e é o próximo de três alunos. A seção 2
--    consome esse último exemplar de propósito — é o que faz a reordenação
--    acontecer —, então a seção 4 repõe uma unidade antes de precisar dele.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(72);

-- Chaves naturais em um lugar só (card 2.8 §11: nunca `limit` sem ordem, nunca
-- UUID literal).
create temporary view alvo as
  select tests.unidade('ESCOLA_A')                                  as unidade,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Carla Menezes')      as carla,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Diego Alves')        as diego,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Felipe Nunes')       as felipe,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Ana Paula Ribeiro')  as ana,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'João Pedro Martins') as joao,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Karina Bastos')      as karina,
         (select a.id from public.aluno a
           where a.unidade_id = tests.unidade('ESCOLA_B') and a.nome = 'Carla Menezes')      as carla_b;

create temporary view mat as
  select m.codigo, me.codigo as metodo, m.id
    from public.material m
    join public.metodo me on me.id = m.metodo_id
   where m.unidade_id = tests.unidade('ESCOLA_A');

create temporary view material_id (chave, id) as
  select metodo || ' ' || codigo, id from mat;

-- ⚠️ As três só servem ao lado `postgres` do arquivo. Dentro de `tests.autenticar`
--    elas são inalcançáveis, e por DUAS razões: o papel muda mas o dono do objeto
--    não (o `select` na view seria negado), e `alvo` chama `tests.unidade`, num
--    schema em que `authenticated` não tem USAGE — a mesma pedra que o card 3.4
--    encontrou em `tests.conta_como`. Nos blocos autenticados a chave natural vai
--    inteira na consulta, com `public.fn_unidade_atual()` no lugar da unidade.

-- ===========================================================================
-- 1. Caminho feliz ENTREGUE — e quem entrega é o MONITOR
-- ===========================================================================
-- O ator é o monitor de propósito: é a jornada dele (card 2.4 §5), e é o perfil
-- que expõe a folga do `or` na política de update de `aluno_material`. Se a
-- entrega funcionasse só para a secretaria, o card estaria entregue quebrado
-- para quem mais o usa — e a decisão 2.4 (b) ("as quatro escritas-efeito-colateral
-- gravam") ficaria sem medida.
select is(
  (select public.fn_saldo_material((select id from material_id where chave = 'INTERATIVO 01'))),
  20,
  'pre-condicao: INTERATIVO 01 tem saldo 20 na fixture (26 de entrada, 6 entregues)');

select tests.autenticar(tests.uid('monitor@escola-a.test'));

create temporary table r_carla as
  select * from public.fn_registrar_entrega(
    (select a.id from public.aluno a
      where a.unidade_id = public.fn_unidade_atual() and a.nome = 'Carla Menezes'),
    null, 'entrega no balcao');

reset role;

select is((select status from r_carla), 'ENTREGUE',
  'a entrega normal devolve ENTREGUE');

select is(
  (select material_id from r_carla),
  (select id from material_id where chave = 'INTERATIVO 01'),
  'e saiu o primeiro item pendente da trilha — o `proximo` derivado, nao um palpite');

select is((select material_solicitado from r_carla), (select material_id from r_carla),
  'material_id e material_solicitado coincidem quando nada foi pulado');

select is((select em_fim from r_carla), false,
  'a trilha nao acabou: Carla tem tres itens e recebeu um');

-- O efeito, que é o que separa "a função devolveu" de "a função fez".
select is(
  (select mv.tipo || '/' || mv.quantidade::text
     from public.movimento_estoque mv where mv.id = (select movimento_id from r_carla)),
  'SAIDA/-1',
  'o movimento e uma SAIDA com quantidade COM SINAL — o saldo e uma soma simples');

select is(
  (select mv.aluno_id from public.movimento_estoque mv
    where mv.id = (select movimento_id from r_carla)),
  (select carla from alvo),
  'e a saida aponta para o aluno que recebeu');

select is(
  (select mv.criado_por from public.movimento_estoque mv
    where mv.id = (select movimento_id from r_carla)),
  tests.uid('monitor@escola-a.test'),
  'a autoria nao e coluna propria: veio de criado_por, preenchido por fn_auditoria');

select is(
  (select am.entregue::text || '/' || (am.data_entrega = public.fn_hoje())::text
       || '/' || (am.movimento_estoque_id = (select movimento_id from r_carla))::text
     from public.aluno_material am
    where am.aluno_id = (select carla from alvo)
      and am.material_id = (select material_id from r_carla)),
  'true/true/true',
  'os passos 7 a 9 do §6.2 sao UM ATO SO: movimento, marca na trilha e vinculo entre os dois');

select is(
  (select public.fn_saldo_material((select id from material_id where chave = 'INTERATIVO 01'))),
  19,
  'e o saldo caiu exatamente um — nao dois, nao zero');

-- Decisão 2.2 (e): "livro atual" e "próximo" são derivados, nunca coluna.
select is(
  (select proximo_material_id from r_carla),
  (select id from material_id where chave = 'INTERATIVO 02'),
  'o retorno ja traz o proximo recalculado — a tela nao volta ao banco para saber o que mostrar');

select is(
  public.fn_trilha_proximo_material((select carla from alvo)),
  (select proximo_material_id from r_carla),
  'e o proximo mudou sem `update` em coluna nenhuma: ele e DERIVADO (decisao 2.2 (e))');

-- ===========================================================================
-- 2. REORDENADA — o item sem estoque é PULADO, não some
-- ===========================================================================
-- Diego tem `INTERATIVO 01` entregue; o próximo é o `02`, cujo saldo é ZERO na
-- fixture (três de entrada, três entregues), e adiante dele está o `03`, com o
-- último exemplar. É o cenário que a camada `trilha_estoque` do seed montou
-- para este card.
select is(
  (select public.fn_saldo_material((select id from material_id where chave = 'INTERATIVO 02'))),
  0,
  'pre-condicao: INTERATIVO 02 esta zerado, e e o proximo de Diego');

select is(
  (select public.fn_saldo_material((select id from material_id where chave = 'INTERATIVO 03'))),
  1,
  'pre-condicao: INTERATIVO 03 tem o ULTIMO exemplar');

select tests.autenticar(tests.uid('monitor@escola-a.test'));

create temporary table r_diego as
  select * from public.fn_registrar_entrega(
    (select a.id from public.aluno a
      where a.unidade_id = public.fn_unidade_atual() and a.nome = 'Diego Alves'));

reset role;

select is((select status from r_diego), 'REORDENADA',
  'sem estoque do proximo, mas com estoque adiante na trilha, a entrega REORDENA');

select is(
  (select material_solicitado from r_diego),
  (select id from material_id where chave = 'INTERATIVO 02'),
  'o retorno diz o que a trilha MANDAVA entregar');

select is(
  (select material_id from r_diego),
  (select id from material_id where chave = 'INTERATIVO 03'),
  'e o que efetivamente saiu — a diferenca entre os dois e o que a tela avisa');

select is(
  (select am.entregue from public.aluno_material am
    where am.aluno_id = (select diego from alvo)
      and am.material_id = (select id from material_id where chave = 'INTERATIVO 02')),
  false,
  'o PULADO continua pendente: ele foi empurrado uma posicao, nao removido da trilha');

select is(
  public.fn_trilha_proximo_material((select diego from alvo)),
  (select id from material_id where chave = 'INTERATIVO 02'),
  'e volta a ser o proximo assim que houver estoque — que e o contrato do §6.2');

-- O rastro. Sem ele a trilha sai da ordem do combo e nada explica por quê, que é
-- exatamente o silêncio que `aluno_material_hist` existe para impedir.
select is(
  (select h.motivo from public.aluno_material_hist h
    where h.aluno_id = (select diego from alvo)
      and h.material_id = (select id from material_id where chave = 'INTERATIVO 03')
      and h.motivo = 'SEM_ESTOQUE'),
  'SEM_ESTOQUE',
  'a reordenacao automatica deixa linha em aluno_material_hist com motivo SEM_ESTOQUE');

select is(
  (select h.usuario_id from public.aluno_material_hist h
    where h.aluno_id = (select diego from alvo) and h.motivo = 'SEM_ESTOQUE'),
  tests.uid('monitor@escola-a.test'),
  'assinada pelo monitor — a escrita de trilha aconteceu na transacao DELE');

-- A exceção nomeada é estreita também no efeito: a linha movida NÃO vira MANUAL.
select is(
  (select am.origem from public.aluno_material am
    where am.aluno_id = (select diego from alvo)
      and am.material_id = (select id from material_id where chave = 'INTERATIVO 03')),
  'COMBO',
  'a linha reposicionada continua COMBO: ninguem decidiu nada, e MANUAL a tiraria da regeneracao');

select is(
  (select p.severidade from public.pendencia p
    where p.unidade_id = (select unidade from alvo)
      and p.chave_dedup = 'ESTOQUE_ZERO:' ||
          (select id from material_id where chave = 'INTERATIVO 02')::text
      and p.resolvida_em is null),
  'MEDIA',
  'e a apostila que faltou virou pendencia ESTOQUE_ZERO, do catalogo do card 2.2 §10.1');

-- ===========================================================================
-- 3. BLOQUEADA_SEM_ESTOQUE — a decisão 2.2 (b), medida
-- ===========================================================================
-- Felipe tem `INGLES 01` entregue e o `02` como ÚNICO item pendente; o saldo do
-- `02` é zero por um AJUSTE de extravio, e não por entregas. Não há para onde
-- pular, e é aqui que a escolha "status de retorno em vez de exceção" aparece:
-- com um `raise`, a pendência de compra iria embora no rollback e o sistema não
-- saberia que faltou apostila.
select is(
  (select public.fn_saldo_material((select id from material_id where chave = 'INGLES 02'))),
  0,
  'pre-condicao: INGLES 02 esta zerado e e o unico item pendente de Felipe');

select tests.autenticar(tests.uid('monitor@escola-a.test'));

create temporary table r_felipe as
  select * from public.fn_registrar_entrega(
    (select a.id from public.aluno a
      where a.unidade_id = public.fn_unidade_atual() and a.nome = 'Felipe Nunes'));

reset role;

select is((select status from r_felipe), 'BLOQUEADA_SEM_ESTOQUE',
  'sem estoque em NENHUM item pendente, a entrega devolve BLOQUEADA_SEM_ESTOQUE');

select ok((select movimento_id is null and material_id is null from r_felipe),
  'e nada de estoque foi movimentado — nem material efetivo, nem movimento');

select is(
  (select material_solicitado from r_felipe),
  (select id from material_id where chave = 'INGLES 02'),
  'mas o retorno diz QUAL apostila faltou, que e o que a tela precisa para pedir a compra');

-- O ponto todo da decisão: a função RETORNOU (não levantou), então a pendência
-- não passou por rollback nenhum e está lá para o commit.
select is(
  (select p.severidade from public.pendencia p
    where p.unidade_id = (select unidade from alvo)
      and p.chave_dedup = 'COMPRA_SEM_ESTOQUE:' || (select felipe from alvo)::text
      and p.resolvida_em is null),
  'ALTA',
  'a pendencia COMPRA_SEM_ESTOQUE ficou aberta com severidade ALTA (decisao 2.2 (b))');

select is(
  (select count(*)::bigint from public.movimento_estoque mv
    where mv.material_id = (select id from material_id where chave = 'INGLES 02')
      and mv.unidade_id = (select unidade from alvo)
      and mv.tipo = 'SAIDA'),
  0::bigint,
  'e nenhuma SAIDA de INGLES 02 foi gravada — bloquear e nao mexer no estoque');

-- ===========================================================================
-- 4. Último livro da trilha — o aviso que o card 8.3 vai transformar em checklist
-- ===========================================================================
-- Repõe uma unidade de `INTERATIVO 03`, consumida na seção 2, e uma de
-- `INTERATIVO 04`, que nasce com saldo zero. A entrada entra como `postgres`,
-- que é como a própria escola-fixture escreve: quem a grava pela porta da frente
-- é fn_pedido_receber, do card 6.5.
--
-- ⚠️ SÃO DUAS ENTREGAS DESDE O CARD 8.1, e a segunda não é redundância: o combo
--    de Informática passou a ter QUATRO materiais (o `04` é o que dá ao degrau
--    RITMO_ALUNO da projeção um aluno com ritmo medido E dois itens pendentes —
--    ver a nota do seed), então entregar o `03` deixou de ser o fim da trilha de
--    Ana Paula. Aproveitando, a primeira entrega passou a medir o lado NEGATIVO
--    do `em_fim`, que antes não era medido em lugar nenhum: uma implementação
--    que devolvesse `true` sempre passava.
insert into public.movimento_estoque (unidade_id, material_id, tipo, quantidade, observacao)
select (select unidade from alvo),
       (select id from material_id where chave = s.chave),
       'ENTRADA', 1, 'reposicao para a secao 4 do teste 052'
  from (values ('INTERATIVO 03'), ('INTERATIVO 04')) as s(chave);

select tests.autenticar(tests.uid('monitor@escola-a.test'));

create temporary table r_ana_03 as
  select * from public.fn_registrar_entrega(
    (select a.id from public.aluno a
      where a.unidade_id = public.fn_unidade_atual()
        and a.nome = 'Ana Paula Ribeiro'));

create temporary table r_ana as
  select * from public.fn_registrar_entrega(
    (select a.id from public.aluno a
      where a.unidade_id = public.fn_unidade_atual()
        and a.nome = 'Ana Paula Ribeiro'));

reset role;

select is((select status from r_ana_03), 'ENTREGUE',
  'com estoque reposto, o penultimo item da trilha de Ana Paula sai normalmente');

select is((select em_fim from r_ana_03), false,
  'e o retorno diz que a trilha NAO acabou — ainda ha o 04 pendente');

select is(
  (select material_id from r_ana),
  (select id from material_id where chave = 'INTERATIVO 04'),
  'a entrega seguinte e o ultimo item da trilha, o 04');

select is((select status from r_ana), 'ENTREGUE',
  'que sai normalmente');

select is((select em_fim from r_ana), true,
  'e o retorno ja diz que a trilha acabou');

select ok((select proximo_material_id is null from r_ana),
  'com proximo NULO, que e como o §5.2 representa o FIM');

select is(
  (select p.severidade from public.pendencia p
    where p.unidade_id = (select unidade from alvo)
      and p.chave_dedup = 'ULTIMO_LIVRO:' || (select ana from alvo)::text
      and p.resolvida_em is null),
  'BAIXA',
  'o FIM abriu ALUNO_ULTIMO_LIVRO — nao ha nada errado, ha algo a fazer');

-- ===========================================================================
-- 5. Os erros de fn_registrar_entrega (§13: um por codigo)
-- ===========================================================================
-- O negativo de permissão primeiro: o PEDAGÓGICO não tem `estoque.lancar_saida`
-- (card 2.4 §5). Sem esta asserção a permissão estaria escrita na função e medida
-- em lugar nenhum, que é a definição de comentário.
--
-- ⚠️ `encerrar_sessao` antes, e não `reset role`: `tests.autenticar` grava
--    `request.jwt.claims` com `is_local => true`, que vale até o FIM DA TRANSAÇÃO
--    — voltar ao papel `postgres` não apaga a identidade, e o `throws_ok` abaixo
--    passaria a rodar como o monitor da seção 4, com permissão, sem levantar nada.
select tests.encerrar_sessao();

select throws_ok(
  format($$select public.fn_registrar_entrega(%L::uuid)$$, (select carla from alvo)),
  'PT403', null,
  'sem permissao o SQLSTATE e PT403 (o texto nunca e contrato — card 2.8 §6.2)');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_registrar_entrega(%L::uuid)$$, (select carla from alvo)),
    tests.uid('pedagogico@escola-a.test')),
  'SEM_PERMISSAO',
  'o pedagogico nao registra entrega: ele nao tem estoque.lancar_saida');

select is(
  tests.codigo_do_erro(
    $$select public.fn_registrar_entrega('00000000-0000-0000-0000-000000000001'::uuid)$$,
    tests.uid('monitor@escola-a.test')),
  'ALUNO_INEXISTENTE',
  'aluno que nao existe e PT404 / ALUNO_INEXISTENTE (precedente do card 4.2)');

-- Isolamento de unidade pela mesma porta: a leitura é `invoker`, então aluno de
-- OUTRA unidade e aluno inexistente respondem a mesma coisa — quem não pode ver
-- não descobre que existe.
select is(
  tests.codigo_do_erro(
    format($$select public.fn_registrar_entrega(%L::uuid)$$, (select carla_b from alvo)),
    tests.uid('monitor@escola-a.test')),
  'ALUNO_INEXISTENTE',
  'e aluno da ESCOLA_B responde o MESMO para o monitor da ESCOLA_A');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_registrar_entrega(%L::uuid)$$, (select joao from alvo)),
    tests.uid('monitor@escola-a.test')),
  'ALUNO_INATIVO',
  'aluno FORMADO nao recebe apostila: a entrega so vale para ATIVO ou ACELERAR');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_registrar_entrega(%L::uuid)$$, (select karina from alvo)),
    tests.uid('monitor@escola-a.test')),
  'TRILHA_EM_FIM',
  'aluna sem trilha nenhuma tambem e TRILHA_EM_FIM — a mesma leitura de fn_trilha_em_fim');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_registrar_entrega(%L::uuid, %L::uuid)$$,
           (select carla from alvo),
           (select id from material_id where chave = 'MODULAR 01')),
    tests.uid('monitor@escola-a.test')),
  'MATERIAL_FORA_DA_TRILHA',
  'material fora da trilha e recusado: sem isso, a tela baixaria estoque de um livro nao devido');

-- Item JÁ ENTREGUE informado à mão cai no mesmo código, e é o que impede a mesma
-- apostila de sair duas vezes para a mesma pessoa.
select is(
  tests.codigo_do_erro(
    format($$select public.fn_registrar_entrega(%L::uuid, %L::uuid)$$,
           (select carla from alvo),
           (select id from material_id where chave = 'INTERATIVO 01')),
    tests.uid('monitor@escola-a.test')),
  'MATERIAL_FORA_DA_TRILHA',
  'e item ja entregue tambem: "pendente na trilha" e a condicao, nao "na trilha"');

-- ===========================================================================
-- 6. Estorno — o movimento original NUNCA muda
-- ===========================================================================
-- Quem estorna é a SECRETARIA: `estoque.estornar` está em {DIRECAO, SECRETARIA} e
-- o monitor NÃO a tem (card 2.4 §5). Desfazer não é a mesma ação que fazer.
create temporary table mov_carla as
  select mv.* from public.movimento_estoque mv
   where mv.id = (select movimento_id from r_carla);

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

create temporary table r_estorno as
  select public.fn_estornar_entrega((select movimento_id from r_carla),
                                    'livro entregue ao aluno errado') as id;

reset role;

select is(
  (select mv.tipo || '/' || mv.quantidade::text
     from public.movimento_estoque mv where mv.id = (select id from r_estorno)),
  'ESTORNO/1',
  'o estorno tem sinal OPOSTO e mesma magnitude do movimento de origem');

select is(
  (select mv.estorno_de_id from public.movimento_estoque mv
    where mv.id = (select id from r_estorno)),
  (select movimento_id from r_carla),
  'e aponta para a saida que desfaz — o vinculo que torna o estorno rastreavel');

select ok(
  (select count(*) = 1 from public.movimento_estoque mv, mov_carla o
    where mv.id = o.id and mv.tipo = o.tipo and mv.quantidade = o.quantidade
      and mv.ocorrido_em = o.ocorrido_em and mv.material_id = o.material_id),
  'o movimento ORIGINAL continua identico: correcao e por estorno, nunca por update');

select is(
  (select public.fn_saldo_material((select id from material_id where chave = 'INTERATIVO 01'))),
  20,
  'o saldo voltou ao que era — duas linhas onde alguem gostaria de ver zero, e e assim que tem de ser');

select is(
  (select am.entregue::text || '/' || (am.data_entrega is null)::text
       || '/' || (am.movimento_estoque_id is null)::text
     from public.aluno_material am
    where am.aluno_id = (select carla from alvo)
      and am.material_id = (select id from material_id where chave = 'INTERATIVO 01')),
  'false/true/true',
  'e a trilha voltou a PENDENTE, com as tres colunas da entrega limpas juntas');

select is(
  public.fn_trilha_proximo_material((select carla from alvo)),
  (select id from material_id where chave = 'INTERATIVO 01'),
  'o "proximo" voltou sozinho para a apostila estornada — de novo sem coluna nenhuma');

-- O aviso do último livro deixou de ser verdade: pendência que ninguém fecha é a
-- central do card 5.8 perdendo credibilidade.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  format($$select public.fn_estornar_entrega(%L::uuid, 'conferencia da secretaria')$$,
         (select movimento_id from r_ana)),
  'a secretaria estorna a entrega do ultimo livro de Ana Paula');

reset role;

select is(
  (select count(*)::bigint from public.pendencia p
    where p.unidade_id = (select unidade from alvo)
      and p.chave_dedup = 'ULTIMO_LIVRO:' || (select ana from alvo)::text
      and p.resolvida_em is null),
  0::bigint,
  'e o estorno que tira o aluno do FIM FECHA a pendencia ALUNO_ULTIMO_LIVRO');

-- O passo 6 do §6.3, por AUSÊNCIA de código: o estorno não desfaz a reordenação.
select is(
  (select count(*)::bigint from public.aluno_material_hist h
    where h.aluno_id = (select diego from alvo) and h.motivo = 'SEM_ESTOQUE'),
  1::bigint,
  'e o historico da reordenacao continua la — estorno nao inventa uma trilha que nunca existiu');

-- ===========================================================================
-- 7. Os erros de fn_estornar_entrega (§13: um por codigo)
-- ===========================================================================
select is(
  tests.codigo_do_erro(
    format($$select public.fn_estornar_entrega(%L::uuid, 'porque sim')$$,
           (select movimento_id from r_diego)),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor entrega mas NAO estorna: estoque.estornar nao esta no perfil dele');

select is(
  tests.codigo_do_erro(
    format($$select public.fn_estornar_entrega(%L::uuid, '   ')$$,
           (select movimento_id from r_diego)),
    tests.uid('secretaria@escola-a.test')),
  'MOTIVO_OBRIGATORIO',
  'motivo em branco nao passa: desfazer uma entrega e decisao, e decisao sem porque se perde');

select is(
  tests.codigo_do_erro(
    $$select public.fn_estornar_entrega('00000000-0000-0000-0000-000000000002'::uuid, 'x')$$,
    tests.uid('secretaria@escola-a.test')),
  'MOVIMENTO_INEXISTENTE',
  'movimento que nao existe e PT404 / MOVIMENTO_INEXISTENTE — o unico codigo novo do card');

select is(
  tests.codigo_do_erro(
    $$select public.fn_estornar_entrega(
        (select mv.id from public.movimento_estoque mv
          where mv.unidade_id = public.fn_unidade_atual() and mv.tipo = 'ENTRADA'
          order by mv.ocorrido_em, mv.id limit 1), 'x')$$,
    tests.uid('secretaria@escola-a.test')),
  'MOVIMENTO_NAO_ESTORNAVEL',
  'ENTRADA de pedido nao se estorna por aqui: desfazer compra e outra conversa (card 6.5)');

-- O par saída+estorno de Eduarda já vem pronto da fixture (seed §8.5) — é a única
-- linha com `estorno_de_id`, e existe justamente para dar à unique parcial
-- `movimento_estorno_uk` algo para vigiar.
select is(
  tests.codigo_do_erro(
    $$select public.fn_estornar_entrega(
        (select mv.estorno_de_id from public.movimento_estoque mv
          where mv.unidade_id = public.fn_unidade_atual() and mv.tipo = 'ESTORNO'
          order by mv.ocorrido_em, mv.id limit 1), 'de novo')$$,
    tests.uid('secretaria@escola-a.test')),
  'MOVIMENTO_JA_ESTORNADO',
  'e movimento ja estornado e recusado com codigo do catalogo, nao com um 23505 cru');

-- ===========================================================================
-- 8. Camada 2 — a exceção nomeada é ESTREITA
-- ===========================================================================
-- O teste 050 §6 já mede a guarda inteira fechada. O que este card acrescenta é a
-- brecha, e o que interessa é o TAMANHO dela: fora do contexto de entrega, nada
-- mudou; dentro dele, só `ordem` passa.
select is(
  tests.codigo_do_erro(
    format($$update public.aluno_material set ordem = ordem + 50
              where aluno_id = %L::uuid$$, (select carla from alvo)),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'fora do contexto de entrega o monitor continua sem reordenar a trilha — nada afrouxou');

select tests.autenticar(tests.uid('monitor@escola-a.test'));
select set_config('app.entrega_reordenacao', 'on', true);

select lives_ok(
  $$update public.aluno_material set ordem = ordem + 1000
     where aluno_id = (select a.id from public.aluno a
                        where a.unidade_id = public.fn_unidade_atual()
                          and a.nome = 'Carla Menezes')$$,
  'dentro do contexto, `ordem` passa — e e so isso que fn_registrar_entrega precisa');

reset role;

-- A GUC continua LIGADA nas duas asserções abaixo — é esse o ponto: mesmo dentro
-- do contexto de entrega, as outras três colunas da guarda continuam fechadas.
select is(
  tests.codigo_do_erro(
    format($$update public.aluno_material set origem = 'MANUAL'
              where aluno_id = %L::uuid$$, (select carla from alvo)),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'e MESMO DENTRO do contexto, `origem` continua exigindo alunos.editar_trilha');

select is(
  tests.codigo_do_erro(
    format($$update public.aluno_material am set material_id =
               (select m.id from public.material m
                 where m.unidade_id = public.fn_unidade_atual()
                   and m.id <> am.material_id
                 order by m.id limit 1)
              where am.aluno_id = %L::uuid$$, (select carla from alvo)),
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'nem `material_id`: a excecao vale para UMA coluna, e a guarda do card 6.1 segue de pe');

select set_config('app.entrega_reordenacao', '', true);
select tests.encerrar_sessao();

-- ===========================================================================
-- 9. Contexto de entrega: quem escreve a GUC, e quem não escreve
-- ===========================================================================
-- A brecha da seção 8 só é segura porque ninguém mais entra no contexto. Isso
-- estava escrito na migração como argumento; aqui vira asserção — a mesma
-- promoção que o C9 faz com o contexto de rotina do card 2.2 §2.2.
--
-- `prosrc` inclui os comentários do corpo (lição do card 4.2), e a migração
-- MENCIONA a GUC em comentário mais de uma vez: sem removê-los, este teste
-- acusaria escritores que não existem.
create temporary view corpo_projeto as
  select p.proname,
         regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as fonte
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f';

select is(
  (select coalesce(string_agg(proname, ', ' order by proname), '')
     from corpo_projeto
    where fonte ~ 'set_config\s*\(\s*''app\.entrega_reordenacao'''),
  'fn_registrar_entrega',
  'so fn_registrar_entrega ESCREVE app.entrega_reordenacao — o contexto nao se forja de fora');

select is(
  (select coalesce(string_agg(proname, ', ' order by proname), '')
     from corpo_projeto
    where fonte ~ 'fn_contexto_entrega'),
  'fn_aluno_material_colunas_permitidas',
  'e so a guarda o LE: nenhuma outra funcao decide nada com base nele');

-- A decisão escrita no cabeçalho da migração: definer NÃO era saída, porque
-- tem_permissao é escrita sobre auth.uid() e não sobre current_user.
select ok(
  not (select prosecdef from pg_proc
        where pronamespace = 'public'::regnamespace and proname = 'fn_registrar_entrega'),
  'fn_registrar_entrega NAO e security definer: definer nao atravessa fn_exige_permissao');

select ok(
  not (select prosecdef from pg_proc
        where pronamespace = 'public'::regnamespace and proname = 'fn_estornar_entrega'),
  'nem fn_estornar_entrega — as duas continuam sujeitas as politicas de movimento_estoque');

-- ===========================================================================
-- 10. O advisory lock não sumiu (C13, docs/estrategia-testes.md §5.1)
-- ===========================================================================
-- Guarda-chuva barato, e NÃO substitui
-- supabase/tests_concorrencia/entrega_ultimo_exemplar.sh: aqui a corrida não
-- existe — o `select` que lê o saldo e o `insert` que grava a saída acontecem na
-- mesma conexão e na mesma transação.
select is(
  (select coalesce(string_agg(proname, ',' order by proname), '')
     from corpo_projeto
    where proname in ('fn_registrar_entrega', 'fn_estornar_entrega')
      and fonte ~ 'pg_advisory_xact_lock'),
  'fn_estornar_entrega,fn_registrar_entrega',
  'C13: entrega e estorno serializam com pg_advisory_xact_lock');

select is(
  (select count(*)::bigint from corpo_projeto
    where proname = 'fn_registrar_entrega' and fonte ~ 'for\s+update'),
  0::bigint,
  'e a entrega NAO usa `for update` em `aluno`: sob RLS ele exigiria a politica de update, que o monitor nao passa');

-- A mecânica da reposição tem um dono só: duas cópias da mesma renumeração
-- divergiriam no dia em que uma mudasse.
select is(
  (select coalesce(string_agg(proname, ',' order by proname), '')
     from corpo_projeto
    where fonte ~ 'fn_trilha_reposicionar' and proname <> 'fn_trilha_reposicionar'),
  'fn_registrar_entrega,fn_trilha_reordenar',
  'a reposicao tem um dono so, e os dois caminhos (manual e por falta de estoque) o chamam');

-- ===========================================================================
-- 11. Portão do card 8.3 — o checklist do certificado
-- ===========================================================================
-- O passo 9 do §6.2 (abrir o checklist no FIM) e o passo 5 do §6.3 (apagar ou
-- marcar inconsistente o checklist no estorno) dependiam de
-- `certificado_checklist`, que é do card 8.3. Esquecê-los não daria erro nenhum:
-- daria um aluno que terminou a trilha e nunca entrou na fila do certificado, e um
-- estorno que deixa um checklist aberto para quem voltou a ter livro pendente.
--
-- ⚠️ O PORTÃO DISPAROU em 05/09/2026, e a expressão dele mudou junto — a
--    DIVERGÊNCIA está registrada. Ele procurava a citação literal de
--    `certificado_checklist` no corpo das duas funções, escrito quando se supunha
--    que elas fariam o `insert` e o `delete` inline. Não fazem, e não devem: o
--    passo 9 chama `fn_certificado_abrir` (a idempotência tem um dono só, como a
--    reposição da seção 10 acima) e o passo 5 chama
--    `fn_certificado_reavaliar_estorno`, que precisa ser `security definer`
--    porque a tabela não tem política de delete para ninguém. Duplicar o SQL para
--    satisfazer a letra do portão seria duas implementações da mesma regra — o
--    defeito que este arquivo já mede na seção 10.
--
--    O que o portão passou a exigir é MAIS específico, não menos: cada função tem
--    de citar a SUA função de certificado, pelo nome. A forma antiga aceitaria
--    qualquer menção à tabela nas duas.
--
-- Mesma cautela do gate de FORMADO (card 4.2, teste 030 §5): os comentários saem
-- do `prosrc` antes da comparação, senão o portão passaria pelo próprio
-- comentário que descreve o que falta.
create temporary view portao_certificado as
  select to_regclass('public.certificado_checklist') is null
      or ((select fonte ~ 'fn_certificado_abrir' from corpo_projeto
            where proname = 'fn_registrar_entrega')
      and (select fonte ~ 'fn_certificado_reavaliar_estorno' from corpo_projeto
            where proname = 'fn_estornar_entrega')) as em_dia;

select ok((select em_dia from portao_certificado),
  'portao do certificado em dia: a tabela existe e as duas funcoes chamam a sua peca do certificado');

select is(
  (select count(*)::bigint from corpo_projeto
    where proname in ('fn_registrar_entrega', 'fn_estornar_entrega')
      and fonte ~ 'fn_certificado_'),
  2::bigint,
  'as DUAS citam — nem uma, que passaria com o estorno esquecido');

-- Prova por construção: portão que nunca foi visto vermelho é decoração. A
-- sabotagem é o estorno como o card 6.3 o deixou, sem o passo 5; a entrega
-- continua inteira, e é isso que prova que o portão exige as duas.
create or replace function public.fn_estornar_entrega(p_movimento_id uuid, p_motivo text)
returns uuid language plpgsql
set search_path = public, pg_temp
as $sab$ begin return null; end $sab$;

select ok(not (select em_dia from portao_certificado),
  'esquecido o passo 5 no estorno, o portao REPROVA mesmo com a entrega inteira');

select * from finish();
rollback;
