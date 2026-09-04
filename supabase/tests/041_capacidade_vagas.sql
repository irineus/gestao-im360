-- =============================================================================
-- Capacidade efetiva, ocupação e vagas livres — card 5.2
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- Card de "Função/regra", e as três não levantam exceção nenhuma: não há
-- `throws_ok` por `codigo` a fazer, e o §13 se resume ao caminho feliz com EFEITO
-- conferido mais o negativo de permissão. Só que aqui o negativo de permissão é
-- o CONTRÁRIO do usual — a asserção é que a função CONTINUA respondendo o número
-- certo para quem não pode ler as tabelas de onde ele sai (seção 5). É a decisão
-- que o card 2.3 §10 (#3) tomou e que este card implementa, e sem ela a grade
-- semanal do card 5.6 aparece inteira lotada para metade da escola.
--
-- Quatro coisas que este arquivo prova e que nenhum catálogo enxerga:
--   • a fórmula sai dos PCs e não de `capacidade_override` (a fixture deixa os
--     três blocos com override nulo justamente para isso);
--   • a ocupação soma as DUAS metades do REP híbrido — a reposição PREVISTA no
--     bloco vazio é a asserção que reprova quem somou só `bloco_aluno`;
--   • substituto de OUTRA sala repõe a capacidade, o da PRÓPRIA sala não — a
--     decisão (b) deste card, que impede dez máquinas valerem onze vagas;
--   • `p_data` é data de verdade: manutenção agendada não derruba a capacidade
--     de hoje e derruba a do dia dela.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(35);

-- ===========================================================================
-- 1. As premissas da fixture, que são o que dá sentido aos números abaixo
-- ===========================================================================
-- Sem elas, "capacidade = 10" passaria por coincidência no dia em que alguém
-- mexesse na fixture, e o teste continuaria verde dizendo outra coisa.
select is(
  (select s.capacidade_nominal::text || '/' ||
          (select count(*) from public.pc p
            where p.sala_id = s.id and p.status = 'OPERACIONAL')::text
     from public.sala s
    where s.unidade_id = tests.unidade('ESCOLA_A') and s.nome = 'Laboratório 1'),
  '10/10',
  'Laboratorio 1: nominal 10 e dez PCs OPERACIONAIS — os dois numeros que a formula combina');

select is(
  (select count(*)::bigint from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A')
      and b.capacidade_override is not null),
  0::bigint,
  'nenhum bloco com capacidade_override: a capacidade TEM de sair dos PCs');

-- Apelidos estáveis dos três blocos do Laboratório 1 (0, 9 e 10 alunos). Em
-- ordem alfabética: cheio, quase, vazio — é essa a ordem das agregações abaixo.
create temporary view t_bloco as
  select b.id,
         case b.dia_semana when 1 then 'vazio' when 2 then 'quase' else 'cheio' end as apelido
    from public.bloco_horario b
    join public.sala s on s.id = b.sala_id
   where b.unidade_id = tests.unidade('ESCOLA_A') and s.nome = 'Laboratório 1';

-- As três funções filtram a unidade NO CORPO (é o preço do `security definer`,
-- card 2.3 §10 #3), e `postgres` sem `auth.uid()` não tem unidade nenhuma: sem
-- contexto, todas devolveriam nulo e as seções 2 a 4 testariam o nada. O contexto
-- de ROTINA (card 2.2 §2.2) é o mais próximo do papel de quem escreve nas tabelas
-- aqui — e não é artifício de bancada: é exatamente o contexto em que
-- fn_revalidar_blocos_sala (card 5.4) e rt_pendencias_diaria (5.5) vão chamar
-- estas funções. A seção 5 o desliga e prova que ele foi desligado, senão o teste
-- que importa passaria de graça.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

-- ===========================================================================
-- 2. fn_capacidade_efetiva — a fórmula
-- ===========================================================================
-- A fixture tem uma manutenção FECHADA em LAB1-01 (hoje−60 a hoje−59): se a
-- função ignorasse `data_fim`, o Laboratório 1 já nasceria com 9 e este 10 seria
-- a única coisa a denunciar.
select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio')),
  10,
  'dez PCs operacionais, nominal 10 e uma manutencao FECHADA no historico: capacidade 10');

-- Laboratório 2 é o caso oposto e o único com os três estados de PC: nominal 6,
-- seis PCs, quatro operacionais, um em MANUTENCAO com manutenção aberta sem
-- substituto e um DESATIVADO. Três números distintos de propósito (card 4.3) —
-- somar a coluna errada dá 6 e não 4. Precisa de um bloco, que a fixture não tem
-- lá: os três dela ficam no Laboratório 1, onde a borda 10/11 do card 5.3 mora.
insert into public.bloco_horario (unidade_id, dia_semana, hora_inicio, metodo_id, sala_id)
select tests.unidade('ESCOLA_A'), 4, time '10:00',
       (select id from public.metodo
         where unidade_id = tests.unidade('ESCOLA_A') and codigo = 'INTERATIVO'),
       s.id
  from public.sala s
 where s.unidade_id = tests.unidade('ESCOLA_A') and s.nome = 'Laboratório 2';

select is(
  public.fn_capacidade_efetiva(
    (select b.id from public.bloco_horario b
       join public.sala s on s.id = b.sala_id
      where b.unidade_id = tests.unidade('ESCOLA_A') and s.nome = 'Laboratório 2')),
  4,
  'Laboratorio 2: DESATIVADO nao conta e manutencao aberta sem substituto derruba — 4, nao 6');

-- ---------------------------------------------------------------------------
-- 2.1 Manutenção: sem substituto derruba; com substituto de FORA repõe
-- ---------------------------------------------------------------------------
insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, descricao)
select tests.unidade('ESCOLA_A'), p.id, 'CORRETIVA', public.fn_hoje(), 'teste: sem substituto'
  from public.pc p
 where p.unidade_id = tests.unidade('ESCOLA_A') and p.identificador = 'LAB1-02';

