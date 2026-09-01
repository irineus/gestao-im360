import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sessao/sessao.dart';
import '../sessao/sessao_provider.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// Tela 1 (segunda metade) — seleção de unidade.
///
/// Na v1 **não é alcançável**: a política de `select` de `unidade` é
/// `id = fn_unidade_atual()` (card 3.4), então o usuário enxerga exatamente uma
/// unidade — a dele —, e o roteador pula esta etapa em silêncio (card 2.6,
/// decisão (g)). A tela existe no fluxo para a Fase 11 não redesenhar o login;
/// quem a torna alcançável é o card 11.4, que precisa mudar aquela política.
class TelaSelecaoUnidade extends ConsumerWidget {
  const TelaSelecaoUnidade({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(sessaoProvider);
    final nome = estado is SessaoAtiva ? estado.sessao.unidadeNome : null;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Dim.larguraFormularioMax),
          child: Padding(
            padding: const EdgeInsets.all(Dim.e24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Escolher unidade', style: Tipografia.titulo),
                const SizedBox(height: Dim.e16),
                Card(
                  child: ListTile(
                    title: Text(
                      nome ?? 'Unidade atual',
                      style: Tipografia.corpo,
                    ),
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
