import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../erros/erro_app.dart';
import 'sessao.dart';
import 'sessao_repositorio.dart';

final clienteSupabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final sessaoRepositorioProvider = Provider<SessaoRepositorio>(
  (ref) => SessaoRepositorioSupabase(ref.watch(clienteSupabaseProvider)),
);

/// O fluxo de eventos do Auth. Provider próprio para o teste injetar os
/// eventos (card 9.2,63) — sem Supabase inicializado, nenhum fluxo.
final fluxoAuthProvider = Provider<Stream<AuthState>?>((ref) {
  try {
    return ref.read(clienteSupabaseProvider).auth.onAuthStateChange;
  } catch (_) {
    // Sem Supabase inicializado (teste, app não configurado): sem fluxo.
    return null;
  }
});

/// Os eventos do Auth que MUDAM quem está logado ou o que ele é. Os outros
/// (`tokenRefreshed`, `mfaChallengeVerified`) renovam credencial e não
/// mudam linha nenhuma de `usuario` — recarregar a sessão por eles era uma
/// ida ao banco por hora de uso, e um rebuild do app inteiro a cada uma.
const eventosQueRecarregam = {
  AuthChangeEvent.initialSession,
  AuthChangeEvent.signedIn,
  AuthChangeEvent.signedOut,
  AuthChangeEvent.userUpdated,
};

/// Estado da sessão, recarregado a cada evento do Auth que muda a sessão.
final sessaoProvider = NotifierProvider<ControladorSessao, EstadoSessao>(
  ControladorSessao.new,
);

/// O que o shell exibe do usuário: nome e unidade. Derivado, e não o estado
/// inteiro, pelo mesmo motivo de `permissoesProvider` — o widget não precisa da
/// máquina de estados da sessão, e um provider pequeno é sobrescritível no
/// widget test sem levantar meio app junto.
final resumoUsuarioProvider = Provider<ResumoUsuario?>((ref) {
  final estado = ref.watch(sessaoProvider);
  return estado is SessaoAtiva
      ? ResumoUsuario(
          nome: estado.sessao.nome,
          unidade: estado.sessao.unidadeNome,
        )
      : null;
});

@immutable
class ResumoUsuario {
  const ResumoUsuario({required this.nome, this.unidade});

  final String nome;
  final String? unidade;
}

/// Permissões do usuário — a fonte única dos guards de rota e da ocultação de
/// botão. Sobrescrito nos widget tests para injetar dados (card 2.8 §9.3).
final permissoesProvider = Provider<Set<String>>(
  (ref) => permissoesDe(ref.watch(sessaoProvider)),
);

/// A unidade do usuário — o que toda escrita carrega em `unidade_id`, porque
/// a coluna não tem default e a política de `insert` exige
/// `unidade_id = fn_unidade_atual()` (card 2.1). Nulo sem sessão pronta.
final unidadeAtualProvider = Provider<String?>((ref) {
  final estado = ref.watch(sessaoProvider);
  return estado is SessaoAtiva ? estado.sessao.unidadeId : null;
});

class ControladorSessao extends Notifier<EstadoSessao> implements Listenable {
  final _ouvintes = <VoidCallback>[];
  StreamSubscription<AuthState>? _inscricao;

  @override
  EstadoSessao build() {
    final repositorio = ref.watch(sessaoRepositorioProvider);

    // Recarrega a sessão a cada evento do Auth que a muda. A carga não é feita
    // no login e esquecida: um `signedIn` vindo do link de recuperação de
    // senha também precisa dela.
    _inscricao?.cancel();
    _inscricao = ref
        .read(fluxoAuthProvider)
        ?.where((e) => eventosQueRecarregam.contains(e.event))
        .listen((_) => unawaited(recarregar()));
    ref.onDispose(() => _inscricao?.cancel());

    _emCurso = null;
    unawaited(_carregarUmaVez(repositorio));
    return const SessaoCarregando();
  }

  /// A carga em andamento, compartilhada por quem pedir outra enquanto ela
  /// não termina.
  ///
  /// ⚠️ Card 9.2,63, medido no stack local pela Performance API: CADA
  /// consulta da sessão saía DUAS vezes — o `build` carregava e o evento
  /// `initialSession`, que o Supabase emite logo depois, carregava de novo;
  /// no login, `entrar` recarregava e o `signedIn` recarregava outra vez.
  /// Pedido que chega com uma carga em andamento pega a MESMA carga.
  Future<void>? _emCurso;

  Future<void> _carregarUmaVez(SessaoRepositorio repositorio) =>
      _emCurso ??= _carregar(repositorio).whenComplete(() => _emCurso = null);

  Future<void> _carregar(SessaoRepositorio repositorio) async {
    final novo = await repositorio.carregar();
    if (!ref.mounted) return;
    _definir(novo);
  }

  Future<void> recarregar() =>
      _carregarUmaVez(ref.read(sessaoRepositorioProvider));

  Future<void> entrar({required String email, required String senha}) async {
    _definir(const SessaoCarregando());
    try {
      await ref
          .read(sessaoRepositorioProvider)
          .entrar(email: email, senha: senha);
      await recarregar();
    } catch (erro) {
      _definir(SessaoDeslogada(aviso: traduzirErro(erro).mensagem));
      rethrow;
    }
  }

  Future<void> sair() async {
    await ref.read(sessaoRepositorioProvider).sair();
    _definir(const SessaoDeslogada());
  }

  void _definir(EstadoSessao novo) {
    // A mesma sessão de novo (valor igual, card 9.2,63) não é mudança: nem o
    // shell se reconstrói, nem o roteador reavalia o redirect.
    if (novo == state) return;
    state = novo;
    for (final ouvinte in List.of(_ouvintes)) {
      ouvinte();
    }
  }

  // Listenable para o `refreshListenable` do go_router: o roteador reavalia o
  // redirect quando a sessão muda, em vez de a tela navegar por conta própria.
  @override
  void addListener(VoidCallback listener) => _ouvintes.add(listener);

  @override
  void removeListener(VoidCallback listener) => _ouvintes.remove(listener);
}
