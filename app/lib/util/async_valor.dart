import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Derivação de um `AsyncValue` que **não perde o valor anterior na recarga**.
///
/// ⚠️ Achado de framework da revisão das telas 08/09 (item A2), medido no
/// Riverpod 3.4.2: quando um provider rebuilda porque uma dependência mudou
/// (`ref.watch` de uma `VersaoX`), o estado é um `AsyncLoading` **com** o valor
/// anterior — é o que permite ao `when(skipLoadingOnReload: true)` manter as
/// linhas na tela. Só que o `whenData`, que toda tela usava para filtrar a
/// lista antes de entregá-la à `TabelaIm360`, trata o `loading` devolvendo um
/// `AsyncLoading` **sem** valor (`async_value.dart`, ramo `loading:` do
/// `whenData`). Resultado: a correção no componente não chegava a nenhuma
/// tela que filtra, e a lista continuava sumindo para o esqueleto a cada
/// escrita.
///
/// O único jeito de construir "carregando com valor" fora do pacote é o
/// `copyWithPrevious`, que o Riverpod marca como interno. O `ignore` fica
/// aqui, num lugar só, com o teste `async_valor_test` medindo o
/// comportamento num provider de verdade — se uma versão do Riverpod mudar
/// isto, é ele que avisa.
extension AsyncValorIm360<T> on AsyncValue<T> {
  /// `whenData` que preserva os três estados **e** a recarga: em `data` mapeia;
  /// em `error` repassa; em `loading` com valor anterior devolve um `loading`
  /// com o valor **mapeado**; em `loading` sem valor, o `loading` puro.
  AsyncValue<R> derivar<R>(R Function(T valor) transformar) {
    if (hasError) return whenData(transformar);
    if (!hasValue) return AsyncLoading<R>(progress: progress);
    final dado = AsyncData<R>(transformar(requireValue));
    if (!isLoading) return dado;
    final carregando = AsyncLoading<R>(progress: progress);
    // ignore: invalid_use_of_internal_member
    return carregando.copyWithPrevious(dado, isRefresh: isRefreshing);
  }
}
