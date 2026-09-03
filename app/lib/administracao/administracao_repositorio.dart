import 'package:supabase_flutter/supabase_flutter.dart';

import '../erros/erro_app.dart';
import 'administracao.dart';

/// Acesso à administração (card 4.7). Interface para o teste injetar
/// **dados**, nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// Lê e escreve **nas tabelas** do card 3.3, pelo PostgREST, e a RLS do card
/// 3.4 decide o que cada perfil pode — a tela só não oferece o que vai falhar
/// (docs/wireframes.md §2.2). A única coisa que não passa pelo PostgREST é o
/// convite: criar usuário no Auth exige a Admin API, e a service key nunca
/// chega ao Flutter — daí a Edge Function `convidar-usuario`
/// (docs/acesso-autenticacao.md §3.2).
abstract interface class AdministracaoRepositorio {
  /// Todos os usuários da unidade, cada um com os ids dos perfis atribuídos.
  Future<List<UsuarioAdmin>> usuarios();

  /// Só nome e ativo mudam por aqui; o e-mail é do Auth.
  Future<UsuarioAdmin> salvarUsuario(UsuarioAdmin usuario);

  /// `usuario_perfil` não tem update: inserir o que falta e apagar o que sobra.
  Future<void> definirPerfis(String usuarioId, PlanoPerfis plano);

  /// Chama a Edge Function. Devolve o id do usuário criado (o espelho do card
  /// 3.5 já criou a linha em `usuario` quando a resposta chega).
  Future<String> convidar({
    required String email,
    required String nome,
    required String redirecionarPara,
  });

  Future<List<Perfil>> perfis();
  Future<Perfil> salvarPerfil(Perfil perfil);

  /// O catálogo — só leitura, por desenho (card 2.4 (e)).
  Future<List<Permissao>> permissoes();

  /// `perfil_id` → ids das permissões marcadas.
  Future<Map<String, Set<String>>> matriz();

  /// Marcar é insert, desmarcar é delete (card 3.4 §8.5).
  Future<void> marcar(String perfilId, String permissaoId);
  Future<void> desmarcar(String perfilId, String permissaoId);

  Future<List<Parametro>> parametros();
  Future<Parametro> salvarParametro(Parametro parametro);

  /// As alterações da matriz, da mais recente para a mais antiga (card 4.7.5).
  Future<List<LinhaHistoricoMatriz>> historico();
}

class AdministracaoRepositorioSupabase implements AdministracaoRepositorio {
  AdministracaoRepositorioSupabase(this._cliente, {required this.unidadeId});

  final SupabaseClient _cliente;

  /// A unidade do usuário — toda escrita a carrega (card 2.1).
  final String unidadeId;

  static const _colunasUsuario = 'id, nome, email, ativo';
  static const _colunasPerfil = 'id, codigo, nome, ativo';
  static const _colunasPermissao = 'id, codigo, descricao, dominio, ativo';
  static const _colunasParametro = 'id, chave, valor, tipo, descricao';

  /// Nome da Edge Function (`supabase/functions/convidar-usuario`).
  static const funcaoConvite = 'convidar-usuario';

  // --- usuários -------------------------------------------------------------

  @override
  Future<List<UsuarioAdmin>> usuarios() async {
    final linhas = await _cliente
        .from('usuario')
        .select(_colunasUsuario)
        .order('nome', ascending: true);
    final atribuicoes = await _cliente
        .from('usuario_perfil')
        .select('usuario_id, perfil_id');
    final perfisPorUsuario = <String, Set<String>>{};
    for (final a in atribuicoes) {
      perfisPorUsuario
          .putIfAbsent('${a['usuario_id']}', () => {})
          .add('${a['perfil_id']}');
    }
    return [
      for (final linha in linhas)
        UsuarioAdmin.deLinha(
          linha,
          perfisIds: perfisPorUsuario['${linha['id']}'] ?? const {},
        ),
    ];
  }

  @override
  Future<UsuarioAdmin> salvarUsuario(UsuarioAdmin usuario) async {
    final gravada = await _atualizar(
      'usuario',
      usuario.id,
      usuario.paraLinha(),
      _colunasUsuario,
    );
    return UsuarioAdmin.deLinha(gravada, perfisIds: usuario.perfisIds);
  }

  @override
  Future<void> definirPerfis(String usuarioId, PlanoPerfis plano) async {
    if (plano.remover.isNotEmpty) {
      final apagadas = await _cliente
          .from('usuario_perfil')
          .delete()
          .eq('usuario_id', usuarioId)
          .inFilter('perfil_id', plano.remover.toList())
          .select('id');
      // Sem política de delete o Postgres apaga nada e diz sucesso
      // (card 3.4 (d)); dizer "salvo" aqui seria mentir.
      if (apagadas.length != plano.remover.length) {
        throw const ErroApp(mensagem: mensagemNadaExcluido, traduzido: true);
      }
    }
    if (plano.inserir.isNotEmpty) {
      await _cliente.from('usuario_perfil').insert([
        for (final perfilId in plano.inserir)
          {
            'unidade_id': unidadeId,
            'usuario_id': usuarioId,
            'perfil_id': perfilId,
          },
      ]);
    }
  }

