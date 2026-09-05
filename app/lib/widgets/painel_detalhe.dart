import 'package:flutter/material.dart';

import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// Largura do painel de detalhe — mais largo que um formulário, porque a
/// lista de dentro tem código e nome lado a lado.
const larguraDetalhe = 760.0;

/// Cabeçalho (título, subtítulo, ações, fechar) e corpo rolável de um painel
/// de detalhe aberto por [mostrarFormulario]. Nasceu nos painéis de curso e
/// combo (card 4.4) e passou para cá no card 4.5, com o painel da sala.
class PainelDetalhe extends StatelessWidget {
  const PainelDetalhe({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.acoes,
    required this.filho,
  });

  final String titulo;
  final String subtitulo;
  final List<Widget> acoes;
  final Widget filho;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Dim.e24, Dim.e16, Dim.e12, Dim.e8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: Tipografia.subtitulo),
                    Text(
                      subtitulo,
                      style: Tipografia.apoio.copyWith(
                        color: cores.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              for (final acao in acoes) ...[
                acao,
                const SizedBox(width: Dim.e8),
              ],
              IconButton(
                tooltip: 'Fechar',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Dim.e24),
            child: filho,
          ),
        ),
      ],
    );
  }
}

/// Título e ações de um painel: lado a lado onde há largura, **empilhados** no
/// celular.
///
/// ⚠️ Uma `Row` dá largura infinita ao filho não flexível: o `Wrap` das ações
/// não tinha onde quebrar e o cabeçalho estourava 80 px à direita em 390 px
/// (item H6). Empilhar é o que o design-system §3 já manda para a faixa mobile.
class CabecalhoDePainel extends StatelessWidget {
  const CabecalhoDePainel({
    super.key,
    required this.titulo,
    required this.acoes,
  });

  final Widget titulo;
  final Widget acoes;

  @override
  Widget build(BuildContext context) {
    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [titulo, acoes],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titulo),
        acoes,
      ],
    );
  }
}

/// Rótulo em cima, valor embaixo — o par que um painel de detalhe repete
/// ("Descrição", "Referência", "Aberta desde").
///
/// Nasceu na central de pendências (card 5.8) e veio para cá na revisão da
/// fase 05: é genérico, e o painel da pendência já o importava de uma tela.
class LinhaDetalhe extends StatelessWidget {
  const LinhaDetalhe({super.key, required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dim.e8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          ),
          Text(valor, style: Tipografia.corpo),
        ],
      ),
    );
  }
}

/// Título de uma seção do painel, com a linha de apoio que diz o que a seção
/// significa (a ordem é a da trilha; a capacidade conta os PCs operacionais).
class TituloSecao extends StatelessWidget {
  const TituloSecao({
    super.key,
    required this.texto,
    this.apoio,
    this.maxLinhasApoio,
  });

  /// Teto de linhas da linha de apoio, com elipse.
  ///
  /// ⚠️ Existe porque o cabeçalho do painel de pedido tem **altura de painel**
  /// (2/5 da tela, card 6.8) e o apoio crescia sem limite: com um rótulo de
  /// botão mais largo ao lado, o texto ganhou uma linha e o painel estourou em
  /// 12 px, engolindo a lista de itens. Nulo = sem limite, que é o caso de quem
  /// mora dentro de uma coluna rolável.
  final int? maxLinhasApoio;

  /// A linha de apoio. **Opcional** desde a revisão das telas 06/07: enquanto o
  /// conteúdo da seção carrega ou falha não há contagem a dar, e um "0
  /// módulos" ali seria um número afirmado sem leitura (item A3).
  final String? apoio;

  final String texto;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(texto, style: Tipografia.rotulo),
      if (apoio != null)
        Text(
          apoio!,
          maxLines: maxLinhasApoio,
          overflow: maxLinhasApoio == null
              ? TextOverflow.clip
              : TextOverflow.ellipsis,
          style: Tipografia.apoio.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      const SizedBox(height: Dim.e8),
    ],
  );
}
