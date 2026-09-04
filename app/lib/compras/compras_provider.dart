import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../estoque/estoque_provider.dart';
import '../sessao/sessao_provider.dart';
import 'compras.dart';
import 'compras_repositorio.dart';

/// Repositório das compras — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final comprasRepositorioProvider = Provider<ComprasRepositorio>(
  (ref) => ComprasRepositorioSupabase(
    ref.watch(clienteSupabaseProvider),
    unidadeId: ref.watch(unidadeAtualProvider) ?? '',
  ),
);

/// Traduz **uma vez**, no provider — cada rebuild não reenvia o mesmo erro ao
/// Sentry (card 3.12).
Future<T> _traduzindo<T>(Future<T> Function() acao) async {
  try {
    return await acao();
  } catch (erro) {
    throw traduzirErro(erro);
  }
}

/// Versão das compras em memória: toda leitura a observa e toda escrita a
/// incrementa (mesmo desenho da `VersaoEstoque` do card 6.7).
class VersaoCompras extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoComprasProvider = NotifierProvider<VersaoCompras, int>(
  VersaoCompras.new,
);

ComprasRepositorio _repositorio(Ref ref) {
  ref.watch(versaoComprasProvider);
  return ref.watch(comprasRepositorioProvider);
}

/// ⚠️ **Recebimento move as DUAS versões.** `fn_pedido_receber` grava ENTRADA em
/// `movimento_estoque` e sobe `qtd_recebida` na mesma transação: sem invalidar o
/// estoque junto, a tela de Materiais continuaria mostrando o saldo de antes da
/// chegada até alguém recarregar a página — e a aba Trilha ofereceria "sem
/// estoque" para o exemplar que já está na prateleira. É a mesma lição do card
/// 6.7, em que o cadastro do material tinha de mover a versão do estoque.
void invalidarComprasEEstoque(WidgetRef ref) {
  ref.read(versaoComprasProvider.notifier).incrementar();
  ref.read(versaoEstoqueProvider.notifier).incrementar();
}

/// A aba "Pedido sugerido": `v_pedido_sugerido` (card 6.4).
///
/// Observa **as duas** versões: o pedido sugerido é a única leitura do sistema
/// que soma estoque e compra na mesma linha, e um ajuste de estoque muda o
/// `saldo` dela tanto quanto o envio de um pedido muda a parcela pendente.
final sugeridoProvider = FutureProvider<List<LinhaSugerida>>((ref) {
  ref.watch(versaoEstoqueProvider);
  return _traduzindo(_repositorio(ref).sugerido);
});

/// A aba "Pedidos": `v_pedido_compra` (card 6.8).
final pedidosProvider = FutureProvider<List<PedidoCompra>>(
  (ref) => _traduzindo(_repositorio(ref).pedidos),
);

/// Os itens de UM pedido. `family` pela mesma razão da trilha (card 6.6) e do
/// painel de movimentações (6.7): o painel é de um pedido, e carregar os itens
/// de todos para mostrar os de um seria o desperdício que o card 4.6 recusou.
final itensDoPedidoProvider = FutureProvider.family<List<ItemPedido>, String>(
  (ref, pedidoId) => _traduzindo(() => _repositorio(ref).itens(pedidoId)),
);

/// Filtro da aba "Pedido sugerido" — estado da tela, sobrevive à navegação de
/// ida e volta dentro da sessão (design-system §5.3).
class FiltroSugeridoNotifier extends Notifier<FiltroSugerido> {
  @override
  FiltroSugerido build() => const FiltroSugerido();

  void definir(FiltroSugerido filtro) => state = filtro;

  /// "Limpar filtros" devolve o padrão — que inclui `soSugeridos` **ligado**:
  /// o padrão da aba é "o que comprar agora", e limpar não é "mostrar tudo".
  void limpar() => state = const FiltroSugerido();
}

final filtroSugeridoProvider =
    NotifierProvider<FiltroSugeridoNotifier, FiltroSugerido>(
      FiltroSugeridoNotifier.new,
    );

class FiltroPedidosNotifier extends Notifier<FiltroPedidos> {
  @override
  FiltroPedidos build() => const FiltroPedidos();

  void definir(FiltroPedidos filtro) => state = filtro;

  void limpar() => state = const FiltroPedidos();
}

final filtroPedidosProvider =
    NotifierProvider<FiltroPedidosNotifier, FiltroPedidos>(
      FiltroPedidosNotifier.new,
    );
