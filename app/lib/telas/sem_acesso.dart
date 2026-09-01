import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/estados.dart';

/// Tela inteira de "sem acesso" — deep-link para rota fora do conjunto mínimo,
/// ou permissão revogada em sessão aberta (docs/wireframes.md §2.3.4).
class TelaSemAcesso extends StatelessWidget {
  const TelaSemAcesso({super.key, required this.faltando, this.paraOndeIr});

  final Set<String> faltando;
  final String? paraOndeIr;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: EstadoSemAcesso(
      faltando: faltando,
      rotuloAcao: paraOndeIr == null ? null : 'Ir para o início',
      aoAgir: paraOndeIr == null ? null : () => context.go(paraOndeIr!),
    ),
  );
}
