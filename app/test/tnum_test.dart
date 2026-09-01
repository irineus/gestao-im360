import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/theme/tipografia.dart';

/// Card 2.8 §9.1: os estilos numéricos carregam `fontFeature tnum`.
///
/// A coluna de estoque desalinhada é o sintoma que ninguém reporta: a tela não
/// dá erro, o número está certo, e a leitura fica pior sem que ninguém saiba
/// dizer por quê.
void main() {
  test('Tipografia.numero acrescenta tabularFigures', () {
    final estilo = Tipografia.numero(Tipografia.corpoTabela);
    expect(estilo.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  test('Tipografia.numero preserva o resto do estilo', () {
    final base = Tipografia.corpoTabela;
    final estilo = Tipografia.numero(base);
    expect(estilo.fontSize, base.fontSize);
    expect(estilo.fontWeight, base.fontWeight);
    expect(estilo.height, base.height);
    expect(estilo.fontFamily, base.fontFamily);
  });

  test('vale para qualquer estilo da escala, não só o da tabela', () {
    for (final base in [
      Tipografia.titulo,
      Tipografia.subtitulo,
      Tipografia.corpo,
      Tipografia.corpoTabela,
      Tipografia.apoio,
      Tipografia.badge,
    ]) {
      expect(
        Tipografia.numero(base).fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    }
  });

  test('todo estilo nomeado usa a Inter empacotada', () {
    // Componente não escolhe família nem tamanho avulso (design-system §11.5);
    // e sem a família declarada o `tnum` não teria onde valer.
    for (final estilo in [
      Tipografia.titulo,
      Tipografia.subtitulo,
      Tipografia.corpo,
      Tipografia.corpoTabela,
      Tipografia.rotulo,
      Tipografia.cabecalhoTabela,
      Tipografia.apoio,
      Tipografia.badge,
    ]) {
      expect(estilo.fontFamily, 'Inter');
      expect(estilo.fontSize, isNotNull);
      expect(estilo.height, isNotNull);
    }
  });

  test('o corpo do formulário tem 16 px — evita o zoom automático do iOS', () {
    // card 1.9 §4, repetido em wireframes §4 para a tela de login.
    expect(Tipografia.corpo.fontSize, 16);
  });

  testWidgets('um Text com estilo numérico chega ao render com o tnum', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Text('1.234', style: Tipografia.numero(Tipografia.corpoTabela)),
      ),
    );
    final texto = tester.widget<Text>(find.byType(Text));
    expect(
      texto.style!.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });
}
