import '../sessao/nomes_usuarios.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'certificados.dart';

/// Acesso aos certificados (card 8.6). Interface para o teste injetar **dados**,
/// nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// **Lê a fila pela view, lê o checklist pela tabela e escreve só por função.**
///
/// - a fila é `v_certificado_fila` (card 8.6), que junta situação e resumo;
/// - o checklist é `certificado_checklist` direto, e não a view, porque a tela
///   §12.2 precisa de "quem/quando" de cada item — quatro FKs para `usuario`
///   que a fila não carrega e que o PostgREST resolve por embed;
/// - **nenhum `PATCH`**: `fn_certificado_marcar` e `fn_certificado_status` são
///   as portas, e `tg_certificado_colunas_permitidas` recusa o resto. Escrever
///   direto passaria pela política de `update` — que é o `or` de três
///   permissões — e RLS não é por coluna (card 2.4 §7, achado 8).
abstract interface class CertificadosRepositorio {
  /// `v_certificado_fila` — quem está chegando ao fim do curso.
  Future<List<LinhaFilaCertificado>> fila();

  /// O checklist de um aluno. **Nulo** quando ele ainda não tem um — que é o
  /// caso normal de quem está no último livro.
  Future<ChecklistCertificado?> checklist(String alunoId);

  /// `fn_certificado_abrir` — idempotente: chamada duas vezes devolve o mesmo
  /// checklist e não zera item nenhum que alguém já marcou.
  Future<void> abrirChecklist(String alunoId);

  /// `fn_certificado_marcar`. [item] é o código de [ItemChecklist].
  Future<void> marcarItem(
    String alunoId, {
    required String item,
    required bool valor,
  });

  /// `fn_certificado_status` — `NAO_PEDIDO` | `PEDIDO` | `ENTREGUE`.
  Future<void> alterarStatus(String alunoId, {required String status});
}

class CertificadosRepositorioSupabase implements CertificadosRepositorio {
  CertificadosRepositorioSupabase(this._cliente);

  final SupabaseClient _cliente;

  static const _colunasFila =
      'aluno_id, aluno_nome, codigo_sgf, aluno_status, metodo_id, metodo_nome, '
      'situacao, itens_pendentes, checklist_id, data_fim_curso, pedagogico_ok, '
      'financeiro_ok, formatura, certificado_status';

  /// Os quatro "quem" (card 9.2,74): os ids `*_por`, e o nome de cada um sai
  /// de `fn_usuarios_nomes()` — o embed `…_por(nome)` vinha **nulo** para quem
  /// não tem `admin.ler`, e o monitor lia o próprio nome e nulo nos outros três
  /// (pendência 9.13(a)).
  ///
  /// ⚠️ As chaves dos nomes não repetem nome de coluna: `formatura` já é a
  /// coluna booleana do item, e um nome com a mesma chave a sobrescreveria.
  static const _colunasChecklist =
      'id, aluno_id, data_fim_curso, '
      'pedagogico_ok, pedagogico_em, financeiro_ok, financeiro_em, '
      'formatura, formatura_em, certificado_status, certificado_em, '
      'pedagogico_por, financeiro_por, formatura_por, certificado_por';

  static const _autores = {
    'pedagogico_por': 'pedagogico_usuario',
    'financeiro_por': 'financeiro_usuario',
    'formatura_por': 'formatura_usuario',
    'certificado_por': 'certificado_usuario',
  };

  @override
  Future<List<LinhaFilaCertificado>> fila() async {
    final linhas = await _cliente
        .from('v_certificado_fila')
        .select(_colunasFila)
        // A ordem final é da tela (`ordenarFila`), que põe FIM na frente; aqui
        // a ordem existe para a lista não chegar embaralhada de leitura para
        // leitura, que é o que faria a tabela "pular" entre atualizações.
        .order('data_fim_curso', ascending: true, nullsFirst: false)
        .order('aluno_nome', ascending: true);
    return linhas.map(LinhaFilaCertificado.deLinha).toList();
  }

  @override
  Future<ChecklistCertificado?> checklist(String alunoId) async {
    final (linhas, nomes) = await (
      _cliente
          .from('certificado_checklist')
          .select(_colunasChecklist)
          .eq('aluno_id', alunoId)
          .limit(1),
      nomesDaUnidade(_cliente),
    ).wait;
    return linhas.isEmpty
        ? null
        : ChecklistCertificado.deLinha(
            comNomes(linhas.first, nomes, colunaParaEmbed: _autores),
          );
  }

  @override
  Future<void> abrirChecklist(String alunoId) => _cliente.rpc<dynamic>(
    'fn_certificado_abrir',
    // `p_data_fim_curso` fica de fora: o banco resolve a data pela última
    // entrega da trilha e, na falta dela, por `fn_hoje()`. Mandar uma data da
    // máquina de quem clicou seria trocar a data no fuso da escola pela do
    // navegador (card 2.3 §3.3).
    params: {'p_aluno_id': alunoId},
  );

  @override
  Future<void> marcarItem(
    String alunoId, {
    required String item,
    required bool valor,
  }) => _cliente.rpc<dynamic>(
    'fn_certificado_marcar',
    params: {'p_aluno_id': alunoId, 'p_item': item, 'p_valor': valor},
  );

  @override
  Future<void> alterarStatus(String alunoId, {required String status}) =>
      _cliente.rpc<dynamic>(
        'fn_certificado_status',
        params: {'p_aluno_id': alunoId, 'p_status': status},
      );
}
