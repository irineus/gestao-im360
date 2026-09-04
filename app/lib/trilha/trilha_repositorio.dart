import 'package:supabase_flutter/supabase_flutter.dart';

import 'trilha.dart';

/// Acesso à trilha do aluno (card 6.6). Interface para o teste injetar
/// **dados**, nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// **Lê pela view e escreve só por função.** A leitura é `v_aluno_trilha`
/// (card 6.6); toda escrita passa pelas funções dos cards 6.2 e 6.3 —
/// `fn_registrar_entrega`, `fn_estornar_entrega`, `fn_trilha_gerar`,
/// `fn_trilha_inserir`, `fn_trilha_remover`, `fn_trilha_reordenar. Nenhum
/// `PATCH` direto em `aluno_material`: a guarda de coluna do card 6.1 §9 recusa
/// o que importa (aluno, material, origem e `ordem` fora da entrega), e o que
/// ela deixa passar — marcar `entregue` sem gravar movimento — é exatamente o
/// desencontro que a planilha tinha e que a "ação única" do card 2.2 §6.2
/// existe para acabar.
abstract interface class TrilhaRepositorio {
  /// A trilha inteira, em ordem. Vazia = aluno sem trilha (ou sem permissão de
  /// ver material, que a aba já barrou antes de chegar aqui).
  Future<List<ItemTrilha>> trilha(String alunoId);

  /// `fn_registrar_entrega`. [materialId] nulo = a próxima da trilha, que é o
  /// caminho do botão; informá-lo é a entrega fora de ordem, e o banco recusa
  /// com `MATERIAL_FORA_DA_TRILHA` o que não estiver pendente.
  Future<ResultadoEntrega> registrarEntrega(
    String alunoId, {
    String? materialId,
    String? observacao,
  });

  /// `fn_estornar_entrega`. Motivo obrigatório: desfazer uma entrega é decisão.
  Future<void> estornarEntrega(String movimentoId, {required String motivo});

  /// `fn_trilha_gerar` — a expansão combo → curso → material. Devolve quantos
  /// itens nasceram.
  Future<int> gerarTrilha(String alunoId, {bool substituir = false});

  Future<void> inserirItem(
    String alunoId, {
    required String materialId,
    String? aposMaterialId,
  });

  Future<void> removerItem(
    String alunoId, {
    required String materialId,
    required String motivo,
  });

  /// `p_nova_ordem` é **posição** (1 = primeiro), não a coluna `ordem`: a
  /// função grampeia fora das bordas e renumera a trilha de 10 em 10.
  Future<void> reordenarItem(
    String alunoId, {
    required String materialId,
    required int novaPosicao,
  });
}

class TrilhaRepositorioSupabase implements TrilhaRepositorio {
  TrilhaRepositorioSupabase(this._cliente);

  final SupabaseClient _cliente;

  @override
  Future<List<ItemTrilha>> trilha(String alunoId) async {
    final linhas = await _cliente
        .from('v_aluno_trilha')
        .select()
        .eq('aluno_id', alunoId)
        .order('ordem', ascending: true);
    return linhas.map(ItemTrilha.deLinha).toList();
  }

  @override
  Future<ResultadoEntrega> registrarEntrega(
    String alunoId, {
    String? materialId,
    String? observacao,
  }) async {
    // O retorno é o composto `tp_entrega_resultado`, que o PostgREST devolve
    // como objeto — os três status chegam em `status`, e nenhum deles é erro.
    final retorno = await _cliente.rpc<dynamic>(
      'fn_registrar_entrega',
      params: {
        'p_aluno_id': alunoId,
        'p_material_id': materialId,
        'p_observacao': observacao,
      },
    );
    return ResultadoEntrega.deLinha(Map<String, dynamic>.from(retorno as Map));
  }

  @override
  Future<void> estornarEntrega(String movimentoId, {required String motivo}) =>
      _cliente.rpc<dynamic>(
        'fn_estornar_entrega',
        params: {'p_movimento_id': movimentoId, 'p_motivo': motivo},
      );

  @override
  Future<int> gerarTrilha(String alunoId, {bool substituir = false}) async {
    final retorno = await _cliente.rpc<dynamic>(
      'fn_trilha_gerar',
      params: {
        'p_aluno_id': alunoId,
        'p_combo_id': null,
        'p_substituir': substituir,
      },
    );
    return (retorno as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> inserirItem(
    String alunoId, {
    required String materialId,
    String? aposMaterialId,
  }) => _cliente.rpc<dynamic>(
    'fn_trilha_inserir',
    params: {
      'p_aluno_id': alunoId,
      'p_material_id': materialId,
      'p_apos_material_id': aposMaterialId,
    },
  );

  @override
  Future<void> removerItem(
    String alunoId, {
    required String materialId,
    required String motivo,
  }) => _cliente.rpc<dynamic>(
    'fn_trilha_remover',
    params: {
      'p_aluno_id': alunoId,
      'p_material_id': materialId,
      'p_motivo': motivo,
    },
  );

  @override
  Future<void> reordenarItem(
    String alunoId, {
    required String materialId,
    required int novaPosicao,
  }) => _cliente.rpc<dynamic>(
    'fn_trilha_reordenar',
    params: {
      'p_aluno_id': alunoId,
      'p_material_id': materialId,
      'p_nova_ordem': novaPosicao,
    },
  );
}
