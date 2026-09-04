import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../compras/compras.dart';
import '../../compras/compras_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import '../../widgets/tabela_im360.dart';
import 'formularios.dart';
import 'painel_pedido.dart';

/// Tela 7 — Compras (docs/wireframes.md §10). Duas abas: o **pedido sugerido**,
/// que responde "o que comprar agora", e os **pedidos**, que respondem "o que
/// já está a caminho e o que chegou".
///
/// Rota: `materiais.ler + estoque.ler + alunos.ler + compras.ler`
/// (docs/permissoes-matriz.md §6, linha 7). É a única tela com perfil de fora
/// por decisão explícita: sem `compras.ler` a parcela pendente zeraria e o
/// sistema mandaria comprar de novo o que já está a caminho.
class TelaCompras extends StatelessWidget {
  const TelaCompras({super.key, this.pedidoId});

  /// `?pedido=<id>` — o mesmo desenho de `?material=` na tela 6: a lista abre
  /// já no pedido pedido. Hoje quem o usa é o próprio app, ao criar um rascunho
  /// a partir do sugerido.
  final String? pedidoId;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    // A aba Pedidos vira a inicial quando se chega com um pedido na URL: cair
    // no sugerido e ter de trocar de aba para ver o que se acabou de criar é o
    // atalho que não atalha.
    initialIndex: pedidoId == null ? 0 : 1,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Pedido sugerido'),
            Tab(text: 'Pedidos'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              const AbaSugerido(),
              AbaPedidos(pedidoId: pedidoId),
            ],
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Aba 1 — Pedido sugerido (wireframe §10.1)
// ---------------------------------------------------------------------------

/// A conta inteira em sete colunas, com **as parcelas ao lado do total**: saldo,
/// imediata, projetada, pendente e sugerido. O usuário confere a conta em vez de
/// acreditar nela (card 2.3 §2.3).
class AbaSugerido extends ConsumerStatefulWidget {
  const AbaSugerido({super.key});

  @override
  ConsumerState<AbaSugerido> createState() => _AbaSugeridoState();
}

class _AbaSugeridoState extends ConsumerState<AbaSugerido> {
  Future<void> _criar(
    BuildContext context,
    List<LinhaSugerida> exibidas,
  ) async {
    final itens = itensSugeridos(exibidas);
    final criado = await mostrarFormulario<String>(
      context,
      largura: larguraDetalhe,
      construtor: (_) => FormularioNovoPedido(linhas: exibidas, itens: itens),
    );
    if (criado == null || !context.mounted) return;
    // Um pedido novo muda a parcela pendente? Não: RASCUNHO não abate. Mas a
    // lista de pedidos mudou, e é para lá que a confirmação manda a pessoa.
    ref.read(versaoComprasProvider.notifier).incrementar();
    confirmarEfemero(context, 'Rascunho criado. Confira antes de enviar.');
    DefaultTabController.of(context).animateTo(1);
  }