select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio')),
  9,
  'um PC em manutencao aberta sem substituto: capacidade cai para 9');

-- O substituto vem do Laboratório 2 — máquina que NÃO estava contada nesta sala.
update public.pc_manutencao m
   set pc_substituto_id = (select p.id from public.pc p
                            where p.unidade_id = tests.unidade('ESCOLA_A')
                              and p.identificador = 'LAB2-01')
 where m.pc_id = (select p.id from public.pc p
                   where p.unidade_id = tests.unidade('ESCOLA_A')
                     and p.identificador = 'LAB1-02')
   and m.data_fim is null;

select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio')),
  10,
  'substituto de OUTRA sala repoe a vaga: capacidade volta a 10');

-- A decisão (b) do card: substituto da PRÓPRIA sala não cria máquina nenhuma.
-- Sem esta cláusula, dez PCs físicos passariam a valer onze vagas — e o número
-- teria a cara de estar certo.
update public.pc_manutencao m
   set pc_substituto_id = (select p.id from public.pc p
                            where p.unidade_id = tests.unidade('ESCOLA_A')
                              and p.identificador = 'LAB1-05')
 where m.pc_id = (select p.id from public.pc p
                   where p.unidade_id = tests.unidade('ESCOLA_A')
                     and p.identificador = 'LAB1-02')
   and m.data_fim is null;

select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio')),
  9,
  'substituto da PROPRIA sala nao repoe: a maquina ja estava contada');

-- O PC em manutenção COM substituto conta mesmo com `status` em MANUTENCAO — que
-- era "o mundo que o tg_pc_manutencao_status do card 5.4 vai criar" quando isto
-- foi escrito, no card 5.2, e **é o mundo de agora**: o trigger existe desde
-- 04/09/2026 e o `update` abaixo virou redundante (o trigger já pôs o PC em
-- MANUTENCAO ao gravar a manutenção). Ficou de propósito, porque é ele que torna
-- o estado explícito para quem lê — e a asserção continua sendo a única coisa
-- entre "substituto mantém a capacidade" e a regra deixar de valer em silêncio.
update public.pc_manutencao m
   set pc_substituto_id = (select p.id from public.pc p
                            where p.unidade_id = tests.unidade('ESCOLA_A')
                              and p.identificador = 'LAB2-01')
 where m.pc_id = (select p.id from public.pc p
                   where p.unidade_id = tests.unidade('ESCOLA_A')
                     and p.identificador = 'LAB1-02')
   and m.data_fim is null;

update public.pc set status = 'MANUTENCAO'
 where unidade_id = tests.unidade('ESCOLA_A') and identificador = 'LAB1-02';

