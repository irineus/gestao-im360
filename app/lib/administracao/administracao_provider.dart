import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'administracao.dart';
import 'administracao_repositorio.dart';

/// Repositório da administração — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final administracaoRepositorioProvider = Provider<AdministracaoRepositorio>(
  (ref) => AdministracaoRepositorioSupabase(
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

/// Versão da administração em memória: toda leitura a observa e toda escrita
/// a incrementa, recarregando a tela depois de salvar (mesmo desenho da
/// `VersaoCatalogo` do card 4.4).
class VersaoAdministracao extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoAdministracaoProvider = NotifierProvider<VersaoAdministracao, int>(
  VersaoAdministracao.new,
);

AdministracaoRepositorio _repositorio(Ref ref) {
  ref.watch(versaoAdministracaoProvider);
  return ref.watch(administracaoRepositorioProvider);
}

final usuariosAdminProvider = FutureProvider<List<UsuarioAdmin>>(
  (ref) => _traduzindo(_repositorio(ref).usuarios),
);

final perfisProvider = FutureProvider<List<Perfil>>(
  (ref) => _traduzindo(_repositorio(ref).perfis),
);

/// O catálogo de permissões. O nome evita colisão com `permissoesProvider`,
/// que é a lista do PRÓPRIO usuário (sessão).
final catalogoPermissoesProvider = FutureProvider<List<Permissao>>(
  (ref) => _traduzindo(_repositorio(ref).permissoes),
);

final matrizProvider = FutureProvider<Map<String, Set<String>>>(
  (ref) => _traduzindo(_repositorio(ref).matriz),
);

final parametrosProvider = FutureProvider<List<Parametro>>(
  (ref) => _traduzindo(_repositorio(ref).parametros),
);

final historicoMatrizProvider = FutureProvider<List<LinhaHistoricoMatriz>>(
  (ref) => _traduzindo(_repositorio(ref).historico),
);

/// Filtros sobrevivem à navegação de ida e volta dentro da sessão — estado no
/// provider da aba, não no widget (design-system §5.3).
class FiltroUsuariosNotifier extends Notifier<FiltroUsuarios> {
  @override
  FiltroUsuarios build() => const FiltroUsuarios();

  void definir(FiltroUsuarios filtro) => state = filtro;

  void limpar() => state = FiltroUsuarios.semFiltro;
}

final filtroUsuariosProvider =
    NotifierProvider<FiltroUsuariosNotifier, FiltroUsuarios>(
      FiltroUsuariosNotifier.new,
    );

/// O perfil aberto na aba da matriz. Nulo = o primeiro ativo da lista.
class PerfilSelecionadoNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? perfilId) => state = perfilId;
}

final perfilSelecionadoProvider =
    NotifierProvider<PerfilSelecionadoNotifier, String?>(
      PerfilSelecionadoNotifier.new,
    );
