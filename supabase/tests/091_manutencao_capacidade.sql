-- =============================================================================
-- Manutenção de PC, status derivado e revalidação de capacidade — card 5.4
-- (mapa suíte → card: docs/estrategia-testes.md §17 — `091_manutencao_capacidade`
--  nasce aqui, ao lado do `090_rotinas`, que é o arquivo das rotinas)
--
-- O card 5.5 já provou o caminho DIÁRIO da pendência de capacidade. Este arquivo
-- prova o que o 5.4 acrescenta e que nenhum catálogo enxerga:
--   • o status do PC passou a ser DERIVADO de pc_manutencao — e derivado por
--     quem registra a manutenção, que é o MONITOR, que não tem `salas.editar`;
--   • a pendência nasce NA HORA, com a MESMA chave da rotina, de modo que os
--     dois caminhos convergem na dedup em vez de duplicar;
--   • "sem substituto" aqui é o mesmo "sem substituto" da fórmula da capacidade
--     (card 5.2): substituto da própria sala não fecha a pendência, porque não
--     repõe máquina nenhuma;
--   • a ORDEM dos dois triggers de `pc_manutencao` é o que faz encerrar uma
--     manutenção fechar a pendência na MESMA transação;
--   • e `rt_pcs_normaliza` existe porque O TEMPO PASSAR NÃO É EVENTO: nenhuma
--     escrita acontece quando uma manutenção agendada começa, ou quando a
--     previsão de fim de uma manutenção aberta fica para trás.
--
-- ⚠️ A ordem das seções não é estética: as que precisam de um ATOR (monitor,
--    secretaria) vêm antes das que precisam do CONTEXTO DE ROTINA, porque dentro
--    do contexto de rotina `tem_permissao()` é sempre verdadeira (card 2.2 §2.2)
--    e uma asserção de permissão escrita lá dentro passaria sem provar nada —
--    a lição que o teste 090 registra na sua seção 11.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(28);

-- ===========================================================================
-- 1. As premissas, sem as quais os números de baixo não querem dizer nada
-- ===========================================================================
select tests.como_rotina(tests.unidade('ESCOLA_A'));

select is(
  (select format('%s/%s/%s',
                 (select count(*) from public.pc p
                    join public.sala s on s.id = p.sala_id
                   where s.unidade_id = tests.unidade('ESCOLA_A')
                     and s.nome = 'Laboratório 1' and p.status = 'OPERACIONAL'),
                 public.fn_capacidade_efetiva(b.id),
                 public.fn_ocupacao_bloco(b.id))
     from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A') and b.dia_semana = 3),
  '10/10/10',
  'fixture: dez PCs operacionais, capacidade 10 e o bloco de quarta com dez alunos — lotado, e nao acima');

select is(
  (select string_agg(pm.codigo, ',' order by pm.codigo)
     from public.usuario_perfil up
     join public.perfil_permissao pp on pp.perfil_id = up.perfil_id
     join public.permissao pm on pm.id = pp.permissao_id
    where up.usuario_id = tests.uid('monitor@escola-a.test')
      and pm.codigo in ('salas.editar', 'salas.registrar_manutencao')),
  'salas.registrar_manutencao',
  'fixture: o monitor REGISTRA manutencao e NAO edita PC — e e essa lacuna que o definer atravessa');

-- ===========================================================================
-- 2. O status é derivado — e quem o deriva é quem não poderia escrevê-lo
-- ===========================================================================
-- Sai o contexto de rotina: dentro dele tem_permissao é sempre verdadeira e
-- toda esta seção passaria de graça.
select tests.encerrar_sessao();
select tests.autenticar(tests.uid('monitor@escola-a.test'));

-- A contraprova primeiro: sem o `security definer` de fn_pc_status_sincronizar,
-- o `update` do trigger seria ESTE — zero linhas afetadas, sem erro nenhum,
-- porque a RLS nega linha em vez de recusar (card 3.4 (d)).
with tentativa as (
  update public.pc set status = 'MANUTENCAO'
   where identificador = 'LAB1-02' and unidade_id = public.fn_unidade_atual()
  returning 1)
select is(
  (select count(*)::bigint from tentativa),
  0::bigint,
  'o monitor NAO consegue escrever pc.status: zero linhas, e nenhum erro — o silencio que o definer existe para vencer');

select lives_ok($$
  insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, descricao)
  select public.fn_unidade_atual(), p.id, 'CORRETIVA', public.fn_hoje(), 'fonte queimada (teste 091)'
    from public.pc p
   where p.unidade_id = public.fn_unidade_atual() and p.identificador = 'LAB1-02'
$$, 'e REGISTRA a manutencao, que e a permissao que ele tem');

