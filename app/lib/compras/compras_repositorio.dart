import 'package:supabase_flutter/supabase_flutter.dart';

import '../erros/erro_app.dart';
import 'compras.dart';

/// Acesso às compras (card 6.8). Interface para o teste injetar **dados**, nunca
/// um cliente HTTP falso (card 2.8 §9.3).
///
/// **Lê por view** (card 2.3 §1): o pedido sugerido é `v_pedido_sugerido`
/// (card 6.4), a lista de pedidos é `v_pedido_compra` e os itens são
/// `v_pedido_item` (card 6.8).
///
/// **Escreve por função onde há regra, e por tabela onde a regra é a política.**
/// A divisão não é de gosto, e vem do card 2.4 §3.5:
///
///   • criar, enviar, cancelar e receber são `fn_pedido_criar/_enviar/_cancelar/
///     _receber` (card 6.5) — cada uma carrega numeração, transição de status,
///     motivo obrigatório ou o vínculo compra ↔ estoque, que são regra;
///   • editar item de rascunho é escrita direta em `pedido_item`, como o
///     catálogo do card 4.4 e a infraestrutura do 4.5 fazem nas tabelas delas:
///     `compras.editar` e `compras.excluir` foram desenhados como POLÍTICA de
///     tabela, e a regra que sobra — "só em rascunho" — mora nos triggers
///     `tg_pedido_item_edicao` (6.8) e `tg_pedido_item_exclusao_valida` (6.1).
///
/// ⚠️ **Não existe "lançar entrada" aqui, e nem poderia.** ENTRADA de estoque
/// nasce dentro de `fn_pedido_receber`, com `pedido_item_id` preenchido — é o
/// vínculo que responde "de que pedido veio este exemplar?" três meses depois.
abstract interface class ComprasRepositorio {
  /// `v_pedido_sugerido` — **todo** material ativo, inclusive o de sugestão
  /// zero. Quem esconde é o filtro da tela.
  Future<List<LinhaSugerida>> sugerido();

  /// `v_pedido_compra`, do mais recente para o mais antigo.
  Future<List<PedidoCompra>> pedidos();

  /// `v_pedido_item` de um pedido.
  Future<List<ItemPedido>> itens(String pedidoId);

  /// `fn_pedido_criar` — devolve o id do RASCUNHO criado.
  Future<String> criar(
    List<ItemNovo> itens, {
    String? fornecedor,
    String? observacao,
  });

  /// `fn_pedido_enviar` — RASCUNHO → ENVIADO, com `data_envio` de `fn_hoje()`.
  Future<void> enviar(String pedidoId);

  /// `fn_pedido_cancelar` — motivo obrigatório; o banco recusa vazio com
  /// `MOTIVO_OBRIGATORIO`.
  Future<void> cancelar(String pedidoId, {required String motivo});

  /// `fn_pedido_receber` — **parcial por padrão**. Devolve quantas ENTRADAs
  /// criou.
  Future<int> receber(String pedidoId, Map<String, int> porItem);

  /// `qtd_pedida` de um item de rascunho.
  Future<void> definirQuantidade(String itemId, int quantidade);

  /// Item novo num rascunho.
  Future<void> acrescentarItem(
    String pedidoId,
    String materialId,
    int quantidade,
  );

  /// Remove item de rascunho (`compras.excluir`).
  Future<void> removerItem(String itemId);

  /// Fornecedor e observação de um rascunho (`compras.editar`).
  Future<void> editarPedido(
    String pedidoId, {
    String? fornecedor,
    String? observacao,
  });
}

class ComprasRepositorioSupabase implements ComprasRepositorio {
  ComprasRepositorioSupabase(this._cliente, {required this.unidadeId});

  final SupabaseClient _cliente;

  /// A política de `insert` de `pedido_item` exige `unidade_id =
  /// fn_unidade_atual()`, e o PostgREST não preenche coluna nenhuma — o mesmo
  /// contrato do catálogo (card 4.4) e da infraestrutura (4.5).
  final String unidadeId;

  static const _colunasSugerido =
      'material_id, metodo_id, codigo, nome, categoria, saldo, estoque_minimo, '
      'qtd_imediata, qtd_projetada, qtd_pedida_pendente, qtd_sugerida';

  static const _colunasPedido =
      'pedido_id, numero, status, data_envio, fornecedor, observacao, '
      'criado_em, data_referencia, qtd_itens, qtd_pedida_total, '
      'qtd_recebida_total';