  @override
  Widget build(BuildContext context) {
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final metodosPorId = {for (final m in metodos) m.id: m};
    final sugerido = ref.watch(sugeridoProvider);
    final filtro = ref.watch(filtroSugeridoProvider);
    final permissoes = ref.watch(permissoesProvider);

    final todas = sugerido.value ?? const <LinhaSugerida>[];
    final exibidas = filtrarSugerido(todas, filtro);
    final haSugestao = todas.any((l) => l.qtdSugerida > 0);

    return TabelaIm360<LinhaSugerida>(
      filtros: _FiltrosSugerido(
        filtro: filtro,
        metodos: metodos,
        categorias: categoriasSugeridas(todas),
      ),
      filtrosAtivos: filtro.ativos,
      acoes: [
        BotaoAcao(
          rotulo: 'Criar pedido com os sugeridos',
          icone: Icons.add_shopping_cart,
          exigePermissao: 'compras.criar',
          // Sem estado → visível e desabilitado COM o motivo
          // (design-system §5.7). Escondê-lo aqui esconderia também a razão.
          desabilitado: itensSugeridos(exibidas).isEmpty
              ? const DesabilitadoCom(
                  'Nenhum material com sugestão maior que zero na lista atual.',
                )
              : null,
          aoTocar: () => _criar(context, exibidas),
        ),
      ],
      colunas: [
        ColunaIm360(
          titulo: 'Código',
          texto: (l) => l.codigo,
          flex: 1,
          larguraMin: 90,
        ),
        ColunaIm360(
          titulo: 'Material',
          texto: (l) => l.nome,
          flex: 3,
          larguraMin: 180,
        ),
        ColunaIm360(
          titulo: 'Método',
          texto: (l) => metodosPorId[l.metodoId]?.nome ?? '—',
          prioridade: 3,
          larguraMin: 120,
        ),
        ColunaIm360(
          titulo: 'Saldo',
          texto: (l) => '${l.saldo}',
          numerica: true,
          flex: 1,
          larguraMin: 80,
        ),
        ColunaIm360(
          titulo: 'Mínimo',
          texto: (l) => '${l.estoqueMinimo}',
          numerica: true,
          prioridade: 3,
          flex: 1,
          larguraMin: 80,
        ),
        ColunaIm360(
          titulo: 'Imediata',
          texto: (l) => '${l.qtdImediata}',
          numerica: true,
          prioridade: 2,
          flex: 1,
          larguraMin: 90,
        ),
        // A coluna `†` do wireframe §10.1: é a primeira a sair na degradação,
        // porque é a que ainda vale zero. Ela existe desde o primeiro dia, e
        // mostrar `0` é honesto — esconder a coluna faria a soma exibida não
        // fechar com o total.
        ColunaIm360(
          titulo: 'Projetada',
          texto: (l) => '${l.qtdProjetada}',
          numerica: true,
          prioridade: 4,
          flex: 1,
          larguraMin: 90,
        ),
        ColunaIm360(
          titulo: 'A caminho',
          texto: (l) => '${l.qtdPedidaPendente}',
          numerica: true,
          prioridade: 2,
          flex: 1,
          larguraMin: 100,
        ),
        ColunaIm360(
          titulo: 'Sugerido',
          texto: (l) => '${l.qtdSugerida}',
          celula: (l) => _CelulaSugerida(linha: l),
          numerica: true,
          flex: 1,
          larguraMin: 100,
        ),
      ],
      // A conta não se refaz aqui: `qtd_sugerida` vem da view. A ordenação, sim
      // — maior sugestão primeiro, que é a ordem em que a compra se decide.
      linhas: sugerido.whenData(
        (_) => [...exibidas]
          ..sort((a, b) {
            final porSugestao = b.qtdSugerida.compareTo(a.qtdSugerida);
            return porSugestao != 0
                ? porSugestao
                : a.codigo.compareTo(b.codigo);
          }),
      ),
      tomDaLinha: (l) => l.qtdSugerida > 0 ? TomLinha.atencao : TomLinha.nenhum,
      cartao: (l) => CartaoIm360(
        titulo: l.nome,
        subtitulo: [
          l.codigo,
          metodosPorId[l.metodoId]?.nome ?? '—',
          l.categoria,
        ].join(' · '),
        apoio:
            'saldo ${l.saldo} · mín. ${l.estoqueMinimo} · '
            'imediata ${l.qtdImediata} · a caminho ${l.qtdPedidaPendente}',
        destaque: 'sugerido ${l.qtdSugerida}',
      ),
      // Dois vazios diferentes, e a diferença importa: "não há o que comprar" é
      // uma resposta; "seus filtros escondem tudo" é outra (design-system §7.2).
      estadoVazio: filtro.ativos > 0 || !haSugestao
          ? EstadoVazio(
              mensagem: haSugestao ? vazioSugeridoFiltro : vazioSugerido,
              icone: haSugestao
                  ? Icons.filter_alt_off_outlined
                  : Icons.check_circle_outline,
              rotuloAcao: filtro.ativos > 0 ? 'Limpar filtros' : null,
              aoAgir: ref.read(filtroSugeridoProvider.notifier).limpar,
            )
          : const EstadoVazio(
              mensagem: vazioSugerido,
              icone: Icons.check_circle_outline,
            ),
      aoTocarLinha: permissoes.contains('compras.criar')
          ? (l) => _criar(context, [l])
          : null,
      aoRepetir: ref.read(versaoComprasProvider.notifier).incrementar,
    );
  }
}

/// Busca, método, categoria e o chip "Só sugeridos" (design-system §5.3).
///
/// ⚠️ O chip vem **ligado** e é **desligável**: a view devolve tudo — inclusive
/// o material que acabou de zerar — e quem esconde é a tela (card 2.3 §2.3(h)).
class _FiltrosSugerido extends ConsumerStatefulWidget {
  const _FiltrosSugerido({
    required this.filtro,
    required this.metodos,
    required this.categorias,
  });

  final FiltroSugerido filtro;
  final List<Metodo> metodos;
  final List<String> categorias;

