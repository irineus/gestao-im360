import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/theme/cores.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/badge_status.dart';

/// `BadgeStatus` (design-system §5.1): o rótulo é sempre texto, e o par
/// texto/fundo é o de `BadgesStatus` do tema em uso — os contrastes AA do
/// card 2.7 valem porque o widget usa exatamente esses pares.
void main() {
  Future<void> montar(
    WidgetTester tester,
    String status, {
    bool escuro = false,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: escuro ? temaEscuro() : temaClaro(),
      home: Scaffold(body: Center(child: BadgeStatus(status))),
    ),
  );

  Container caixa(WidgetTester tester) => tester.widget<Container>(
    find.ancestor(of: find.byType(Text), matching: find.byType(Container)),
  );

  testWidgets('claro: o par de BadgesStatus.claro', (tester) async {
    await montar(tester, 'ATIVO');
    expect(find.text('ATIVO'), findsOneWidget);
    final decoracao = caixa(tester).decoration! as BoxDecoration;
    expect(decoracao.color, BadgesStatus.claro['ATIVO']!.fundo);
    expect(
      tester.widget<Text>(find.text('ATIVO')).style?.color,
      BadgesStatus.claro['ATIVO']!.texto,
    );
  });

  testWidgets('escuro: o par de BadgesStatus.escuro — a lacuna que o card 2.7 '
      'fechou', (tester) async {
    await montar(tester, 'FORMADO', escuro: true);
    final decoracao = caixa(tester).decoration! as BoxDecoration;
    expect(decoracao.color, BadgesStatus.escuro['FORMADO']!.fundo);
    expect(
      tester.widget<Text>(find.text('FORMADO')).style?.color,
      BadgesStatus.escuro['FORMADO']!.texto,
    );
  });

  testWidgets('status desconhecido não quebra: par neutro, texto igual', (
    tester,
  ) async {
    await montar(tester, 'XPTO');
    expect(find.text('XPTO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