select is(
  (select p.status from public.pc p
    where p.identificador = 'LAB1-02' and p.unidade_id = public.fn_unidade_atual()),
  'MANUTENCAO',
  'o status foi para MANUTENCAO pelo trigger — escrito por quem nao pode escreve-lo, que e o ponto');

select is(
  (select public.fn_capacidade_efetiva(b.id) from public.bloco_horario b
    where b.unidade_id = public.fn_unidade_atual() and b.dia_semana = 3),
  9,
  'e a capacidade caiu para 9 na mesma transacao');

-- ===========================================================================
-- 3. A pendência nasce NA HORA, com a chave da rotina
-- ===========================================================================
-- É o caminho por EVENTO. Sem ele, o bloco ficaria acima da capacidade até as
-- 03:10 do dia seguinte — e quem registrou a manutenção não teria como saber
-- que acabou de estourar uma turma.
select is(
  (select format('%s/%s/%s', p.severidade,
                 p.chave_dedup = 'CAPACIDADE:' || b.id::text,
                 p.descricao like '%10 aluno(s) para capacidade de 9%')
     from public.pendencia p
     join public.bloco_horario b on b.id = p.bloco_id
    where p.tipo = 'BLOCO_ACIMA_CAPACIDADE' and p.resolvida_em is null
      and p.unidade_id = public.fn_unidade_atual()),
  'ALTA/t/t',
  'BLOCO_ACIMA_CAPACIDADE aberta na hora, ALTA, com a chave CAPACIDADE:<bloco_id> — a MESMA da rotina');

select is(
  (select format('%s/%s', p.severidade, p.chave_dedup = 'PC_SEM_SUBST:' || pc.id::text)
     from public.pendencia p
     join public.pc pc on pc.id = p.pc_id
    where p.tipo = 'PC_SEM_SUBSTITUTO' and p.resolvida_em is null
      and pc.identificador = 'LAB1-02' and p.unidade_id = public.fn_unidade_atual()),
  'MEDIA/t',
  'e PC_SEM_SUBSTITUTO (MEDIA) para o PC parado: o bloco estourado e o sintoma, o PC sem substituto e a causa');

select is(
  (select count(*)::bigint from public.pendencia p
    where p.tipo = 'BLOCO_ACIMA_CAPACIDADE' and p.resolvida_em is null
      and p.unidade_id = public.fn_unidade_atual()),
  1::bigint,
  'so o bloco de quarta: o de terca tem 9 alunos para 9 lugares, e 9 > 9 e falso');

reset role;

-- ===========================================================================
-- 4. Admissão bloqueada enquanto o bloco estiver acima da capacidade
-- ===========================================================================
-- É o outro entregável do card, e ele já existia: `tg_bloco_aluno_admissao`
-- compara `ocupacao >= capacidade` desde o card 5.3, e um bloco ACIMA satisfaz
-- isso com folga. A Nota do card mandava conferir antes de escrever código novo,
-- e é isto que a conferência virou — asserção, e não uma frase no relatório.
-- Escrever uma segunda guarda a partir da PENDÊNCIA teria modo de falha próprio:
-- a pendência é estado gravado, e um bloco já normalizado continuaria bloqueado
-- até alguém fechá-la.
select is(
  tests.codigo_do_erro(
    format('select public.fn_bloco_admitir(%L, %L, ''REM'')',
           (select id from public.bloco_horario
             where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3),
           (select id from public.aluno
             where unidade_id = tests.unidade('ESCOLA_A') and nome = 'Aluno de Lotação 05')),
    tests.uid('secretaria@escola-a.test')),
  'BLOCO_LOTADO',
  'bloco ACIMA da capacidade recusa admissao nova — o >= do card 5.3 ja cobre o caso, sem guarda nova');

-- ===========================================================================
-- 5. "Sem substituto" é o MESMO "sem substituto" da fórmula da capacidade
-- ===========================================================================
select tests.como_rotina(tests.unidade('ESCOLA_A'));

-- Substituto da PRÓPRIA sala: a máquina já estava contada (card 5.2, decisão b).
update public.pc_manutencao m
   set pc_substituto_id = (select p.id from public.pc p
                            where p.unidade_id = tests.unidade('ESCOLA_A')
                              and p.identificador = 'LAB1-05')
 where m.pc_id = (select p.id from public.pc p
                   where p.unidade_id = tests.unidade('ESCOLA_A')
                     and p.identificador = 'LAB1-02')
   and m.data_fim is null;

