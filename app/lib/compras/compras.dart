/// As compras como o app as vê (card 6.8): o modelo de `v_pedido_sugerido`
/// (card 6.4), os de `v_pedido_compra` e `v_pedido_item` (card 6.8) e a lógica
/// **pura** da tela 7 — filtros, rótulos de status e o que cada estado do
/// pedido permite fazer.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3).
///
/// ⚠️ **Nada neste arquivo refaz a conta do pedido sugerido.** `qtd_sugerida` é
/// `imediata + projetada + mínimo − saldo − pendente`, com piso zero, e quem a
/// calcula é a view (docs/views-leitura.md §6). Uma segunda soma em Dart
/// divergiria no dia em que a parcela projetada deixasse de ser zero — que é
/// exatamente o que o card 8.2 vai fazer.
library;

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Pedido sugerido — uma linha de v_pedido_sugerido
// ---------------------------------------------------------------------------

/// O que comprar de um material, com **as parcelas ao lado do total**: o
/// usuário confere a conta em vez de acreditar nela (card 2.3 §2.3).
@immutable
class LinhaSugerida {
  const LinhaSugerida({
    required this.materialId,
    required this.metodoId,
    required this.codigo,
    required this.nome,
    required this.categoria,
    required this.saldo,
    required this.estoqueMinimo,
    required this.qtdImediata,
    required this.qtdProjetada,
    required this.qtdPedidaPendente,
    required this.qtdSugerida,
  });

  factory LinhaSugerida.deLinha(Map<String, dynamic> linha) => LinhaSugerida(
    materialId: '${linha['material_id']}',
    metodoId: '${linha['metodo_id']}',
    codigo: '${linha['codigo']}',
    nome: '${linha['nome']}',
    categoria: '${linha['categoria']}',
    saldo: (linha['saldo'] as num?)?.toInt() ?? 0,
    estoqueMinimo: (linha['estoque_minimo'] as num?)?.toInt() ?? 0,
    qtdImediata: (linha['qtd_imediata'] as num?)?.toInt() ?? 0,
    qtdProjetada: (linha['qtd_projetada'] as num?)?.toInt() ?? 0,
    qtdPedidaPendente: (linha['qtd_pedida_pendente'] as num?)?.toInt() ?? 0,
    qtdSugerida: (linha['qtd_sugerida'] as num?)?.toInt() ?? 0,
  );

  final String materialId;
  final String metodoId;
  final String codigo;
  final String nome;
  final String categoria;

  final int saldo;
  final int estoqueMinimo;

  /// Alunos com este material como PRÓXIMO da trilha (card 6.4).
  final int qtdImediata;

  /// Zero até o card 8.1 preencher a projeção. A coluna existe desde o primeiro
  /// dia, na posição definitiva — mostrar `0` é honesto, e esconder a coluna
  /// faria a soma exibida não fechar com o total.
  final int qtdProjetada;

  /// `qtd_pedida − qtd_recebida` dos itens de pedidos ENVIADO e PARCIAL, com
  /// piso zero por item. RASCUNHO não abate: não foi pedido a ninguém.
  final int qtdPedidaPendente;

  /// **Vem da view.** Nunca recalculado aqui.
  final int qtdSugerida;

  String get rotulo => '$codigo $nome';
}

// ---------------------------------------------------------------------------
// Pedido de compra — uma linha de v_pedido_compra
// ---------------------------------------------------------------------------

/// Os cinco estados do ciclo (card 2.1 §10 e wireframe §10.2). Pedido não se
/// apaga: enviado, ele vira `CANCELADO` e fica no histórico.
enum StatusPedido { rascunho, enviado, parcial, recebido, cancelado }

const _statusPorCodigo = <String, StatusPedido>{
  'RASCUNHO': StatusPedido.rascunho,
  'ENVIADO': StatusPedido.enviado,
  'PARCIAL': StatusPedido.parcial,
  'RECEBIDO': StatusPedido.recebido,
  'CANCELADO': StatusPedido.cancelado,
};

/// Status desconhecido cai em `rascunho`? **Não.** Ele vira nulo e a tela mostra
/// o texto cru — inventar um estado conhecido para um código que o banco passou
/// a usar seria oferecer os botões errados para ele.
StatusPedido? statusPedidoDe(String codigo) => _statusPorCodigo[codigo];

String rotuloStatusPedido(String codigo) => switch (statusPedidoDe(codigo)) {
  StatusPedido.rascunho => 'Rascunho',
  StatusPedido.enviado => 'Enviado',
  StatusPedido.parcial => 'Parcial',
  StatusPedido.recebido => 'Recebido',
  StatusPedido.cancelado => 'Cancelado',
  null => codigo,
};

