-- =============================================================================
-- Geração e edição da trilha — card 6.2
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Card de "Função/regra", então o §13 cobra quatro coisas: caminho feliz com
-- EFEITO conferido, um `throws_ok`/`codigo_do_erro` por código que as funções
-- podem levantar, um negativo de permissão, e a camada 2 quando houver trigger.
-- As quatro estão aqui, nesta ordem.
--
-- Fora da obrigação, o arquivo prova o que este card DECIDIU e que nenhum
-- catálogo enxerga:
--   • a trilha da fixture passou a NASCER da função (card 6.2) em vez de ter uma
--     cópia à mão da expansão do combo no seed — se as duas divergirem, é aqui
--     que aparece;
--   • "livro atual" e "próximo" continuam DERIVADOS: uma entrega muda o próximo
--     sem `update` em coluna nenhuma (decisão 2.2 (e), §14 da estratégia);
--   • a numeração de 10 em 10 não é estética — é o espaço da inserção manual, e
--     quando ele acaba a trilha é renumerada em vez de estourar num 23505 cru;
--   • `p_nova_ordem` de fn_trilha_reordenar é POSIÇÃO, não a coluna `ordem`;
--   • trocar o combo NÃO regenera a trilha: abre pendência, e a regeneração
--     fecha a pendência.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(54);

-- ===========================================================================
-- 1. A trilha da fixture nasceu da função (efeito conferido)
-- ===========================================================================
-- O seed tinha, até o card 6.1, uma cópia da expansão combo → curso → material.
-- Ela saiu: a camada `alunos` insere o aluno e `tg_aluno_trilha_inicial` faz o
-- resto. Estas quatro asserções são o que garante que a troca foi de caminho e
-- não de resultado.
select is(
  (select string_agg(am.ordem::text, ',' order by am.ordem)
     from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Carla Menezes'),
  '10,20,30',
  'a trilha do combo de Informatica sai numerada de 10 em 10 (card 2.2 §5.1, passo 4)');

select is(
  (select string_agg(distinct am.origem, ',')
     from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Carla Menezes'),
  'COMBO',
  'e com origem COMBO em todos os itens — o que a permite ser regenerada depois');

-- O histórico da geração é o que dá base de comparação a toda reordenação
-- futura: sem ele, "por que esta trilha está fora da ordem do combo" não tem
-- ponto de partida.
select is(
  (select count(*)::bigint
     from public.aluno_material_hist h
     join public.aluno a on a.id = h.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Carla Menezes'
      and h.motivo = 'GERACAO_COMBO'),
  3::bigint,
  'a geracao deixou uma linha GERACAO_COMBO por item em aluno_material_hist');

select is(
  (select count(*)::bigint from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Karina Bastos'),
  0::bigint,
  'a aluna SEM combo continua sem trilha — o `when` do trigger a deixa de fora');

-- ===========================================================================
-- 2. As três consultas derivadas (§5.2)
-- ===========================================================================
select is(
  public.fn_trilha_proximo_material(
    (select id from public.aluno
      where nome = 'Carla Menezes' and unidade_id = tests.unidade('ESCOLA_A'))),
  (select m.id from public.material m
     join public.metodo me on me.id = m.metodo_id
    where m.unidade_id = tests.unidade('ESCOLA_A')
      and me.codigo = 'INTERATIVO' and m.codigo = '01'),
  'o proximo livro e a MENOR ordem ainda nao entregue');

select is(
  public.fn_trilha_atual(
    (select id from public.aluno
      where nome = 'Carla Menezes' and unidade_id = tests.unidade('ESCOLA_A'))),
  public.fn_trilha_proximo_material(
    (select id from public.aluno
      where nome = 'Carla Menezes' and unidade_id = tests.unidade('ESCOLA_A'))),
  'fn_trilha_atual e fn_trilha_proximo_material devolvem o MESMO item — sao sinonimos por construcao');

select is(
  public.fn_trilha_em_fim(
    (select id from public.aluno
      where nome = 'João Pedro Martins' and unidade_id = tests.unidade('ESCOLA_A'))),
  true,
  'quem teve todos os itens entregues esta em FIM');

select is(
  public.fn_trilha_em_fim(
    (select id from public.aluno
      where nome = 'Carla Menezes' and unidade_id = tests.unidade('ESCOLA_A'))),
  false,
  'e quem tem item pendente nao esta');

-- A armadilha, escrita porque ela é real e é a mesma da coluna `em_fim` de
-- v_dashboard_alunos_metodo (card 2.3 §8.1): aluno SEM trilha também responde
-- FIM. Quem precisa distinguir "acabou" de "nunca começou" pergunta pela trilha.
select is(
  public.fn_trilha_em_fim(
    (select id from public.aluno
      where nome = 'Karina Bastos' and unidade_id = tests.unidade('ESCOLA_A'))),
  true,
  'aluno sem trilha nenhuma tambem devolve FIM — mesma leitura do dashboard do card 2.3');

-- "Livro atual e próximo são DERIVADOS, nunca coluna" (decisão 2.2 (e), §14 da
-- estratégia de testes). A entrega é simulada com o `update` das três colunas que
-- o card 6.1 §9 deixa fora da guarda — nenhuma coluna de "próximo" é tocada,
-- porque nenhuma existe.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

update public.aluno_material
   set entregue = true, data_entrega = public.fn_hoje()
 where aluno_id = (select id from public.aluno
                    where nome = 'Carla Menezes'
                      and unidade_id = public.fn_unidade_atual())
   and ordem = 10;

reset role;

select is(
  public.fn_trilha_proximo_material(
    (select id from public.aluno
      where nome = 'Carla Menezes' and unidade_id = tests.unidade('ESCOLA_A'))),
  (select m.id from public.material m
     join public.metodo me on me.id = m.metodo_id
    where m.unidade_id = tests.unidade('ESCOLA_A')
      and me.codigo = 'INTERATIVO' and m.codigo = '02'),
  'entregue o primeiro, o PROXIMO anda sozinho — sem update em coluna nenhuma que o guarde');

-- ===========================================================================
-- 3. fn_trilha_gerar — os erros primeiro, enquanto o cenário ainda os permite
-- ===========================================================================
-- A ordem é deliberada: ALUNO_SEM_COMBO só existe enquanto Karina não tem combo,
-- e a seção 4 lhe dá um. Teste que depende de ordem é teste frágil — mas teste
-- que MONTA o cenário que quer é pior, porque passa a medir o próprio setup.
select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_gerar(
        (select id from public.aluno
          where nome = 'Karina Bastos' and unidade_id = public.fn_unidade_atual()))$$,
    tests.uid('secretaria@escola-a.test')),
  'ALUNO_SEM_COMBO',
  'sem combo no aluno e sem p_combo_id, nao ha de onde gerar a trilha');

select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_gerar(
        (select id from public.aluno
          where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()))$$,
    tests.uid('secretaria@escola-a.test')),
  'TRILHA_JA_EXISTE',
  'gerar sobre trilha existente sem p_substituir e recusado');

