import 'package:gestao_im360/compras/compras.dart';
import 'package:gestao_im360/compras/compras_repositorio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP falso
/// (card 2.8 §9.3).
///
/// ⚠️ **Ele espelha as três views, não uma lista à parte.** `qtd_sugerida` é
/// derivada das parcelas a cada leitura, com a mesma fórmula e o mesmo piso zero
/// de `v_pedido_sugerido`; `qtd_itens`/`qtd_pedida_total`/`qtd_recebida_total`
/// são derivadas dos itens, como em `v_pedido_compra`; e `qtd_pendente` tem o
/// piso por item de `v_pedido_item`. Uma cópia escrita à mão deixaria os números
/// livres para divergirem dentro do próprio teste — e o defeito que este card
/// mais teme é justamente uma conta que não fecha.
///
/// A forma dos dados é a da camada `trilha_estoque` da escola-fixture
/// (`supabase/seed.sql`, cards 6.1 e 6.8):
///
///   • `2026-001` RECEBIDO, um item 26/26 — o pedido que não abate mais nada;
///   • `2026-002` ENVIADO, dois itens (10/0 e 5/0) — o que está a caminho;
///   • `2026-003` RASCUNHO, um item 5/0 — o que **não** abate;
///   • `2026-004` CANCELADO, sem item — o pedido sem item, que é estado real e
///     conta ZERO (a armadilha do card 2.3 §3.2).
class ComprasFalso implements ComprasRepositorio {
  ComprasFalso({
    required List<MaterialFalso> materiais,
    required List<PedidoCompra> pedidos,
    required Map<String, List<ItemPedido>> itens,
  }) : materiais_ = List.of(materiais),
       pedidos_ = List.of(pedidos),
       itens_ = {for (final e in itens.entries) e.key: List.of(e.value)};

  factory ComprasFalso.fixture() {
    // saldo, mínimo, imediata e pendente — as parcelas; a sugestão é derivada.
    const materiais = [
      MaterialFalso(
        'mat-int-01',
        'm-int',
        '01',
        'Informática Essencial 1',
        24,
        2,
        0,
      ),
      MaterialFalso(
        'mat-int-02',
        'm-int',
        '02',
        'Informática Essencial 2',
        0,
        1,
        5,
      ),
      MaterialFalso(
        'mat-int-03',
        'm-int',
        '03',
        'Informática Avançada 1',
        1,
        1,
        4,
      ),
      MaterialFalso('mat-ing-01', 'm-ing', '01', 'English Book 1', 11, 1, 0),
      MaterialFalso('mat-ing-02', 'm-ing', '02', 'English Book 2', -2, 2, 4),
      MaterialFalso(
        'mat-mod-01',
        'm-mod',
        '01',
        'Eletricista Instalador',
        10,
        1,
        12,
      ),
    ];

    ItemPedido item(
      String id,
      String pedido,
      String material,
      String codigo,
      String nome,
      int pedida,
      int recebida,
    ) => ItemPedido(
      itemId: id,
      pedidoId: pedido,
      materialId: material,
      metodoId: material.startsWith('mat-ing') ? 'm-ing' : 'm-int',
      codigo: codigo,
      nome: nome,
      categoria: 'APOSTILA',
      qtdPedida: pedida,
      qtdRecebida: recebida,
      // O piso por item da view (card 6.5): excedente falta ZERO, não −2.
      qtdPendente: pedida - recebida < 0 ? 0 : pedida - recebida,
    );

    return ComprasFalso(
      materiais: materiais,
      pedidos: [
        _pedido('p-001', '2026-001', 'RECEBIDO', DateTime(2026, 5, 7)),
        _pedido('p-002', '2026-002', 'ENVIADO', DateTime(2026, 8, 25)),
        _pedido('p-003', '2026-003', 'RASCUNHO', null),
        _pedido('p-004', '2026-004', 'CANCELADO', DateTime(2026, 8, 5)),
      ],
      itens: {
        'p-001': [
          item(
            'i-1',
            'p-001',
            'mat-int-01',
            '01',
            'Informática Essencial 1',
            26,
            26,
          ),
        ],
        'p-002': [
          item(
            'i-2',
            'p-002',
            'mat-int-02',
            '02',
            'Informática Essencial 2',
            10,
            0,
          ),
          item('i-3', 'p-002', 'mat-ing-02', '02', 'English Book 2', 5, 0),
        ],
        'p-003': [
          item(
            'i-4',
            'p-003',
            'mat-int-03',
            '03',
            'Informática Avançada 1',
            5,
            0,
          ),
        ],
        // `2026-004` fica SEM item de propósito.
        'p-004': const [],
      },
    );
  }

