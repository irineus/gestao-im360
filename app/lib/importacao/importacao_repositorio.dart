import 'package:supabase_flutter/supabase_flutter.dart';

import 'importacao.dart';

/// Acesso à importação (card 9.1). Interface para o teste injetar **dados**,
/// nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// **Lê pelas duas views e escreve só por função.** Não existe `POST` nem
/// `PATCH` daqui: `importacao` e `importacao_ocorrencia` têm política de insert,
/// mas quem as escreve são `fn_importacao_registrar` e `fn_importacao_aplicar` —
/// escrever direto criaria um lote sem relatório, que é um lote que ninguém
/// consegue explicar depois.
abstract interface class ImportacaoRepositorio {
  /// `v_importacao` — os lotes desta unidade, do mais novo para o mais antigo.
  Future<List<LoteImportacao>> lotes();

  /// Um lote só, para a tela acompanhar o que acabou de fazer.
  Future<LoteImportacao?> lote(String id);

  /// `v_importacao_ocorrencia` — o relatório do passo 3.
  Future<List<OcorrenciaImportacao>> ocorrencias(String importacaoId);

  /// `fn_importacao_registrar` — cria o lote e valida. Devolve o id.
  Future<String> registrar({
    required String arquivo,
    required DateTime snapshotEm,
    required Map<String, dynamic> dados,
  });

  /// `fn_importacao_aplicar`. Com [simular] (o padrão) escreve tudo e desfaz por
  /// subtransação, devolvendo os totais que os triggers reais produziram.
  Future<Map<String, dynamic>> aplicar(String importacaoId, {bool simular});
}

class ImportacaoRepositorioSupabase implements ImportacaoRepositorio {
  ImportacaoRepositorioSupabase(this._cliente);

  final SupabaseClient _cliente;

  static const _colunasLote =
      'id, arquivo, snapshot_em, status, totais, simulado_em, aplicado_em, '
      'criado_em, aplicado_por_nome, erros, avisos';

  static const _colunasOcorrencia =
      'id, severidade, entidade, linha, codigo, mensagem, valor';

  @override
  Future<List<LoteImportacao>> lotes() async {
    final linhas = await _cliente
        .from('v_importacao')
        .select(_colunasLote)
        .order('criado_em', ascending: false);
    return linhas.map(LoteImportacao.deLinha).toList();
  }

  @override
  Future<LoteImportacao?> lote(String id) async {
    final linhas = await _cliente
        .from('v_importacao')
        .select(_colunasLote)
        .eq('id', id)
        .limit(1);
    return linhas.isEmpty ? null : LoteImportacao.deLinha(linhas.first);
  }

  @override
  Future<List<OcorrenciaImportacao>> ocorrencias(String importacaoId) async {
    final linhas = await _cliente
        .from('v_importacao_ocorrencia')
        .select(_colunasOcorrencia)
        .eq('importacao_id', importacaoId)
        // A ordem final é da tela (`ordenarOcorrencias`), que põe ERRO na
        // frente; aqui ela existe para o relatório não chegar embaralhado de
        // leitura para leitura.
        .order('severidade', ascending: true)
        .order('entidade', ascending: true)
        .order('linha', ascending: true, nullsFirst: true);
    return linhas.map(OcorrenciaImportacao.deLinha).toList();
  }

  @override
  Future<String> registrar({
    required String arquivo,
    required DateTime snapshotEm,
    required Map<String, dynamic> dados,
  }) async {
    final id = await _cliente.rpc<dynamic>(
      'fn_importacao_registrar',
      params: {
        'p_arquivo': arquivo,
        // Só a data: `snapshot_em` é `date` no banco, e mandar o instante do
        // navegador junto traria o fuso de quem clicou para dentro de uma data
        // que é da escola (card 2.3 §3.3).
        'p_snapshot_em': snapshotEm.toIso8601String().substring(0, 10),
        'p_dados': dados,
      },
    );
    return '$id';
  }

  @override
  Future<Map<String, dynamic>> aplicar(
    String importacaoId, {
    bool simular = true,
  }) async {
    final resultado = await _cliente.rpc<dynamic>(
      'fn_importacao_aplicar',
      params: {'p_importacao_id': importacaoId, 'p_simular': simular},
    );
    return resultado is Map<String, dynamic> ? resultado : <String, dynamic>{};
  }
}