-- O caso mais caro dos dois: substituir uma trilha COM entrega apagaria a única
-- ligação entre a SAIDA de estoque e o aluno que a recebeu, e a apostila poderia
-- ser entregue outra vez com cara de entrega legítima.
select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_gerar(
        (select id from public.aluno
          where nome = 'Ana Paula Ribeiro' and unidade_id = public.fn_unidade_atual()),
        null, true)$$,
    tests.uid('secretaria@escola-a.test')),
  'TRILHA_COM_ENTREGA',
  'nem com p_substituir: trilha com entrega se edita item a item, nunca em bloco');

select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_gerar('00000000-0000-0000-0000-000000000000'::uuid)$$,
    tests.uid('secretaria@escola-a.test')),
  'ALUNO_INEXISTENTE',
  'aluno que nao existe (ou e de outra unidade) para em ALUNO_INEXISTENTE, nao num nulo silencioso');

-- O negativo de permissão que o §13 cobra. O monitor é o caso REAL, não um perfil
-- montado para o teste: ele tem `alunos.ler` e não tem `alunos.editar_trilha` nem
-- `alunos.criar` (card 2.4 §5).
select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_gerar(
        (select id from public.aluno
          where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
        null, true)$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor nao gera trilha — nem tem editar_trilha nem tem criar');

-- ===========================================================================
-- 4. fn_trilha_gerar — caminho feliz, com o efeito conferido
-- ===========================================================================
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select is(
  public.fn_trilha_gerar(
    (select id from public.aluno
      where nome = 'Karina Bastos' and unidade_id = public.fn_unidade_atual()),
    (select id from public.combo
      where nome = 'Informática Completo' and unidade_id = public.fn_unidade_atual())),
  3,
  'p_combo_id gera a trilha de quem nao tem combo no cadastro, e devolve quantos itens criou');

reset role;

select is(
  (select string_agg(am.ordem::text, ',' order by am.ordem)
     from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Karina Bastos'),
  '10,20,30',
  'com a mesma numeracao de 10 em 10 da matricula');

-- MATERIAL REPETIDO ENTRE CURSOS DO COMBO (§5.1, passo 5). A fixture não tem esse
-- caso — os dois cursos de Informática não compartilham apostila —, então ele é
-- montado aqui: `INTERATIVO 01` entra também no curso Avançada, que é o SEGUNDO
-- do combo. Sem o `distinct on`, a expansão devolveria quatro linhas e a segunda
-- morreria em `aluno_material_uk`, derrubando a matrícula inteira num 23505 cru.
insert into public.curso_material (unidade_id, curso_id, material_id, ordem)
select tests.unidade('ESCOLA_A'), c.id, m.id, 2
  from public.curso c
  join public.metodo me on me.id = c.metodo_id
  join public.material m on m.unidade_id = tests.unidade('ESCOLA_A')
                        and m.metodo_id = me.id and m.codigo = '01'
 where c.unidade_id = tests.unidade('ESCOLA_A') and c.nome = 'Informática Avançada';

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select is(
  public.fn_trilha_gerar(
    (select id from public.aluno
      where nome = 'Karina Bastos' and unidade_id = public.fn_unidade_atual()),
    (select id from public.combo
      where nome = 'Informática Completo' and unidade_id = public.fn_unidade_atual()),
    true),
  3,
  'material repetido entre dois cursos do combo entra UMA vez — tres itens, nao quatro');

reset role;

select is(
  (select am.ordem from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
     join public.material m on m.id = am.material_id
     join public.metodo me on me.id = m.metodo_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Karina Bastos'
      and me.codigo = 'INTERATIVO' and m.codigo = '01'),
  10,
  'e na PRIMEIRA posicao em que aparece, nao na ultima');

-- ===========================================================================
-- 5. Substituição válida — a trilha sem entrega pode ser regenerada
-- ===========================================================================
-- Gabriela tem trilha de Inglês (dois itens) e nenhuma entrega: é o único caso da
-- fixture em que p_substituir é legítimo.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select is(
  public.fn_trilha_gerar(
    (select id from public.aluno
      where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
    null, true),
  2,
  'trilha sem entrega e regenerada com p_substituir');

reset role;

-- A trilha antiga saiu COM RASTRO. Sem estas linhas, uma regeneração deixaria a
-- trilha diferente do que era e nada explicando a diferença.
select is(
  (select count(*)::bigint from public.aluno_material_hist h
     join public.aluno a on a.id = h.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'
      and h.motivo = 'REMOCAO'),
  2::bigint,
  'e a trilha antiga saiu com uma linha REMOCAO por item — regeneracao nao apaga historia');

-- ===========================================================================
-- 6. fn_trilha_inserir — o espaço da numeração, e o que acontece quando acaba
-- ===========================================================================
-- As inclusões abaixo põem apostilas de INTERATIVO na trilha de uma aluna de
-- INGLÊS, e isso é de propósito: a fixture tem seis materiais e o combo dela usa
-- dois, então não haveria com que exercitar a inserção sem sair do método. Vale
-- registrar que o banco PERMITE — o trigger de coerência do card 6.1 §11 vigia a
-- composição do CATÁLOGO (curso, módulo, combo), não a trilha de um aluno, que é
-- decisão de quem tem `alunos.editar_trilha`. Se um dia isso tiver de mudar, é
-- decisão de produto e não conserto de teste.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_trilha_inserir(
      (select id from public.aluno
        where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
      (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
        where m.unidade_id = public.fn_unidade_atual()
          and me.codigo = 'INTERATIVO' and m.codigo = '01'),
      (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
        where m.unidade_id = public.fn_unidade_atual()
          and me.codigo = 'INGLES' and m.codigo = '01'))$$,
  'inserir depois do primeiro item da trilha');

reset role;

select is(
  (select am.ordem from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
     join public.material m on m.id = am.material_id
     join public.metodo me on me.id = m.metodo_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'
      and me.codigo = 'INTERATIVO' and m.codigo = '01'),
  15,
  'o item entra NO ESPACO entre 10 e 20 — e por isso a geracao numera de 10 em 10');

select is(
  (select am.origem from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
     join public.material m on m.id = am.material_id
     join public.metodo me on me.id = m.metodo_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'
      and me.codigo = 'INTERATIVO' and m.codigo = '01'),
  'MANUAL',
  'com origem MANUAL — e o que distingue o que uma pessoa decidiu do que veio do combo');

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_trilha_inserir(
      (select id from public.aluno
        where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
      (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
        where m.unidade_id = public.fn_unidade_atual()
          and me.codigo = 'INTERATIVO' and m.codigo = '02'))$$,
  'p_apos_material_id nulo poe o item no COMECO da trilha');

reset role;

select is(
  (select am.ordem from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
     join public.material m on m.id = am.material_id
     join public.metodo me on me.id = m.metodo_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'
      and me.codigo = 'INTERATIVO' and m.codigo = '02'),
  5,
  'e ele fica ANTES do primeiro (ordem 5), sem renumerar nada');

select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_inserir(
        (select id from public.aluno
          where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
        (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
          where m.unidade_id = public.fn_unidade_atual()
            and me.codigo = 'INGLES' and m.codigo = '01'))$$,
    tests.uid('secretaria@escola-a.test')),
  'MATERIAL_JA_NA_TRILHA',
  'a mesma apostila duas vezes na trilha e recusada COM CODIGO — sem isto seria um 23505 cru na tela');

select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_inserir(
        (select id from public.aluno
          where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
        (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
          where m.unidade_id = public.fn_unidade_atual()
            and me.codigo = 'INTERATIVO' and m.codigo = '03'),
        (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
          where m.unidade_id = public.fn_unidade_atual()
            and me.codigo = 'MODULAR' and m.codigo = '01'))$$,
    tests.uid('secretaria@escola-a.test')),
  'MATERIAL_FORA_DA_TRILHA',
  'e a referencia "depois de X" precisa estar na trilha do aluno');

-- O ESPAÇO ACABA, e é o ramo que ninguém escreveria sem pensar nele: quatro
-- inclusões na mesma fresta esgotam o intervalo. Aqui as duas primeiras posições
-- são grudadas de propósito (1 e 2) para chegar ao caso em uma tacada.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

update public.aluno_material set ordem = 1
 where aluno_id = (select id from public.aluno
                    where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual())
   and ordem = 5;

update public.aluno_material set ordem = 2
 where aluno_id = (select id from public.aluno
                    where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual())
   and ordem = 10;

select lives_ok(
  $$select public.fn_trilha_inserir(
      (select id from public.aluno
        where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
      (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
        where m.unidade_id = public.fn_unidade_atual()
          and me.codigo = 'INTERATIVO' and m.codigo = '03'),
      (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
        where m.unidade_id = public.fn_unidade_atual()
          and me.codigo = 'INTERATIVO' and m.codigo = '02'))$$,
  'sem espaco entre 1 e 2, a insercao RENUMERA a trilha em vez de estourar');

reset role;

-- ⚠️ ACHADO DA CONTRAPROVA (04/09/2026): este `lives_ok` sozinho **não pega** a
--    ausência da renumeração. Medido — com o ramo sabotado (`if false then`), a
--    inserção grava a ordem 1 em cima da que já existe e o `lives_ok` passa
--    VERDE, porque `aluno_material_ordem_uk` é DEFERRABLE INITIALLY DEFERRED
--    (card 2.1 (e)): a violação só seria levantada no `commit`, e este arquivo
--    termina em `rollback`. Quem acusa é a asserção seguinte, que LÊ a trilha de
--    volta. É a lição do card 2.8 escrita mais uma vez: "não levantou exceção"
--    não é asserção, e num schema com constraint adiada isso deixa de ser
--    princípio e vira mecânica.

select is(
  (select string_agg(am.ordem::text, ',' order by am.ordem)
     from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'),
  '10,15,20,30,40',
  'a trilha volta a ser multipla de 10 e o item novo cai no espaco recem-aberto');

-- E a ordem RELATIVA não mudou: renumerar não é reordenar. Sem esta asserção, a
-- renumeração poderia embaralhar a trilha e o teste anterior passaria igual.
select is(
  (select string_agg(me.codigo || ' ' || m.codigo, ',' order by am.ordem)
     from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
     join public.material m on m.id = am.material_id
     join public.metodo me on me.id = m.metodo_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'),
  'INTERATIVO 02,INTERATIVO 03,INGLES 01,INTERATIVO 01,INGLES 02',
  'e a sequencia relativa sobreviveu a renumeracao — renumerar nao e reordenar');

-- ===========================================================================
-- 7. fn_trilha_remover
-- ===========================================================================
select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_remover(
        (select id from public.aluno
          where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
        (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
          where m.unidade_id = public.fn_unidade_atual()
            and me.codigo = 'INTERATIVO' and m.codigo = '03'),
        '   ')$$,
    tests.uid('secretaria@escola-a.test')),
  'MOTIVO_OBRIGATORIO',
  'tirar apostila da trilha e decisao, e decisao sem porque e decisao perdida');

select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_remover(
        (select id from public.aluno
          where nome = 'Ana Paula Ribeiro' and unidade_id = public.fn_unidade_atual()),
        (select am.material_id from public.aluno_material am
          where am.aluno_id = (select id from public.aluno
                                where nome = 'Ana Paula Ribeiro'
                                  and unidade_id = public.fn_unidade_atual())
            and am.entregue order by am.ordem limit 1),
        'quero tirar mesmo assim')$$,
    tests.uid('secretaria@escola-a.test')),
  'ITEM_JA_ENTREGUE',
  'item entregue nao sai pela funcao — a guarda do card 6.1 §10.1 e a mesma regra na camada de baixo');

select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_remover(
        (select id from public.aluno
          where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
        (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
          where m.unidade_id = public.fn_unidade_atual()
            and me.codigo = 'MODULAR' and m.codigo = '01'),
        'nao esta na trilha dela')$$,
    tests.uid('secretaria@escola-a.test')),
  'MATERIAL_FORA_DA_TRILHA',
  'e o que nao esta na trilha nao se remove dela');

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_trilha_remover(
      (select id from public.aluno
        where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
      (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
        where m.unidade_id = public.fn_unidade_atual()
          and me.codigo = 'INTERATIVO' and m.codigo = '03'),
      'entrou por engano na matricula')$$,
  'item PENDENTE sai da trilha com motivo');