  @override
  Future<String> convidar({
    required String email,
    required String nome,
    required String redirecionarPara,
  }) async {
    // O token da sessão vai no cabeçalho sozinho: é com ele que a função
    // verifica admin.gerir_usuarios no banco. Erro (4xx/5xx) chega como
    // FunctionException, que `traduzirErro` sabe ler.
    final resposta = await _cliente.functions.invoke(
      funcaoConvite,
      body: {
        'email': email.trim(),
        'nome': nome.trim(),
        'redirecionar_para': redirecionarPara,
      },
    );
    final dados = resposta.data;
    final id = dados is Map ? dados['usuario_id'] : null;
    if (id == null) {
      throw ErroApp(
        mensagem:
            'O convite foi enviado, mas a resposta não trouxe o usuário '
            'criado. Recarregue a lista.',
        original: resposta,
      );
    }
    return '$id';
  }

  // --- perfis e matriz ------------------------------------------------------

  @override
  Future<List<Perfil>> perfis() async {
    final linhas = await _cliente
        .from('perfil')
        .select(_colunasPerfil)
        .order('codigo', ascending: true);
    return linhas.map(Perfil.deLinha).toList();
  }

  @override
  Future<Perfil> salvarPerfil(Perfil perfil) async {
    final linha = perfil.paraLinha(unidadeId);
    final id = perfil.id;
    final gravada = id == null
        ? await _inserir('perfil', linha, _colunasPerfil)
        : await _atualizar('perfil', id, linha, _colunasPerfil);
    return Perfil.deLinha(gravada);
  }

  @override
  Future<List<Permissao>> permissoes() async {
    final linhas = await _cliente
        .from('permissao')
        .select(_colunasPermissao)
        .order('codigo', ascending: true);
    return linhas.map(Permissao.deLinha).toList();
  }

  @override
  Future<Map<String, Set<String>>> matriz() async {
    final linhas = await _cliente
        .from('perfil_permissao')
        .select('perfil_id, permissao_id');
    final matriz = <String, Set<String>>{};
    for (final l in linhas) {
      matriz
          .putIfAbsent('${l['perfil_id']}', () => {})
          .add('${l['permissao_id']}');
    }
    return matriz;
  }

  @override
  Future<void> marcar(String perfilId, String permissaoId) =>
      _cliente.from('perfil_permissao').insert({
        'unidade_id': unidadeId,
        'perfil_id': perfilId,
        'permissao_id': permissaoId,
      });

  @override
  Future<void> desmarcar(String perfilId, String permissaoId) async {
    final apagadas = await _cliente
        .from('perfil_permissao')
        .delete()
        .eq('perfil_id', perfilId)
        .eq('permissao_id', permissaoId)
        .select('id');
    if (apagadas.isEmpty) {
      throw const ErroApp(mensagem: mensagemNadaExcluido, traduzido: true);
    }
  }

  // --- parâmetros -----------------------------------------------------------

  @override
  Future<List<Parametro>> parametros() async {
    final linhas = await _cliente
        .from('parametro')
        .select(_colunasParametro)
        .order('chave', ascending: true);
    return linhas.map(Parametro.deLinha).toList();
  }

  @override
  Future<Parametro> salvarParametro(Parametro parametro) async {
    final linha = parametro.paraLinha(unidadeId);
    final id = parametro.id;
    final gravada = id == null
        ? await _inserir('parametro', linha, _colunasParametro)
        : await _atualizar('parametro', id, linha, _colunasParametro);
    return Parametro.deLinha(gravada);
  }

  // --- histórico (card 4.7.5) -----------------------------------------------

  @override
  Future<List<LinhaHistoricoMatriz>> historico() async {
    final linhas = await _cliente
        .from('perfil_permissao_hist')
        .select('perfil_codigo, permissao_codigo, acao, criado_em, criado_por')
        .order('criado_em', ascending: false)
        .limit(500);
    // Quem mexeu: `usuario` é legível com admin.ler, o mesmo código que abre
    // o histórico. Uma consulta, não uma por linha.
    final nomes = <String, String>{
      for (final u in await _cliente.from('usuario').select('id, nome'))
        '${u['id']}': '${u['nome']}',
    };
    return [
      for (final l in linhas)
        LinhaHistoricoMatriz(
          perfilCodigo: '${l['perfil_codigo']}',
          permissaoCodigo: '${l['permissao_codigo']}',
          acao: '${l['acao']}',
          em: DateTime.parse('${l['criado_em']}'),
          porNome: l['criado_por'] == null ? null : nomes['${l['criado_por']}'],
        ),
    ];
  }

  // --- primitivas (as mesmas do catálogo e da infraestrutura) ---------------

  Future<Map<String, dynamic>> _inserir(
    String tabela,
    Map<String, dynamic> linha,
    String colunas,
  ) => _cliente.from(tabela).insert(linha).select(colunas).single();

  /// `.single()` de propósito: `update` sem política devolve zero linhas e
  /// nenhum erro (card 3.4 (d)); com ele, zero linhas vira exceção.
  Future<Map<String, dynamic>> _atualizar(
    String tabela,
    String id,
    Map<String, dynamic> linha,
    String colunas,
  ) =>
      _cliente.from(tabela).update(linha).eq('id', id).select(colunas).single();
}