  @override
  ConsumerState<_FiltrosSugerido> createState() => _FiltrosSugeridoState();
}

class _FiltrosSugeridoState extends ConsumerState<_FiltrosSugerido> {
  late final _busca = TextEditingController(text: widget.filtro.busca);

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Limpar filtros" vem de fora (estado vazio): o campo acompanha.
    ref.listen(filtroSugeridoProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = widget.filtro;
    final controlador = ref.read(filtroSugeridoProvider.notifier);

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            controller: _busca,
            style: Tipografia.corpo,
            decoration: InputDecoration(
              labelText: 'Código ou material',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: filtro.busca.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          controlador.definir(filtro.copiar(busca: '')),
                    ),
            ),
            onChanged: (valor) =>
                controlador.definir(filtro.copiar(busca: valor)),
          ),
        ),
        DropdownMenu<String>(
          key: ValueKey('metodo-${filtro.metodoId}'),
          width: 180,
          label: const Text('Método'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.metodoId ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final metodo in widget.metodos)
              DropdownMenuEntry(value: metodo.id, label: metodo.nome),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              metodoId: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        DropdownMenu<String>(
          key: ValueKey('categoria-${filtro.categoria}'),
          width: 180,
          label: const Text('Categoria'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.categoria ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todas'),
            for (final categoria in widget.categorias)
              DropdownMenuEntry(value: categoria, label: categoria),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              categoria: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        FilterChip(
          label: const Text('Só sugeridos'),
          selected: filtro.soSugeridos,
          onSelected: (valor) =>
              controlador.definir(filtro.copiar(soSugeridos: valor)),
        ),
      ],
    );
  }
}

/// O número sugerido, em destaque quando há o que comprar.
///
/// ⚠️ Cor não é portadora única (design-system §8.2): o `Semantics` diz a
/// palavra, e o fundo tonal da linha é a segunda metade do par — quem enxerga só
/// o número continua lendo o número certo.
class _CelulaSugerida extends StatelessWidget {
  const _CelulaSugerida({required this.linha});

  final LinhaSugerida linha;

