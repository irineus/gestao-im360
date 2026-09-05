/// Os seis formulários da tela 7 (docs/wireframes.md §10).
///
/// Todos usam `FormularioIm360`, e é ele que dá de graça o que o design-system
/// §5.4 exige: validação local **só de formato**, erro de regra como banner
/// traduzido pelo `codigo` (nunca pelo texto do banco), primário travando
/// reenvio, e "Fechar" no lugar de "Cancelar" quando não há escrita.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../compras/compras.dart';
import '../../compras/compras_provider.dart';
import '../../erros/erro_app.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/botoes.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';

// ---------------------------------------------------------------------------
// 1. Criar pedido com os sugeridos (wireframe §10.1)
// ---------------------------------------------------------------------------

/// O `[Criar pedido com os sugeridos]`: monta um RASCUNHO com as linhas
/// exibidas que têm sugestão maior que zero, **editável antes de enviar**.
///
/// As quantidades vêm preenchidas com a sugestão e são editáveis aqui, e não só
/// depois: quem faz a compra costuma arredondar para a caixa do fornecedor, e
/// obrigar a criar o rascunho para depois corrigir item a item é um passo a mais
/// em cada compra.
class FormularioNovoPedido extends ConsumerStatefulWidget {
  const FormularioNovoPedido({
    super.key,
    required this.linhas,
    required this.itens,
  });

  /// As linhas exibidas na aba — a fonte dos rótulos.
  final List<LinhaSugerida> linhas;

  /// O que entra no pedido: as exibidas com sugestão maior que zero.
  final List<ItemNovo> itens;

  @override
  ConsumerState<FormularioNovoPedido> createState() =>
      _FormularioNovoPedidoState();
}

class _FormularioNovoPedidoState extends ConsumerState<FormularioNovoPedido> {
  final _chave = GlobalKey<FormState>();
  final _fornecedor = TextEditingController();
  final _observacao = TextEditingController();
  late final Map<String, TextEditingController> _quantidades = {
    for (final i in widget.itens)
      i.materialId: TextEditingController(text: '${i.quantidade}'),
  };

  /// Materiais tirados do rascunho antes de criá-lo. Some da lista sem apagar
  /// nada: o pedido ainda não existe.
  final _fora = <String>{};

  @override
  void dispose() {
    _fornecedor.dispose();
    _observacao.dispose();
    for (final c in _quantidades.values) {
      c.dispose();
    }
    super.dispose();
  }

  LinhaSugerida? _linhaDe(String materialId) {
    for (final l in widget.linhas) {
      if (l.materialId == materialId) return l;
    }
    return null;
  }

  List<ItemNovo> get _selecionados => [
    for (final i in widget.itens)
      if (!_fora.contains(i.materialId))
        ItemNovo(
          materialId: i.materialId,
          quantidade:
              int.tryParse(_quantidades[i.materialId]!.text.trim()) ?? 0,
        ),
  ];

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final dentro = [
      for (final i in widget.itens)
        if (!_fora.contains(i.materialId)) i,
    ];