select is(
  (select public.fn_capacidade_efetiva(b.id) from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A') and b.dia_semana = 3),
  9,
  'substituto da propria sala nao repoe maquina nenhuma: capacidade continua 9');

-- ⚠️ E A PENDÊNCIA CONTINUA ABERTA. Uma condição escrita como "tem substituto?"
--    em vez de "tem substituto que reponha?" fecharia aqui, dizendo "resolvido"
--    exatamente enquanto a capacidade seguisse caída — a mentira plausível que
--    este projeto cataloga, e na direção que ninguém confere.
select is(
  (select count(*)::bigint from public.pendencia p
     join public.pc pc on pc.id = p.pc_id
    where p.tipo = 'PC_SEM_SUBSTITUTO' and p.resolvida_em is null
      and pc.identificador = 'LAB1-02' and p.unidade_id = tests.unidade('ESCOLA_A')),
  1::bigint,
  'e a pendencia CONTINUA aberta: as duas condicoes sao a mesma frase, de proposito');

-- Substituto de OUTRA sala: máquina que não estava contada aqui.
update public.pc_manutencao m
   set pc_substituto_id = (select p.id from public.pc p
                            where p.unidade_id = tests.unidade('ESCOLA_A')
                              and p.identificador = 'LAB2-01')
 where m.pc_id = (select p.id from public.pc p
                   where p.unidade_id = tests.unidade('ESCOLA_A')
                     and p.identificador = 'LAB1-02')
   and m.data_fim is null;

select is(
  (select public.fn_capacidade_efetiva(b.id) from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A') and b.dia_semana = 3),
  10,
  'substituto de OUTRA sala repoe: capacidade volta a 10');

select is(
  format('%s/%s',
    (select count(*) from public.pendencia p
      where p.tipo = 'BLOCO_ACIMA_CAPACIDADE' and p.resolvida_em is null
        and p.unidade_id = tests.unidade('ESCOLA_A')),
    (select count(*) from public.pendencia p
       join public.pc pc on pc.id = p.pc_id
      where p.tipo = 'PC_SEM_SUBSTITUTO' and p.resolvida_em is null
        and pc.identificador = 'LAB1-02'
        and p.unidade_id = tests.unidade('ESCOLA_A'))),
  '0/0',
  'informar o substituto FECHA as duas na mesma transacao — sem esperar as 03:10');

-- ===========================================================================
-- 6. Duas manutenções abertas, e a ORDEM dos dois triggers
-- ===========================================================================
-- Um PC pode ter mais de uma manutenção em aberto (a corretiva de ontem e a
-- preventiva de hoje). Um trigger que decidisse o status pela LINHA que o
-- disparou devolveria a máquina à operação ao encerrar a primeira — e a
-- capacidade da sala subiria por engano, vendendo vaga que não existe.
insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, descricao)
select tests.unidade('ESCOLA_A'), p.id, 'CORRETIVA', public.fn_hoje() - 5, 'primeira (teste 091)'
  from public.pc p
 where p.unidade_id = tests.unidade('ESCOLA_A') and p.identificador = 'LAB1-03';

select is(
  (select format('%s/%s',
                 (select p.status from public.pc p
                   where p.identificador = 'LAB1-03' and p.unidade_id = tests.unidade('ESCOLA_A')),
                 public.fn_capacidade_efetiva(b.id))
     from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A') and b.dia_semana = 3),
  'MANUTENCAO/9',
  'a primeira manutencao para o PC e derruba a capacidade de novo');

insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, descricao)
select tests.unidade('ESCOLA_A'), p.id, 'PREVENTIVA', public.fn_hoje() - 2, 'segunda (teste 091)'
  from public.pc p
 where p.unidade_id = tests.unidade('ESCOLA_A') and p.identificador = 'LAB1-03';

update public.pc_manutencao set data_fim = public.fn_hoje() - 1
 where unidade_id = tests.unidade('ESCOLA_A') and descricao = 'primeira (teste 091)';

select is(
  (select p.status from public.pc p
    where p.identificador = 'LAB1-03' and p.unidade_id = tests.unidade('ESCOLA_A')),
  'MANUTENCAO',
  'encerrada UMA das duas, o PC continua parado: o trigger olha TODAS as manutencoes, nao a linha que o disparou');

update public.pc_manutencao set data_fim = public.fn_hoje() - 1
 where unidade_id = tests.unidade('ESCOLA_A') and descricao = 'segunda (teste 091)';

select is(
  (select p.status from public.pc p
    where p.identificador = 'LAB1-03' and p.unidade_id = tests.unidade('ESCOLA_A')),
  'OPERACIONAL',
  'encerrada a segunda, o PC volta a operar');

select is(
  (select public.fn_capacidade_efetiva(b.id) from public.bloco_horario b
    where b.unidade_id = tests.unidade('ESCOLA_A') and b.dia_semana = 3),
  10,
  'e a capacidade volta a 10');

-- Encerrar a manutenção FECHA a pendência na MESMA transação: entre o clique e
-- a rotina do dia seguinte passa até um dia, e nesse dia a central mentiria para
-- quem acabou de consertar a máquina.
--
-- ⚠️ Registro de contraprova: esta asserção foi escrita para medir a ORDEM dos
--    dois triggers de `pc_manutencao` (alfabética, `..._status` antes de
--    `..._revalida_blocos`), e a sabotagem que inverteu a ordem saiu VERDE — o
--    `update` de `pc.status` dispara `tg_pc_revalida_blocos` em `pc` e revalida
--    a sala de novo, já com o status certo. A independência de ordem vem dessa
--    redundância, não do nome; quem remover o trigger de `pc` por achá-lo
--    redundante traz a dependência de volta, e aí calada. Está escrito na seção
--    4 da migração.
select is(
  (select count(*)::bigint from public.pendencia p
    where p.tipo = 'BLOCO_ACIMA_CAPACIDADE' and p.resolvida_em is null
      and p.unidade_id = tests.unidade('ESCOLA_A')),
  0::bigint,
  'encerrar a manutencao FECHA a pendencia na mesma transacao — o status sincroniza ANTES de a sala ser revalidada');

-- ===========================================================================
-- 7. rt_pcs_normaliza — porque o tempo passar não é evento
-- ===========================================================================
-- Os dois estados abaixo são alcançáveis sem escrita nenhuma: basta a data
-- virar. Aqui eles são montados à mão (`pc.status` é editável por quem tem
-- `salas.editar`, e o `update` em `pc` não sincroniza status — só revalida a
-- sala), que é a única forma de simular a passagem do tempo dentro de uma
-- transação.
insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, descricao)
select tests.unidade('ESCOLA_A'), p.id, 'CORRETIVA', public.fn_hoje() - 1, 'agendada que comecou (teste 091)'
  from public.pc p
 where p.unidade_id = tests.unidade('ESCOLA_A') and p.identificador = 'LAB1-04';