  @override
  Widget build(BuildContext context) {
    final comprar = linha.qtdSugerida > 0;
    return Semantics(
      label: comprar
          ? 'Sugerido ${linha.qtdSugerida}, comprar'
          : 'Sugerido 0, nada a comprar',
      excludeSemantics: true,
      child: Text(
        '${linha.qtdSugerida}',
        style: Tipografia.numero(Tipografia.corpoTabela)
            .copyWith(fontWeight: comprar ? FontWeight.w600 : null),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aba 2 — Pedidos (wireframe §10.2)
// ---------------------------------------------------------------------------

class AbaPedidos extends ConsumerStatefulWidget {
  const AbaPedidos({super.key, this.pedidoId});

  final String? pedidoId;

  @override
  ConsumerState<AbaPedidos> createState() => _AbaPedidosState();
}

class _AbaPedidosState extends ConsumerState<AbaPedidos> {
  /// O pedido do painel. Guarda o **id**, não a linha: a lista recarrega a cada
  /// recebimento, e segurar o objeto deixaria o cabeçalho mostrando o total de
  /// antes da chegada — o mesmo defeito do card 6.7.
  String? _selecionado;

  bool _abriuPeloUrl = false;

  @override
  void didUpdateWidget(AbaPedidos anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.pedidoId != widget.pedidoId) _abriuPeloUrl = false;
  }

  void _selecionar(BuildContext context, PedidoCompra pedido) {
    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
    setState(() => _selecionado = pedido.pedidoId);
    if (!mobile) return;
    // No mobile não há altura para lista e painel: o painel vira tela cheia
    // (design-system §5.4), como o de movimentações do card 6.7.
    mostrarFormulario<void>(
      context,
      largura: larguraDetalhe,
      construtor: (_) => _PainelMobile(pedidoId: pedido.pedidoId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = ref.watch(pedidosProvider);
    final filtro = ref.watch(filtroPedidosProvider);

    final pedido = widget.pedidoId;
    if (pedido != null && !_abriuPeloUrl && pedidos.hasValue) {
      for (final p in pedidos.requireValue) {
        if (p.pedidoId == pedido) {
          _abriuPeloUrl = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _selecionar(context, p);
          });
        }
      }
    }

    final todos = pedidos.value ?? const <PedidoCompra>[];
    final haPedido = todos.isNotEmpty;

    final tabela = TabelaIm360<PedidoCompra>(
      filtros: _FiltrosPedidos(filtro: filtro),
      filtrosAtivos: filtro.ativos,
      colunas: [
        ColunaIm360(
          titulo: 'Número',
          texto: (p) => p.numero,
          flex: 1,
          larguraMin: 110,
        ),
        ColunaIm360(
          titulo: 'Situação',
          texto: (p) => rotuloStatusPedido(p.status),
          flex: 1,
          larguraMin: 110,
        ),
        ColunaIm360(
          titulo: 'Data',
          texto: (p) => formatarData(p.dataReferencia),
          numerica: true,
          flex: 1,
          larguraMin: 110,
        ),
        ColunaIm360(
          titulo: 'Fornecedor',
          texto: (p) => p.fornecedor ?? '—',
          prioridade: 3,
          flex: 2,
          larguraMin: 160,
        ),
        ColunaIm360(
          titulo: 'Itens',
          texto: (p) => '${p.qtdItens}',
          numerica: true,
          prioridade: 2,
          flex: 1,
          larguraMin: 80,
        ),
        ColunaIm360(
          titulo: 'Recebido',
          texto: (p) => resumoRecebido(p),
          numerica: true,
          flex: 1,
          larguraMin: 120,
        ),
      ],
      linhas: pedidos.whenData((lista) => filtrarPedidos(lista, filtro)),
      linhaSelecionada: (p) => p.pedidoId == _selecionado,
      cartao: (p) => CartaoIm360(
        titulo: '${p.numero} · ${rotuloStatusPedido(p.status)}',
        subtitulo: [formatarData(p.dataReferencia), ?p.fornecedor].join(' · '),
        apoio: resumoPedido(p),
        destaque: resumoRecebido(p),
      ),
      estadoVazio: haPedido
          ? EstadoVazio(
              mensagem: vazioPedidosFiltro,
              icone: Icons.filter_alt_off_outlined,
              rotuloAcao: 'Limpar filtros',
              aoAgir: ref.read(filtroPedidosProvider.notifier).limpar,
            )
          : EstadoVazio(
              mensagem: vazioPedidos,
              icone: Icons.receipt_long_outlined,
              rotuloAcao: 'Ir ao pedido sugerido',
              aoAgir: () => DefaultTabController.of(context).animateTo(0),
            ),
      aoTocarLinha: (p) => _selecionar(context, p),
      aoRepetir: ref.read(versaoComprasProvider.notifier).incrementar,
    );

    final selecionado = _selecionadoDe(pedidos.value);
    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
    if (selecionado == null || mobile) return tabela;

    return Column(
      children: [
        Expanded(flex: 3, child: tabela),
        const Divider(height: 1),
        Expanded(
          flex: 2,
          child: PainelPedido(
            pedido: selecionado,
            aoFechar: () => setState(() => _selecionado = null),
          ),
        ),
      ],
    );
  }

  /// A linha atual do pedido escolhido — relida a cada build, para o cabeçalho
  /// do painel mostrar o status de depois do recebimento.
  PedidoCompra? _selecionadoDe(List<PedidoCompra>? lista) {
    final id = _selecionado;
    if (id == null || lista == null) return null;
    for (final p in lista) {
      if (p.pedidoId == id) return p;
    }
    return null;
  }
}

/// "12/15" na coluna, "—" onde recebimento não é assunto (rascunho, cancelado).
String resumoRecebido(PedidoCompra pedido) => switch (pedido.situacao) {
  StatusPedido.rascunho || StatusPedido.cancelado || null => '—',
  _ => '${pedido.qtdRecebidaTotal}/${pedido.qtdPedidaTotal}',
};

class _FiltrosPedidos extends ConsumerStatefulWidget {
  const _FiltrosPedidos({required this.filtro});

  final FiltroPedidos filtro;

  @override
  ConsumerState<_FiltrosPedidos> createState() => _FiltrosPedidosState();
}

class _FiltrosPedidosState extends ConsumerState<_FiltrosPedidos> {
  static const _status = [
    'RASCUNHO',
    'ENVIADO',
    'PARCIAL',
    'RECEBIDO',
    'CANCELADO',
  ];

  late final _busca = TextEditingController(text: widget.filtro.busca);

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(filtroPedidosProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = widget.filtro;
    final controlador = ref.read(filtroPedidosProvider.notifier);

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            controller: _busca,
            style: Tipografia.corpo,
            decoration: InputDecoration(
              labelText: 'Número ou fornecedor',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: filtro.busca.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          controlador.definir(filtro.copiar(busca: '')),
                    ),
            ),
            onChanged: (valor) =>
                controlador.definir(filtro.copiar(busca: valor)),
          ),
        ),
        DropdownMenu<String>(
          key: ValueKey('status-${filtro.status}'),
          width: 180,
          label: const Text('Situação'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.status ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todas'),
            for (final s in _status)
              DropdownMenuEntry(value: s, label: rotuloStatusPedido(s)),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              status: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
      ],
    );
  }
}

/// O painel do mobile: mesma coisa do desktop, em tela cheia.
class _PainelMobile extends ConsumerWidget {
  const _PainelMobile({required this.pedidoId});

  final String pedidoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lista = ref.watch(pedidosProvider).value ?? const <PedidoCompra>[];
    PedidoCompra? pedido;
    for (final p in lista) {
      if (p.pedidoId == pedidoId) pedido = p;
    }
    if (pedido == null) return const SizedBox.shrink();
    return PainelPedido(pedido: pedido);
  }
}
