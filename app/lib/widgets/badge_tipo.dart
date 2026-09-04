import 'package:flutter/material.dart';

import '../theme/cores.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// Badge do tipo na turma — **contorno** de 1,5 px e fundo transparente
/// (design-system §5.1 e §2.4, card 5.7).
///
/// A forma é o que separa os dois vocabulários (card 1.9 §6): status do aluno é
/// preenchido tonal (`BadgeStatus`), tipo na turma é contorno, e as duas nunca
/// se misturam — é assim que a distinção sobrevive a P&B e a daltonismo, mesmo
/// numa tela onde só uma delas aparece.
///
/// Tipo fora dos quatro do `check` (não deveria acontecer) cai no traço neutro
/// da superfície em vez de quebrar: o texto continua dizendo qual é.
class BadgeTipo extends StatelessWidget {
  const BadgeTipo(this.tipo, {super.key});

  final String tipo;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final escuro = tema.brightness == Brightness.dark;
    final cores = escuro ? BadgesTipo.escuro : BadgesTipo.claro;
    final cor = cores[tipo] ?? tema.colorScheme.onSurfaceVariant;
    return Semantics(
      label: 'Tipo na turma $tipo',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Dim.e8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: cor, width: 1.5),
          borderRadius: BorderRadius.circular(Dim.raioBadge),
        ),
        child: Text(
          tipo.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Tipografia.badge.copyWith(color: cor),
        ),
      ),
    );
  }
}