  static PedidoCompra _pedido(
    String id,
    String numero,
    String status,
    DateTime? envio,
  ) => PedidoCompra(
    pedidoId: id,
    numero: numero,
    status: status,
    dataReferencia: envio ?? DateTime(2026, 9, 4),
    dataEnvio: envio,
    fornecedor: status == 'RASCUNHO' ? null : 'Editora Interativa',
    qtdItens: 0,
    qtdPedidaTotal: 0,
    qtdRecebidaTotal: 0,
  );

  final List<MaterialFalso> materiais_;
  final List<PedidoCompra> pedidos_;
  final Map<String, List<ItemPedido>> itens_;

  /// Se definido, toda **leitura** lança isto.
  Object? falhaAoLer;

  /// Se definido, só a leitura dos ITENS lança isto — é como o teste verifica
  /// que o erro do painel fica dentro dele e não no lugar da tela.
  Object? falhaAoLerItens;

  /// Se definido, toda **escrita** lança isto.
  Object? falhaAoGravar;

  /// Quando a projeção foi calculada (card 8.2). `null` é a projeção que nunca
  /// rodou — o padrão da fixture, que não tem parcela projetada nenhuma.
  DateTime? projecaoEm;

  /// Se definido, só a leitura do CARIMBO da projeção lança isto — o mesmo
  /// desenho de [falhaAoLerItens]: é como o teste verifica que o erro fica no
  /// lugar dele e não derruba a lista inteira.
  Object? falhaAoLerProjecao;

  final chamadas = <String>[];

  static PostgrestException erro(
    String status,
    String codigo, [
    Map<String, Object?> detalhe = const {},
  ]) => PostgrestException(
    message: codigo,
    code: 'PT$status',
    details:
        '{"codigo":"$codigo"'
        '${detalhe.entries.map((e) => ',"${e.key}":"${e.value}"').join()}}',
  );

  /// A parcela "já pedida": `qtd_pedida − qtd_recebida` dos itens de pedidos
  /// ENVIADO e PARCIAL, com **piso zero por item** — RASCUNHO, RECEBIDO e
  /// CANCELADO não abatem (card 2.3 §6).
  int _pendenteDe(String materialId) {
    var total = 0;
    for (final p in pedidos_) {
      if (p.status != 'ENVIADO' && p.status != 'PARCIAL') continue;
      for (final i in itens_[p.pedidoId] ?? const <ItemPedido>[]) {
        if (i.materialId != materialId) continue;
        final falta = i.qtdPedida - i.qtdRecebida;
        total += falta < 0 ? 0 : falta;
      }
    }
    return total;
  }

  @override
  Future<List<LinhaSugerida>> sugerido() async {
    chamadas.add('sugerido');
    final falha = falhaAoLer;
    if (falha != null) throw falha;
    return [
      for (final m in materiais_)
        LinhaSugerida(
          materialId: m.id,
          metodoId: m.metodoId,
          codigo: m.codigo,
          nome: m.nome,
          categoria: 'APOSTILA',
          saldo: m.saldo,
          estoqueMinimo: m.minimo,
          qtdImediata: m.imediata,
          qtdProjetada: m.projetada,
          qtdPedidaPendente: _pendenteDe(m.id),
          qtdSugerida: _sugerida(m),
        ),
    ];
  }

