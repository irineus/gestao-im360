import 'package:supabase_flutter/supabase_flutter.dart';

import 'estoque.dart';

/// Acesso ao estoque (card 6.7). Interface para o teste injetar **dados**,
/// nunca um cliente HTTP falso (card 2.8 §9.3).
///
/// **Lê por view e escreve só por função** (card 2.3 §1): a lista é
/// `v_estoque_atual` (card 6.4), o painel é `v_material_movimento` (card 6.7) e
/// a única escrita é `fn_ajustar_estoque` (card 6.5).
///
/// ⚠️ **Não existe "lançar entrada" aqui, e não é omissão** — é a decisão (c) do
/// card 2.4 §7: `movimento_estoque` recebe `insert` **por tipo**, e `ENTRADA`
/// exige `compras.receber`. Entrada é sempre recebimento de pedido, na tela 7
/// (card 6.8). Um `POST` direto de ENTRADA a partir desta tela seria escrita sem
/// função, contra o §1 do card 2.3, e daria ao monitor um caminho para inventar
/// estoque que ninguém comprou. Divergência da nota do card registrada em
/// `docs/wireframes.md` §17.
abstract interface class EstoqueRepositorio {
  /// `v_estoque_atual` — todo material, inclusive sem movimento (saldo 0) e
  /// inativo. Quem esconde é o filtro da tela.
  Future<List<MaterialEstoque>> estoque();

  /// `v_material_movimento` de um material, do mais recente para o mais antigo.
  Future<List<MovimentoMaterial>> movimentos(String materialId);

  /// `fn_ajustar_estoque` (card 6.5). [quantidade] com **sinal**; motivo
  /// obrigatório — desfazer uma contagem é decisão, e o banco recusa vazio com
  /// `MOTIVO_OBRIGATORIO`.
  Future<void> ajustar(
    String materialId, {
    required int quantidade,
    required String motivo,
  });
}

class EstoqueRepositorioSupabase implements EstoqueRepositorio {
  EstoqueRepositorioSupabase(this._cliente);

  final SupabaseClient _cliente;

  static const _colunasEstoque =
      'material_id, metodo_id, codigo, nome, categoria, ativo, '
      'estoque_minimo, saldo, abaixo_minimo, qtd_movimentos, '
      'ultimo_movimento_em';

  @override
  Future<List<MaterialEstoque>> estoque() async {
    final linhas = await _cliente
        .from('v_estoque_atual')
        .select(_colunasEstoque)
        .order('codigo', ascending: true);
    return linhas.map(MaterialEstoque.deLinha).toList();
  }

  @override
  Future<List<MovimentoMaterial>> movimentos(String materialId) async {
    final linhas = await _cliente
        .from('v_material_movimento')
        .select()
        .eq('material_id', materialId)
        .order('ocorrido_em', ascending: false);
    return linhas.map(MovimentoMaterial.deLinha).toList();
  }

  @override
  Future<void> ajustar(
    String materialId, {
    required int quantidade,
    required String motivo,
  }) => _cliente.rpc<dynamic>(
    'fn_ajustar_estoque',
    params: {
      'p_material_id': materialId,
      'p_quantidade': quantidade,
      'p_motivo': motivo,
    },
  );
}
