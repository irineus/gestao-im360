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

/// Título de uma seção do painel, com a linha de apoio que diz o que a seção
/// significa (a ordem é a da trilha; a capacidade conta os PCs operacionais).
class TituloSecao extends StatelessWidget {
  const TituloSecao({super.key, required this.texto, required this.apoio});

  final String texto;
  final String apoio;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(texto, style: Tipografia.rotulo),
      Text(
        apoio,
        style: Tipografia.apoio.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: Dim.e8),
    ],
  );
}
