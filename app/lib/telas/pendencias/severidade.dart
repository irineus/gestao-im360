import 'package:flutter/material.dart';

import '../../pendencias/pendencias.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';

/// A severidade de uma pendência: **ícone + texto**, e não badge.
///
/// A escolha é deliberada e vem do card 1.9 §6: o sistema tem **dois**
/// vocabulários de badge, e cada um carrega um significado — preenchido tonal é
/// *status do aluno* ([BadgeStatus]) e contorno é *tipo na turma*
/// ([BadgeTipo]). Um terceiro badge nesta lista, que mostra nome de aluno na
/// coluna ao lado, faria a forma deixar de dizer qual dos três vocabulários se
/// está lendo — e a separação por forma existe justamente para sobreviver a P&B
/// e a daltonismo, onde a cor não ajuda a desempatar.
///
/// O texto vai sempre junto do ícone, pela mesma razão do ⚠ da lista de alunos
/// (card 5.7): a cor nunca é o único portador do significado (card 1.9 §7).
class Severidade extends StatelessWidget {
  const Severidade(this.severidade, {super.key});

  final String severidade;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final (icone, cor) = switch (severidade) {
      'ALTA' => (Icons.error_outline, cores.error),
      'MEDIA' => (Icons.warning_amber_rounded, cores.tertiary),
      _ => (Icons.info_outline, cores.onSurfaceVariant),
    };

    return Semantics(
      label: 'Severidade ${rotuloSeveridade(severidade)}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 16, color: cor),
          const SizedBox(width: Dim.e4),
          Flexible(
            child: Text(
              rotuloSeveridade(severidade),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tipografia.badge.copyWith(color: cor),
            ),
          ),
        ],
      ),
    );
  }
}