  @override
  Future<DateTime?> projecaoCalculadaEm() async {
    chamadas.add('projecaoCalculadaEm');
    final falha = falhaAoLerProjecao ?? falhaAoLer;
    if (falha != null) throw falha;
    return projecaoEm;
  }

  /// A fórmula de `v_pedido_sugerido` §6, **com a parcela projetada** (card 8.2)
  /// e o `greatest(…, 0)`. Derivada aqui pela mesma razão de sempre: uma cópia
  /// escrita à mão deixaria os números livres para divergirem dentro do próprio
  /// teste, e o defeito que este card mais teme é uma conta que não fecha.
  int _sugerida(MaterialFalso m) {
    final bruto =
        m.imediata + m.projetada + m.minimo - m.saldo - _pendenteDe(m.id);
    return bruto < 0 ? 0 : bruto;
  }

  @override
  Future<List<PedidoCompra>> pedidos() async {
    chamadas.add('pedidos');
    final falha = falhaAoLer;
    if (falha != null) throw falha;
    return [for (final p in pedidos_) _comAgregados(p)]
      ..sort((a, b) => b.numero.compareTo(a.numero));
  }

  PedidoCompra _comAgregados(PedidoCompra p) {
    final lista = itens_[p.pedidoId] ?? const <ItemPedido>[];
    var pedida = 0;
    var recebida = 0;
    for (final i in lista) {
      pedida += i.qtdPedida;
      recebida += i.qtdRecebida;
    }
    return PedidoCompra(
      pedidoId: p.pedidoId,
      numero: p.numero,
      status: p.status,
      dataReferencia: p.dataReferencia,
      dataEnvio: p.dataEnvio,
      fornecedor: p.fornecedor,
      observacao: p.observacao,
      qtdItens: lista.length,
      qtdPedidaTotal: pedida,
      qtdRecebidaTotal: recebida,
    );
  }

  @override
  Future<List<ItemPedido>> itens(String pedidoId) async {
    chamadas.add('itens:$pedidoId');
    final falha = falhaAoLerItens ?? falhaAoLer;
    if (falha != null) throw falha;
    return [...?itens_[pedidoId]]..sort((a, b) => a.codigo.compareTo(b.codigo));
  }

  @override
  Future<String> criar(
    List<ItemNovo> novos, {
    String? fornecedor,
    String? observacao,
  }) async {
    chamadas.add(
      'criar:${novos.map((i) => '${i.materialId}=${i.quantidade}').join(',')}',
    );
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    // As recusas de `fn_pedido_criar`, na ordem em que a função as faz.
    if (novos.isEmpty) throw erro('422', 'PEDIDO_SEM_ITEM');
    if ({for (final i in novos) i.materialId}.length != novos.length) {
      throw erro('409', 'MATERIAL_JA_NO_PEDIDO');
    }
    for (final i in novos) {
      if (i.quantidade <= 0) throw erro('422', 'QUANTIDADE_INVALIDA');
    }
    final id = 'p-90${pedidos_.length}';
    pedidos_.add(_pedido(id, '2026-90${pedidos_.length}', 'RASCUNHO', null));
    itens_[id] = [
      for (final i in novos)
        ItemPedido(
          itemId: 'i-$id-${i.materialId}',
          pedidoId: id,
          materialId: i.materialId,
          metodoId: 'm-int',
          codigo: _codigoDe(i.materialId),
          nome: _nomeDe(i.materialId),
          categoria: 'APOSTILA',
          qtdPedida: i.quantidade,
          qtdRecebida: 0,
          qtdPendente: i.quantidade,
        ),
    ];
    return id;
  }

  @override
  Future<void> enviar(String pedidoId) async {
    chamadas.add('enviar:$pedidoId');
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    final atual = _acharPedido(pedidoId);
    if (atual.status != 'RASCUNHO') {
      throw erro('409', 'PEDIDO_NAO_ENVIAVEL', {'status': atual.status});
    }
    if ((itens_[pedidoId] ?? const []).isEmpty) {
      throw erro('422', 'PEDIDO_SEM_ITEM');
    }
    _trocarStatus(pedidoId, 'ENVIADO', envio: DateTime(2026, 9, 4));
  }

