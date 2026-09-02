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

/// Estado da sessão, recarregado a cada evento do Auth.
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

    // Recarrega a sessão a cada evento do Auth. A carga não é feita no login e
    // esquecida: um `signedIn` vindo do link de recuperação de senha também
    // precisa dela.
    _inscricao?.cancel();
    _inscricao = _fluxoAuth()?.listen((_) => unawaited(recarregar()));
    ref.onDispose(() => _inscricao?.cancel());

    unawaited(_carregar(repositorio));
    return const SessaoCarregando();
  }

  Stream<AuthState>? _fluxoAuth() {
    try {
      return ref.read(clienteSupabaseProvider).auth.onAuthStateChange;
    } catch (_) {
      // Sem Supabase inicializado (teste, app não configurado): sem fluxo.
      return null;
    }
  }

  Future<void> _carregar(SessaoRepositorio repositorio) async {
    final novo = await repositorio.carregar();
    if (!ref.mounted) return;
    _definir(novo);
  }

  Future<void> recarregar() => _carregar(ref.read(sessaoRepositorioProvider));

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
