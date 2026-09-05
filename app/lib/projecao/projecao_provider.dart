import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'projecao.dart';
import 'projecao_repositorio.dart';

/// Repositório da projeção — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final projecaoRepositorioProvider = Provider<ProjecaoRepositorio>(
  (ref) => ProjecaoRepositorioSupabase(ref.watch(clienteSupabaseProvider)),
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

/// Versão da projeção em memória: toda leitura a observa e "Tentar de novo" a
/// incrementa (mesmo desenho do card 6.7).
///
/// ⚠️ Não existe escrita que a mova, e isso não é esquecimento: a tela 8 é
/// **só leitura** — `demanda_projetada` só aceita escrita de `fn_contexto_
/// rotina()` (card 8.1). A versão existe para o botão de repetir e para o
/// recarregar manual, e é o que impede a tela de ficar presa ao primeiro erro
/// da sessão.
class VersaoProjecao extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoProjecaoProvider = NotifierProvider<VersaoProjecao, int>(
  VersaoProjecao.new,
);

ProjecaoRepositorio _repositorio(Ref ref) {
  ref.watch(versaoProjecaoProvider);
  return ref.watch(projecaoRepositorioProvider);
}

/// A grade: `v_projecao_material_mes`, no grão do banco. Quem pivota é a tela.
final gradeProjecaoProvider = FutureProvider<List<CelulaProjecao>>(
  (ref) => _traduzindo(_repositorio(ref).grade),
);

/// Há `ROTINA_FALHOU` aberta para a projeção — o que separa os dois vazios do
/// design-system §7.2.
final rotinaProjecaoFalhouProvider = FutureProvider<bool>(
  (ref) => _traduzindo(_repositorio(ref).rotinaFalhou),
);

/// Qual célula o drill-down está mostrando: um material e, quando a pessoa tocou
/// uma célula de mês, aquele mês.
@immutable
class CelulaPedida {
  const CelulaPedida({required this.materialId, this.mes});

  final String materialId;

  /// Nulo = o material inteiro, que é o alvo do cartão do celular.
  final DateTime? mes;

  @override
  bool operator ==(Object other) =>
      other is CelulaPedida &&
      other.materialId == materialId &&
      other.mes == mes;

  @override
  int get hashCode => Object.hash(materialId, mes);
}

/// Os alunos de uma célula, **ao vivo**.
///
/// `family` pela mesma razão da trilha (card 6.6) e do painel de movimentações
/// (6.7): o painel é de uma célula, e carregar o detalhe da grade inteira para
/// mostrar o de uma linha seria o desperdício que o card 4.6 recusou.
final detalheProjecaoProvider =
    FutureProvider.family<List<DetalheProjecao>, CelulaPedida>(
      (ref, celula) => _traduzindo(
        () => _repositorio(ref).detalhe(celula.materialId, mes: celula.mes),
      ),
    );

/// Filtro da grade — estado da tela, sobrevive à navegação de ida e volta
/// dentro da sessão (design-system §5.3).
class FiltroProjecaoNotifier extends Notifier<FiltroProjecao> {
  @override
  FiltroProjecao build() => const FiltroProjecao();

  void definir(FiltroProjecao filtro) => state = filtro;

  void limpar() => state = const FiltroProjecao();
}

final filtroProjecaoProvider =
    NotifierProvider<FiltroProjecaoNotifier, FiltroProjecao>(
      FiltroProjecaoNotifier.new,
    );