  @override
  Future<void> cancelar(String pedidoId, {required String motivo}) async {
    chamadas.add('cancelar:$pedidoId:$motivo');
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    if (motivo.trim().isEmpty) throw erro('422', 'MOTIVO_OBRIGATORIO');
    final atual = _acharPedido(pedidoId);
    if (atual.status == 'RECEBIDO' || atual.status == 'CANCELADO') {
      throw erro('409', 'PEDIDO_NAO_CANCELAVEL', {'status': atual.status});
    }
    _trocarStatus(pedidoId, 'CANCELADO');
  }

  @override
  Future<int> receber(String pedidoId, Map<String, int> porItem) async {
    chamadas.add(
      'receber:$pedidoId:'
      '${porItem.entries.map((e) => '${e.key}=${e.value}').join(',')}',
    );
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    final atual = _acharPedido(pedidoId);
    if (atual.status != 'ENVIADO' && atual.status != 'PARCIAL') {
      throw erro('409', 'PEDIDO_NAO_RECEBIVEL', {'status': atual.status});
    }
    if (porItem.isEmpty) throw erro('422', 'PEDIDO_SEM_ITEM');

    final lista = itens_[pedidoId] ?? const <ItemPedido>[];
    final novos = <ItemPedido>[];
    var entradas = 0;
    for (final i in lista) {
      final chegou = porItem[i.itemId];
      if (chegou == null) {
        novos.add(i);
        continue;
      }
      if (chegou <= 0) throw erro('422', 'QUANTIDADE_INVALIDA');
      if (i.qtdRecebida + chegou > i.qtdPedida && !permiteExcedente) {
        throw erro('422', 'RECEBIMENTO_EXCEDE_PEDIDO', {
          'qtd_pedida': i.qtdPedida,
          'qtd_recebida': i.qtdRecebida,
        });
      }
      entradas++;
      final recebida = i.qtdRecebida + chegou;
      novos.add(
        ItemPedido(
          itemId: i.itemId,
          pedidoId: i.pedidoId,
          materialId: i.materialId,
          metodoId: i.metodoId,
          codigo: i.codigo,
          nome: i.nome,
          categoria: i.categoria,
          qtdPedida: i.qtdPedida,
          qtdRecebida: recebida,
          qtdPendente: i.qtdPedida - recebida < 0 ? 0 : i.qtdPedida - recebida,
        ),
      );
    }
    itens_[pedidoId] = novos;
    final completo = novos.every((i) => i.qtdRecebida >= i.qtdPedida);
    _trocarStatus(pedidoId, completo ? 'RECEBIDO' : 'PARCIAL');
    return entradas;
  }

  /// O que `compras.receber_excedente` significa do lado do banco — o teste o
  /// liga para exercitar a exceção de permissão do card 6.5.
  bool permiteExcedente = false;

  @override
  Future<void> definirQuantidade(String itemId, int quantidade) async {
    chamadas.add('quantidade:$itemId=$quantidade');
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    if (quantidade <= 0) throw erro('422', 'QUANTIDADE_INVALIDA');
    for (final e in itens_.entries) {
      for (var i = 0; i < e.value.length; i++) {
        if (e.value[i].itemId != itemId) continue;
        // `tg_pedido_item_edicao` (card 6.8): só em rascunho.
        if (_acharPedido(e.key).status != 'RASCUNHO') {
          throw erro('409', 'PEDIDO_NAO_RASCUNHO');
        }
        final antigo = e.value[i];
        e.value[i] = ItemPedido(
          itemId: antigo.itemId,
          pedidoId: antigo.pedidoId,
          materialId: antigo.materialId,
          metodoId: antigo.metodoId,
          codigo: antigo.codigo,
          nome: antigo.nome,
          categoria: antigo.categoria,
          qtdPedida: quantidade,
          qtdRecebida: antigo.qtdRecebida,
          qtdPendente: quantidade - antigo.qtdRecebida < 0
              ? 0
              : quantidade - antigo.qtdRecebida,
        );
        return;
      }
    }
  }