-- Estado "a manutenção começou hoje e nada disparou".
update public.pc set status = 'OPERACIONAL'
 where unidade_id = tests.unidade('ESCOLA_A') and identificador = 'LAB1-04';

select public.rt_pcs_normaliza();

select is(
  (select p.status from public.pc p
    where p.identificador = 'LAB1-04' and p.unidade_id = tests.unidade('ESCOLA_A')),
  'MANUTENCAO',
  'manutencao que COMECOU e ninguem tocou: a rotina poe o PC em MANUTENCAO — o erro na direcao que vende vaga inexistente');

-- Estado "a previsão de fim ficou para trás e nada disparou".
update public.pc_manutencao set data_fim = public.fn_hoje() - 1
 where unidade_id = tests.unidade('ESCOLA_A') and descricao = 'agendada que comecou (teste 091)';

update public.pc set status = 'MANUTENCAO'
 where unidade_id = tests.unidade('ESCOLA_A') and identificador = 'LAB1-04';

select public.rt_pcs_normaliza();

select is(
  (select p.status from public.pc p
    where p.identificador = 'LAB1-04' and p.unidade_id = tests.unidade('ESCOLA_A')),
  'OPERACIONAL',
  'manutencao que TERMINOU e ninguem tocou: a rotina devolve o PC a OPERACIONAL');

-- DESATIVADO é baixa definitiva, e nem o trigger nem a rotina o tocam: é o que
-- mantém um caminho para tirar uma máquina de circulação sem inventar uma
-- manutenção que não houve.
insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, descricao)
select tests.unidade('ESCOLA_A'), p.id, 'CORRETIVA', public.fn_hoje(), 'no PC desativado (teste 091)'
  from public.pc p
 where p.unidade_id = tests.unidade('ESCOLA_A') and p.identificador = 'LAB2-06';

select public.rt_pcs_normaliza();

select is(
  (select p.status from public.pc p
    where p.identificador = 'LAB2-06' and p.unidade_id = tests.unidade('ESCOLA_A')),
  'DESATIVADO',
  'nem o trigger nem a rotina tocam em DESATIVADO — a excecao que o §4.6 escreve');

-- ===========================================================================
-- 8. rt_capacidades — o laço por sala, e a varredura que o laço não alcança
-- ===========================================================================
-- A queda vem de `capacidade_override`, que é a única fonte que trigger nenhum
-- observa: assim a pendência só pode ter vindo da rotina.
update public.bloco_horario set capacidade_override = 9
 where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3;

