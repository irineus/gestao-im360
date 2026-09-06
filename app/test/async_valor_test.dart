import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/util/async_valor.dart';

/// `derivar` (item A2 da revisão das telas 08/09): a derivação que as telas
/// fazem antes de entregar a lista à `TabelaIm360` NÃO pode perder o valor
/// anterior na recarga — é o que o `whenData` do Riverpod 3.4.2 faz, e é por
/// isso que este arquivo mede o comportamento **num provider de verdade**, e
/// não sobre um `AsyncValue` montado à mão.
void main() {
  final versao = NotifierProvider<_Versao, int>(_Versao.new);
  final lento = FutureProvider<List<int>>((ref) async {
    ref.watch(versao);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return [1, 2, 3];
  });

  test(
    'na recarga o valor derivado continua lá, e continua "carregando"',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(lento, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(container.read(lento).hasValue, isTrue);

      container.read(versao.notifier).incrementar();
      final recarregando = container.read(lento);
      expect(recarregando.isReloading, isTrue, reason: 'premissa do teste');

      // O `whenData` do framework perde o valor — é o achado.
      expect(recarregando.whenData((l) => l.length).hasValue, isFalse);

      // `derivar` não perde: mapeia e continua dizendo que está carregando.
      final derivado = recarregando.derivar((l) => l.length);
      expect(derivado.hasValue, isTrue);
      expect(derivado.value, 3);
      expect(derivado.isLoading, isTrue);
      expect(
        derivado.when(
          skipLoadingOnReload: true,
          data: (n) => 'dados $n',
          error: (_, _) => 'erro',
          loading: () => 'carregando',
        ),
        'dados 3',
      );
    },
  );

  test('nos outros estados é o próprio whenData', () {
    expect(const AsyncData([1, 2]).derivar((l) => l.length).value, 2);
    expect(
      const AsyncLoading<List<int>>().derivar((l) => l.length).isLoading,
      isTrue,
    );
    expect(
      AsyncValue<List<int>>.error(
        'x',
        StackTrace.empty,
      ).derivar((l) => l.length).hasError,
      isTrue,
    );
  });
}

class _Versao extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}