reset role;

-- O motivo vai para `observacao` (ajuste 4 do §14 do card 2.2), e o `motivo` da
-- tabela continua sendo o enum fechado. É a leitura que resolve a colisão de nome
-- entre o parâmetro do §5.3 e a coluna do §14.
select is(
  (select h.observacao from public.aluno_material_hist h
     join public.aluno a on a.id = h.aluno_id
     join public.material m on m.id = h.material_id
     join public.metodo me on me.id = m.metodo_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'
      and h.motivo = 'REMOCAO' and me.codigo = 'INTERATIVO' and m.codigo = '03'),
  'entrou por engano na matricula',
  'o p_motivo da remocao mora em `observacao`; o `motivo` da tabela e REMOCAO, do enum fechado');

-- ===========================================================================
-- 8. fn_trilha_reordenar — `p_nova_ordem` é POSIÇÃO, não a coluna `ordem`
-- ===========================================================================
-- A trilha de Gabriela está em 10, 20, 30, 40 (INTERATIVO 02, INGLES 01,
-- INTERATIVO 01, INGLES 02). Mover o último para a posição 1 é o caso que
-- distingue as duas leituras possíveis do parâmetro: com "posição", ele vira o
-- primeiro; com "ordem bruta", ele iria para a ordem 1 e ficaria antes de tudo
-- por acidente de numeração, e a diferença só apareceria depois de uma
-- renumeração.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_trilha_reordenar(
      (select id from public.aluno
        where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
      (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
        where m.unidade_id = public.fn_unidade_atual()
          and me.codigo = 'INGLES' and m.codigo = '02'),
      1)$$,
  'reordenar para a posicao 1 e UM UNICO update — o que o unique DEFERRABLE do card 2.1 (e) compra');

