import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/projecao/projecao.dart';

import 'apoio/projecao_falso.dart';

/// A lógica **pura** da tela 8 (card 8.5): o pivô material × mês, os filtros, a
/// proveniência e os rótulos. Sem rede e sem cliente Supabase (card 2.8 §9.3).
void main() {
  final outubro = DateTime(2026, 10);
  final novembro = DateTime(2026, 11);

  late List<CelulaProjecao> celulas;

  setUp(() {
    celulas = ProjecaoFalso.fixture().grade_;
  });

  group('pivô material × mês', () {
    test('uma linha por material, com a quantidade de cada mês', () {
      final linhas = pivotar(celulas);

      expect(linhas.map((l) => l.codigo), ['02', '03', '04']);
      expect(linhas[0].quantidadeEm(outubro), 3);
      expect(linhas[2].quantidadeEm(novembro), 3);
    });

    test('soma as regras do mesmo material e mês num número só', () {
      // `04` tem 2 por MEDIA_METODO e 1 por RITMO_ALUNO em novembro. A célula da
      // tela mostra 3 — e a coluna Regra é quem diz que vieram de dois degraus.
      final linha = pivotar(celulas).firstWhere((l) => l.codigo == '04');

      expect(linha.quantidadeEm(novembro), 3);
      expect(linha.total, 3);
      expect(linha.rotuloProveniencia, regrasMistas);
    });

    test('proveniência de um degrau só vem com o nome do degrau', () {
      final linha = pivotar(celulas).firstWhere((l) => l.codigo == '02');

      expect(linha.regras, ['MEDIA_METODO']);
      expect(linha.rotuloProveniencia, 'Média do método');
    });

    test('mês sem projeção não tem chave — é traço, não zero', () {
      // A distinção é a mesma do card 2.3 §3.1: ausência não é zero. `0` na
      // célula afirmaria que a conta foi feita e deu nada; o traço diz que
      // aquele mês não entrou na conta daquele material.
      final linha = pivotar(celulas).firstWhere((l) => l.codigo == '03');

      expect(linha.temMes(outubro), isFalse);
      expect(linha.quantidadeEm(outubro), 0);
      expect(linha.temMes(novembro), isTrue);
    });

    test('o total é a soma dos meses, e sai do pivô e não da tela', () {
      expect(pivotar(celulas).map((l) => l.total), [3, 2, 3]);
    });

    test('as regras saem na ordem da cascata, não na de chegada', () {
      final linha = pivotar(celulas).firstWhere((l) => l.codigo == '04');

      // MODULAR → RITMO_ALUNO → PREVISAO_CURSO → MEDIA_METODO. Na fixture as
      // células chegam com MEDIA_METODO primeiro; a ordem exibida é a da
      // cascata, que é como a decisão se lê.
      expect(linha.regras, ['RITMO_ALUNO', 'MEDIA_METODO']);
    });

    test('degrau desconhecido não some da linha', () {
      // O banco pode ganhar um quinto degrau antes deste app. Descartá-lo aqui
      // faria a coluna Regra mentir justamente sobre a novidade.
      final comNovo = [
        ...celulas,
        CelulaProjecao(
          materialId: 'mat-02',
          metodoId: 'm-int',
          codigo: '02',
          nome: 'Informática Essencial 2',
          categoria: 'APOSTILA',
          mes: outubro,
          quantidade: 1,
          regra: 'DEGRAU_NOVO',
          calculadoEm: DateTime(2026, 9, 6, 3, 12),
        ),
      ];
      final linha = pivotar(comNovo).firstWhere((l) => l.codigo == '02');

      expect(linha.regras, ['MEDIA_METODO', 'DEGRAU_NOVO']);
      expect(linha.rotuloProveniencia, regrasMistas);
      expect(linha.quantidadeEm(outubro), 4);
    });
  });

  group('meses e rótulos', () {
    test('os meses saem em ordem e sem repetição', () {
      expect(mesesDaProjecao(celulas), [outubro, novembro]);
    });

    test('o ano entra só quando a janela cruza o ano', () {
      expect(mesesCruzamAno([outubro, novembro]), isFalse);
      expect(rotuloMes(outubro), 'out');

      final cruzando = [novembro, DateTime(2026, 12), DateTime(2027, 1)];
      expect(mesesCruzamAno(cruzando), isTrue);
      // `nov · dez · jan` lê-se como se janeiro viesse antes — a mesma
      // armadilha que `formatarPeriodo` resolveu no card 8.1,5.
      expect(rotuloMes(DateTime(2027, 1), comAno: true), 'jan/27');
      expect(rotuloMes(DateTime(2027, 1), comAno: false), 'jan');
    });

    test('ano de dois dígitos com zero à esquerda', () {
      expect(rotuloMes(DateTime(2007, 3), comAno: true), 'mar/07');
    });

    test('regra desconhecida volta como veio', () {
      expect(rotuloRegra('MODULAR'), 'Cronograma da turma');
      expect(rotuloRegra('DEGRAU_NOVO'), 'DEGRAU_NOVO');
    });

    test('ritmo nulo é traço, e não o ritmo do método', () {
      expect(rotuloRitmo(30), '30 d');
      expect(rotuloRitmo(null), '—');
    });

    test('a posição diz onde o item está na trilha pendente', () {
      final detalhe = ProjecaoFalso.fixture().detalhe_.first;
      expect(rotuloPosicao(detalhe), '2º de 5 pendentes');
    });
  });

  group('filtro', () {
    test('filtra por método, categoria e busca', () {
      expect(
        pivotar(
          filtrarCelulas(celulas, const FiltroProjecao(metodoId: 'm-ing')),
        ).map((l) => l.codigo),
        ['04'],
      );
      expect(
        pivotar(
          filtrarCelulas(celulas, const FiltroProjecao(categoria: 'APOSTILA')),
        ).map((l) => l.codigo),
        ['02', '03'],
      );
      expect(
        pivotar(
          filtrarCelulas(celulas, const FiltroProjecao(busca: 'avançada')),
        ).map((l) => l.codigo),
        ['03', '04'],
      );
    });

    test('o filtro por regra age ANTES do pivô, e por isso muda o total', () {
      // É a razão de `filtrarCelulas` existir separada de `pivotar`: com o
      // filtro aplicado depois, `04` continuaria somando 3 e a tela diria que
      // 3 exemplares vêm de média do método quando 1 vem de ritmo próprio.
      final linhas = pivotar(
        filtrarCelulas(celulas, const FiltroProjecao(regra: 'MEDIA_METODO')),
      );
      final quatro = linhas.firstWhere((l) => l.codigo == '04');

      expect(quatro.total, 2);
      expect(quatro.rotuloProveniencia, 'Média do método');
      expect(linhas.map((l) => l.codigo), ['02', '04']);
    });

    test('o contador de filtros ativos conta os quatro', () {
      expect(const FiltroProjecao().ativos, 0);
      expect(
        const FiltroProjecao(
          busca: 'x',
          metodoId: 'm-int',
          categoria: 'APOSTILA',
          regra: 'MODULAR',
        ).ativos,
        4,
      );
      // Busca só de espaços não é filtro.
      expect(const FiltroProjecao(busca: '   ').ativos, 0);
    });

    test('copiar apaga o filtro quando a função devolve nulo', () {
      const cheio = FiltroProjecao(metodoId: 'm-int', regra: 'MODULAR');
      expect(cheio.copiar(metodoId: () => null).metodoId, isNull);
      expect(cheio.copiar(metodoId: () => null).regra, 'MODULAR');
    });

    test('as listas dos filtros só oferecem o que existe', () {
      expect(categoriasProjetadas(celulas), ['APOSTILA', 'LIVRO']);
      // Na ordem da cascata, e sem MODULAR — que não está nesta projeção.
      expect(regrasPresentes(celulas), [
        'RITMO_ALUNO',
        'PREVISAO_CURSO',
        'MEDIA_METODO',
      ]);
    });
  });

  group('carimbo', () {
    test('é o mais recente das células', () {
      expect(calculadoEmDe(celulas), DateTime(2026, 9, 6, 3, 12));
    });

    test('projeção sem célula nenhuma não tem carimbo', () {
      // E é isso que faz a tela dizer "ainda não foi calculada" em vez de
      // desenhar um traço mudo.
      expect(calculadoEmDe(const []), isNull);
    });
  });

  group('o detalhe fecha com o total', () {
    test('a contagem de alunos de cada célula é a quantidade da grade', () {
      // A propriedade que a tela 8 inteira depende, e a mesma que o
      // `082_projecao_views_tela` §3.1 mede contra o banco.
      final falso = ProjecaoFalso.fixture();
      for (final c in falso.grade_) {
        final alunos = falso.detalhe_.where(
          (d) =>
              d.materialId == c.materialId &&
              d.mes == c.mes &&
              d.regra == c.regra,
        );
        expect(
          alunos.length,
          c.quantidade,
          reason: 'célula ${c.codigo} · ${c.mes} · ${c.regra}',
        );
      }
    });
  });
}
