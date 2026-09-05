import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../compras/compras.dart';
import '../../compras/compras_provider.dart';
import '../../erros/erro_app.dart';
import '../../theme/cores.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import 'formularios.dart';

/// O painel de um pedido (docs/wireframes.md §10.2): os itens, o que já chegou
/// de cada um e as quatro ações do ciclo — editar, enviar, receber e cancelar.
///
/// ⚠️ **As duas metades da regra de exibição do design-system §5.7 estão
/// separadas de propósito.** A permissão vai no `exigePermissao` do `BotaoAcao`
/// (sem ela o botão **não é renderizado**); o ESTADO do pedido vai no
/// `desabilitado`, com o motivo obrigatório em tooltip — "Só pedido em rascunho
/// pode ser editado ou enviado" é informação, e esconder o botão a esconderia.
///
/// ⚠️ **A tela não pré-verifica regra de negócio** (card 2.6 decisão 2): quem
/// recusa é `fn_pedido_enviar`/`_cancelar`/`_receber`, dentro da transação e com
/// o advisory lock por pedido. O `desabilitado` existe para não oferecer o que
/// vai falhar, e não para decidir no lugar do banco.
class PainelPedido extends ConsumerWidget {
  const PainelPedido({super.key, required this.pedido, this.aoFechar});

  final PedidoCompra pedido;

  /// Fechar o painel. Nulo no mobile, onde quem fecha é o próprio diálogo.
  final VoidCallback? aoFechar;

  Future<void> _enviar(BuildContext context, WidgetRef ref) async {
    final confirmou = await mostrarFormulario<bool>(
      context,
      construtor: (_) => FormularioEnviarPedido(pedido: pedido),
    );
    if (confirmou != true || !context.mounted) return;
    ref.read(versaoComprasProvider.notifier).incrementar();
    confirmarEfemero(context, 'Pedido ${pedido.numero} enviado.');
  }

