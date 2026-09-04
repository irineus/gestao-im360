import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'pendencias.dart';
import 'pendencias_repositorio.dart';

/// Repositório das pendências — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final pendenciasRepositorioProvider = Provider<PendenciasRepositorio>(
  (ref) => PendenciasRepositorioSupabase(ref.watch(clienteSupabaseProvider)),
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

/// Versão das pendências em memória: resolver ou executar uma virada incrementa,
/// e lista, contador do menu e painel recarregam juntos (mesmo desenho da
/// `VersaoCatalogo` do card 4.4).
class VersaoPendencias extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoPendenciasProvider = NotifierProvider<VersaoPendencias, int>(
  VersaoPendencias.new,
);

void recarregarPendencias(WidgetRef ref) =>
    ref.read(versaoPendenciasProvider.notifier).incrementar();

/// As pendências abertas da unidade.
///
/// Devolve vazio para quem não tem `pendencias.ler` em vez de deixar a RLS o
/// fazer em silêncio, e aqui a razão é mais forte que na lista de alunos do card
/// 5.7: **o shell observa este provider em TODA tela**, inclusive nas cujo
/// conjunto mínimo não inclui `pendencias.ler`. Sem o guarda, cada uma dessas
/// telas dispararia uma consulta que a RLS devolveria vazia — e o contador
/// mostraria "0 pendências ALTA" a quem não pode ler pendência nenhuma, que é
/// número errado com cara de certo. Sem permissão o contador simplesmente não
/// existe, junto com o item de menu que o carregaria.
final pendenciasProvider = FutureProvider<List<Pendencia>>((ref) {
  if (!ref.watch(permissoesProvider).contains('pendencias.ler')) {
    return Future.value(const <Pendencia>[]);
  }
  ref.watch(versaoPendenciasProvider);
  return _traduzindo(ref.watch(pendenciasRepositorioProvider).abertas);
});

/// O contador do menu: só severidade **ALTA** aberta (card 2.6 decisão f).
///
/// Zero enquanto carrega e zero no erro — de propósito. O contador é um aviso de
/// canto de tela, e um "!" ali por falha de rede mandaria a pessoa abrir a
/// central para não achar nada; quem mostra erro de leitura é a tela, que tem
/// onde dizer o que houve e um botão de tentar de novo.
final pendenciasAltasProvider = Provider<int>(
  (ref) => contarAltas(ref.watch(pendenciasProvider).value ?? const []),
);

/// A pendência aberta com este id, ou nula quando já saiu da lista — é o que
/// mantém o painel coerente depois de alguém resolvê-la em outra aba.
final pendenciaProvider = Provider.family<Pendencia?, String>((ref, id) {
  for (final p in ref.watch(pendenciasProvider).value ?? const <Pendencia>[]) {
    if (p.id == id) return p;
  }
  return null;
});

/// Filtros sobrevivem à navegação de ida e volta dentro da sessão — estado no
/// provider da tela, não no widget (design-system §5.3).
class FiltroPendenciasNotifier extends Notifier<FiltroPendencias> {
  @override
  FiltroPendencias build() => const FiltroPendencias();

  void definir(FiltroPendencias filtro) => state = filtro;

  void limpar() => state = FiltroPendencias.semFiltro;
}

final filtroPendenciasProvider =
    NotifierProvider<FiltroPendenciasNotifier, FiltroPendencias>(
      FiltroPendenciasNotifier.new,
    );