  static const _colunasItem =
      'pedido_item_id, pedido_id, material_id, metodo_id, codigo, nome, '
      'categoria, qtd_pedida, qtd_recebida, qtd_pendente';

  @override
  Future<List<LinhaSugerida>> sugerido() async {
    final linhas = await _cliente
        .from('v_pedido_sugerido')
        .select(_colunasSugerido)
        .order('codigo', ascending: true);
    return linhas.map(LinhaSugerida.deLinha).toList();
  }

  @override
  Future<List<PedidoCompra>> pedidos() async {
    final linhas = await _cliente
        .from('v_pedido_compra')
        .select(_colunasPedido)
        .order('numero', ascending: false);
    return linhas.map(PedidoCompra.deLinha).toList();
  }

  @override
  Future<List<ItemPedido>> itens(String pedidoId) async {
    final linhas = await _cliente
        .from('v_pedido_item')
        .select(_colunasItem)
        .eq('pedido_id', pedidoId)
        .order('codigo', ascending: true);
    return linhas.map(ItemPedido.deLinha).toList();
  }

  @override
  Future<String> criar(
    List<ItemNovo> itens, {
    String? fornecedor,
    String? observacao,
  }) async {
    final id = await _cliente.rpc<dynamic>(
      'fn_pedido_criar',
      params: {
        'p_itens': [for (final i in itens) i.paraJson()],
        'p_fornecedor': fornecedor,
        'p_observacao': observacao,
      },
    );
    return '$id';
  }

  @override
  Future<void> enviar(String pedidoId) => _cliente.rpc<dynamic>(
    'fn_pedido_enviar',
    // Sem `p_data_envio`: a data é `fn_hoje()`, no fuso da escola. Mandar a do
    // aparelho registraria como enviado amanhã um pedido despachado às 21h.
    params: {'p_pedido_id': pedidoId},
  );

  @override
  Future<void> cancelar(String pedidoId, {required String motivo}) =>
      _cliente.rpc<dynamic>(
        'fn_pedido_cancelar',
        params: {'p_pedido_id': pedidoId, 'p_motivo': motivo},
      );

  @override
  Future<int> receber(String pedidoId, Map<String, int> porItem) async {
    final entradas = await _cliente.rpc<dynamic>(
      'fn_pedido_receber',
      params: {
        'p_pedido_id': pedidoId,
        'p_itens': [
          for (final e in porItem.entries)
            {'pedido_item_id': e.key, 'quantidade': e.value},
        ],
      },
    );
    return (entradas as num?)?.toInt() ?? 0;
  }

  /// `.select()` depois do `update`/`delete`, e o vazio vira erro: sem política
  /// o Postgres não levanta nada — muda zero linha e diz sucesso (card 3.4 (d)).
  /// A tela nunca mostra "salvo" para o que não foi salvo.
  @override
  Future<void> definirQuantidade(String itemId, int quantidade) async {
    final linhas = await _cliente
        .from('pedido_item')
        .update({'qtd_pedida': quantidade})
        .eq('id', itemId)
        .select('id');
    if (linhas.isEmpty) throw _nadaMudou;
  }

  @override
  Future<void> acrescentarItem(
    String pedidoId,
    String materialId,
    int quantidade,
  ) => _cliente.from('pedido_item').insert({
    'unidade_id': unidadeId,
    'pedido_id': pedidoId,
    'material_id': materialId,
    'qtd_pedida': quantidade,
  });

  @override
  Future<void> removerItem(String itemId) async {
    final apagadas = await _cliente
        .from('pedido_item')
        .delete()
        .eq('id', itemId)
        .select('id');
    if (apagadas.isEmpty) {
      throw const ErroApp(mensagem: mensagemNadaExcluido, traduzido: true);
    }
  }

  @override
  Future<void> editarPedido(
    String pedidoId, {
    String? fornecedor,
    String? observacao,
  }) async {
    final linhas = await _cliente
        .from('pedido_compra')
        .update({'fornecedor': fornecedor, 'observacao': observacao})
        .eq('id', pedidoId)
        .select('id');
    if (linhas.isEmpty) throw _nadaMudou;
  }

  static const _nadaMudou = ErroApp(
    mensagem:
        'Nada foi salvo: o pedido não existe mais ou você não tem permissão '
        'para alterá-lo.',
    traduzido: true,
  );
}
