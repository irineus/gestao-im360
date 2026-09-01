import 'package:flutter/material.dart';

import '../rotas/rotas.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// Placeholder das telas cujos cards ainda não chegaram.
///
/// Existe para que o shell, o menu e os guards de rota deste card sejam
/// exercitáveis de verdade — e diz **qual card** entrega cada tela, para o
/// placeholder não virar um destino permanente.
class TelaEmConstrucao extends StatelessWidget {
  const TelaEmConstrucao({super.key, required this.rota, required this.card});

  final Rota rota;
  final String card;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Dim.e24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rota.titulo, style: Tipografia.subtitulo),
          const SizedBox(height: Dim.e8),
          Text(
            'Tela do card $card.',
            style: Tipografia.apoio.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
