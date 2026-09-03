import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'alunos.dart';
import 'alunos_repositorio.dart';

/// Repositório dos alunos — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final alunosRepositorioProvider = Provider<AlunosRepositorio>(
  (ref) => AlunosRepositorioSupabase(
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

/// Versão dos alunos em memória: toda leitura a observa e toda escrita a
/// incrementa, recarregando lista, ficha e histórico depois de salvar (mesmo
/// desenho da `VersaoCatalogo` do card 4.4).
class VersaoAlunos extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoAlunosProvider = NotifierProvider<VersaoAlunos, int>(
  VersaoAlunos.new,
);

AlunosRepositorio _repositorio(Ref ref) {
  ref.watch(versaoAlunosProvider);
  return ref.watch(alunosRepositorioProvider);
}

final alunosProvider = FutureProvider<List<Aluno>>(
  (ref) => _traduzindo(_repositorio(ref).alunos),
);

/// A ficha lê o aluno **sozinho**, e não da lista: deep-link abre a ficha
/// sem a lista ter carregado, e a lista pode estar filtrada.
final alunoProvider = FutureProvider.family<Aluno?, String>(
  (ref, id) => _traduzindo(() => _repositorio(ref).aluno(id)),
);

final historicoAlunoProvider =
    FutureProvider.family<List<TransicaoStatus>, String>(
      (ref, id) => _traduzindo(() => _repositorio(ref).historico(id)),
    );

/// Filtros sobrevivem à navegação de ida e volta dentro da sessão — estado no
/// provider da tela, não no widget (design-system §5.3).
class FiltroAlunosNotifier extends Notifier<FiltroAlunos> {
  @override
  FiltroAlunos build() => const FiltroAlunos();

  void definir(FiltroAlunos filtro) => state = filtro;

  void limpar() => state = FiltroAlunos.semFiltro;
}

final filtroAlunosProvider =
    NotifierProvider<FiltroAlunosNotifier, FiltroAlunos>(
      FiltroAlunosNotifier.new,
    );