@immutable
class PedidoCompra {
  const PedidoCompra({
    required this.pedidoId,
    required this.numero,
    required this.status,
    required this.dataReferencia,
    required this.qtdItens,
    required this.qtdPedidaTotal,
    required this.qtdRecebidaTotal,
    this.dataEnvio,
    this.fornecedor,
    this.observacao,
  });

  factory PedidoCompra.deLinha(Map<String, dynamic> linha) => PedidoCompra(
    pedidoId: '${linha['pedido_id']}',
    numero: '${linha['numero']}',
    status: '${linha['status']}',
    dataReferencia: DateTime.parse('${linha['data_referencia']}'),
    dataEnvio: linha['data_envio'] == null
        ? null
        : DateTime.parse('${linha['data_envio']}'),
    fornecedor: linha['fornecedor'] as String?,
    observacao: linha['observacao'] as String?,
    qtdItens: (linha['qtd_itens'] as num?)?.toInt() ?? 0,
    qtdPedidaTotal: (linha['qtd_pedida_total'] as num?)?.toInt() ?? 0,
    qtdRecebidaTotal: (linha['qtd_recebida_total'] as num?)?.toInt() ?? 0,
  );

  final String pedidoId;
  final String numero;

  /// O código cru do banco — a tela traduz por [rotuloStatusPedido] e decide o
  /// que oferecer por [motivoIndisponivel].
  final String status;

  /// A data que a linha mostra: a do envio quando houve envio, a da criação
  /// enquanto o pedido é rascunho. **Vem da view**, no fuso da escola.
  final DateTime dataReferencia;

  final DateTime? dataEnvio;
  final String? fornecedor;
  final String? observacao;

  final int qtdItens;
  final int qtdPedidaTotal;

  /// Pode passar de [qtdPedidaTotal]: o recebimento com excedente é permitido à
  /// direção, e grampear o número faria o pedido dizer "15 de 15" com 17 na
  /// caixa.
  final int qtdRecebidaTotal;

  StatusPedido? get situacao => statusPedidoDe(status);
}

/// "3 itens" / "10 de 15 recebidos" — a segunda linha do wireframe §10.2.
///
/// O rascunho e o cancelado não falam de recebimento: um nunca foi pedido, o
/// outro não vem. Dizer "0 de 5 recebidos" num rascunho sugeriria uma espera
/// que não existe.
String resumoPedido(PedidoCompra pedido) {
  final itens = pedido.qtdItens == 1 ? '1 item' : '${pedido.qtdItens} itens';
  return switch (pedido.situacao) {
    StatusPedido.rascunho || StatusPedido.cancelado || null => itens,
    _ =>
      '$itens · ${pedido.qtdRecebidaTotal} de ${pedido.qtdPedidaTotal} '
          'recebidos',
  };
}

// ---------------------------------------------------------------------------
// O que cada estado permite — a metade "estado" da regra do design-system §5.7
// ---------------------------------------------------------------------------

/// As quatro ações da aba Pedidos. A metade "permissão" da regra (`compras.
/// editar`, `compras.receber`) é do `BotaoAcao`; aqui mora só o que o ESTADO
/// do pedido permite, e é o que vira motivo no botão desabilitado.
enum AcaoPedido { editar, enviar, receber, cancelar }

/// Nulo = a ação vale neste estado. Não nulo = o motivo, palavra por palavra,
/// para o tooltip do botão desabilitado (design-system §5.7: motivo é parte do
/// contrato, não um `onPressed: null` solto).
///
/// ⚠️ Isto **não** pré-verifica regra de negócio (card 2.6 decisão 2): quem
/// recusa é `fn_pedido_enviar`/`_cancelar`/`_receber`, dentro da transação. O
/// que está aqui existe para não oferecer o que vai falhar — e o texto é o
/// mesmo que o catálogo do card 2.7 §7.1 mostraria se a pessoa insistisse.
String? motivoIndisponivel(AcaoPedido acao, PedidoCompra pedido) {
  final situacao = pedido.situacao;
  return switch (acao) {
    AcaoPedido.editar || AcaoPedido.enviar =>
      situacao == StatusPedido.rascunho
          ? (acao == AcaoPedido.enviar && pedido.qtdItens == 0
                ? 'Um pedido sem item não pode ser enviado.'
                : null)
          : 'Só pedido em rascunho pode ser editado ou enviado.',
    AcaoPedido.receber =>
      situacao == StatusPedido.enviado || situacao == StatusPedido.parcial
          ? null
          : 'Este pedido não está aguardando recebimento.',
    AcaoPedido.cancelar =>
      situacao == StatusPedido.recebido || situacao == StatusPedido.cancelado
          ? 'Pedido já recebido ou cancelado não pode ser cancelado.'
          : null,
  };
}

