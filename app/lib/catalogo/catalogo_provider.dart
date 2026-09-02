import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'catalogo.dart';
import 'catalogo_repositorio.dart';

/// Repositório do catálogo — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final catalogoRepositorioProvider = Provider<CatalogoRepositorio>(
  (ref) => CatalogoRepositorioSupabase(
    ref.watch(clienteSupabaseProvider),
    unidadeId: ref.watch(unidadeAtualProvider) ?? '',
  ),
);

/// Traduz **uma vez**, no provider. Se a tabela traduzisse no `build`, cada
/// rebuild chamaria o gancho do Sentry de novo com o mesmo erro (card 3.12).
Future<T> _traduzindo<T>(Future<T> Function() acao) async {
  try {
    return await acao();
  } catch (erro) {
    throw traduzirErro(erro);
  }
}

/// Versão do catálogo em memória. Toda leitura a observa e toda escrita a
/// incrementa: é o que recarrega a tela inteira depois de salvar, sem que cada
/// formulário precise saber quais das nove consultas dependem do que gravou.
class VersaoCatalogo extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoCatalogoProvider = NotifierProvider<VersaoCatalogo, int>(
  VersaoCatalogo.new,
);

CatalogoRepositorio _repositorio(Ref ref) {
  ref.watch(versaoCatalogoProvider);
  return ref.watch(catalogoRepositorioProvider);
}

final metodosProvider = FutureProvider<List<Metodo>>(
  (ref) => _traduzindo(_repositorio(ref).metodos),
);

final materiaisProvider = FutureProvider<List<MaterialDidatico>>(
  (ref) => _traduzindo(_repositorio(ref).materiais),
);

final cursosProvider = FutureProvider<List<Curso>>(
  (ref) => _traduzindo(_repositorio(ref).cursos),
);

final apostilasPorCursoProvider = FutureProvider<Map<String, int>>(
  (ref) => _traduzindo(_repositorio(ref).apostilasPorCurso),
);

final sequenciaDoCursoProvider =
    FutureProvider.family<List<LinhaOrdenada>, String>(
      (ref, cursoId) =>
          _traduzindo(() => _repositorio(ref).sequenciaDoCurso(cursoId)),
    );

final modulosProvider = FutureProvider.family<List<Modulo>, String>(
  (ref, cursoId) => _traduzindo(() => _repositorio(ref).modulos(cursoId)),
);

final combosProvider = FutureProvider<List<Combo>>(
  (ref) => _traduzindo(_repositorio(ref).combos),
);

final cursosPorComboProvider = FutureProvider<Map<String, int>>(
  (ref) => _traduzindo(_repositorio(ref).cursosPorCombo),
);

final cursosDoComboProvider =
    FutureProvider.family<List<LinhaOrdenada>, String>(
      (ref, comboId) =>
          _traduzindo(() => _repositorio(ref).cursosDoCombo(comboId)),
    );

/// Filtros sobrevivem à navegação de ida e volta dentro da sessão — estado no
/// provider da tela, não no widget (design-system §5.3).
class FiltroCatalogoNotifier extends Notifier<FiltroCatalogo> {
  @override
  FiltroCatalogo build() => const FiltroCatalogo();

  void definir(FiltroCatalogo filtro) => state = filtro;

  void limpar() => state = FiltroCatalogo.semFiltro;
}

final filtroMateriaisProvider =
    NotifierProvider<FiltroCatalogoNotifier, FiltroCatalogo>(
      FiltroCatalogoNotifier.new,
    );

final filtroCursosProvider =
    NotifierProvider<FiltroCatalogoNotifier, FiltroCatalogo>(
      FiltroCatalogoNotifier.new,
    );

final filtroCombosProvider =
    NotifierProvider<FiltroCatalogoNotifier, FiltroCatalogo>(
      FiltroCatalogoNotifier.new,
    );
