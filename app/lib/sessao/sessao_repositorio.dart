import 'package:supabase_flutter/supabase_flutter.dart';

import '../erros/erro_app.dart';
import 'sessao.dart';

/// Acesso ao banco para montar a sessão. É uma interface para o teste injetar
/// **dados**, e não um cliente HTTP falso (card 2.8 §9.3).
abstract interface class SessaoRepositorio {
  /// Estado da sessão do usuário autenticado agora.
  Future<EstadoSessao> carregar();

  Future<void> entrar({required String email, required String senha});

  Future<void> recuperarSenha(String email, {required String redirecionarPara});

  Future<void> trocarSenha(String novaSenha);

  Future<void> sair();
}

class SessaoRepositorioSupabase implements SessaoRepositorio {
  SessaoRepositorioSupabase(this._cliente);

  final SupabaseClient _cliente;

  @override
  Future<EstadoSessao> carregar() async {
    final autenticado = _cliente.auth.currentUser;
    if (autenticado == null) return const SessaoDeslogada();

    try {
      // 1. A própria linha de usuario. Zero linhas aqui não é "usuário vazio":
      //    é ausência de espelho OU usuário desativado — ver SessaoSemEspelho.
      final linha = await _cliente
          .from('usuario')
          .select('id, nome, email, unidade_id')
          .eq('id', autenticado.id)
          .maybeSingle();

      if (linha == null) {
        return SessaoSemEspelho(autenticado.email ?? '');
      }

      // 2. As permissões. Uma chamada, não uma por código.
      final retorno = await _cliente.rpc('fn_minhas_permissoes');
      final permissoes = <String>{
        for (final item in (retorno as List? ?? const []))
          if (item is String)
            item
          else
            '${(item as Map)['fn_minhas_permissoes']}',
      };

      final unidadeId = '${linha['unidade_id']}';

      // 3. A unidade. Falta de `unidades.ler` degrada o cabeçalho e não derruba
      //    a sessão: o nome da unidade é enfeite, a unidade em si vem do
      //    usuário.
      final unidade = await _cliente
          .from('unidade')
          .select('id, nome')
          .eq('id', unidadeId)
          .maybeSingle();

      final sessao = Sessao(
        usuarioId: '${linha['id']}',
        nome: '${linha['nome']}',
        email: '${linha['email']}',
        unidadeId: unidadeId,
        unidadeNome: unidade == null ? null : '${unidade['nome']}',
        permissoes: permissoes,
      );

      return permissoes.isEmpty ? SessaoSemPerfil(sessao) : SessaoAtiva(sessao);
    } catch (erro) {
      final traduzido = traduzirErro(erro);
      return SessaoErro(traduzido.mensagem, codigo: traduzido.codigo);
    }
  }

  @override
  Future<void> entrar({required String email, required String senha}) =>
      _cliente.auth.signInWithPassword(email: email.trim(), password: senha);

  @override
  Future<void> recuperarSenha(
    String email, {
    required String redirecionarPara,
  }) => _cliente.auth.resetPasswordForEmail(
    email.trim(),
    redirectTo: redirecionarPara,
  );

  @override
  Future<void> trocarSenha(String novaSenha) =>
      _cliente.auth.updateUser(UserAttributes(password: novaSenha));

  @override
  Future<void> sair() => _cliente.auth.signOut();
}
