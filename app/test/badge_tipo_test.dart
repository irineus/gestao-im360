import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/theme/cores.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/badge_status.dart';
import 'package:gestao_im360/widgets/badge_tipo.dart';

/// `BadgeTipo` (design-system §5.1 e §2.4, card 5.7): contorno de 1,5 px e
/// fundo transparente, com a cor de `BadgesTipo` do tema em uso.
///
/// O par com `badge_status_test.dart` é o que importa: **as duas formas nunca
/// se misturam** (card 1.9 §6). Status é preenchido tonal, tipo é contorno, e
/// é a FORMA que separa os dois vocabulários numa tela onde os dois aparecem
/// lado a lado — sem ela, restaria a cor, que morre em P&B e em daltonismo.
void main() {
  Future<void> montar(
    WidgetTester tester,
    String tipo, {
    bool escuro = false,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: escuro ? temaEscuro() : temaClaro(),
      home: Scaffold(body: Center(child: BadgeTipo(tipo))),
    ),
  );

  Container caixa(WidgetTester tester) => tester.widget<Container>(
    find.ancestor(of: find.byType(Text), matching: find.byType(Container)),
  );

  testWidgets('claro: contorno na cor de BadgesTipo.claro, sem preenchimento', (
    tester,
  ) async {
    await montar(tester, 'REM');
    expect(find.text('REM'), findsOneWidget);
    final decoracao = caixa(tester).decoration! as BoxDecoration;
    expect(decoracao.color, isNull, reason: 'tipo é contorno, não preenchido');
    expect(decoracao.border!.top.color, BadgesTipo.claro['REM']);
    expect(decoracao.border!.top.width, 1.5);
    expect(
      tester.widget<Text>(find.text('REM')).style?.color,
      BadgesTipo.claro['REM'],
    );
  });

  testWidgets('escuro: a cor de BadgesTipo.escuro', (tester) async {
    await montar(tester, 'REP', escuro: true);
    final decoracao = caixa(tester).decoration! as BoxDecoration;
    expect(decoracao.border!.top.color, BadgesTipo.escuro['REP']);
    expect(
      tester.widget<Text>(find.text('REP')).style?.color,
      BadgesTipo.escuro['REP'],
    );
  });

  testWidgets('tipo desconhecido não quebra: traço neutro, texto igual', (
    tester,
  ) async {
    await montar(tester, 'XPTO');
    expect(find.text('XPTO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('as duas formas nunca se misturam (card 1.9 §6)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        home: const Scaffold(
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [BadgeStatus('ATIVO'), BadgeTipo('REM')],
            ),
          ),
        ),
      ),
    );

    BoxDecoration decoracaoDe(String texto) =>
        tester
                .widget<Container>(
                  find.ancestor(
                    of: find.text(texto),
                    matching: find.byType(Container),
                  ),
                )
                .decoration!
            as BoxDecoration;

    final status = decoracaoDe('ATIVO');
    final tipo = decoracaoDe('REM');
    expect(status.color, isNotNull, reason: 'status é preenchido');
    expect(status.border, isNull, reason: 'e não tem contorno');
    expect(tipo.color, isNull, reason: 'tipo é contorno');
    expect(tipo.border, isNotNull, reason: 'e não é preenchido');
  });
}
