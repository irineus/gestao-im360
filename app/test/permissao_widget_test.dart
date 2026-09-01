import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/botoes.dart';

/// Card 2.8 §9.1: as **duas metades** da decisão 1 do card 2.6 —
/// botão sem permissão é **ocultado**; botão sem estado é **desabilitado com
/// motivo**. A diferença não é estética: botão desabilitado sugere que algo na
/// tela pode destravá-lo, e permissão não destrava na tela.
void main() {
  Future<void> montar(
    WidgetTester tester,
    Widget botao, {
    Set<String> permissoes = const {},
    Size tamanho = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [permissoesProvider.overrideWithValue(permissoes)],
        child: MaterialApp(
          theme: temaClaro(),
          home: Scaffold(body: Center(child: botao)),
        ),
      ),
    );
  }

  testWidgets('sem permissão: o botão não é renderizado', (tester) async {
    await montar(
      tester,
      BotaoAcao(
        rotulo: 'Registrar entrega',
        exigePermissao: 'estoque.lancar_saida',
        aoTocar: () {},
      ),
      permissoes: const {'alunos.ler'},
    );
    expect(find.text('Registrar entrega'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('com permissão: o botão aparece e funciona', (tester) async {
    var tocou = false;
    await montar(
      tester,
      BotaoAcao(
        rotulo: 'Registrar entrega',
        exigePermissao: 'estoque.lancar_saida',
        aoTocar: () => tocou = true,
      ),
      permissoes: const {'estoque.lancar_saida'},
    );
    expect(find.text('Registrar entrega'), findsOneWidget);
    await tester.tap(find.text('Registrar entrega'));
    expect(tocou, isTrue);
  });

  testWidgets('sem estado: visível, desabilitado e com o motivo em tooltip', (
    tester,
  ) async {
    await montar(
      tester,
      BotaoAcao(
        rotulo: 'Avançar módulo',
        exigePermissao: 'turmas.editar',
        desabilitado: const DesabilitadoCom(
          'O último módulo já foi concluído.',
        ),
        aoTocar: () {},
      ),
      permissoes: const {'turmas.editar'},
    );

    expect(find.text('Avançar módulo'), findsOneWidget);
    final botao = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(botao.onPressed, isNull, reason: 'desabilitado pelo estado');

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'O último módulo já foi concluído.');
  });

  testWidgets('no mobile o motivo também aparece como legenda visível', (
    tester,
  ) async {
    // Tooltip depende de hover/long-press: no celular do monitor o motivo
    // precisa estar na tela.
    await montar(
      tester,
      BotaoAcao(
        rotulo: 'Avançar módulo',
        desabilitado: const DesabilitadoCom(
          'O último módulo já foi concluído.',
        ),
        aoTocar: () {},
      ),
      tamanho: const Size(390, 800),
    );
    expect(find.text('O último módulo já foi concluído.'), findsOneWidget);
  });

  testWidgets('sem exigência de permissão o botão aparece para qualquer um', (
    tester,
  ) async {
    await montar(tester, BotaoAcao(rotulo: 'Cancelar', aoTocar: () {}));
    expect(find.text('Cancelar'), findsOneWidget);
  });

  testWidgets('permissão vence estado: sem permissão nem o motivo vaza', (
    tester,
  ) async {
    // Quem não pode a ação não fica sabendo por que ela estaria indisponível.
    await montar(
      tester,
      BotaoAcao(
        rotulo: 'Estornar',
        exigePermissao: 'estoque.estornar',
        desabilitado: const DesabilitadoCom('Movimento já estornado.'),
        aoTocar: () {},
      ),
      tamanho: const Size(390, 800),
    );
    expect(find.text('Estornar'), findsNothing);
    expect(find.text('Movimento já estornado.'), findsNothing);
  });

  test('DesabilitadoCom exige motivo', () {
    expect(() => DesabilitadoCom(''), throwsAssertionError);
  });
}
