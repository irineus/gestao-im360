import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'trilha.dart';
import 'trilha_repositorio.dart';

/// Repositório da trilha — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final trilhaRepositorioProvider = Provider<TrilhaRepositorio>(
  (ref) => TrilhaRepositorioSupabase(ref.watch(clienteSupabaseProvider)),
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

/// Versão da trilha em memória: toda leitura a observa e toda escrita a
/// incrementa (mesmo desenho da `VersaoAlunos` do card 4.6).
class VersaoTrilha extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoTrilhaProvider = NotifierProvider<VersaoTrilha, int>(
  VersaoTrilha.new,
);

TrilhaRepositorio _repositorio(Ref ref) {
  ref.watch(versaoTrilhaProvider);
  return ref.watch(trilhaRepositorioProvider);
}

/// A trilha de um aluno. `family` e não lista inteira: a aba é de UM aluno, e
/// carregar a trilha de todos para mostrar a de um seria o mesmo desperdício
/// que a lista de alunos evitou no card 4.6.
final trilhaAlunoProvider = FutureProvider.family<List<ItemTrilha>, String>(
  (ref, alunoId) => _traduzindo(() => _repositorio(ref).trilha(alunoId)),
);