    return FormularioIm360(
      titulo: 'Criar pedido de compra',
      rotuloSalvar: 'Criar rascunho',
      chave: _chave,
      aviso: avisoCriarPedido,
      campos: [
        Text(
          dentro.length == 1
              ? '1 material no pedido'
              : '${dentro.length} materiais no pedido',
          style: Tipografia.rotulo,
        ),
        const SizedBox(height: Dim.e8),
        if (dentro.isEmpty)
          Text(
            'Nenhum material no pedido. Feche e escolha ao menos um.',
            style: Tipografia.corpoTabela.copyWith(
              color: cores.onSurfaceVariant,
            ),
          ),
        for (final item in dentro)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.e8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _linhaDe(item.materialId)?.rotulo ?? item.materialId,
                    style: Tipografia.corpoTabela,
                  ),
                ),
                const SizedBox(width: Dim.e8),
                SizedBox(
                  width: 96,
                  child: TextFormField(
                    controller: _quantidades[item.materialId],
                    style: Tipografia.corpo,
                    textAlign: TextAlign.end,
                    keyboardType: TextInputType.number,
                    inputFormatters: [somenteDigitos],
                    decoration: const InputDecoration(labelText: 'Qtd.'),
                    validator: validarInteiroPositivo,
                  ),
                ),
                IconButton(
                  tooltip: 'Tirar do pedido',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() => _fora.add(item.materialId)),
                ),
              ],
            ),
          ),
        const SizedBox(height: Dim.e8),
        TextFormField(
          controller: _fornecedor,
          style: Tipografia.corpo,
          decoration: const InputDecoration(
            labelText: 'Fornecedor',
            helperText: 'Opcional — aparece na lista de pedidos.',
          ),
        ),
        const SizedBox(height: Dim.e12),
        TextFormField(
          controller: _observacao,
          style: Tipografia.corpo,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Observação'),
        ),
      ],
      legendaObrigatorio: false,
      aoSalvar: dentro.isEmpty
          ? null
          : () async {
              final id = await ref
                  .read(comprasRepositorioProvider)
                  .criar(
                    _selecionados,
                    fornecedor: _texto(_fornecedor),
                    observacao: _texto(_observacao),
                  );
              return id;
            },
    );
  }
}

String? _texto(TextEditingController controlador) {
  final valor = controlador.text.trim();
  return valor.isEmpty ? null : valor;
}

// ---------------------------------------------------------------------------
// 2. Dados do pedido — fornecedor e observação de um rascunho
// ---------------------------------------------------------------------------

class FormularioDadosPedido extends ConsumerStatefulWidget {
  const FormularioDadosPedido({super.key, required this.pedido});

  final PedidoCompra pedido;

  @override
  ConsumerState<FormularioDadosPedido> createState() =>
      _FormularioDadosPedidoState();
}

class _FormularioDadosPedidoState extends ConsumerState<FormularioDadosPedido> {
  final _chave = GlobalKey<FormState>();
  late final _fornecedor = TextEditingController(
    text: widget.pedido.fornecedor ?? '',
  );
  late final _observacao = TextEditingController(
    text: widget.pedido.observacao ?? '',
  );

