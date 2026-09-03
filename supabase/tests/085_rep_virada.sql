-- =============================================================================
-- A virada REP: pontual → contínuo — card 5.3
-- (mapa suíte → card: docs/estrategia-testes.md §17; critério em
--  docs/regra-virada-rep.md, card 2.5)
--
-- O card 2.5 é ARITMÉTICO, então o §6.5 manda testar BORDA e não exemplo: débito
-- exatamente no limite → nada; mais uma aula → sugestão. E o pingue-pongue, que
-- é a razão de existir da carência: virar contínuo zera o relógio e cancela as
-- reposições PREVISTA, de modo que no instante seguinte as duas primeiras
-- condições da volta já estariam satisfeitas — sem a carência, a rotina do card
-- 5.5 sugeriria desfazer todo dia o que acabou de ser feito.
--
-- DIVERGÊNCIA REGISTRADA com a Nota do card, e o motivo está escrito no próprio
-- enunciado: o §6.5 descreve as bordas em termos de PENDÊNCIA aberta com
-- `chave_dedup` terminada em `:CONTINUO`. `pendencia`, fn_pendencia_abrir e
-- rt_rep_avaliar são do card 5.5 e não existem hoje. O que existe — e o que este
-- arquivo mede — é a camada de baixo: o VEREDITO, que é o valor a partir do qual
-- a rotina do 5.5 abrirá e fechará aquelas pendências. As bordas são as mesmas,
-- na única superfície que já está de pé. A seção 6 é o portão que reprova no dia
-- em que `pendencia` nascer e este arquivo continuar parando no veredito.
--
-- Nenhum número mágico: os quatro parâmetros `rep_*` são lidos do banco. Teste
-- que escreve o próprio 30 passa a acreditar em si mesmo, e o dia em que a
-- direção mudar o parâmetro na tela do card 4.7 ele continuará verde dizendo
-- outra coisa.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(25);

-- ===========================================================================
-- 1. A borda da fixture: débito EXATAMENTE no limite
-- ===========================================================================
-- Contexto de rotina para as leituras: fn_rep_situacao exige `turmas.ler` e lê
-- por RLS. A seção 5 desliga o contexto e prova que a exigência é de verdade.
select tests.como_rotina(tests.unidade('ESCOLA_A'));

select is(
  (select format('%s/%s/%s/%s/%s/%s',
                 s.debito,
                 public.fn_hoje() - s.aula_mais_antiga,
                 s.prazo_final - public.fn_hoje(),
                 s.semanas_uteis,
                 s.capacidade,
                 s.faltas_recentes)
     from public.fn_rep_situacao(
            (select id from public.aluno
              where nome = 'Lucas Ferreira'
                and unidade_id = tests.unidade('ESCOLA_A'))) s),
  '3/10/20/3/1/1',
  'Lucas: 3 aulas em aberto, a mais antiga de 10 dias atras, prazo em 20 dias, 3 semanas, capacidade 1, 1 falta');

-- 3 > 1 × 3 é FALSO. Com `floor` seriam 2 semanas, 3 > 2 seria verdadeiro e o
-- mesmo aluno viraria contínuo: a borda foi escolhida onde as duas
-- implementações divergem, senão a fixture passaria nas duas.
select is(
  public.fn_rep_avaliar_virada(
    (select id from public.aluno
      where nome = 'Lucas Ferreira' and unidade_id = tests.unidade('ESCOLA_A'))),
  'MANTER',
  'no limite exato o veredito e MANTER — o arredondamento e a favor do aluno (ceil, card 2.5 §3.3)');

-- A aula QUITADA é a mais antiga de todas, de propósito: uma implementação que
-- tome min(data_origem) sem filtrar as quitadas acharia prazo vencido (20 dias
-- atrás + 30 = daqui a 10) e sugeriria a virada de um aluno em dia.
select is(
  (select (public.fn_hoje() - min(coalesce(br.data_origem, br.data)))::text
     from public.bloco_aluno_reposicao br
     join public.aluno a on a.id = br.aluno_id
    where a.nome = 'Lucas Ferreira' and a.unidade_id = tests.unidade('ESCOLA_A')),
  '20',
  'e existe uma aula ainda mais antiga, de 20 dias — REALIZADA, e por isso fora da conta');