select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio')),
  10,
  'status MANUTENCAO com substituto de fora: continua contando (o mundo do card 5.4)');

-- E o inverso: status MANUTENCAO marcado à mão, sem manutenção aberta nenhuma,
-- não conta.
--
-- ⚠️ REESCRITO NO CARD 5.4, e a ordem das duas escritas é o que mudou. Encerrar
--    a manutenção agora dispara `tg_pc_manutencao_status`, que devolve o PC a
--    OPERACIONAL na mesma transação — a marcação à mão TEM de vir depois, senão
--    o trigger a desfaz e a asserção mede outra coisa. O estado continua
--    alcançável (`pc.status` é editável por quem tem `salas.editar`, e é um
--    PATCH direto no PostgREST), e é ele que se mede aqui: PC marcado parado sem
--    nada que o explique não conta vaga. `rt_pcs_normaliza` (card 5.4) o
--    normaliza na execução seguinte, o que é outro teste, no arquivo 091.
update public.pc_manutencao
   set data_inicio = public.fn_hoje() - 2, data_fim = public.fn_hoje() - 1
 where pc_id = (select p.id from public.pc p
                 where p.unidade_id = tests.unidade('ESCOLA_A')
                   and p.identificador = 'LAB1-02')
   and data_fim is null;

update public.pc set status = 'MANUTENCAO'
 where unidade_id = tests.unidade('ESCOLA_A') and identificador = 'LAB1-02';

select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio')),
  9,
  'status MANUTENCAO sem manutencao aberta: nao conta — a fórmula olha a manutencao, nao so o status');

update public.pc set status = 'OPERACIONAL'
 where unidade_id = tests.unidade('ESCOLA_A') and identificador = 'LAB1-02';

-- ---------------------------------------------------------------------------
-- 2.2 p_data é data de verdade, não "agora"
-- ---------------------------------------------------------------------------
insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, data_fim, descricao)
select tests.unidade('ESCOLA_A'), p.id, 'PREVENTIVA',
       public.fn_hoje() + 7, public.fn_hoje() + 9, 'teste: agendada para a semana que vem'
  from public.pc p
 where p.unidade_id = tests.unidade('ESCOLA_A') and p.identificador = 'LAB1-03';

select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio')),
  10,
  'manutencao AGENDADA nao derruba a capacidade de hoje');

select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio'),
                               public.fn_hoje() + 8),
  9,
  'e derruba a do dia dela: p_data avalia admissao futura e reposicao agendada');

select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio'),
                               public.fn_hoje() + 10),
  10,
  'depois de data_fim a capacidade volta');

-- ⚠️ AS DUAS BORDAS, e elas mudaram no card 5.4: o intervalo é `[data_inicio,
--    data_fim)`. `data_fim` é o dia em que o PC VOLTA a operar — a leitura que o
--    card 4.5 (c) deu à coluna e que o botão "Encerrar" produz, e que o banco
--    lia ao contrário até aqui. Sem estas duas asserções a mudança seria
--    invisível: o teste do dia 8, no meio da janela, passa nas duas leituras.
select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio'),
                               public.fn_hoje() + 7),
  9,
  'a borda de INICIO esta DENTRO: no primeiro dia da manutencao o PC ja nao conta');

select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio'),
                               public.fn_hoje() + 9),
  10,
  'a borda de FIM esta FORA: data_fim e o dia em que o PC volta, nao o ultimo dia parado');

-- ---------------------------------------------------------------------------
-- 2.3 Override vence sempre; nominal é teto
-- ---------------------------------------------------------------------------
update public.bloco_horario set capacidade_override = 4
 where id = (select id from t_bloco where apelido = 'cheio');

select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio')),
  4,
  'capacidade_override vence: escape manual da secretaria, sem olhar PC nenhum');

update public.bloco_horario set capacidade_override = null
 where id = (select id from t_bloco where apelido = 'cheio');

insert into public.pc (unidade_id, sala_id, identificador, status)
select tests.unidade('ESCOLA_A'), s.id, 'LAB1-11', 'OPERACIONAL'
  from public.sala s
 where s.unidade_id = tests.unidade('ESCOLA_A') and s.nome = 'Laboratório 1';

select is(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio')),
  10,
  'onze PCs numa sala de nominal 10: o teto nominal vence — a sala nao comporta mais gente');

delete from public.pc
 where unidade_id = tests.unidade('ESCOLA_A') and identificador = 'LAB1-11';

