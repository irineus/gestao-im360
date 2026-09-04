import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/turmas/turmas.dart';

import 'apoio/turmas_falso.dart';

/// A lógica pura da grade (card 5.6): a semana, a montagem da matriz, os
/// alertas e os filtros. Nada aqui calcula capacidade, ocupação ou vaga — os
/// três chegam prontos do banco (card 5.2 é o dono da fórmula), e é justamente
/// por isso que esta camada é pequena.
void main() {
  group('semana', () {
    test('segundaDe devolve a segunda-feira ISO de qualquer dia da semana', () {
      // 07/09/2026 é uma segunda-feira.
      final segunda = DateTime(2026, 9, 7);
      for (var i = 0; i < 7; i++) {
        expect(
          segundaDe(DateTime(2026, 9, 7 + i)),
          segunda,
          reason: 'dia ${7 + i}/09',
        );
      }
    });

    test('segundaDe atravessa a virada do mês e a do ano', () {
      expect(segundaDe(DateTime(2026, 10, 1)), DateTime(2026, 9, 28));
      expect(segundaDe(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
    });

    test('segundaDe não usa Duration: hora do dia não desloca a semana', () {
      // Com `subtract(Duration(days:))` uma data às 00:00 num dia de mudança de
      // horário cai às 23h do dia anterior — e a semana inteira andaria um dia.
      expect(segundaDe(DateTime(2026, 10, 18, 23, 59)), DateTime(2026, 10, 12));
      expect(segundaDe(DateTime(2026, 10, 18)), DateTime(2026, 10, 12));
    });

    test('rotuloSemana vai até sábado, e até domingo quando há bloco nele', () {
      final segunda = DateTime(2026, 8, 31);
      expect(rotuloSemana(segunda), '31/08 a 05/09');
      expect(rotuloSemana(segunda, incluiDomingo: true), '31/08 a 06/09');
    });

    test('rotuloSemana normaliza a data recebida', () {
      expect(rotuloSemana(DateTime(2026, 9, 2)), '31/08 a 05/09');
    });
  });

  group('hora', () {
    test('horaHhMm corta os segundos que o PostgREST devolve em `time`', () {
      expect(horaHhMm('08:00:00'), '08:00');
      expect(horaHhMm('09:30'), '09:30');
      expect(horaHhMm('nada'), 'nada');
    });

    test('validarHora aceita hh:mm e recusa o resto', () {
      expect(validarHora('08:00'), isNull);
      expect(validarHora('23:59'), isNull);
      expect(validarHora(''), isNotNull);
      expect(validarHora('24:00'), isNotNull);
      expect(validarHora('8:00'), isNotNull);
      expect(validarHora('08:60'), isNotNull);
    });
  });

  group('montagem da grade', () {
    late List<CelulaGrade> celulas;
    final segunda = DateTime(2026, 8, 31);

    setUp(() async {
      celulas = await TurmasFalso.fixture().grade(segunda);
    });

    test('as linhas são os horários existentes, em ordem', () {
      final grade = montarGrade(segunda, celulas);
      expect(grade.horas, ['08:00', '09:30']);
    });

    test('as colunas são sempre Seg–Sáb, e a grade não muda de forma', () {
      final grade = montarGrade(segunda, celulas);
      expect(grade.dias, [1, 2, 3, 4, 5, 6]);
    });

    test(
      'domingo entra quando há bloco nele — sumir em silêncio seria pior',
      () {
        final comDomingo = [
          ...celulas,
          CelulaGrade(
            blocoId: 'b-dom',
            diaSemana: 7,
            horaInicio: '10:00',
            dataReferencia: DateTime(2026, 9, 6),
            metodoId: 'm-int',
            metodoCodigo: 'INTERATIVO',
            salaId: 's-lab1',
            salaNome: 'Laboratório 1',
            capacidade: 10,
            ocupacao: 1,
            vagasLivres: 9,
            acimaCapacidade: false,
          ),
        ];
        expect(montarGrade(segunda, comDomingo).dias, [1, 2, 3, 4, 5, 6, 7]);
      },
    );

    test('a célula é uma LISTA: duas salas cabem no mesmo dia e horário', () {
      final grade = montarGrade(segunda, celulas);
      final quarta = grade.em(3, '08:00');
      expect(quarta.length, 2, reason: 'a unique de bloco_horario é por sala');
      expect(
        quarta.map((c) => c.salaNome),
        ['Laboratório 1', 'Laboratório 2'],
        reason:
            'ordenadas por sala, para a grade não trocar de ordem a cada carga',
      );
    });

    test('cruzamento sem bloco devolve lista vazia, não nulo', () {
      final grade = montarGrade(segunda, celulas);
      expect(grade.em(5, '08:00'), isEmpty);
    });

    test('dataDe dá a data daquele dia na semana montada', () {
      final grade = montarGrade(segunda, celulas);
      expect(grade.dataDe(1), DateTime(2026, 8, 31));
      expect(grade.dataDe(6), DateTime(2026, 9, 5));
    });

    test('grade sem célula nenhuma é vazia — e é o estado vazio da tela', () {
      expect(montarGrade(segunda, const []).vazia, isTrue);
      expect(montarGrade(segunda, celulas).vazia, isFalse);
    });

    test('a data de cada célula acompanha a semana pedida', () async {
      final outra = await TurmasFalso.fixture().grade(DateTime(2026, 9, 9));
      final quarta = outra.firstWhere((c) => c.blocoId == 'b-cheio');
      expect(quarta.dataReferencia, DateTime(2026, 9, 9));
    });
  });

  group('alertas da célula', () {
    late List<CelulaGrade> celulas;

    setUp(() async {
      celulas = await TurmasFalso.fixture().grade(DateTime(2026, 8, 31));
    });

    CelulaGrade de(String id) => celulas.firstWhere((c) => c.blocoId == id);

    test('lotado NÃO é alerta: a turma encher é o sistema funcionando', () {
      final cheio = de('b-cheio');
      expect(cheio.lotado, isTrue);
      expect(alertasDo(cheio), isNot(contains(AlertaBloco.acimaCapacidade)));
    });

    test('acima da capacidade é alerta, e não conta como lotado', () {
      final acima = de('b-acima');
      expect(alertasDo(acima), contains(AlertaBloco.acimaCapacidade));
      expect(
        acima.lotado,
        isFalse,
        reason: 'lotado e acima são estados diferentes',
      );
    });

    test('bloco sem professor é alerta próprio', () {
      expect(alertasDo(de('b-cheio')), contains(AlertaBloco.semProfessor));
      expect(
        alertasDo(de('b-vazio')),
        isNot(contains(AlertaBloco.semProfessor)),
      );
    });

    test('ocupacaoTexto é a leitura da célula do wireframe', () {
      expect(de('b-quase').ocupacaoTexto, '9/10');
      expect(de('b-ingles').ocupacaoTexto, '4/6');
    });
  });

  group('filtros', () {
    late List<CelulaGrade> celulas;

    setUp(() async {
      celulas = await TurmasFalso.fixture().grade(DateTime(2026, 8, 31));
    });

    test('sem filtro, tudo passa', () {
      expect(
        filtrarGrade(celulas, FiltroGrade.semFiltro).length,
        celulas.length,
      );
    });

    test('por método e por sala, e os dois juntos', () {
      expect(
        filtrarGrade(celulas, const FiltroGrade(metodoId: 'm-ing')).length,
        1,
      );
      expect(
        filtrarGrade(celulas, const FiltroGrade(salaId: 's-lab1')).length,
        4,
      );
      expect(
        filtrarGrade(
          celulas,
          const FiltroGrade(metodoId: 'm-int', salaId: 's-lab2'),
        ),
        isEmpty,
      );
    });

    test('contador de filtros ativos', () {
      expect(FiltroGrade.semFiltro.ativos, 0);
      expect(const FiltroGrade(salaId: 's-lab1').ativos, 1);
      expect(const FiltroGrade(metodoId: 'm-int', salaId: 's-lab1').ativos, 2);
    });

    test('copiar apaga o filtro quando o construtor devolve nulo', () {
      const filtro = FiltroGrade(metodoId: 'm-int', salaId: 's-lab1');
      expect(filtro.copiar(metodoId: () => null).metodoId, isNull);
      expect(filtro.copiar(metodoId: () => null).salaId, 's-lab1');
    });
  });

  group('BlocoHorario', () {
    test('paraLinha carrega a unidade e manda o override nulo como nulo', () {
      const bloco = BlocoHorario(
        diaSemana: 3,
        horaInicio: '08:00',
        metodoId: 'm-int',
        salaId: 's-lab1',
      );
      final linha = bloco.paraLinha('u-1');
      expect(linha['unidade_id'], 'u-1');
      expect(linha['dia_semana'], 3);
      expect(linha['hora_inicio'], '08:00');
      expect(linha['professor_id'], isNull);
      expect(linha['capacidade_override'], isNull);
      expect(linha['ativo'], isTrue);
    });

    test('deLinha lê o `time` com segundos que o PostgREST devolve', () {
      final bloco = BlocoHorario.deLinha({
        'id': 'b-1',
        'dia_semana': 2,
        'hora_inicio': '09:30:00',
        'metodo_id': 'm-int',
        'sala_id': 's-lab1',
        'professor_id': null,
        'capacidade_override': 8,
        'ativo': false,
      });
      expect(bloco.horaInicio, '09:30');
      expect(bloco.capacidadeOverride, 8);
      expect(bloco.ativo, isFalse);
    });

    test(
      'a célula sabe voltar ao bloco, para editar sem segunda consulta',
      () async {
        final celulas = await TurmasFalso.fixture().grade(
          DateTime(2026, 8, 31),
        );
        final bloco = celulas.firstWhere((c) => c.blocoId == 'b-quase').bloco;
        expect(bloco.id, 'b-quase');
        expect(bloco.diaSemana, 2);
        expect(bloco.horaInicio, '08:00');
        expect(bloco.ativo, isTrue, reason: 'a grade só traz bloco ativo');
      },
    );
  });

  // -------------------------------------------------------------------------
  // Card 5.7
  // -------------------------------------------------------------------------

  group('alunos do bloco', () {
    test('a linha da reposição diz de que aula ela é (wireframe §7.2)', () {
      expect(
        reposicaoFalsa().rotuloReposicao,
        'reposição de Qua 08:00 27/08',
        reason: 'o apontamento #3 do §17 do card 2.6 existe para isto',
      );
    });

    test('sem bloco de origem a linha diz o que sabe, e não inventa', () {
      // `bloco_origem_id` é nulo de propósito (card 2.5 §3.1): a escola nem
      // sempre sabe qual encontro foi perdido.
      expect(
        reposicaoFalsa(
          blocoOrigemDia: null,
          blocoOrigemHora: null,
        ).rotuloReposicao,
        'reposição de 27/08',
      );
      expect(
        const AlunoDoBloco(
          origem: OrigemNoBloco.reposicao,
          registroId: 'rep-1',
          alunoId: 'al-9',
          alunoNome: 'Lucas',
          alunoStatus: 'ATIVO',
          tipo: 'REP',
        ).rotuloReposicao,
        'reposição avulsa',
        reason: 'sem origem nenhuma, a linha diz o que é e para de inventar',
      );
    });

    test('alocação não tem rótulo de reposição', () {
      final aloc = alocacaoFalsa(alunoId: 'x', nome: 'Fulano', tipo: 'REM');
      expect(aloc.ehReposicao, isFalse);
      expect(aloc.rotuloReposicao, isNull);
    });

    test('deLinha lê as duas origens que fn_bloco_alunos devolve', () {
      final aloc = AlunoDoBloco.deLinha(const {
        'origem': 'ALOCACAO',
        'registro_id': 'aloc-1',
        'aluno_id': 'al-1',
        'aluno_nome': 'Ana',
        'codigo_sgf': '3001',
        'aluno_status': 'ATIVO',
        'tipo': 'REM',
        'tipo_desde': '2026-03-12',
        'data_inicio_prevista': null,
        'bloco_ativo': true,
        'data': null,
        'bloco_origem_id': null,
        'bloco_origem_dia': null,
        'bloco_origem_hora': null,
        'data_origem': null,
        'observacao': null,
      });
      expect(aloc.origem, OrigemNoBloco.alocacao);
      expect(aloc.tipoDesde, DateTime(2026, 3, 12));

      final rep = AlunoDoBloco.deLinha(const {
        'origem': 'REPOSICAO',
        'registro_id': 'rep-1',
        'aluno_id': 'al-9',
        'aluno_nome': 'Lucas',
        'codigo_sgf': null,
        'aluno_status': 'ATIVO',
        'tipo': 'REP',
        'tipo_desde': null,
        'data_inicio_prevista': null,
        'bloco_ativo': true,
        'data': '2026-09-07',
        'bloco_origem_id': 'b-cheio',
        'bloco_origem_dia': 3,
        'bloco_origem_hora': '08:00:00',
        'data_origem': '2026-08-27',
        'observacao': 'faltou',
      });
      expect(rep.ehReposicao, isTrue);
      expect(rep.data, DateTime(2026, 9, 7));
      expect(
        rep.blocoOrigemHora,
        '08:00:00',
        reason: 'o corte para hh:mm é do rótulo, não do modelo',
      );
      expect(rep.rotuloReposicao, 'reposição de Qua 08:00 27/08');
    });

    test('resumoLotacao separa fixos de reposições do dia', () {
      final lista = [
        alocacaoFalsa(alunoId: 'a', nome: 'A', tipo: 'REM'),
        alocacaoFalsa(alunoId: 'b', nome: 'B', tipo: 'PRE'),
        reposicaoFalsa(),
      ];
      expect(
        resumoLotacao(lista, capacidade: 10),
        'Ocupação 3/10 (2 fixos + 1 reposição no dia)',
      );
    });

    test('sem reposição o resumo não fala de reposição nenhuma', () {
      expect(
        resumoLotacao([
          alocacaoFalsa(alunoId: 'a', nome: 'A', tipo: 'REM'),
        ], capacidade: 6),
        'Ocupação 1/6 (1 aluno)',
      );
      expect(resumoLotacao(const [], capacidade: 6), 'Ocupação 0/6 (0 alunos)');
    });
  });

  group('turmas do aluno', () {
    test(
      'rotuloBloco é o nome curto do bloco em toda tela que não é a grade',
      () {
        expect(rotuloBloco(1, '08:00'), 'Seg 08:00');
        expect(rotuloBloco(6, '14:30:00'), 'Sáb 14:30');
      },
    );

    test('agruparPorAluno ordena por dia e depois por hora', () {
      final turmas = [
        turmaFalsa(
          alunoId: 'al-1',
          blocoId: 'b-2',
          tipo: 'REM',
          diaSemana: 4,
          horaInicio: '09:30',
        ),
        turmaFalsa(
          alunoId: 'al-1',
          blocoId: 'b-1',
          tipo: 'REM',
          diaSemana: 2,
          horaInicio: '19:00',
        ),
        turmaFalsa(
          alunoId: 'al-1',
          blocoId: 'b-3',
          tipo: 'PRE',
          diaSemana: 2,
          horaInicio: '08:00',
        ),
      ];
      expect(agruparPorAluno(turmas)['al-1']!.map((t) => t.rotulo).toList(), [
        'Ter 08:00',
        'Ter 19:00',
        'Qui 09:30',
      ]);
    });

    test('rotuloTurmasDoAluno mostra só os blocos ATIVOS', () {
      final turmas = [
        turmaFalsa(alunoId: 'al-1', blocoId: 'b-1', tipo: 'REM'),
        turmaFalsa(
          alunoId: 'al-1',
          blocoId: 'b-inativo',
          tipo: 'REM',
          diaSemana: 5,
          horaInicio: '14:00',
          blocoAtivo: false,
        ),
      ];
      expect(rotuloTurmasDoAluno(turmas), 'Qua 08:00');
      expect(rotuloTurmasDoAluno(const []), '—');
    });

    test(
      'alunosEmTurma ignora alocação em bloco desativado — a mesma definição '
      'de rt_pendencias_diaria desde o card 5.7',
      () {
        final turmas = [
          turmaFalsa(alunoId: 'al-1', blocoId: 'b-1', tipo: 'REM'),
          turmaFalsa(
            alunoId: 'al-2',
            blocoId: 'b-inativo',
            tipo: 'REM',
            blocoAtivo: false,
          ),
        ];
        expect(alunosEmTurma(turmas), {'al-1'});
      },
    );

    test('deLinha de v_bloco_alunos lê o hh:mm:ss e o bloco_ativo', () {
      final turma = TurmaDoAluno.deLinha(const {
        'alocacao_id': 'aloc-1',
        'bloco_id': 'b-1',
        'aluno_id': 'al-1',
        'dia_semana': 3,
        'hora_inicio': '08:00:00',
        'metodo_id': 'm-int',
        'sala_id': 's-lab1',
        'bloco_ativo': false,
        'tipo': 'NOVO',
        'tipo_desde': '2026-03-12',
        'data_inicio_prevista': '2026-09-10',
      });
      expect(turma.rotulo, 'Qua 08:00');
      expect(turma.blocoAtivo, isFalse);
      expect(turma.dataInicioPrevista, DateTime(2026, 9, 10));
    });
  });

  group('situação REP', () {
    SituacaoRep situacao({
      int debito = 0,
      DateTime? repDesde,
      String veredito = 'MANTER',
    }) => SituacaoRep(
      debito: debito,
      semanasUteis: 2,
      capacidade: 1,
      faltasRecentes: 0,
      repDesde: repDesde,
      veredito: veredito,
    );

    test('aluno em dia e pontual não vira painel na ficha', () {
      // Um painel permanente dizendo "0 aulas a repor" em toda ficha treina a
      // pessoa a não olhar para ele.
      expect(situacao().relevante, isFalse);
    });

    test(
      'débito, contínuo ou veredito diferente de MANTER tornam relevante',
      () {
        expect(situacao(debito: 3).relevante, isTrue);
        expect(situacao(repDesde: DateTime(2026, 8, 1)).relevante, isTrue);
        expect(situacao(veredito: 'SUGERIR_VOLTA').relevante, isTrue);
      },
    );

    test(
      'só os dois vereditos de sugestão têm aviso — MANTER não é notícia',
      () {
        expect(avisoVeredito('MANTER'), isNull);
        expect(avisoVeredito('SUGERIR_CONTINUO'), isNotNull);
        expect(avisoVeredito('SUGERIR_VOLTA'), isNotNull);
      },
    );

    test('deLinha lê o tipo composto tp_rep_situacao', () {
      final s = SituacaoRep.deLinha(const {
        'debito': 3,
        'aula_mais_antiga': '2026-09-12',
        'prazo_final': '2026-10-12',
        'semanas_uteis': 2,
        'capacidade': 1,
        'faltas_recentes': 1,
        'rep_desde': null,
        'veredito': 'SUGERIR_CONTINUO',
      });
      expect(s.debito, 3);
      expect(s.prazoFinal, DateTime(2026, 10, 12));
      expect(s.continuo, isFalse);
      expect(s.relevante, isTrue);
    });
  });
}
