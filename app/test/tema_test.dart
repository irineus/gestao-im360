import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/theme/cores.dart';
import 'package:gestao_im360/theme/tema.dart';

/// O `ColorScheme` é montado à mão (card 2.7): papel que ninguém declara **não
/// fica vazio** — o Flutter o preenche com outro, e o resultado é uma
/// superfície tonal em que fundo e texto acabam na mesma cor, ou na cor errada.
///
/// Nenhum teste desenha cor e nenhum `analyze` lê contraste: são estas
/// asserções que separam "declarado" de "herdado por acidente". A do
/// `errorContainer` nasceu no card 5.11, no escuro; a do `tertiaryContainer`,
/// na revisão das telas 06/07 (item A1), nos dois temas.
void main() {
  group('os pares tonais existem e são os tokens', () {
    final esquemas = {
      'claro': temaClaro().colorScheme,
      'escuro': temaEscuro().colorScheme,
    };

    esquemas.forEach((nome, esquema) {
      test('$nome: container de erro é distinto do `error`', () {
        expect(esquema.errorContainer, isNot(esquema.error));
        expect(esquema.onErrorContainer, isNot(esquema.errorContainer));
      });

      test('$nome: container de ATENÇÃO é distinto do `tertiary`', () {
        // Sem `tertiaryContainer` declarado o Flutter devolve `tertiary`, e
        // sem `tertiary` devolve `secondary` (grafite): a linha "abaixo do
        // mínimo" de Materiais e a "sugerido > 0" de Compras saíam com fundo
        // grafite escuro e texto grafite escuro.
        expect(esquema.tertiaryContainer, isNot(esquema.tertiary));
        expect(esquema.tertiaryContainer, isNot(esquema.secondary));
        expect(esquema.onTertiaryContainer, isNot(esquema.tertiaryContainer));
      });
    });

    test('claro: os pares são os tokens do design-system §2.1', () {
      final claro = esquemas['claro']!;
      expect(claro.tertiary, Cores.atencao);
      expect(claro.tertiaryContainer, Cores.atencaoFundo);
      expect(claro.onTertiaryContainer, Cores.atencao);
      expect(claro.errorContainer, Cores.erroFundo);
      expect(claro.onErrorContainer, Cores.erro);
    });

    test('escuro: os pares são os tokens do §2.3', () {
      final escuro = esquemas['escuro']!;
      expect(escuro.tertiary, Cores.atencaoEscuro);
      expect(escuro.tertiaryContainer, Cores.atencaoFundoEscuro);
      expect(escuro.onTertiaryContainer, Cores.atencaoEscuro);
      expect(escuro.errorContainer, Cores.erroFundoEscuro);
      expect(escuro.onErrorContainer, Cores.erroEscuro);
    });

    test(
      'o fundo tonal de atenção do escuro é o do badge STANDBY, cujo contraste '
      'já foi verificado',
      () {
        // Não é coincidência nem gosto: reaproveitar o par verificado é o que
        // dispensa recalcular contraste a cada token novo (o mesmo argumento do
        // `erroFundoEscuro`, card 5.11).
        expect(Cores.atencaoFundoEscuro, BadgesStatus.escuro['STANDBY']!.fundo);
        expect(Cores.atencaoEscuro, BadgesStatus.escuro['STANDBY']!.texto);
      },
    );
  });
}
