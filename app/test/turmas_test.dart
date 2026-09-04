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
}
