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
      // ⚠️ Card 9.2,63: as três consultas saíam EM SÉRIE (usuario → rpc →
      // unidade), sem dependência nenhuma entre a segunda e as outras — cada
      // abertura de tela pagava três idas e voltas antes do primeiro dado.
      // Agora são DUAS, em paralelo: a linha do usuário já traz o nome da
      // unidade por embed, e as permissões vão junto.
      final respostas = await Future.wait<Object?>([
        // 1. A própria linha de usuario, com a unidade embutida. Zero linhas
        //    aqui não é "usuário vazio": é ausência de espelho OU usuário
        //    desativado — ver SessaoSemEspelho.
        _cliente
            .from('usuario')
            .select('id, nome, email, unidade_id, unidade:unidade_id(nome)')
            .eq('id', autenticado.id)
            .maybeSingle(),
        // 2. As permissões. Uma chamada, não uma por código.
        _cliente.rpc('fn_minhas_permissoes'),
      ]);
      final linha = respostas[0] as Map<String, dynamic>?;
      final retorno = respostas[1];

      if (linha == null) {
        return SessaoSemEspelho(autenticado.email ?? '');
      }

      final permissoes = <String>{
        for (final item in (retorno as List? ?? const []))
          if (item is String)
            item
          else
            '${(item as Map)['fn_minhas_permissoes']}',
      };

      final unidadeId = '${linha['unidade_id']}';

      // 3. A unidade, pelo embed. Falta de `unidades.ler` degrada o cabeçalho
      //    e não derruba a sessão: o PostgREST devolve o embed NULO quando a
      //    RLS não deixa ler a linha — o nome da unidade é enfeite, a unidade
      //    em si vem do usuário.
      final unidade = linha['unidade'] as Map<String, dynamic>?;

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
