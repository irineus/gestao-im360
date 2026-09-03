import 'package:flutter/material.dart';

import '../theme/cores.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// Badge de status do aluno — preenchido tonal (design-system §5.1, card 4.6).
///
/// Status do aluno é **preenchido**; tipo na turma é **contorno** (card 1.9
/// §6): as duas formas nunca se misturam, para o vocabulário sobreviver a
/// P&B e a daltonismo. O rótulo é sempre texto — a cor nunca é o único
/// portador do significado — e o par texto/fundo vem de `BadgesStatus`, com
/// os contrastes AA verificados nos dois temas (design-system §2.3).
///
/// Status fora dos seis do `check` (não deveria acontecer) cai num par neutro
/// em vez de quebrar: o texto continua dizendo qual é.
class BadgeStatus extends StatelessWidget {
  const BadgeStatus(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final escuro = tema.brightness == Brightness.dark;
    final pares = escuro ? BadgesStatus.escuro : BadgesStatus.claro;
    final par =
        pares[status] ??
        ParBadge(
          tema.colorScheme.onSurfaceVariant,
          tema.colorScheme.surfaceContainerHighest,
        );
    return Semantics(
      label: 'Status $status',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Dim.e8, vertical: 2),
        decoration: BoxDecoration(
          color: par.fundo,
          borderRadius: BorderRadius.circular(Dim.raioBadge),
        ),
        child: Text(
          status.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Tipografia.badge.copyWith(color: par.texto),
        ),
      ),
    );
  }
}