reset role;

select is(
  (select string_agg(me.codigo || ' ' || m.codigo, ',' order by am.ordem)
     from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
     join public.material m on m.id = am.material_id
     join public.metodo me on me.id = m.metodo_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'),
  'INGLES 02,INTERATIVO 02,INGLES 01,INTERATIVO 01',
  'o item movido virou o PRIMEIRO da trilha, e os outros desceram na ordem em que estavam');

select is(
  (select string_agg(am.ordem::text, ',' order by am.ordem)
     from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'),
  '10,20,30,40',
  'e a trilha saiu renumerada de 10 em 10, com o espaco de volta para a proxima insercao');

select is(
  (select am.origem from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
     join public.material m on m.id = am.material_id
     join public.metodo me on me.id = m.metodo_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'
      and me.codigo = 'INGLES' and m.codigo = '02'),
  'MANUAL',
  'so a linha MOVIDA vira MANUAL — as outras foram empurradas, nao editadas');

select is(
  (select h.ordem_anterior || '->' || h.ordem_nova
     from public.aluno_material_hist h
     join public.aluno a on a.id = h.aluno_id
     join public.material m on m.id = h.material_id
     join public.metodo me on me.id = m.metodo_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'
      and h.motivo = 'MANUAL' and me.codigo = 'INGLES' and m.codigo = '02'),
  '40->10',
  'e o historico guarda de onde para onde — que e a pergunta feita tres meses depois');

-- Posição fora da trilha é GRAMPEADA nas bordas, e não erro: arrastar para além
-- do fim é gesto comum na tela e significa "põe no fim".
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_trilha_reordenar(
      (select id from public.aluno
        where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
      (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
        where m.unidade_id = public.fn_unidade_atual()
          and me.codigo = 'INGLES' and m.codigo = '02'),
      999)$$,
  'posicao alem do fim nao e erro — e "poe no fim"');

reset role;

select is(
  (select am.ordem from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
     join public.material m on m.id = am.material_id
     join public.metodo me on me.id = m.metodo_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Gabriela Souza'
      and me.codigo = 'INGLES' and m.codigo = '02'),
  40,
  'e o item foi mesmo para a ultima posicao');

select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_reordenar(
        (select id from public.aluno
          where nome = 'Ana Paula Ribeiro' and unidade_id = public.fn_unidade_atual()),
        (select am.material_id from public.aluno_material am
          where am.aluno_id = (select id from public.aluno
                                where nome = 'Ana Paula Ribeiro'
                                  and unidade_id = public.fn_unidade_atual())
            and am.entregue order by am.ordem limit 1),
        3)$$,
    tests.uid('secretaria@escola-a.test')),
  'ITEM_JA_ENTREGUE',
  'item entregue nao muda de posicao — a trilha entregue e passado');