// ---------------------------------------------------------------------------
// Item de pedido — uma linha de v_pedido_item
// ---------------------------------------------------------------------------

@immutable
class ItemPedido {
  const ItemPedido({
    required this.itemId,
    required this.pedidoId,
    required this.materialId,
    required this.metodoId,
    required this.codigo,
    required this.nome,
    required this.categoria,
    required this.qtdPedida,
    required this.qtdRecebida,
    required this.qtdPendente,
  });

  factory ItemPedido.deLinha(Map<String, dynamic> linha) => ItemPedido(
    itemId: '${linha['pedido_item_id']}',
    pedidoId: '${linha['pedido_id']}',
    materialId: '${linha['material_id']}',
    metodoId: '${linha['metodo_id']}',
    codigo: '${linha['codigo']}',
    nome: '${linha['nome']}',
    categoria: '${linha['categoria']}',
    qtdPedida: (linha['qtd_pedida'] as num).toInt(),
    qtdRecebida: (linha['qtd_recebida'] as num).toInt(),
    qtdPendente: (linha['qtd_pendente'] as num).toInt(),
  );

  final String itemId;
  final String pedidoId;
  final String materialId;
  final String metodoId;
  final String codigo;
  final String nome;
  final String categoria;

  final int qtdPedida;
  final int qtdRecebida;

  /// O que falta chegar, com **piso zero** — vem da view. Item recebido com
  /// excedente falta zero, e não `−2`.
  final int qtdPendente;

  String get rotulo => '$codigo $nome';

  /// Já chegou tudo (ou mais). É o que apaga o campo "receber" da linha.
  bool get completo => qtdRecebida >= qtdPedida;
}

/// O excedente é **fato**, não erro: só a direção consegue produzi-lo, e
/// escondê-lo faria o painel dizer "10 de 10" com 12 na prateleira.
bool recebidoAcimaDoPedido(ItemPedido item) =>
    item.qtdRecebida > item.qtdPedida;

// ---------------------------------------------------------------------------
// Filtro da aba Pedido sugerido — wireframe §10.1
// ---------------------------------------------------------------------------

bool _casaBusca(String busca, Iterable<String> campos) {
  final termo = busca.trim().toLowerCase();
  if (termo.isEmpty) return true;
  return campos.any((c) => c.toLowerCase().contains(termo));
}

@immutable
class FiltroSugerido {
  const FiltroSugerido({
    this.busca = '',
    this.metodoId,
    this.categoria,
    this.soSugeridos = true,
  });

  final String busca;
  final String? metodoId;
  final String? categoria;

  /// O "só sugerido > 0" do wireframe §10.1. Vem **ligado**, porque a pergunta
  /// da aba é "o que comprar agora" — e é **desligável**, porque a view devolve
  /// tudo e quem esconde é a tela (card 2.3 §2.3(h)): o material que acabou de
  /// zerar continua alcançável.
  final bool soSugeridos;

  /// Quantos filtros diferem do padrão — o `(n)` do botão "Filtrar" no mobile.
  /// `soSugeridos` conta quando está **desligado**, que é o desvio do padrão.
  int get ativos =>
      (busca.trim().isEmpty ? 0 : 1) +
      (metodoId == null ? 0 : 1) +
      (categoria == null ? 0 : 1) +
      (soSugeridos ? 0 : 1);

  FiltroSugerido copiar({
    String? busca,
    String? Function()? metodoId,
    String? Function()? categoria,
    bool? soSugeridos,
  }) => FiltroSugerido(
    busca: busca ?? this.busca,
    metodoId: metodoId == null ? this.metodoId : metodoId(),
    categoria: categoria == null ? this.categoria : categoria(),
    soSugeridos: soSugeridos ?? this.soSugeridos,
  );
}

List<LinhaSugerida> filtrarSugerido(
  List<LinhaSugerida> todas,
  FiltroSugerido filtro,
) => [
  for (final l in todas)
    if ((filtro.metodoId == null || l.metodoId == filtro.metodoId) &&
        (filtro.categoria == null || l.categoria == filtro.categoria) &&
        (!filtro.soSugeridos || l.qtdSugerida > 0) &&
        _casaBusca(filtro.busca, [l.codigo, l.nome]))
      l,
];

List<String> categoriasSugeridas(Iterable<LinhaSugerida> linhas) =>
    ({for (final l in linhas) l.categoria}.toList()..sort());

// ---------------------------------------------------------------------------
// Filtro da aba Pedidos
// ---------------------------------------------------------------------------