-- ===========================================================================
-- 3. fn_ocupacao_bloco — as duas metades do REP híbrido
-- ===========================================================================
select is(
  (select string_agg(public.fn_ocupacao_bloco(id)::text, ',' order by apelido)
     from t_bloco),
  '10,9,0',
  'cheio 10, quase 9, vazio 0 — a lotacao semanal, que vem de bloco_aluno');

-- Todo tipo ocupa vaga. O bloco de 9 tem REM, PRE e um REP contínuo; o de 10 tem
-- REM, PRE e um NOVO. Uma implementação que filtrasse `tipo` para "só quem já
-- começou" devolveria 8 e 9, e a grade venderia vagas que não existem.
select is(
  (select count(distinct ba.tipo)::bigint from public.bloco_aluno ba
     join t_bloco t on t.id = ba.bloco_id
    where ba.ativo),
  4::bigint,
  'os quatro tipos (REM, PRE, REP, NOVO) estao entre os alocados — e todos contam');

-- A metade PONTUAL. Lucas Ferreira tem uma reposição PREVISTA em hoje+3 no bloco
-- vazio: é ela que reprova uma fn_ocupacao_bloco que somou só `bloco_aluno`.
select is(
  public.fn_ocupacao_bloco((select id from t_bloco where apelido = 'vazio'),
                           public.fn_hoje() + 3),
  1,
  'bloco vazio no dia da reposicao PREVISTA: ocupacao 1 — a metade pontual do REP conta');

select is(
  public.fn_ocupacao_bloco((select id from t_bloco where apelido = 'vazio'),
                           public.fn_hoje() + 4),
  0,
  'no dia seguinte, 0: reposicao vale SO no dia, e nao toda semana');

-- REALIZADA (hoje−16), FALTOU (hoje−9) e CANCELADA (hoje−5) não ocupam vaga: o
-- passado não bloqueia o presente (card 2.2 §4.4).
select is(
  (select string_agg(public.fn_ocupacao_bloco(
            (select id from t_bloco where apelido = 'vazio'),
            public.fn_hoje() + d)::text, ',' order by d)
     from unnest(array[-16, -9, -5]) as d),
  '0,0,0',
  'REALIZADA, FALTOU e CANCELADA nao ocupam vaga em dia nenhum');

select is(
  (select count(*)::bigint from public.bloco_aluno_reposicao br
     join t_bloco t on t.id = br.bloco_id
    where br.status <> 'PREVISTA'),
  3::bigint,
  'guarda da fixture: as tres reposicoes nao-PREVISTAS existem mesmo');

-- ===========================================================================
-- 4. fn_vagas_livres — nunca negativa, e nunca zero por engano
-- ===========================================================================
select is(
  (select string_agg(public.fn_vagas_livres(id)::text, ',' order by apelido)
     from t_bloco),
  '0,1,10',
  'cheio 0, quase 1, vazio 10 — capacidade menos ocupacao');

select is(
  public.fn_vagas_livres((select id from t_bloco where apelido = 'vazio'),
                         public.fn_hoje() + 3),
  9,
  'a reposicao PREVISTA come uma vaga do bloco vazio no dia dela');

-- Bloco acima da capacidade: 10 alunos e override 3. É o estado que o card 5.4
-- transforma em pendência BLOCO_ACIMA_CAPACIDADE; aqui basta que a subtração não
-- devolva −7, que a tela mostraria como "menos sete vagas".
update public.bloco_horario set capacidade_override = 3
 where id = (select id from t_bloco where apelido = 'cheio');

select is(
  public.fn_vagas_livres((select id from t_bloco where apelido = 'cheio')),
  0,
  'bloco acima da capacidade: vagas livres 0, nunca negativo');

select ok(
  public.fn_capacidade_efetiva((select id from t_bloco where apelido = 'cheio'))
    < public.fn_ocupacao_bloco((select id from t_bloco where apelido = 'cheio')),
  'e continua ACIMA: o zero de vagas nao apaga o excesso, que as duas parcelas mostram');

update public.bloco_horario set capacidade_override = null
 where id = (select id from t_bloco where apelido = 'cheio');

