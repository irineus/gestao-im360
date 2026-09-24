import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/theme/cores.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/ocupacao.dart';

/// A barra de ocupação das duas grades (card 9.2,61) mede a LARGURA do
/// preenchimento, e não só que o widget existe.
///
/// ⚠️ A primeira versão usava `Stack(fit: StackFit.expand)`, que força o filho
/// a ocupar tudo: a barra saía CHEIA para todo bloco, inclusive o vazio, e
/// todos os testes das telas passavam — eles contavam `BarraOcupacao`, não o
/// desenho. Só o navegador mostrou "10 livres" com a barra de lotado.
void main() {
  Future<double> larguraPreenchida(
    WidgetTester tester, {
    required double fracao,
    bool acima = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        home: Center(
          child: SizedBox(
            width: 200,
            child: BarraOcupacao(fracao: fracao, acimaCapacidade: acima),
          ),
        ),
      ),
    );
    return tester.getSize(find.byKey(chavePreenchimentoOcupacao)).width;
  }

  testWidgets('bloco vazio: nada preenchido', (tester) async {
    expect(await larguraPreenchida(tester, fracao: 0), 0);
  });

  testWidgets('nove de dez: 90% da largura', (tester) async {
    expect(await larguraPreenchida(tester, fracao: 0.9), closeTo(180, 0.01));
  });

  testWidgets('lotado: tudo', (tester) async {
    expect(await larguraPreenchida(tester, fracao: 1), 200);
  });

  testWidgets('acima da capacidade: cheia mesmo com fração menor, e fora da '
      'faixa não estoura', (tester) async {
    expect(await larguraPreenchida(tester, fracao: 0.3, acima: true), 200);
    expect(await larguraPreenchida(tester, fracao: 1.4), 200);
    expect(await larguraPreenchida(tester, fracao: -1), 0);
  });

  testWidgets('o trilho vazio é CLARO nos dois temas — nunca da cor do '
      'preenchido', (tester) async {
    // ⚠️ A primeira versão pintava o trilho de `outlineVariant`, que o tema
    // não declara: o Flutter devolve uma cor quase preta, e o bloco vazio
    // parecia lotado no navegador. Nenhum teste de largura pega isso.
    for (final (tema, trilhoEsperado) in [
      (temaClaro(), Cores.grafite200),
      (temaEscuro(), Cores.divisorEscuro),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: tema,
          home: const Center(
            child: SizedBox(width: 200, child: BarraOcupacao(fracao: 0.5)),
          ),
        ),
      );
      // O MaterialApp anima a troca de tema: sem assentar, a segunda volta
      // leria as cores da primeira.
      await tester.pumpAndSettle();
      final caixas = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(BarraOcupacao),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      expect(caixas.first.color, trilhoEsperado, reason: 'o trilho');
      expect(caixas.last.color, tema.colorScheme.onSurfaceVariant);
      expect(caixas.first.color, isNot(caixas.last.color));
    }
  });
}
