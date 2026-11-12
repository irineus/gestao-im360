import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/turmas/modular.dart';

import 'apoio/modular_falso.dart';

/// A lógica **pura** da tela 5 (card 7.3): o que se testa sem rede e sem cliente
/// Supabase (card 2.8 §9.3).
///
/// O que este arquivo protege, e nenhum catálogo enxerga:
///
///   • **turma sem módulo corrente tem DOIS sentidos** — "terminou" e "sem
///     cronograma" —, e o modelo não os confunde: quem os separa é a presença
///     de linhas no cronograma, exatamente como `fn_turma_modular_avancar` faz
///     com `TURMA_SEM_MODULO_CORRENTE` × `TURMA_SEM_CRONOGRAMA`;
///
///   • **`vagas_livres` tem piso zero e `acimaCapacidade` não**: a turma de 16
///     numa capacidade de 15 mostra `16/15` e zero vagas, e é o `acimaCapacidade`
///     que a distingue de uma turma exatamente cheia;
///
///   • **`periodo` diz o que sabe** e não inventa a metade que falta — o módulo
///     com só uma das datas não vira um intervalo com uma ponta em branco.
void main() {
  group('TurmaModular', () {
    test('lotação, vagas e os três estados de ocupação', () {
      final vazia = turmaModularFalsa(id: 't', nome: 'T', alocados: 0);
      expect(vazia.lotacaoTexto, '0/15');
      expect(vazia.vagasLivres, 15);
      expect(vazia.lotada, isFalse);
      expect(vazia.acimaCapacidade, isFalse);

      final cheia = turmaModularFalsa(id: 't', nome: 'T', alocados: 15);
      expect(cheia.lotada, isTrue);
      expect(cheia.vagasLivres, 0);
      expect(cheia.acimaCapacidade, isFalse);

      // Piso zero em `vagas_livres`, como na view: "−1 vaga livre" não é frase
      // de tela. Quem distingue "cheia" de "estourada" é `acimaCapacidade`.
      final acima = turmaModularFalsa(id: 't', nome: 'T', alocados: 16);
      expect(acima.vagasLivres, 0);
      expect(acima.acimaCapacidade, isTrue);
      expect(
        acima.lotada,
        isFalse,
        reason:
            'turma estourada não é "lotada": o aviso e a saída são outros, e '
            'confundir os dois esconderia o estado que precisa de ação',
      );
    });

    test('módulo corrente nulo NÃO é lido como fim de turma pelo modelo', () {
      final semCorrente = turmaModularFalsa(id: 't', nome: 'T');
      expect(semCorrente.semModuloCorrente, isTrue);
      expect(
        semCorrente.moduloCorrenteRotulo,
        isNull,
        reason:
            'sem nome não há rótulo — quem decide se é "terminou" ou "sem '
            'cronograma" é o cronograma, não a turma',
      );
    });

    test('o rótulo do módulo corrente traz a ordem do catálogo', () {
      final t = turmaModularFalsa(
        id: 't',
        nome: 'T',
        moduloCorrenteId: 'm2',
        moduloCorrenteNome: 'Instalações prediais',
        moduloCorrenteOrdem: 2,
      );
      expect(t.moduloCorrenteRotulo, '2. Instalações prediais');
    });
  });

  group('ModuloDaTurma', () {
    test('o período diz o que sabe e não inventa a metade que falta', () {
      final completo = moduloDaTurmaFalso(
        id: 'c',
        turmaId: 't',
        moduloId: 'm',
        nome: 'M',
        ordem: 1,
        dataInicio: DateTime(2026, 8, 1),
        prevConclusao: DateTime(2026, 9, 20),
      );
      expect(completo.periodo, '01/08–20/09');

      final soInicio = moduloDaTurmaFalso(
        id: 'c',
        turmaId: 't',
        moduloId: 'm',
        nome: 'M',
        ordem: 1,
        dataInicio: DateTime(2026, 8, 1),
      );
      expect(soInicio.periodo, 'desde 01/08');

      final soFim = moduloDaTurmaFalso(
        id: 'c',
        turmaId: 't',
        moduloId: 'm',
        nome: 'M',
        ordem: 1,
        prevConclusao: DateTime(2026, 9, 20),
      );
      expect(soFim.periodo, 'até 20/09');

      final nenhuma = moduloDaTurmaFalso(
        id: 'c',
        turmaId: 't',
        moduloId: 'm',
        nome: 'M',
        ordem: 1,
      );
      expect(nenhuma.periodo, semDatasTexto);
      expect(nenhuma.semDatas, isTrue);
    });

    test('os três estados da faixa do cronograma', () {
      ModuloDaTurma fazer({bool concluido = false, bool corrente = false}) =>
          moduloDaTurmaFalso(
            id: 'c',
            turmaId: 't',
            moduloId: 'm',
            nome: 'M',
            ordem: 1,
            concluido: concluido,
            corrente: corrente,
          );

      expect(fazer(concluido: true).estado, EstadoModulo.concluido);
      expect(fazer(corrente: true).estado, EstadoModulo.corrente);
      expect(fazer().estado, EstadoModulo.futuro);
    });
  });

  group('agrupamento e filtro', () {
    test('os alunos vêm com os ativos primeiro e os que saíram depois', () {
      final mapa = agruparPorTurma([
        alunoDaTurmaFalso(
          alocacaoId: '1',
          turmaId: 't',
          alunoId: 'a',
          nome: 'Zulmira',
        ),
        alunoDaTurmaFalso(
          alocacaoId: '2',
          turmaId: 't',
          alunoId: 'b',
          nome: 'Ana',
          ativo: false,
          motivoSaida: 'trancou',
        ),
        alunoDaTurmaFalso(
          alocacaoId: '3',
          turmaId: 't',
          alunoId: 'c',
          nome: 'Bruno',
        ),
      ]);
      expect(
        mapa['t']!.map((a) => a.alunoNome).toList(),
        ['Bruno', 'Zulmira', 'Ana'],
        reason:
            'ativos por nome, e os que saíram no fim — a lista é de quem está '
            'na turma, e o histórico vem depois',
      );
    });

    test('o cronograma vem na ordem do catálogo, e não na de chegada', () {
      final mapa = agruparCronograma([
        moduloDaTurmaFalso(
          id: 'c3',
          turmaId: 't',
          moduloId: 'm3',
          nome: 'Três',
          ordem: 3,
        ),
        moduloDaTurmaFalso(
          id: 'c1',
          turmaId: 't',
          moduloId: 'm1',
          nome: 'Um',
          ordem: 1,
        ),
        moduloDaTurmaFalso(
          id: 'c2',
          turmaId: 't',
          moduloId: 'm2',
          nome: 'Dois',
          ordem: 2,
        ),
      ]);
      expect(mapa['t']!.map((m) => m.moduloOrdem).toList(), [1, 2, 3]);
    });

    test(
      'o filtro casa nome da turma e nome do curso, e a view devolve tudo',
      () {
        final turmas = [
          turmaModularFalsa(id: 't1', nome: 'Eletricista 2026.1'),
          turmaModularFalsa(
            id: 't2',
            nome: 'Depilação 2026.1',
            cursoId: 'c-dep',
            cursoNome: 'Depilação',
          ),
        ];
        expect(
          filtrarTurmas(
            turmas,
            const FiltroTurmasModular(busca: 'depil'),
          ).map((t) => t.id),
          ['t2'],
        );
        expect(
          filtrarTurmas(
            turmas,
            const FiltroTurmasModular(cursoId: 'c-dep'),
          ).map((t) => t.id),
          ['t2'],
        );
        expect(
          filtrarTurmas(turmas, FiltroTurmasModular.semFiltro).length,
          2,
          reason: 'filtro é estado da tela, desligável (card 2.3 §2.3(h))',
        );
        expect(const FiltroTurmasModular(busca: '   ').ativos, 0);
      },
    );

    test('a ordem da lista é curso e depois turma', () {
      final ordenadas = ordenarTurmas([
        turmaModularFalsa(id: 'b', nome: 'Eletricista 2025.2'),
        turmaModularFalsa(
          id: 'c',
          nome: 'Depilação 2026.1',
          cursoNome: 'Depilação',
        ),
        turmaModularFalsa(id: 'a', nome: 'Eletricista 2026.1'),
      ]);
      expect(ordenadas.map((t) => t.id).toList(), ['c', 'b', 'a']);
    });

    test('os módulos já no cronograma são os que "Montar cronograma" pula', () {
      final noCronograma = modulosNoCronograma([
        moduloDaTurmaFalso(
          id: 'c1',
          turmaId: 't',
          moduloId: 'm1',
          nome: 'Um',
          ordem: 1,
        ),
      ]);
      expect(noCronograma, {'m1'});
      expect(modulosNoCronograma(const []), isEmpty);
    });
  });

  group('resumo do avanço', () {
    final corrente = moduloDaTurmaFalso(
      id: 'c2',
      turmaId: 't',
      moduloId: 'm2',
      nome: 'Instalações prediais',
      ordem: 2,
      corrente: true,
    );
    final proximo = moduloDaTurmaFalso(
      id: 'c3',
      turmaId: 't',
      moduloId: 'm3',
      nome: 'Comandos elétricos',
      ordem: 3,
    );

    test('diz o que fecha e o que abre, com a data', () {
      final linhas = resumoAvanco(
        corrente: corrente,
        proximo: proximo,
        dataConclusao: DateTime(2026, 10, 10),
      );
      expect(linhas.first, contains('2. Instalações prediais'));
      expect(linhas.first, contains('10/10/2026'));
      expect(linhas.last, contains('3. Comandos elétricos'));
    });

    test('sem linha seguinte no ciclo, abre o próximo do RODÍZIO', () {
      // Card 9.2,90. Vermelho antes: a frase dizia que a turma passava a
      // "turma terminou" — e desde o 9.2,88 a turma é cíclica, o avanço do
      // último módulo abre o primeiro, num ciclo novo. Quem diz qual é o
      // próximo é a view (`proximo_modulo_nome`), não uma conta feita aqui.
      final linhas = resumoAvanco(
        corrente: corrente,
        proximo: null,
        dataConclusao: DateTime(2026, 10, 10),
        proximoDoRodizio: 'Comandos elétricos',
      );
      expect(
        linhas.last,
        'Abre Comandos elétricos — a turma segue em rodízio.',
      );
      expect(linhas.join(' '), isNot(contains('terminou')));
    });

    test(
      'sem próximo e sem o nome do próximo, ainda assim NÃO anuncia fim',
      () {
        final linhas = resumoAvanco(
          corrente: corrente,
          proximo: null,
          dataConclusao: DateTime(2026, 10, 10),
        );
        expect(linhas.last, contains('segue em rodízio'));
        expect(linhas.join(' '), isNot(contains('terminou')));
      },
    );

    test('a frase NÃO promete a data de início do próximo', () {
      // Quem a calcula é `fn_turma_modular_avancar`, com o passo médio da turma
      // e preservando o que já estiver informado: um número escrito aqui seria
      // a segunda conta que o card 2.3 §4.1 proíbe.
      final linhas = resumoAvanco(
        corrente: corrente,
        proximo: proximo,
        dataConclusao: DateTime(2026, 10, 10),
      );
      expect(linhas.last, isNot(contains('11/10')));
      expect(linhas.last, isNot(contains(semDatasTexto)));
    });
  });

  group('a sequência do aluno e a previsão calculada (card 9.2,905)', () {
    ProgressoAlunoModular progresso(String aluno, DateTime? prev) =>
        ProgressoAlunoModular(
          alocacaoId: 'a-$aluno-${prev?.year}',
          turmaId: 't',
          alunoId: aluno,
          modulosTotal: 6,
          modulosFeitos: 2,
          prevConclusao: prev,
        );

    test(
      'previsaoCalculada: fora de turma não é o mesmo que turma sem data',
      () {
        final linhas = [
          progresso('ana', DateTime(2027, 3, 20)),
          progresso('bia', null),
        ];
        expect(previsaoCalculada(linhas, 'ana'), (
          emTurma: true,
          data: DateTime(2027, 3, 20),
        ));
        expect(previsaoCalculada(linhas, 'bia'), (emTurma: true, data: null));
        expect(previsaoCalculada(linhas, 'caio'), (emTurma: false, data: null));
      },
    );

    test('em duas turmas vale a MAIOR previsão — o curso acaba quando acaba a '
        'última', () {
      final linhas = [
        progresso('ana', DateTime(2027, 3, 20)),
        progresso('ana', DateTime(2027, 9, 1)),
      ];
      expect(previsaoCalculada(linhas, 'ana').data, DateTime(2027, 9, 1));
    });

    test('previsaoQueVale: em turma, a calculada — MESMO nula; fora, a '
        'digitada', () {
      final digitada = DateTime(2026, 12, 1);
      // ⚠️ O caso que decide: turma sem datas. A calculada é nula, e a digitada
      // NÃO volta a valer por isso — ela deixou de ser lida (decisão D2).
      expect(
        previsaoQueVale(
          alunoId: 'bia',
          digitada: digitada,
          progresso: [progresso('bia', null)],
        ),
        (data: null, calculada: true),
      );
      expect(
        previsaoQueVale(
          alunoId: 'caio',
          digitada: digitada,
          progresso: const [],
        ),
        (data: digitada, calculada: false),
      );
    });

    test('ModuloFeito lê o nome do módulo e do curso do embed', () {
      final m = ModuloFeito.deLinha({
        'modulo_id': 'mod-1',
        'data_conclusao': '2026-08-10',
        'origem': 'MANUAL',
        'observacao': ' fez na turma da manhã ',
        'modulo': {
          'nome': 'Massas e Molhos',
          'ordem': 2,
          'curso': {'nome': 'Chef Profissional'},
        },
      });
      expect(m.moduloNome, 'Massas e Molhos');
      expect(m.moduloOrdem, 2);
      expect(m.cursoNome, 'Chef Profissional');
      expect(
        apoioModuloFeito(m),
        'concluído em 10/08/2026 · lançado à mão · fez na turma da manhã',
      );
    });

    test('ModuloFeito sem embed (catálogo ilegível) não quebra a ficha', () {
      final m = ModuloFeito.deLinha({
        'modulo_id': 'mod-1',
        'data_conclusao': '2026-08-10',
        'origem': 'COISA_NOVA',
      });
      expect(m.moduloNome, '—');
      // Origem que o app não conhece volta como veio.
      expect(apoioModuloFeito(m), 'concluído em 10/08/2026 · COISA_NOVA');
    });

    test('apoioModuloAFazer: com as duas datas, com uma, e sem nenhuma', () {
      ModuloAFazer m({DateTime? inicio, DateTime? fim, bool entrada = false}) =>
          ModuloAFazer(
            turmaId: 't',
            moduloId: 'm',
            moduloNome: 'Confeitaria',
            moduloOrdem: 3,
            sequencia: 1,
            deEntrada: entrada,
            dataPrevistaInicio: inicio,
            dataPrevistaFim: fim,
          );
      expect(
        apoioModuloAFazer(
          m(inicio: DateTime(2026, 10, 11), fim: DateTime(2026, 11, 20)),
        ),
        'previsto 11/10/2026 a 20/11/2026',
      );
      expect(
        apoioModuloAFazer(m(fim: DateTime(2026, 11, 20), entrada: true)),
        'previsto 20/11/2026 · módulo de entrada',
      );
      expect(apoioModuloAFazer(m()), 'sem data prevista');
    });
  });
}