select public.rt_capacidades();

select is(
  (select count(*)::bigint from public.pendencia p
    where p.tipo = 'BLOCO_ACIMA_CAPACIDADE' and p.resolvida_em is null
      and p.unidade_id = tests.unidade('ESCOLA_A')),
  1::bigint,
  'rt_capacidades percorre as salas e ve a queda venha ela de onde vier — inclusive de um override a mao');

-- ⚠️ E o bloco DESATIVADO sai do laço por sala. Sem a varredura do fim, a
--    pendência dele ficaria aberta para sempre, esperando uma revalidação que
--    nunca mais olharia para ele — a lista acumulando o que deixou de ser
--    verdade, que é o oposto do que o card 5.5 promete.
update public.bloco_horario set ativo = false
 where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3;

select public.rt_capacidades();

select is(
  (select count(*)::bigint from public.pendencia p
    where p.tipo = 'BLOCO_ACIMA_CAPACIDADE' and p.resolvida_em is null
      and p.unidade_id = tests.unidade('ESCOLA_A')),
  0::bigint,
  'bloco desativado sai do laco por sala, e a varredura do fim fecha a pendencia dele');

update public.bloco_horario set ativo = true, capacidade_override = null
 where unidade_id = tests.unidade('ESCOLA_A') and dia_semana = 3;

-- PC desativado é o caso espelho, e ele NÃO precisa de varredura: o laço de
-- fn_revalidar_blocos_sala percorre também o DESATIVADO, justamente para poder
-- fechar a pendência que ele tinha aberta.
insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, descricao)
select tests.unidade('ESCOLA_A'), p.id, 'CORRETIVA', public.fn_hoje(), 'antes da baixa (teste 091)'
  from public.pc p
 where p.unidade_id = tests.unidade('ESCOLA_A') and p.identificador = 'LAB1-06';

update public.pc set status = 'DESATIVADO'
 where unidade_id = tests.unidade('ESCOLA_A') and identificador = 'LAB1-06';

select is(
  (select count(*)::bigint from public.pendencia p
     join public.pc pc on pc.id = p.pc_id
    where p.tipo = 'PC_SEM_SUBSTITUTO' and p.resolvida_em is null
      and pc.identificador = 'LAB1-06' and p.unidade_id = tests.unidade('ESCOLA_A')),
  0::bigint,
  'dar baixa no PC fecha a PC_SEM_SUBSTITUTO dele: DESATIVADO nao e "parado sem substituto"');

-- ===========================================================================
-- 9. Unidade: o filtro está no CORPO, porque definer de dono ignora a RLS
-- ===========================================================================
select is(
  public.fn_revalidar_blocos_sala(
    (select s.id from public.sala s
      where s.unidade_id = tests.unidade('ESCOLA_B') and s.nome = 'Laboratório 1')),
  null::integer,
  'sala de outra unidade devolve NULO, e nao 0 — zero diria "sua sala, e nada acima"');

select is(
  (select count(*)::bigint from public.pendencia p
    where p.unidade_id = tests.unidade('ESCOLA_B')
      and p.tipo = 'BLOCO_ACIMA_CAPACIDADE'),
  0::bigint,
  'e nada foi escrito na Escola B: o filtro de unidade esta no corpo, como manda o card 2.3 §10 #3');

-- ===========================================================================
-- 10. Os dois caminhos convergem na dedup, e é a chave que os une
-- ===========================================================================
-- É a promessa que o card 5.5 deixou escrita ao antecipar este card. Evento
-- primeiro, rotina depois, e o resultado é UMA linha — porque a chave é a mesma.
insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, descricao)
select tests.unidade('ESCOLA_A'), p.id, 'CORRETIVA', public.fn_hoje(), 'convergencia (teste 091)'
  from public.pc p
 where p.unidade_id = tests.unidade('ESCOLA_A') and p.identificador = 'LAB1-07';

select public.rt_capacidades();
select public.rt_diaria();

select is(
  (select count(*)::bigint from public.pendencia p
     join public.bloco_horario b on b.id = p.bloco_id
    where p.tipo = 'BLOCO_ACIMA_CAPACIDADE' and p.resolvida_em is null
      and b.dia_semana = 3 and p.unidade_id = tests.unidade('ESCOLA_A')),
  1::bigint,
  'evento + rotina + rt_diaria: UMA pendencia, porque a chave CAPACIDADE:<bloco_id> e a mesma nos dois caminhos');

select * from finish();
rollback;
