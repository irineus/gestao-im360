import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'modular.dart';
import 'modular_repositorio.dart';

/// Repositório das turmas Modular — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final modularRepositorioProvider = Provider<ModularRepositorio>(
  (ref) => ModularRepositorioSupabase(
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

/// Versão das turmas Modular em memória: toda leitura a observa e toda escrita a
/// incrementa (mesmo desenho da `VersaoTurmas` do card 5.6).
class VersaoModular extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoModularProvider = NotifierProvider<VersaoModular, int>(
  VersaoModular.new,
);

/// Recarrega tudo o que depende de turmas Modular depois de uma escrita.
void recarregarModular(WidgetRef ref) =>
    ref.read(versaoModularProvider.notifier).incrementar();

ModularRepositorio _repositorio(Ref ref) {
  ref.watch(versaoModularProvider);
  return ref.watch(modularRepositorioProvider);
}

final turmasModularProvider = FutureProvider<List<TurmaModular>>(
  (ref) => _traduzindo(_repositorio(ref).turmas),
);

final turmasModularInativasProvider = FutureProvider<List<TurmaModular>>(
  (ref) => _traduzindo(_repositorio(ref).turmasInativas),
);

final cronogramaModularProvider = FutureProvider<List<ModuloDaTurma>>(
  (ref) => _traduzindo(_repositorio(ref).cronograma),
);

/// `turma_id` → cronograma dela, na ordem do catálogo.
final cronogramaPorTurmaProvider = Provider<Map<String, List<ModuloDaTurma>>>(
  (ref) => agruparCronograma(
    ref.watch(cronogramaModularProvider).value ?? const <ModuloDaTurma>[],
  ),
);

/// Os alunos das turmas Modular.
///
/// ⚠️ Devolve vazio para quem **não tem `alunos.ler`**, em vez de deixar a RLS
/// fazê-lo em silêncio. O conjunto da rota da tela 5 é `turmas.ler` +
/// `salas.ler` + `materiais.ler` (permissoes-matriz §6, linha 5) e não inclui
/// `alunos.ler` — então um perfil sem ela chega até aqui, e uma lista vazia
/// vinda da RLS faria toda turma parecer **sem aluno nenhum**, com a lotação
/// dizendo `8/15` ao lado. Quem mostra o diagnóstico é a tela; este provider não
/// finge que consultou. É a mesma decisão do `turmasProvider` do card 5.7.
final alunosModularProvider = FutureProvider<List<AlunoDaTurmaModular>>((ref) {
  if (!ref.watch(permissoesProvider).contains('alunos.ler')) {
    return Future.value(const <AlunoDaTurmaModular>[]);
  }
  return _traduzindo(_repositorio(ref).alunos);
});

/// `turma_id` → alunos dela, ativos primeiro.
final alunosPorTurmaProvider = Provider<Map<String, List<AlunoDaTurmaModular>>>(
  (ref) => agruparPorTurma(
    ref.watch(alunosModularProvider).value ?? const <AlunoDaTurmaModular>[],
  ),
);

class FiltroTurmasModularNotifier extends Notifier<FiltroTurmasModular> {
  @override
  FiltroTurmasModular build() => const FiltroTurmasModular();

  void definir(FiltroTurmasModular filtro) => state = filtro;

  void limpar() => state = FiltroTurmasModular.semFiltro;
}

/// Filtros sobrevivem à navegação de ida e volta dentro da sessão — estado no
/// provider da tela, não no widget (design-system §5.3).
final filtroTurmasModularProvider =
    NotifierProvider<FiltroTurmasModularNotifier, FiltroTurmasModular>(
      FiltroTurmasModularNotifier.new,
    );

/// A turma aberta no acordeão. **Uma por vez**: o cartão expandido carrega
/// cronograma, alunos e três ações, e dois abertos no celular empurram tudo o
/// mais para fora da tela (wireframe §8: "cartões colapsados por turma").
class TurmaAbertaNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void alternar(String turmaId) => state = state == turmaId ? null : turmaId;

  void abrir(String turmaId) => state = turmaId;
}

final turmaAbertaProvider = NotifierProvider<TurmaAbertaNotifier, String?>(
  TurmaAbertaNotifier.new,
);
