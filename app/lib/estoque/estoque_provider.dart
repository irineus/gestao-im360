import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'estoque.dart';
import 'estoque_repositorio.dart';

/// Repositório do estoque — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final estoqueRepositorioProvider = Provider<EstoqueRepositorio>(
  (ref) => EstoqueRepositorioSupabase(ref.watch(clienteSupabaseProvider)),
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

/// Versão do estoque em memória: toda leitura a observa e toda escrita a
/// incrementa (mesmo desenho da `VersaoCatalogo` do card 4.4).
class VersaoEstoque extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoEstoqueProvider = NotifierProvider<VersaoEstoque, int>(
  VersaoEstoque.new,
);

EstoqueRepositorio _repositorio(Ref ref) {
  ref.watch(versaoEstoqueProvider);
  return ref.watch(estoqueRepositorioProvider);
}

/// A lista da aba Materiais (card 6.7): `v_estoque_atual`.
final estoqueProvider = FutureProvider<List<MaterialEstoque>>(
  (ref) => _traduzindo(_repositorio(ref).estoque),
);

/// O painel de movimentações de UM material. `family` pela mesma razão da
/// trilha (card 6.6): o painel é de um material, e carregar a história de todos
/// para mostrar a de um seria o desperdício que o card 4.6 já recusou.
final movimentosDoMaterialProvider =
    FutureProvider.family<List<MovimentoMaterial>, String>(
      (ref, materialId) =>
          _traduzindo(() => _repositorio(ref).movimentos(materialId)),
    );

/// Filtro do painel — estado da tela, sobrevive à navegação de ida e volta
/// dentro da sessão (design-system §5.3).
class FiltroMovimentoNotifier extends Notifier<FiltroMovimento> {
  @override
  FiltroMovimento build() => const FiltroMovimento();

  void definir(FiltroMovimento filtro) => state = filtro;

  void limpar() => state = const FiltroMovimento();
}

final filtroMovimentoProvider =
    NotifierProvider<FiltroMovimentoNotifier, FiltroMovimento>(
      FiltroMovimentoNotifier.new,
    );