-- Duas reposições da MESMA aula são UM débito (card 2.5 §3.1): a primeira
-- cancelada, a segunda remarcada. Contar por LINHA dobraria o débito de quem
-- remarcou — exatamente quem está tentando se acertar.
insert into public.bloco_aluno_reposicao
  (unidade_id, bloco_id, aluno_id, data, bloco_origem_id, data_origem, status)
select tests.unidade('ESCOLA_A'),
       (select id from public.bloco_horario
         where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 1),
       a.id, public.fn_hoje() + 6,
       br.bloco_origem_id, br.data_origem, 'PREVISTA'
  from public.aluno a
  join public.bloco_aluno_reposicao br on br.aluno_id = a.id and br.status = 'FALTOU'
 where a.nome = 'Lucas Ferreira' and a.unidade_id = tests.unidade('ESCOLA_A');

select is(
  (select s.debito from public.fn_rep_situacao(
     (select id from public.aluno
       where nome = 'Lucas Ferreira' and unidade_id = tests.unidade('ESCOLA_A'))) s),
  3,
  'remarcar a aula que ele faltou NAO cria um segundo debito — a contagem e por aula de origem');

-- ===========================================================================
-- 2. Uma aula a mais vira o veredito — a outra metade da borda
-- ===========================================================================
-- Origem nova e mais RECENTE que a mais antiga: o prazo não muda, só o débito.
-- Assim a asserção mede o débito, e não o calendário.
insert into public.bloco_aluno_reposicao
  (unidade_id, bloco_id, aluno_id, data, bloco_origem_id, data_origem, status)
select tests.unidade('ESCOLA_A'),
       (select id from public.bloco_horario
         where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 1),
       a.id, public.fn_hoje() + 8,
       (select id from public.bloco_horario
         where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3),
       public.fn_hoje() - 3, 'PREVISTA'
  from public.aluno a
 where a.nome = 'Lucas Ferreira' and a.unidade_id = tests.unidade('ESCOLA_A');

select is(
  (select format('%s/%s/%s', s.debito, s.semanas_uteis, s.veredito)
     from public.fn_rep_situacao(
            (select id from public.aluno
              where nome = 'Lucas Ferreira'
                and unidade_id = tests.unidade('ESCOLA_A'))) s),
  '4/3/SUGERIR_CONTINUO',
  'uma quarta aula em aberto, com o MESMO prazo, ja nao cabe: 4 > 1 x 3');