-- ===========================================================================
-- 5. A decisão do card: o número não depende do que o leitor enxerga
-- ===========================================================================
-- `semperfil@escola-a.test` não tem perfil nenhum, logo não tem `salas.ler` nem
-- `turmas.ler`: para ele, `pc` e `bloco_aluno` estão vazias. Como `security
-- invoker`, as duas funções devolveriam capacidade 0 e ocupação 0 — e a RLS não
-- levantaria erro nenhum, porque ela nega LINHA. A grade semanal inteira
-- apareceria lotada (card 2.3 §3.4 e §10 #3).
--
-- O id vai por GUC de transação: depois de `set role authenticated` o teste não
-- alcança mais o schema `tests` nem enxerga `bloco_horario`, então buscar o bloco
-- ali dentro devolveria nulo e a asserção passaria a testar outra coisa.
select set_config('tests.bloco_cheio',
                  (select id::text from t_bloco where apelido = 'cheio'), true);

-- Fim do contexto de rotina. A asserção seguinte prova que ele acabou de verdade:
-- com ele ligado, `tem_permissao` devolve TRUE para todo mundo (card 2.2 §2.2) e
-- as três asserções da pele do `semperfil` passariam sem provar nada. Ela é, de
-- graça, o teste de que a unidade é lida do CORPO — sem unidade, sem número.
select tests.encerrar_sessao();

select is(
  public.fn_capacidade_efetiva(current_setting('tests.bloco_cheio')::uuid),
  null::integer,
  'sem contexto nenhum (postgres, sem auth.uid()) a capacidade e NULA — o contexto de rotina acabou');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.pc'),
  0::bigint,
  'quem nao tem salas.ler nao enxerga PC nenhum — a RLS reduz, e em silencio');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'),
                   'select 1 from public.bloco_aluno'),
  0::bigint,
  'nem alocacao nenhuma, por falta de turmas.ler');

select tests.autenticar(tests.uid('semperfil@escola-a.test'));

select is(
  public.fn_capacidade_efetiva(current_setting('tests.bloco_cheio')::uuid),
  10,
  'e AINDA ASSIM a capacidade e 10: security definer, como manda o card 2.3 §10 (#3)');

select is(
  public.fn_ocupacao_bloco(current_setting('tests.bloco_cheio')::uuid),
  10,
  'e a ocupacao e 10: sem isso a grade ofereceria vaga num bloco cheio');

select is(
  public.fn_vagas_livres(current_setting('tests.bloco_cheio')::uuid),
  0,
  'e vagas livres 0 — fn_vagas_livres nao precisa ser definer, herda das duas');

reset role;

-- ===========================================================================
-- 6. Isolamento de unidade — e a diferença entre 0 e nulo
-- ===========================================================================
-- O filtro de unidade tem de estar no CORPO: `definer` de dono com BYPASSRLS não
-- tem RLS para lhe segurar a mão. A ESCOLA_B tem os MESMOS blocos, no mesmo dia e
-- horário — se o filtro sumisse, a função responderia por um bloco da outra
-- escola sem nada acusar.
select set_config('tests.bloco_b',
                  (select b.id::text from public.bloco_horario b
                     join public.sala s on s.id = b.sala_id
                    where b.unidade_id = tests.unidade('ESCOLA_B')
                      and s.nome = 'Laboratório 1' and b.dia_semana = 3), true);

select tests.autenticar(tests.uid('direcao@escola-a.test'));

select is(
  public.fn_capacidade_efetiva(current_setting('tests.bloco_b')::uuid),
  null::integer,
  'bloco de outra unidade: capacidade NULA — e a direcao da ESCOLA_A tem as 50 permissoes');

select is(
  public.fn_ocupacao_bloco(current_setting('tests.bloco_b')::uuid),
  null::integer,
  'ocupacao NULA, e nao 0: zero diria "bloco seu, e vazio", que e outra coisa');

-- ⚠️ `greatest(null, 0)` devolve 0, porque o greatest IGNORA nulos. Escrita como
-- `greatest(capacidade - ocupacao, 0)`, esta função responderia "0 vagas livres"
-- para um bloco que ela nem deveria enxergar — mentira plausível e na direção que
-- ninguém confere ("lotado"). É a asserção que protege o `case` explícito.
select is(
  public.fn_vagas_livres(current_setting('tests.bloco_b')::uuid),
  null::integer,
  'vagas livres NULA: o case explicito preserva o nulo que o greatest engoliria');

reset role;

select * from finish();
rollback;
