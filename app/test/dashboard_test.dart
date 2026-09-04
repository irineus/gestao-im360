import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/dashboard/dashboard.dart';

import 'apoio/dashboard_falso.dart';
import 'apoio/turmas_falso.dart';

/// A lógica pura do dashboard (card 5.9): a soma das parcelas que o banco já
/// mandou prontas, a escolha do método visível e a semana lida de
/// `data_referencia`.
///
/// Nada aqui recalcula capacidade, ocupação ou vaga — o card 5.2 é o dono da
/// fórmula. O que estes testes protegem é o **jeito de somar**, que é onde uma
/// tela de agregação erra sem dar erro.
void main() {
  Future<List<CelulaGrade>> daFixture() => DashboardFalso().vagasDaSemana();

  group('totais por método', () {
    test('somam blocos, capacidade, ocupação e vagas de cada método', () async {
      final totais = totaisPorMetodo(await daFixture());

      expect(totais.length, 2);
      final interativo = totais.first;
      expect(
        interativo.metodoCodigo,
        'INTERATIVO',
        reason: 'a ordem é por tamanho, não alfabética: INGLES viria antes',
      );
      expect(interativo.blocos, 4);
      expect(interativo.capacidade, 40);
      expect(interativo.ocupacao, 30);
      expect(interativo.blocosLotados, 1, reason: 'o bloco 10/10');
      expect(interativo.blocosAcimaCapacidade, 1, reason: 'o bloco 11/10');
      expect(interativo.temAlerta, isTrue);

      final ingles = totais.last;
      expect(ingles.metodoCodigo, 'INGLES');
      expect(ingles.blocos, 1);
      expect(ingles.vagasLivres, 2);
      expect(ingles.temAlerta, isFalse);
    });

    test('vagas é a SOMA das parcelas, e não capacidade − ocupação', () async {
      final interativo = totaisPorMetodo(await daFixture()).first;

      // As duas contas divergem exatamente quando existe bloco acima da
      // capacidade: `fn_vagas_livres` devolve 0 ali (card 5.2 recusa negativo),
      // e a diferença faria o excesso de uma turma abater a vaga real de outra.
      expect(interativo.vagasLivres, 11);
      expect(
        interativo.capacidade - interativo.ocupacao,
        10,
        reason: 'é o número ERRADO, e é plausível: por isso não se recalcula',
      );
    });

    test('método sem vaga nenhuma continua na lista, com zero', () {
      final totais = totaisPorMetodo([
        vagaFalsa(
          blocoId: 'b1',
          dia: 1,
          dataReferencia: DateTime(2026, 1, 5),
          ocupacao: 10,
        ),
      ]);
      expect(totais.single.vagasLivres, 0);
      expect(totais.single.blocosLotados, 1);
      // design-system §7.2: no dashboard, número que desaparece parece erro.
      expect(totais.single.vagasTexto, '0 vagas livres');
    });

    // Todos os PCs da sala em manutenção dão `0/0`. Antes o bloco entrava em
    // `blocosLotados` e a célula era pintada como lotada — o oposto do que
    // houve: não está cheio, não há o que ocupar (revisão da fase 05).
    test('capacidade zero não é "lotado"', () {
      final celula = vagaFalsa(
        blocoId: 'b1',
        dia: 1,
        dataReferencia: DateTime(2026, 1, 5),
        capacidade: 0,
        vagasLivres: 0,
      );
      expect(celula.lotado, isFalse);
      expect(celula.semCapacidade, isTrue);
      expect(totaisPorMetodo([celula]).single.blocosLotados, 0);

      final vagas = vagasDa([celula]);
      expect(vagas.lotada, isFalse);
      expect(vagas.semCapacidade, isTrue);
      expect(descricaoCelula(1, '08:00', vagas), contains('sem capacidade'));
      expect(descricaoCelula(1, '08:00', vagas), isNot(contains('lotado')));
    });
  });

  group('método visível', () {
    test('sem escolha é o primeiro — o maior', () async {
      final totais = totaisPorMetodo(await daFixture());
      expect(metodoVisivel(totais, null)?.metodoCodigo, 'INTERATIVO');
    });

    test('escolhido é o escolhido', () async {
      final totais = totaisPorMetodo(await daFixture());
      expect(metodoVisivel(totais, 'm-ing')?.metodoCodigo, 'INGLES');
    });

    test(
      'escolha que deixou de existir cai no primeiro, sem tela vazia',
      () async {
        // Acontece quando o último bloco daquele método é desativado com a tela
        // aberta: manter o id sumido deixaria a grade vazia sem motivo visível.
        final totais = totaisPorMetodo(await daFixture());
        expect(metodoVisivel(totais, 'm-que-nao-existe')?.metodoId, 'm-int');
        expect(metodoVisivel(const [], null), isNull);
      },
    );
  });

  group('célula de vagas', () {
    test('soma os blocos do cruzamento e conta as salas', () {
      final data = DateTime(2026, 1, 7);
      final vagas = vagasDa([
        vagaFalsa(blocoId: 'b1', dia: 3, dataReferencia: data, ocupacao: 8),
        vagaFalsa(
          blocoId: 'b2',
          dia: 3,
          dataReferencia: data,
          salaId: 's-lab2',
          capacidade: 6,
          ocupacao: 1,
        ),
      ]);
      expect(vagas.blocos, 2);
      expect(vagas.salas, 2);
      expect(vagas.capacidade, 16);
      expect(vagas.vagasLivres, 7);
      expect(vagas.texto, '7/16');
    });

    test('um bloco acima da capacidade marca a célula inteira', () {
      final data = DateTime(2026, 1, 7);
      final vagas = vagasDa([
        vagaFalsa(blocoId: 'b1', dia: 3, dataReferencia: data, ocupacao: 2),
        vagaFalsa(
          blocoId: 'b2',
          dia: 3,
          dataReferencia: data,
          salaId: 's-lab2',
          ocupacao: 11,
          vagasLivres: 0,
          acima: true,
        ),
      ]);
      // Não se dilui na soma: 11 em 10 continua sendo um problema mesmo com a
      // sala ao lado sobrando.
      expect(vagas.acimaCapacidade, isTrue);
      expect(vagas.lotada, isFalse, reason: 'acima vence lotada');
    });

    test('cruzamento sem bloco não é cruzamento lotado', () {
      expect(vagasDa(const []).semBloco, isTrue);
      expect(vagasDa(const []).lotada, isFalse);
    });

    test('a descrição diz "vagas livres", não um par de números', () {
      final vagas = vagasDa([
        vagaFalsa(
          blocoId: 'b1',
          dia: 3,
          dataReferencia: DateTime(2026, 1, 7),
          ocupacao: 8,
        ),
      ]);
      expect(
        descricaoCelula(3, '08:00', vagas),
        'Quarta 08:00, 2 vagas livres de 10',
      );
    });
  });

  group('a semana vem do banco', () {
    test('sai de data_referencia, e não do relógio do aparelho', () {
      // Quarta, 07/01/2026 → a segunda é 05/01/2026. Uma semana que não é a de
      // hoje: se a tela usasse `DateTime.now()`, este teste passaria só no dia
      // certo — e em produção rotularia a grade certa com a semana errada para
      // quem estivesse em outro fuso.
      final segunda = segundaDaGrade([
        vagaFalsa(blocoId: 'b1', dia: 3, dataReferencia: DateTime(2026, 1, 7)),
      ]);
      expect(segunda, DateTime(2026, 1, 5));
      expect(rotuloSemana(segunda!), '05/01 a 10/01');
    });

    test('sem linha nenhuma não há semana a afirmar', () {
      expect(segundaDaGrade(const []), isNull);
    });
  });

  test(
    'celulasDoMetodo separa os métodos — vaga de um não serve ao outro',
    () async {
      final todas = await daFixture();
      final interativo = celulasDoMetodo(todas, 'm-int');
      expect(interativo.length, 4);
      expect(interativo.every((c) => c.metodoCodigo == 'INTERATIVO'), isTrue);
      expect(celulasDoMetodo(todas, 'm-ing').single.metodoCodigo, 'INGLES');
    },
  );

  test('a grade montada é a do método, e não a soma dos dois', () async {
    final todas = await daFixture();
    final grade = montarGrade(
      segundaDaGrade(todas)!,
      celulasDoMetodo(todas, 'm-int'),
    );
    // Quarta 08:00 tem INTERATIVO (10/10) e INGLES (4/6) no mesmo cruzamento.
    // Com o filtro, a célula é só a do método visível.
    final quarta = vagasDa(grade.em(3, '08:00'));
    expect(quarta.blocos, 1);
    expect(quarta.capacidade, 10);
    expect(quarta.vagasLivres, 0);
  });

  test(
    'a fixture do dashboard descreve a MESMA escola que a de turmas',
    () async {
      // Os dois falsos concordarem é o que reproduz o teste 095 do banco, que
      // assere que a view e a função devolvem as mesmas linhas na semana corrente.
      final doDashboard = await daFixture();
      final deTurmas = await TurmasFalso.fixture().grade(
        segundaDe(DateTime.now()),
      );
      expect(
        doDashboard.map((c) => c.blocoId).toList(),
        deTurmas.map((c) => c.blocoId).toList(),
      );
    },
  );
}
