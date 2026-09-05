import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/util/datas.dart';

/// `formatarPeriodo` (item B3 da revisão das telas 06/07).
///
/// ⚠️ Vermelho antes da correção — que era `formatarDataCurta` nas duas
/// pontas: o cronograma de "Eletricista 2025.2" mostrava `09/11–27/07` para
/// 09/11/2025 → 27/07/2026, um período que **se lê ao contrário**.
void main() {
  final hoje = DateTime(2026, 9, 5);

  group('formatarPeriodo', () {
    test('dentro do ano corrente, sem ano', () {
      expect(
        formatarPeriodo(DateTime(2026, 8, 11), DateTime(2026, 10, 10), hoje),
        '11/08–10/10',
      );
    });

    test('atravessando o ano, COM ano nas duas pontas', () {
      expect(
        formatarPeriodo(DateTime(2025, 11, 9), DateTime(2026, 7, 27), hoje),
        '09/11/2025–27/07/2026',
      );
    });

    test('inteiramente em outro ano, também com ano', () {
      expect(
        formatarPeriodo(DateTime(2025, 3, 1), DateTime(2025, 6, 30), hoje),
        '01/03/2025–30/06/2025',
      );
    });

    test('só uma das pontas', () {
      expect(formatarPeriodo(DateTime(2026, 8, 11), null, hoje), 'desde 11/08');
      expect(formatarPeriodo(null, DateTime(2026, 10, 10), hoje), 'até 10/10');
    });

    test('sem nenhuma', () {
      expect(formatarPeriodo(null, null, hoje), 'sem datas');
    });
  });
}
