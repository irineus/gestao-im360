import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'infraestrutura.dart';
import 'infraestrutura_repositorio.dart';

/// Repositório da infraestrutura — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final infraestruturaRepositorioProvider = Provider<InfraestruturaRepositorio>(
  (ref) => InfraestruturaRepositorioSupabase(
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

/// Versão da infraestrutura em memória: toda leitura a observa e toda escrita
/// a incrementa, recarregando a tela inteira depois de salvar (mesmo desenho
/// da `VersaoCatalogo` do card 4.4).
class VersaoInfraestrutura extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoInfraestruturaProvider =
    NotifierProvider<VersaoInfraestrutura, int>(VersaoInfraestrutura.new);

InfraestruturaRepositorio _repositorio(Ref ref) {
  ref.watch(versaoInfraestruturaProvider);
  return ref.watch(infraestruturaRepositorioProvider);
}

final salasProvider = FutureProvider<List<Sala>>(
  (ref) => _traduzindo(_repositorio(ref).salas),
);

final pcsProvider = FutureProvider<List<Pc>>(
  (ref) => _traduzindo(_repositorio(ref).pcs),
);

final manutencoesProvider = FutureProvider<List<PcManutencao>>(
  (ref) => _traduzindo(_repositorio(ref).manutencoes),
);

final professoresProvider = FutureProvider<List<Professor>>(
  (ref) => _traduzindo(_repositorio(ref).professores),
);

/// Filtros sobrevivem à navegação de ida e volta dentro da sessão — estado no
/// provider da aba, não no widget (design-system §5.3).
class FiltroSalasNotifier extends Notifier<FiltroSalas> {
  @override
  FiltroSalas build() => const FiltroSalas();

  void definir(FiltroSalas filtro) => state = filtro;

  void limpar() => state = FiltroSalas.semFiltro;
}

final filtroSalasProvider = NotifierProvider<FiltroSalasNotifier, FiltroSalas>(
  FiltroSalasNotifier.new,
);

class FiltroProfessoresNotifier extends Notifier<FiltroProfessores> {
  @override
  FiltroProfessores build() => const FiltroProfessores();

  void definir(FiltroProfessores filtro) => state = filtro;

  void limpar() => state = FiltroProfessores.semFiltro;
}

final filtroProfessoresProvider =
    NotifierProvider<FiltroProfessoresNotifier, FiltroProfessores>(
      FiltroProfessoresNotifier.new,
    );