@immutable
class FiltroPedidos {
  const FiltroPedidos({this.busca = '', this.status});

  final String busca;

  /// Código cru (`RASCUNHO`, `ENVIADO`, …) ou nulo para todos.
  final String? status;

  int get ativos => (busca.trim().isEmpty ? 0 : 1) + (status == null ? 0 : 1);

  FiltroPedidos copiar({String? busca, String? Function()? status}) =>
      FiltroPedidos(
        busca: busca ?? this.busca,
        status: status == null ? this.status : status(),
      );
}

List<PedidoCompra> filtrarPedidos(
  List<PedidoCompra> todos,
  FiltroPedidos filtro,
) => [
  for (final p in todos)
    if ((filtro.status == null || p.status == filtro.status) &&
        _casaBusca(filtro.busca, [p.numero, p.fornecedor ?? '']))
      p,
];

// ---------------------------------------------------------------------------
// O rascunho que a aba "Pedido sugerido" monta
// ---------------------------------------------------------------------------

/// Um item do pedido a criar. Vira `[{"material_id":…,"qtd_pedida":…}]` para
/// `fn_pedido_criar` (card 6.5).
@immutable
class ItemNovo {
  const ItemNovo({required this.materialId, required this.quantidade});

  final String materialId;
  final int quantidade;

  Map<String, dynamic> paraJson() => {
    'material_id': materialId,
    'qtd_pedida': quantidade,
  };
}

/// As linhas que entram no `[Criar pedido com os sugeridos]`: as que a tela está
/// mostrando **e** têm sugestão maior que zero.
///
/// ⚠️ Parte das linhas exibidas, e não da lista inteira: com o filtro de método
/// ligado, o botão diz "criar pedido com os sugeridos" e o que está na frente da
/// pessoa é um método só. Montar o pedido com o que ela não vê é a mesma
/// surpresa que uma exclusão em massa sem confirmação.
List<ItemNovo> itensSugeridos(Iterable<LinhaSugerida> exibidas) => [
  for (final l in exibidas)
    if (l.qtdSugerida > 0)
      ItemNovo(materialId: l.materialId, quantidade: l.qtdSugerida),
];

// ---------------------------------------------------------------------------
// Textos de tela — docs/design-system.md §7.2 e §7.3, palavra por palavra
// ---------------------------------------------------------------------------

/// §7.2, linha "Compras → sugerido".
const vazioSugerido =
    'Nada a comprar agora: nenhum material com sugestão maior que zero.';

/// O mesmo painel com filtro ligado — o texto padrão das listas filtradas.
const vazioSugeridoFiltro = 'Nenhum material com esses filtros.';

/// §7.2, linha "Compras → pedidos".
const vazioPedidos = 'Nenhum pedido. Crie a partir do Pedido sugerido.';

const vazioPedidosFiltro = 'Nenhum pedido com esses filtros.';

/// O painel de um pedido sem item — o rascunho recém-criado a que ainda não se
/// acrescentou nada. Diz o que fazer, porque é a pergunta que ele produz.
const vazioItens =
    'Este pedido ainda não tem item. Acrescente um material antes de enviar.';

/// Sem pedido escolhido o painel não tem assunto.
const semPedidoSelecionado =
    'Escolha um pedido na lista para ver os itens e registrar o recebimento.';

/// Aviso de consequência do "Criar pedido" (design-system §5.4). Diz o que o
/// rascunho **não** faz, que é o que a conta do pedido sugerido depende.
const avisoCriarPedido =
    'O pedido nasce como rascunho e ainda não conta como compra a caminho: só '
    'depois de enviado ele desconta da sugestão. Dá para editar as quantidades '
    'antes de enviar.';

/// Aviso do envio: é o instante em que a conta muda.
const avisoEnviarPedido =
    'Depois de enviado, o pedido passa a descontar da sugestão de compra e as '
    'quantidades não podem mais ser alteradas.';

/// Aviso do recebimento parcial (wireframe §10.2: parcial é a regra).
const avisoReceber =
    'Informe o que chegou de cada item — pode ser menos que o pedido, e o '
    'restante continua a caminho. Cada linha vira uma entrada no estoque, e '
    'entrada de estoque não se apaga: para corrigir, use o estorno.';

/// A exceção de permissão do card 6.5, dita antes de a pessoa esbarrar nela.
const avisoExcedente =
    'Receber mais do que foi pedido é permitido só à direção.';

/// Confirmação destrutiva do cancelamento (design-system §5.8): a consequência
/// dita, e o botão nomeando a ação.
const avisoCancelarPedido =
    'O pedido não é apagado: ele fica no histórico como cancelado, com o motivo '
    'que você escrever, e deixa de descontar da sugestão de compra.';
