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

/// Uma contagem lida de um mapa que talvez ainda não tenha chegado (card
/// 9.2,62): `0` só quando o mapa CHEGOU e não tem a chave.
///
/// ⚠️ A forma antiga, `mapa.value?[id] ?? 0`, dizia "0 apostilas" enquanto a
/// leitura carregava e **para sempre** quando ela falhava — a família B1 do
/// card 5.11 ("`AsyncValue` que decide texto precisa dos três estados").
/// [carregando] e [naoLido] são o que a célula mostra nos outros dois estados.
String contagemDe(
  AsyncValue<Map<String, int>> mapa,
  String? chave,
  String Function(int n) formatar, {
  String carregando = '…',
  String naoLido = textoNaoLido,
}) {
  if (mapa.hasError) return naoLido;
  if (!mapa.hasValue) return carregando;
  return formatar(mapa.requireValue[chave] ?? 0);
}

/// O que uma célula diz quando o número dela não pôde ser lido.
const textoNaoLido = 'não lido';