  Future<void> _cancelar(BuildContext context, WidgetRef ref) async {
    final motivo = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioCancelarPedido(pedido: pedido),
    );
    if (motivo == null || !context.mounted) return;
    ref.read(versaoComprasProvider.notifier).incrementar();
    confirmarEfemero(context, 'Pedido ${pedido.numero} cancelado.');
  }

  Future<void> _receber(BuildContext context, WidgetRef ref) async {
    final resultado = await mostrarFormulario<String>(
      context,
      largura: larguraDetalhe,
      construtor: (_) => FormularioReceber(pedido: pedido),
    );
    if (resultado == null || !context.mounted) return;
    // ⚠️ Recebimento move as DUAS versões: `fn_pedido_receber` grava ENTRADA em
    //    `movimento_estoque` na mesma transação, e sem isto a tela de Materiais
    //    continuaria mostrando o saldo de antes da chegada.
    invalidarComprasEEstoque(ref);
    confirmarEfemero(context, resultado);
  }

  Future<void> _editarDados(BuildContext context, WidgetRef ref) async {
    final salvo = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioDadosPedido(pedido: pedido),
    );
    if (salvo == null || !context.mounted) return;
    ref.read(versaoComprasProvider.notifier).incrementar();
    confirmarEfemero(context, 'Pedido salvo.');
  }

  Future<void> _item(
    BuildContext context,
    WidgetRef ref, {
    ItemPedido? item,
  }) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioItemPedido(pedido: pedido, item: item),
    );
    if (resultado == null || !context.mounted) return;
    ref.read(versaoComprasProvider.notifier).incrementar();
    confirmarEfemero(context, resultado);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final itens = ref.watch(itensDoPedidoProvider(pedido.pedidoId));
    final rascunho = pedido.situacao == StatusPedido.rascunho;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Dim.e16, Dim.e12, Dim.e16, Dim.e8),
          // Lado a lado onde há largura, empilhados no celular (item H6).
          child: CabecalhoDePainel(
            titulo: TituloSecao(
              texto:
                  'Pedido ${pedido.numero} · '
                  '${rotuloStatusPedido(pedido.status)}',
              apoio: _apoio(pedido),
              // O cabeçalho do painel tem altura de painel: apoio sem teto
              // rouba a lista de itens e estoura (ver `maxLinhasApoio`).
              maxLinhasApoio: 2,
            ),
            acoes: Wrap(
              spacing: Dim.e8,
              runSpacing: Dim.e8,
              children: [
                BotaoAcao(
                  // "Dados" é rótulo opaco ao lado de quatro ações; o verbo
                  // diz o que acontece, como o "Editar material / Ver
                  // cadastro" da tela 6 (item C4).
                  //
                  // ⚠️ Divergência do item C4, registrada: ele previa também
                  // um "Ver dados" para o modo somente leitura, e este painel
                  // NÃO tem esse estado — fora do rascunho o botão fica
                  // desabilitado com o motivo, e não abre formulário nenhum.
                  // Um "Ver dados" desabilitado prometeria uma leitura que
                  // não existe.
                  rotulo: 'Editar dados',
                  nivel: NivelBotao.terciario,
                  exigePermissao: 'compras.editar',
                  desabilitado: _motivo(AcaoPedido.editar),
                  aoTocar: () => _editarDados(context, ref),
                ),
                BotaoAcao(
                  rotulo: 'Acrescentar item',
                  icone: Icons.add,
                  nivel: NivelBotao.secundario,
                  exigePermissao: 'compras.editar',
                  desabilitado: _motivo(AcaoPedido.editar),
                  aoTocar: () => _item(context, ref),
                ),
                BotaoAcao(
                  rotulo: 'Cancelar pedido',
                  nivel: NivelBotao.destrutivo,
                  exigePermissao: 'compras.editar',
                  desabilitado: _motivo(AcaoPedido.cancelar),
                  aoTocar: () => _cancelar(context, ref),
                ),
                BotaoAcao(
                  rotulo: 'Enviar',
                  icone: Icons.outbox_outlined,
                  exigePermissao: 'compras.editar',
                  desabilitado: _motivo(AcaoPedido.enviar),
                  aoTocar: () => _enviar(context, ref),
                ),
                BotaoAcao(
                  rotulo: 'Receber',
                  icone: Icons.inventory_outlined,
                  exigePermissao: 'compras.receber',
                  desabilitado: _motivo(AcaoPedido.receber),
                  aoTocar: () => _receber(context, ref),
                ),
                if (aoFechar != null)
                  IconButton(
                    tooltip: 'Fechar pedido',
                    icon: const Icon(Icons.close),
                    onPressed: aoFechar,
                  ),
              ],
            ),
          ),
        ),
        if (pedido.observacao != null && pedido.observacao!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Dim.e16, 0, Dim.e16, Dim.e8),
            child: Text(
              pedido.observacao!,
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            ),
          ),
        Expanded(
          child: itens.when(
            loading: () => const EstadoCarregando(linhas: 4),
            error: (erro, _) {
              final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
              return EstadoErro(
                mensagem: traduzido.mensagem,
                codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
                aoRepetir: ref.read(versaoComprasProvider.notifier).incrementar,
              );
            },
            data: (lista) => lista.isEmpty
                ? EstadoVazio(
                    mensagem: vazioItens,
                    icone: Icons.playlist_add,
                    rotuloAcao: rascunho ? 'Acrescentar item' : null,
                    aoAgir: () => _item(context, ref),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      Dim.e16,
                      0,
                      Dim.e16,
                      Dim.e16,
                    ),
                    itemCount: lista.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: cores.outlineVariant),
                    itemBuilder: (context, i) => _LinhaItem(
                      item: lista[i],
                      rascunho: rascunho,
                      aoEditar: () => _item(context, ref, item: lista[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  DesabilitadoCom? _motivo(AcaoPedido acao) {
    final motivo = motivoIndisponivel(acao, pedido);
    return motivo == null ? null : DesabilitadoCom(motivo);
  }
}

String _apoio(PedidoCompra pedido) {
  final quando = pedido.dataEnvio == null
      ? 'criado em ${formatarData(pedido.dataReferencia)}'
      : 'enviado em ${formatarData(pedido.dataEnvio!)}';
  return [?pedido.fornecedor, quando, resumoPedido(pedido)].join(' · ');
}

/// Uma linha do painel: material, pedido, recebido — e, no rascunho, a edição.
///
/// ⚠️ O excedente é **dito**, não escondido: "12 de 10" com a palavra ao lado.
/// Só a direção consegue produzi-lo, e um painel que grampeasse o número diria
/// "10 de 10" com 12 exemplares na prateleira (card 6.5).
class _LinhaItem extends StatelessWidget {
  const _LinhaItem({
    required this.item,
    required this.rascunho,
    required this.aoEditar,
  });

  final ItemPedido item;
  final bool rascunho;
  final VoidCallback aoEditar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final excedente = recebidoAcimaDoPedido(item);
    final situacao = rascunho
        ? 'pedido ${item.qtdPedida}'
        : excedente
        ? 'recebido ${item.qtdRecebida} de ${item.qtdPedida} · acima do pedido'
        : item.completo
        ? 'recebido ${item.qtdRecebida} de ${item.qtdPedida} · completo'
        : 'recebido ${item.qtdRecebida} de ${item.qtdPedida} · '
              'faltam ${item.qtdPendente}';

    // ⚠️ O `excludeSemantics` cobria a linha inteira, e o "Editar item" que
    // mora dentro dela deixava de existir para leitor de tela e para o foco
    // (item A5, a mesma correção da linha da trilha). Agora ele cobre só o
    // bloco de texto.
    final descricao = MergeSemantics(
      child: Semantics(
        label: '${item.rotulo}, $situacao',
        excludeSemantics: true,
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(item.codigo, style: Tipografia.corpoTabela),
            ),
            Expanded(child: Text(item.nome, style: Tipografia.corpoTabela)),
            const SizedBox(width: Dim.e12),
            if (excedente) ...[
              Icon(
                Icons.warning_amber_outlined,
                size: 16,
                color: Cores.atencao,
              ),
              const SizedBox(width: Dim.e4),
            ],
            Text(
              situacao,
              style: Tipografia.numero(Tipografia.apoio).copyWith(
                color: excedente ? Cores.atencao : cores.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      constraints: const BoxConstraints(minHeight: Dim.alvoMobile),
      padding: const EdgeInsets.symmetric(vertical: Dim.e8),
      child: Row(
        children: [
          Expanded(child: descricao),
          if (rascunho) ...[
            const SizedBox(width: Dim.e8),
            // Sem guarda de permissão aqui, e é a mesma exceção do card 6.7:
            // o formulário abre em leitura para quem não pode escrever, e é
            // ele que decide se há "Salvar" e "Remover".
            IconButton(
              tooltip: 'Editar item',
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: aoEditar,
            ),
          ],
        ],
      ),
    );
  }
}
