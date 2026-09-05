import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/theme/dimensoes.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/dialogo_resultado.dart';

/// `mostrarResultado` — o componente do card 6.6 previsto em
/// docs/estrategia-testes.md §17.
///
/// O que ele existe para garantir (design-system §5.8 e wireframe §6.3), e o
/// que este arquivo mede:
///
///   • **nunca snackbar**: o resultado que muda a próxima ação some antes de
///     ser lido se for efêmero. Aqui isso é asserção, não intenção;
///   • **duas formas, uma por faixa**: folha inferior no celular (perto do
///     polegar, sem cobrir a lista), diálogo no desktop;
///   • **o link fecha antes de navegar** — sem isso a folha fica por cima da
///     tela de destino e a pessoa chega ao lugar certo sem conseguir vê-lo;
///   • **cor não é portadora única** (§8.2): cada tom tem ícone de forma
///     própria, e o título diz em palavras o que aconteceu;
///   • **alvo de 44 px** em toda ação (§8.4) — a jornada é do monitor, no
///     celular.
void main() {
  const desktop = Size(1400, 900);
  const celular = Size(390, 844);

  Future<void> abrir(
    WidgetTester tester, {
    required Size tamanho,
    TomResultado tom = TomResultado.sucesso,
    List<LinkResultado> links = const [],
    String titulo = 'Entrega registrada',
    String mensagem = 'INT-02 foi entregue. A próxima apostila é INT-03.',
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        home: Scaffold(
          body: Builder(
            builder: (contexto) => TextButton(
              onPressed: () => mostrarResultado(
                contexto,
                titulo: titulo,
                mensagem: mensagem,
                tom: tom,
                links: links,
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('no desktop é diálogo, e nunca snackbar', (tester) async {
    await abrir(tester, tamanho: desktop);

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    // A asserção que dá sentido ao componente inteiro (design-system §5.8).
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Entrega registrada'), findsOneWidget);
    expect(
      find.text('INT-02 foi entregue. A próxima apostila é INT-03.'),
      findsOneWidget,
    );
  });

  testWidgets('no celular é folha inferior', (tester) async {
    await abrir(tester, tamanho: celular);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Entrega registrada'), findsOneWidget);
  });

  testWidgets('o botão "Entendi" fecha, e o resultado some', (tester) async {
    await abrir(tester, tamanho: desktop);
    expect(find.byKey(chaveFecharResultado), findsOneWidget);

    await tester.tap(find.byKey(chaveFecharResultado));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Entrega registrada'), findsNothing);
  });

  testWidgets('o link dispara a ação e o resultado sai do caminho', (
    tester,
  ) async {
    // Sem o `pop` antes de navegar, a folha inferior fica POR CIMA da tela de
    // destino: a pessoa chega ao lugar certo e não consegue vê-lo. O que se
    // mede é o observável — a ação rodou uma vez e a folha não está mais lá —,
    // e não a ordem interna: `Navigator.pop` só termina de retirar a rota
    // depois da animação, então perguntar pela árvore dentro do callback
    // mediria o `pop` do Flutter, não a decisão deste componente.
    var aberto = 0;
    await abrir(
      tester,
      tamanho: celular,
      tom: TomResultado.alerta,
      links: [LinkResultado(rotulo: 'Ver pendência', aoTocar: () => aberto++)],
    );

    await tester.tap(find.text('Ver pendência'));
    await tester.pumpAndSettle();

    expect(aberto, 1);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Entrega registrada'), findsNothing);
  });

  testWidgets('cada tom tem ícone de forma própria — cor não basta', (
    tester,
  ) async {
    await abrir(tester, tamanho: desktop, tom: TomResultado.sucesso);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    await tester.tap(find.byKey(chaveFecharResultado));
    await tester.pumpAndSettle();

    await abrir(tester, tamanho: desktop, tom: TomResultado.atencao);
    expect(find.byIcon(Icons.swap_vert), findsOneWidget);

    await tester.tap(find.byKey(chaveFecharResultado));
    await tester.pumpAndSettle();

    await abrir(tester, tamanho: desktop, tom: TomResultado.alerta);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('as ações têm 44 px de alvo, no celular e no desktop', (
    tester,
  ) async {
    for (final tamanho in [celular, desktop]) {
      await abrir(
        tester,
        tamanho: tamanho,
        links: [LinkResultado(rotulo: 'Ver pendência', aoTocar: () {})],
      );
      for (final rotulo in ['Ver pendência', 'Entendi']) {
        expect(
          tester
              .getSize(
                find
                    .ancestor(
                      of: find.text(rotulo),
                      matching: find.byType(SizedBox),
                    )
                    .first,
              )
              .height,
          Dim.alvoMobile,
          reason: '$rotulo em ${tamanho.width.toInt()}px',
        );
      }
      await tester.tap(find.byKey(chaveFecharResultado));
      await tester.pumpAndSettle();
    }
  });
}