-- ===========================================================================
-- 3. Reincidência é gatilho INDEPENDENTE da aritmética (card 2.5 §3.4)
-- ===========================================================================
-- Quem falta às próprias reposições não está repondo, mesmo com o saldo cabendo
-- no prazo. É a diferença entre FALTOU e CANCELADA que torna isto possível — e é
-- por isso que o valor FALTOU foi bloqueante lá no card 5.1.
select tests.encerrar_sessao();

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_reposicao_registrar(
      public.fn_reposicao_agendar(
        (select id from public.aluno
          where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
        (select id from public.bloco_horario
          where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
        public.fn_hoje() - 6,
        (select id from public.bloco_horario
          where dia_semana = 3 and unidade_id = public.fn_unidade_atual()),
        public.fn_hoje() - 6),
      false)$$,
  'a secretaria lanca e marca a PRIMEIRA falta de Carla');

-- A segunda falta é a que fecha o gatilho, e o veredito volta pela PRÓPRIA
-- fn_reposicao_registrar — que é o ponto do ajuste 7 do card 2.2 §14: a
-- secretaria vê na hora em que marca, e não no dia seguinte quando a rotina do
-- card 5.5 abrir a pendência.
select is(
  (select public.fn_reposicao_registrar(
     public.fn_reposicao_agendar(
       (select id from public.aluno
         where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
       (select id from public.bloco_horario
         where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
       public.fn_hoje() - 5,
       (select id from public.bloco_horario
         where dia_semana = 3 and unidade_id = public.fn_unidade_atual()),
       public.fn_hoje() - 5),
     false)),
  'SUGERIR_CONTINUO',
  'a segunda falta sugere a virada NA HORA, pelo retorno de fn_reposicao_registrar');

reset role;

select tests.como_rotina(tests.unidade('ESCOLA_A'));

-- E a aritmética sozinha diria que ela está em dia: 2 aulas, prazo de sobra.
-- Sem o gatilho de reincidência, quem falta a tudo passaria despercebido.
select is(
  (select format('%s/%s/%s', s.debito, s.capacidade * s.semanas_uteis,
                 s.faltas_recentes)
     from public.fn_rep_situacao(
            (select id from public.aluno
              where nome = 'Carla Menezes'
                and unidade_id = tests.unidade('ESCOLA_A'))) s),
  '2/4/2',
  'e o debito dela CABE no prazo (2 de 4): quem sugeriu a virada foram as duas faltas, nao a conta');

-- ===========================================================================
-- 4. A virada, e o pingue-pongue que a carência existe para evitar
-- ===========================================================================
-- `Aluno de Lotação 02` está no bloco cheio, é ATIVO, não tem reposição nenhuma
-- e nunca faltou: é o aluno que ISOLA a carência. Feita a virada, débito e
-- faltas são zero — as duas primeiras condições da volta —, e a ÚNICA coisa
-- entre o sistema e uma sugestão de desfazer o que acabou de ser feito é
-- rep_janela_volta_dias.
select tests.encerrar_sessao();

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_rep_virar_continuo(
      (select id from public.aluno
        where nome = 'Aluno de Lotação 02' and unidade_id = public.fn_unidade_atual()),
      (select id from public.bloco_horario
        where dia_semana = 1 and unidade_id = public.fn_unidade_atual()))$$,
  'a secretaria converte um aluno para REP continuo no bloco com vaga');

reset role;

select is(
  (select format('%s/%s/%s', ba.tipo, ba.ativo, public.fn_hoje() - ba.tipo_desde)
     from public.bloco_aluno ba
     join public.aluno a on a.id = ba.aluno_id
     join public.bloco_horario b on b.id = ba.bloco_id
    where a.nome = 'Aluno de Lotação 02' and b.dia_semana = 1
      and b.unidade_id = tests.unidade('ESCOLA_A')),
  'REP/t/0',
  'a alocacao REP nasceu ativa e com o relogio zerado hoje — e ele que corta o debito');

select tests.como_rotina(tests.unidade('ESCOLA_A'));

select is(
  (select format('%s/%s/%s', s.debito, s.faltas_recentes, s.veredito)
     from public.fn_rep_situacao(
            (select id from public.aluno
              where nome = 'Aluno de Lotação 02'
                and unidade_id = tests.unidade('ESCOLA_A'))) s),
  '0/0/MANTER',
  'PINGUE-PONGUE: sem debito e sem falta, o veredito e MANTER — a carencia segura a sugestao de volta');

-- A contraprova, sem a qual a asserção de cima passaria mesmo que SUGERIR_VOLTA
-- nunca acontecesse: o aluno de REP da fixture está nele há 40 dias, fora da
-- carência de 30, e recebe a sugestão.
select is(
  (select format('%s/%s',
                 public.fn_hoje() - s.rep_desde, s.veredito)
     from public.fn_rep_situacao(
            (select id from public.aluno
              where nome = 'Aluno de Lotação 13'
                and unidade_id = tests.unidade('ESCOLA_A'))) s),
  '40/SUGERIR_VOLTA',
  'e passada a carencia a sugestao de volta APARECE — 40 dias contra os 30 do parametro');

-- A virada corta o relógio do débito, e sem esse corte o aluno convertido nunca
-- poderia voltar a pontual: o débito que motivou a conversão pesaria para
-- sempre. Lucas tem quatro aulas em aberto, todas anteriores a hoje.
select is(
  (select s.debito from public.fn_rep_situacao(
     (select id from public.aluno
       where nome = 'Lucas Ferreira'
         and unidade_id = tests.unidade('ESCOLA_A'))) s),
  4,
  'premissa: Lucas continua com quatro aulas em aberto, todas anteriores a hoje');

select tests.encerrar_sessao();

select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_rep_virar_continuo(
      (select id from public.aluno
        where nome = 'Lucas Ferreira' and unidade_id = public.fn_unidade_atual()),
      (select id from public.bloco_horario
        where dia_semana = 1 and unidade_id = public.fn_unidade_atual()),
      'virado no teste')$$,
  'e o proprio Lucas, com quatro aulas em aberto, e convertido');

reset role;

select tests.como_rotina(tests.unidade('ESCOLA_A'));

select is(
  (select s.debito from public.fn_rep_situacao(
     (select id from public.aluno
       where nome = 'Lucas Ferreira'
         and unidade_id = tests.unidade('ESCOLA_A'))) s),
  0,
  'depois da virada o debito e ZERO: tipo_desde corta o relogio (card 2.5 §3.2)');

-- As reposições pontuais deixam de fazer sentido — ele passa a vir toda semana —
-- e cancelá-las devolve as vagas que ocupavam naquelas datas.
select is(
  (select format('%s previstas / %s canceladas com observacao',
                 count(*) filter (where br.status = 'PREVISTA'),
                 count(*) filter (where br.status = 'CANCELADA'
                                    and br.observacao = 'virado no teste'))
     from public.bloco_aluno_reposicao br
     join public.aluno a on a.id = br.aluno_id
    where a.nome = 'Lucas Ferreira' and a.unidade_id = tests.unidade('ESCOLA_A')),
  '0 previstas / 3 canceladas com observacao',
  'e as reposicoes PREVISTA foram absorvidas pela virada, com a observacao de quem as cancelou');

select tests.encerrar_sessao();

-- ===========================================================================
-- 5. Os códigos e a permissão
-- ===========================================================================
select is(
  tests.codigo_do_erro(
    $$select public.fn_rep_virar_continuo(
        (select id from public.aluno
          where nome = 'Lucas Ferreira' and unidade_id = public.fn_unidade_atual()),
        (select id from public.bloco_horario
          where dia_semana = 2 and unidade_id = public.fn_unidade_atual()))$$,
    tests.uid('secretaria@escola-a.test')),
  'REP_JA_CONTINUO',
  'virar duas vezes e recusado — a segunda alocacao REP consumiria uma vaga a mais toda semana');

select is(
  tests.codigo_do_erro(
    $$select public.fn_rep_voltar_pontual(
        (select id from public.aluno
          where nome = 'Lucas Ferreira' and unidade_id = public.fn_unidade_atual()),
        '   ')$$,
    tests.uid('secretaria@escola-a.test')),
  'MOTIVO_OBRIGATORIO',
  'voltar a pontual sem motivo e recusado — e agora o motivo tem onde ser gravado');

select is(
  tests.codigo_do_erro(
    $$select public.fn_rep_voltar_pontual(
        (select id from public.aluno
          where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
        'nao esta em REP')$$,
    tests.uid('secretaria@escola-a.test')),
  'REP_NAO_CONTINUO',
  'e voltar quem nao esta em REP continuo tambem');

select is(
  tests.codigo_do_erro(
    $$select public.fn_rep_virar_continuo(
        (select id from public.aluno
          where nome = 'Carla Menezes' and unidade_id = public.fn_unidade_atual()),
        (select id from public.bloco_horario
          where dia_semana = 1 and unidade_id = public.fn_unidade_atual()))$$,
    tests.uid('monitor@escola-a.test')),
  'SEM_PERMISSAO',
  'o monitor nao executa a virada: ela consome vaga toda semana e exige turmas.alocar');

-- fn_rep_situacao exige `turmas.ler`, e a exigência não é burocracia: sem ela
-- quem não enxerga as reposições recebe débito ZERO — e para um aluno JÁ em REP
-- contínuo isso vira 'SUGERIR_VOLTA', o sistema sugerindo desfazer a virada
-- porque não conseguiu ver a dívida. Erro alto no lugar de resposta plausível.
select is(
  tests.codigo_do_erro(
    $$select public.fn_rep_situacao(
        (select id from public.aluno where nome = 'Lucas Ferreira'))$$,
    tests.uid('semperfil@escola-a.test')),
  'SEM_PERMISSAO',
  'quem nao tem turmas.ler recebe ERRO, e nao um debito zero que parece verdade');

-- ---------------------------------------------------------------------------
-- 5.1 A volta, com o motivo gravado
-- ---------------------------------------------------------------------------
select tests.autenticar(tests.uid('secretaria@escola-a.test'));

select lives_ok(
  $$select public.fn_rep_voltar_pontual(
      (select id from public.aluno
        where nome = 'Aluno de Lotação 13' and unidade_id = public.fn_unidade_atual()),
      'voltou a repor sozinho')$$,
  'a secretaria devolve a REP pontual quem passou a carencia sem debito');

reset role;

select is(
  (select format('%s/%s', ba.ativo, ba.motivo_saida)
     from public.bloco_aluno ba
     join public.aluno a on a.id = ba.aluno_id
    where a.nome = 'Aluno de Lotação 13' and a.unidade_id = tests.unidade('ESCOLA_A')
      and ba.tipo = 'REP'),
  'f/voltou a repor sozinho',
  'a alocacao REP fica inativa com o motivo — o MOTIVO_OBRIGATORIO deixa de ser um campo que some');

-- ===========================================================================
-- 6. O portão do card 5.5 DISPAROU — e o que ficou no lugar dele
-- ===========================================================================
-- Esta seção era um portão. Ele existia porque o passo 4 do §5.2 do card 2.5
-- manda fn_rep_virar_continuo fechar a pendência REP:<aluno>:CONTINUO, e
-- `pendencia` só nasceu no card 5.5: esquecer de voltar aqui não daria erro
-- nenhum — daria a central do card 5.8 sugerindo, todo dia, uma virada que já
-- aconteceu, até a rotina do dia seguinte desfazer o engano.
--
-- Em 03/09/2026 a tabela nasceu, o portão reprovou como prometido, e o que era
-- promessa virou código. O COMPORTAMENTO — a rotina abre, a virada fecha na
-- mesma transação — é medido ponta a ponta no teste 090 (§9 e §10), que é o
-- arquivo da pendência; este continua sendo o arquivo do CRITÉRIO, e o que
-- sobra aqui é a asserção estrutural que impede a ligação de se desfazer num
-- refactor: as duas funções da virada citam fn_pendencia_resolver, cada uma com
-- o SEU sufixo. Trocar os dois sufixos de lugar não daria erro nenhum — fecharia
-- a sugestão errada, calada, e as duas ficariam abertas para sempre.
--
-- `prosrc` inclui os comentários do corpo, e por isso eles saem antes: um
-- comentário descrevendo o que falta faria o portão aprovar a si mesmo (lição
-- que custou uma sessão no card 5.3).
create temporary view corpo_virada as
  select p.proname,
         regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as fonte
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('fn_rep_virar_continuo', 'fn_rep_voltar_pontual');

select is(
  (select coalesce(string_agg(c.proname, ', ' order by c.proname), '')
     from corpo_virada c
    where c.fonte !~ 'fn_pendencia_resolver'),
  '',
  'as duas funcoes da virada fecham a pendencia — nenhuma delas deixa a sugestao aberta');

select is(
  (select string_agg(format('%s:%s', c.proname,
                            case when c.fonte ~ ':CONTINUO' then 'CONTINUO'
                                 when c.fonte ~ ':VOLTA'    then 'VOLTA'
                                 else 'NENHUM' end), ' ' order by c.proname)
     from corpo_virada c),
  'fn_rep_virar_continuo:CONTINUO fn_rep_voltar_pontual:VOLTA',
  'e cada uma fecha o SEU sufixo: trocados, fechariam a sugestao errada em silencio');

select * from finish();
rollback;