  @override
  void dispose() {
    _fornecedor.dispose();
    _observacao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final podeEditar = ref.watch(permissoesProvider).contains('compras.editar');
    return FormularioIm360(
      titulo: 'Pedido ${widget.pedido.numero}',
      chave: _chave,
      somenteLeitura: !podeEditar,
      legendaObrigatorio: false,
      campos: [
        TextFormField(
          controller: _fornecedor,
          style: Tipografia.corpo,
          readOnly: !podeEditar,
          decoration: const InputDecoration(labelText: 'Fornecedor'),
        ),
        const SizedBox(height: Dim.e12),
        TextFormField(
          controller: _observacao,
          style: Tipografia.corpo,
          readOnly: !podeEditar,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Observação'),
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(comprasRepositorioProvider)
            .editarPedido(
              widget.pedido.pedidoId,
              fornecedor: _texto(_fornecedor),
              observacao: _texto(_observacao),
            );
        return 'salvo';
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Enviar — o instante em que a conta muda
// ---------------------------------------------------------------------------

/// Enviar não é mudança de rótulo: é quando o pedido passa a descontar da
/// sugestão de compra e as quantidades param de poder mudar. Por isso é
/// confirmação com a consequência dita (design-system §5.8), e não um clique
/// direto.
class FormularioEnviarPedido extends ConsumerStatefulWidget {
  const FormularioEnviarPedido({super.key, required this.pedido});

  final PedidoCompra pedido;

  @override
  ConsumerState<FormularioEnviarPedido> createState() =>
      _FormularioEnviarPedidoState();
}

class _FormularioEnviarPedidoState
    extends ConsumerState<FormularioEnviarPedido> {
  final _chave = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) => FormularioIm360(
    titulo: 'Enviar o pedido ${widget.pedido.numero}',
    rotuloSalvar: 'Enviar pedido',
    chave: _chave,
    aviso: avisoEnviarPedido,
    legendaObrigatorio: false,
    campos: [Text(resumoPedido(widget.pedido), style: Tipografia.corpoTabela)],
    aoSalvar: () async {
      await ref.read(comprasRepositorioProvider).enviar(widget.pedido.pedidoId);
      return true;
    },
  );
}

// ---------------------------------------------------------------------------
// 4. Cancelar — motivo obrigatório, e o pedido não some
// ---------------------------------------------------------------------------

class FormularioCancelarPedido extends ConsumerStatefulWidget {
  const FormularioCancelarPedido({super.key, required this.pedido});

  final PedidoCompra pedido;

  @override
  ConsumerState<FormularioCancelarPedido> createState() =>
      _FormularioCancelarPedidoState();
}

class _FormularioCancelarPedidoState
    extends ConsumerState<FormularioCancelarPedido> {
  final _chave = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  bool _realceMotivo = false;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormularioIm360(
    titulo: 'Cancelar o pedido ${widget.pedido.numero}',
    // O primário nomeia a ação e é vermelho: um "Salvar" na cor de ação
    // lê-se igual a qualquer outro salvar (design-system §5.7 e §5.8).
    rotuloSalvar: 'Cancelar pedido',
    nivelSalvar: NivelBotao.destrutivo,
    chave: _chave,
    aviso: avisoCancelarPedido,
    campos: [
      TextFormField(
        controller: _motivo,
        style: Tipografia.corpo,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: 'Motivo *',
          helperText: 'Fica no histórico do pedido, junto da observação.',
          errorText: _realceMotivo ? 'Informe o motivo para continuar.' : null,
        ),
        validator: validarObrigatorio,
      ),
    ],
    aoErro: (erro) =>
        setState(() => _realceMotivo = erro.codigo == 'MOTIVO_OBRIGATORIO'),
    aoSalvar: () async {
      await ref
          .read(comprasRepositorioProvider)
          .cancelar(widget.pedido.pedidoId, motivo: _motivo.text);
      return _motivo.text;
    },
  );
}

// ---------------------------------------------------------------------------
// 5. Receber — parcial por padrão (wireframe §10.2)
// ---------------------------------------------------------------------------

/// ⚠️ **Os campos vêm VAZIOS, e não preenchidos com o que falta.** Preencher
/// seria oferecer "recebi tudo" como resposta pronta a uma conferência que é o
/// ponto do formulário — e cada linha vira ENTRADA de estoque, que é imutável.
/// O que falta fica escrito ao lado, como apoio.
///
/// A tela **não** pré-verifica o excedente (card 2.6 decisão 2): o campo aceita
/// qualquer número, e quem recusa é `fn_pedido_receber` — com
/// `RECEBIMENTO_EXCEDE_PEDIDO` traduzido pelo catálogo do card 2.7 §7.1 para
/// quem não tem `compras.receber_excedente`. O aviso diz isso antes, para a
/// recusa não ser surpresa.
class FormularioReceber extends ConsumerStatefulWidget {
  const FormularioReceber({super.key, required this.pedido});

  final PedidoCompra pedido;

  @override
  ConsumerState<FormularioReceber> createState() => _FormularioReceberState();
}

class _FormularioReceberState extends ConsumerState<FormularioReceber> {
  final _chave = GlobalKey<FormState>();
  final _campos = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _campo(String itemId) =>
      _campos.putIfAbsent(itemId, TextEditingController.new);

  Map<String, int> get _informado => {
    for (final e in _campos.entries)
      if ((int.tryParse(e.value.text.trim()) ?? 0) > 0)
        e.key: int.parse(e.value.text.trim()),
  };

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final itens = ref.watch(itensDoPedidoProvider(widget.pedido.pedidoId));
    final lista = itens.value ?? const <ItemPedido>[];
    final podeExcedente = ref
        .watch(permissoesProvider)
        .contains('compras.receber_excedente');

    // ⚠️ `hasError` ANTES de tudo (design-system §5.6, card 5.11). Com o
    // `itens.value ?? []` de antes, a leitura que falhava abria o formulário
    // VAZIO e "Confirmar recebimento" respondia "Informe quanto chegou de ao
    // menos um item" — que é a mensagem errada para "a lista não carregou"
    // (item B1).
    if (itens.hasError) {
      return FormularioIm360(
        titulo: 'Receber o pedido ${widget.pedido.numero}',
        rotuloSalvar: 'Confirmar recebimento',
        chave: _chave,
        somenteLeitura: true,
        legendaObrigatorio: false,
        campos: [
          EstadoErro(
            mensagem: erroItensDoPedido,
            aoRepetir: ref.read(versaoComprasProvider.notifier).incrementar,
          ),
        ],
      );
    }

    return FormularioIm360(
      titulo: 'Receber o pedido ${widget.pedido.numero}',
      rotuloSalvar: 'Confirmar recebimento',
      chave: _chave,
      aviso: avisoReceber,
      legendaObrigatorio: false,
      campos: [
        if (itens.isLoading && !itens.hasValue)
          const EstadoCarregando(linhas: 3),
        for (final item in lista)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.e8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.rotulo, style: Tipografia.corpoTabela),
                      Text(
                        item.completo
                            ? 'pedido ${item.qtdPedida} · recebido '
                                  '${item.qtdRecebida} · completo'
                            : 'pedido ${item.qtdPedida} · recebido '
                                  '${item.qtdRecebida} · faltam '
                                  '${item.qtdPendente}',
                        style: Tipografia.numero(Tipografia.apoio)
                            .copyWith(color: cores.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Dim.e8),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _campo(item.itemId),
                    style: Tipografia.corpo,
                    textAlign: TextAlign.end,
                    keyboardType: TextInputType.number,
                    inputFormatters: [somenteDigitos],
                    decoration: const InputDecoration(labelText: 'Chegou'),
                  ),
                ),
              ],
            ),
          ),
        if (!podeExcedente) ...[
          const SizedBox(height: Dim.e8),
          const AvisoTonal(mensagem: avisoExcedente),
        ],
      ],
      aoSalvar: () async {
        final informado = _informado;
        // Recusa local de FORMATO, não de regra: sem nenhum número não há o que
        // enviar, e `PEDIDO_SEM_ITEM` do banco diria a mesma coisa depois de uma
        // ida ao servidor.
        if (informado.isEmpty) {
          throw const ErroApp(
            mensagem: 'Informe quanto chegou de ao menos um item.',
            traduzido: true,
          );
        }
        final entradas = await ref
            .read(comprasRepositorioProvider)
            .receber(widget.pedido.pedidoId, informado);
        return entradas == 1
            ? 'Recebimento registrado: 1 entrada no estoque.'
            : 'Recebimento registrado: $entradas entradas no estoque.';
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Item de rascunho — acrescentar, mudar a quantidade, remover
// ---------------------------------------------------------------------------

/// ⚠️ **Escrita direta em `pedido_item`, e não por função** — é a decisão do
/// card 2.4 §3.5: `compras.editar` e `compras.excluir` foram desenhados como
/// política de tabela, e a regra que sobra ("só em rascunho") mora nos triggers
/// `tg_pedido_item_edicao` e `tg_pedido_item_exclusao_valida`. A tela não a
/// repete: submete e traduz `PEDIDO_NAO_RASCUNHO` pelo catálogo.
class FormularioItemPedido extends ConsumerStatefulWidget {
  const FormularioItemPedido({super.key, required this.pedido, this.item});

  final PedidoCompra pedido;

  /// Nulo = item novo.
  final ItemPedido? item;

  @override
  ConsumerState<FormularioItemPedido> createState() =>
      _FormularioItemPedidoState();
}

class _FormularioItemPedidoState extends ConsumerState<FormularioItemPedido> {
  final _chave = GlobalKey<FormState>();
  late final _quantidade = TextEditingController(
    text: widget.item == null ? '' : '${widget.item!.qtdPedida}',
  );
  String? _materialId;
  bool _realceQuantidade = false;

  @override
  void dispose() {
    _quantidade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    // A lista de materiais sai de `v_pedido_sugerido`, que é o catálogo ATIVO
    // com saldo e sugestão — a mesma leitura que a aba já carregou. Trazer o
    // catálogo inteiro por baixo seria uma consulta a mais para o mesmo nome.
    final materiais = ref.watch(sugeridoProvider).value ?? const [];
    final podeExcluir = ref
        .watch(permissoesProvider)
        .contains('compras.excluir');

    return FormularioIm360(
      titulo: item == null ? 'Acrescentar item' : 'Item ${item.codigo}',
      rotuloSalvar: item == null ? 'Acrescentar' : 'Salvar',
      chave: _chave,
      campos: [
        if (item == null)
          DropdownButtonFormField<String>(
            initialValue: _materialId,
            isExpanded: true,
            style: Tipografia.corpo,
            decoration: const InputDecoration(labelText: 'Material *'),
            items: [
              for (final m in materiais)
                DropdownMenuItem(value: m.materialId, child: Text(m.rotulo)),
            ],
            onChanged: (valor) => setState(() => _materialId = valor),
            validator: (valor) => valor == null ? 'Escolha o material.' : null,
          )
        else
          Text(item.rotulo, style: Tipografia.corpoTabela),
        const SizedBox(height: Dim.e12),
        TextFormField(
          controller: _quantidade,
          style: Tipografia.corpo,
          keyboardType: TextInputType.number,
          inputFormatters: [somenteDigitos],
          decoration: InputDecoration(
            labelText: 'Quantidade *',
            errorText: _realceQuantidade
                ? 'Informe uma quantidade válida.'
                : null,
          ),
          validator: validarInteiroPositivo,
        ),
      ],
      acoes: [
        if (item != null)
          AcaoFormulario(
            rotulo: 'Remover do pedido',
            nivel: NivelBotao.destrutivo,
            exigePermissao: 'compras.excluir',
            confirmacao: ConfirmacaoAcao(
              titulo: 'Remover ${item.codigo} do pedido?',
              mensagem:
                  'O item sai do rascunho e a quantidade dele deixa de fazer '
                  'parte da compra. Isso não mexe no estoque.',
              rotulo: 'Remover do pedido',
            ),
            executar: () async {
              await ref
                  .read(comprasRepositorioProvider)
                  .removerItem(item.itemId);
              return 'Item removido do pedido.';
            },
          ),
      ],
      // Sem `compras.excluir` a pessoa ainda vê o item; o que não aparece é o
      // botão (design-system §5.7). O `somenteLeitura` não entra aqui porque
      // quem chega a este formulário tem `compras.editar` — é ele que guarda o
      // botão que o abre.
      legendaObrigatorio: podeExcluir || item == null,
      aoErro: (erro) => setState(
        () => _realceQuantidade = erro.codigo == 'QUANTIDADE_INVALIDA',
      ),
      aoSalvar: () async {
        final quantidade = int.parse(_quantidade.text.trim());
        final repositorio = ref.read(comprasRepositorioProvider);
        if (item == null) {
          await repositorio.acrescentarItem(
            widget.pedido.pedidoId,
            _materialId!,
            quantidade,
          );
          return 'Item acrescentado ao pedido.';
        }
        await repositorio.definirQuantidade(item.itemId, quantidade);
        return 'Quantidade salva.';
      },
    );
  }
}
