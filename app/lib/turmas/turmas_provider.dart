import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'turmas.dart';
import 'turmas_repositorio.dart';

/// Repositório das turmas — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final turmasRepositorioProvider = Provider<TurmasRepositorio>(
  (ref) => TurmasRepositorioSupabase(
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

/// Versão das turmas em memória: toda leitura a observa e toda escrita a
/// incrementa, recarregando a tela depois de salvar (mesmo desenho da
/// `VersaoCatalogo` do card 4.4).
class VersaoTurmas extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoTurmasProvider = NotifierProvider<VersaoTurmas, int>(
  VersaoTurmas.new,
);

TurmasRepositorio _repositorio(Ref ref) {
  ref.watch(versaoTurmasProvider);
  return ref.watch(turmasRepositorioProvider);
}

/// A semana visível, sempre pela segunda-feira. Estado no provider e não no
/// widget para a semana sobreviver a abrir e fechar o painel de um bloco
/// (design-system §5.3) — voltar sempre para a semana corrente depois de editar
/// um bloco de outra semana esconderia o resultado da própria edição.
class SemanaNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => segundaDe(DateTime.now());

  void mover(int semanas) =>
      state = DateTime(state.year, state.month, state.day + 7 * semanas);

  void hoje() => state = segundaDe(DateTime.now());
}

final semanaProvider = NotifierProvider<SemanaNotifier, DateTime>(
  SemanaNotifier.new,
);

/// A grade da semana visível. Depende de [semanaProvider], então mudar de
/// semana recarrega sozinho.
final gradeProvider = FutureProvider<List<CelulaGrade>>((ref) {
  final semana = ref.watch(semanaProvider);
  return _traduzindo(() => _repositorio(ref).grade(semana));
});

final blocosInativosProvider = FutureProvider<List<BlocoHorario>>(
  (ref) => _traduzindo(_repositorio(ref).blocosInativos),
);

class FiltroGradeNotifier extends Notifier<FiltroGrade> {
  @override
  FiltroGrade build() => const FiltroGrade();

  void definir(FiltroGrade filtro) => state = filtro;

  void limpar() => state = FiltroGrade.semFiltro;
}

final filtroGradeProvider = NotifierProvider<FiltroGradeNotifier, FiltroGrade>(
  FiltroGradeNotifier.new,
);