-- ===========================================================================
-- 9. O negativo de permissão nas três funções de edição (§13)
-- ===========================================================================
-- As três exigem `alunos.editar_trilha` (card 2.2 §5.3), e o monitor não a tem.
-- Sem estas três, a permissão estaria escrita na função e não medida em lugar
-- nenhum — que é a definição de comentário.
select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_inserir(
        (select id from public.aluno
          where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
        (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
          where m.unidade_id = public.fn_unidade_atual()
            and me.codigo = 'MODULAR' and m.codigo = '01'))$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor nao inclui item na trilha');

select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_remover(
        (select id from public.aluno
          where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
        (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
          where m.unidade_id = public.fn_unidade_atual()
            and me.codigo = 'INGLES' and m.codigo = '01'),
        'porque sim')$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'nem remove');

select is(
  tests.codigo_do_erro(
    $$select public.fn_trilha_reordenar(
        (select id from public.aluno
          where nome = 'Gabriela Souza' and unidade_id = public.fn_unidade_atual()),
        (select m.id from public.material m join public.metodo me on me.id = m.metodo_id
          where m.unidade_id = public.fn_unidade_atual()
            and me.codigo = 'INGLES' and m.codigo = '01'),
        1)$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'nem reordena — e e por isso que o card 6.3 tera de decidir como a entrega dele reordena');

-- ===========================================================================
-- 10. Camada 2 — tg_aluno_trilha_inicial (a trilha nasce na matrícula)
-- ===========================================================================
-- É o trigger que impede fn_trilha_gerar de ser uma função entregue, testada e
-- sem chamador (o defeito do card 4.7,7).
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

insert into public.aluno (unidade_id, nome, metodo_id, combo_id, status)
select public.fn_unidade_atual(), 'Matricula Com Combo', me.id, cb.id, 'ATIVO'
  from public.metodo me
  join public.combo cb on cb.unidade_id = public.fn_unidade_atual()
                      and cb.nome = 'Inglês Kids Completo'
 where me.unidade_id = public.fn_unidade_atual() and me.codigo = 'INGLES';

insert into public.aluno (unidade_id, nome, metodo_id, status)
select public.fn_unidade_atual(), 'Matricula Sem Combo', me.id, 'ATIVO'
  from public.metodo me
 where me.unidade_id = public.fn_unidade_atual() and me.codigo = 'INGLES';

reset role;

select is(
  (select string_agg(am.ordem::text, ',' order by am.ordem)
     from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Matricula Com Combo'),
  '10,20',
  'matricular com combo gera a trilha na hora — ninguem precisa lembrar de clicar num botao');

select is(
  (select count(*)::bigint from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Matricula Sem Combo'),
  0::bigint,
  'e matricular SEM combo continua funcionando, sem trilha e sem ALUNO_SEM_COMBO derrubando o cadastro');

-- ===========================================================================
-- 11. Camada 2 — tg_aluno_combo_alterado (trocar combo não regenera)
-- ===========================================================================
-- Regenerar apagaria entregas já feitas ou duplicaria saídas de estoque (card 2.2
-- §3.2). A pendência põe um humano na decisão.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

update public.aluno set combo_id = (select id from public.combo
                                     where nome = 'Informática Completo'
                                       and unidade_id = public.fn_unidade_atual())
 where nome = 'Matricula Com Combo' and unidade_id = public.fn_unidade_atual();

reset role;

select is(
  (select p.tipo from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Matricula Com Combo'
      and p.resolvida_em is null),
  'TRILHA_DIVERGENTE_COMBO',
  'trocar o combo abre pendencia em vez de regenerar a trilha por conta propria');

select is(
  (select string_agg(am.ordem::text, ',' order by am.ordem)
     from public.aluno_material am
     join public.aluno a on a.id = am.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Matricula Com Combo'),
  '10,20',
  'e a trilha continua sendo a do combo ANTERIOR, intacta — dois itens de Ingles');

-- A pendência não é eterna: quem a resolve é a regeneração, que é a ação que a
-- própria pendência pede. Pendência que ninguém fecha é a central do card 5.8
-- perdendo credibilidade.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_trilha_gerar(
      (select id from public.aluno
        where nome = 'Matricula Com Combo' and unidade_id = public.fn_unidade_atual()),
      null, true)$$,
  'a regeneracao pedida pela pendencia e aceita — a trilha nao tinha entrega');

reset role;

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Matricula Com Combo'
      and p.resolvida_em is null),
  0::bigint,
  'e fecha a pendencia TRILHA_DIVERGENTE_COMBO ao terminar');

-- O `when (new.combo_id is distinct from old.combo_id)`: gravar o MESMO combo de
-- novo não abre pendência. Sem ele, `update of combo_id` dispara por a coluna
-- estar na lista do UPDATE, e a central encheria de ruído.
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

update public.aluno set combo_id = combo_id
 where nome = 'Matricula Com Combo' and unidade_id = public.fn_unidade_atual();

reset role;

select is(
  (select count(*)::bigint from public.pendencia p
     join public.aluno a on a.id = p.aluno_id
    where a.unidade_id = tests.unidade('ESCOLA_A') and a.nome = 'Matricula Com Combo'
      and p.resolvida_em is null),
  0::bigint,
  'gravar o mesmo combo de novo nao abre pendencia nenhuma');

select * from finish();
rollback;
