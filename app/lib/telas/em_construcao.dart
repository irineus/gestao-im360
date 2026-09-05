import 'package:flutter/material.dart';

import '../rotas/rotas.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// Placeholder das telas cujos cards ainda não chegaram.
///
/// Existe para que o shell, o menu e os guards de rota sejam exercitáveis de
/// verdade.
///
/// ⚠️ Dizia "Tela do card 8.5." — o número do card do board **na tela**, que é
/// vocabulário de quem escreveu o sistema e não de quem o usa (item C1). Qual
/// card entrega cada tela continua registrado em `_cardDaRota`, no roteador,
/// que é onde a informação serve.
class TelaEmConstrucao extends StatelessWidget {
  const TelaEmConstrucao({super.key, required this.rota});

  final Rota rota;

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
            'Esta tela chega numa próxima versão.',
            style: Tipografia.apoio.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