  @override
  Future<void> acrescentarItem(
    String pedidoId,
    String materialId,
    int quantidade,
  ) async {
    chamadas.add('acrescentar:$pedidoId:$materialId=$quantidade');
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    if (_acharPedido(pedidoId).status != 'RASCUNHO') {
      throw erro('409', 'PEDIDO_NAO_RASCUNHO');
    }
    itens_
        .putIfAbsent(pedidoId, () => <ItemPedido>[])
        .add(
          ItemPedido(
            itemId: 'i-novo-${chamadas.length}',
            pedidoId: pedidoId,
            materialId: materialId,
            metodoId: 'm-int',
            codigo: _codigoDe(materialId),
            nome: _nomeDe(materialId),
            categoria: 'APOSTILA',
            qtdPedida: quantidade,
            qtdRecebida: 0,
            qtdPendente: quantidade,
          ),
        );
  }

  @override
  Future<void> removerItem(String itemId) async {
    chamadas.add('remover:$itemId');
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    for (final e in itens_.entries) {
      if (!e.value.any((i) => i.itemId == itemId)) continue;
      if (_acharPedido(e.key).status != 'RASCUNHO') {
        throw erro('409', 'PEDIDO_NAO_RASCUNHO');
      }
      e.value.removeWhere((i) => i.itemId == itemId);
      return;
    }
  }

  @override
  Future<void> editarPedido(
    String pedidoId, {
    String? fornecedor,
    String? observacao,
  }) async {
    chamadas.add('dados:$pedidoId:$fornecedor');
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    final i = pedidos_.indexWhere((p) => p.pedidoId == pedidoId);
    final atual = pedidos_[i];
    pedidos_[i] = PedidoCompra(
      pedidoId: atual.pedidoId,
      numero: atual.numero,
      status: atual.status,
      dataReferencia: atual.dataReferencia,
      dataEnvio: atual.dataEnvio,
      fornecedor: fornecedor,
      observacao: observacao,
      qtdItens: atual.qtdItens,
      qtdPedidaTotal: atual.qtdPedidaTotal,
      qtdRecebidaTotal: atual.qtdRecebidaTotal,
    );
  }

  PedidoCompra _acharPedido(String id) =>
      pedidos_.firstWhere((p) => p.pedidoId == id);

  void _trocarStatus(String id, String status, {DateTime? envio}) {
    final i = pedidos_.indexWhere((p) => p.pedidoId == id);
    final atual = pedidos_[i];
    pedidos_[i] = PedidoCompra(
      pedidoId: atual.pedidoId,
      numero: atual.numero,
      status: status,
      dataReferencia: envio ?? atual.dataReferencia,
      dataEnvio: envio ?? atual.dataEnvio,
      fornecedor: atual.fornecedor,
      observacao: atual.observacao,
      qtdItens: atual.qtdItens,
      qtdPedidaTotal: atual.qtdPedidaTotal,
      qtdRecebidaTotal: atual.qtdRecebidaTotal,
    );
  }

  String _codigoDe(String materialId) =>
      materiais_.firstWhere((m) => m.id == materialId).codigo;

  String _nomeDe(String materialId) =>
      materiais_.firstWhere((m) => m.id == materialId).nome;
}

/// As parcelas de um material, das quais a sugestão é derivada.
class MaterialFalso {
  const MaterialFalso(
    this.id,
    this.metodoId,
    this.codigo,
    this.nome,
    this.saldo,
    this.minimo,
    this.imediata, [
    this.projetada = 0,
  ]);

  final String id;
  final String metodoId;
  final String codigo;
  final String nome;
  final int saldo;
  final int minimo;
  final int imediata;

  /// A parcela do card 8.2. Opcional e zero por omissão para que a fixture
  /// continue medindo o que media — quem exercita a projeção a informa.
  final int projetada;
}
