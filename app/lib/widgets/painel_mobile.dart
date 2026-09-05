import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// O painel de detalhe do celular: o mesmo conteúdo do painel do desktop, em
/// tela cheia, **sempre relido da lista** pelo id.
///
/// Ler da lista a cada build, e não guardar o objeto, é o que faz o cabeçalho
/// mostrar o saldo de DEPOIS do ajuste (a armadilha do `AsyncValue`
/// reaproveitado, card 4.4). Materiais e Compras tinham cada um a sua cópia
/// deste mesmo desenho, com o mesmo defeito: quando o item sumia da lista — um
/// material excluído —, devolviam `SizedBox.shrink()` e a pessoa ficava com um
/// diálogo de tela cheia **vazio** (itens A6 e F2).
///
/// Aqui o desaparecimento fecha o painel, uma vez, no frame seguinte.
class PainelMobileDe<T> extends ConsumerStatefulWidget {
  const PainelMobileDe({
    super.key,
    required this.itens,
    required this.id,
    required this.idDe,
    required this.construtor,
  });

  /// Lê a lista de onde o item é relido — a mesma que a tela observa. É um
  /// callback, e não um provider tipado, porque as telas expõem `FutureProvider`
  /// de tipos diferentes e o painel só precisa do `AsyncValue`.
  final AsyncValue<List<T>> Function(WidgetRef ref) itens;

  final String id;
  final String Function(T item) idDe;
  final Widget Function(BuildContext context, T item) construtor;

  @override
  ConsumerState<PainelMobileDe<T>> createState() => _PainelMobileDeState<T>();
}

class _PainelMobileDeState<T> extends ConsumerState<PainelMobileDe<T>> {
  bool _fechando = false;

  @override
  Widget build(BuildContext context) {
    final async = widget.itens(ref);
    T? achado;
    for (final item in async.value ?? const []) {
      if (widget.idDe(item) == widget.id) achado = item;
    }

    if (achado == null) {
      // Só depois de a lista ter chegado: durante o carregamento o item ainda
      // não sumiu, ele apenas não chegou.
      if (async.hasValue && !_fechando) {
        _fechando = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const SizedBox.shrink();
    }
    return widget.construtor(context, achado);
  }
}
