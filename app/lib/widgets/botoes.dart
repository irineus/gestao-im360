import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sessao/sessao_provider.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// Motivo pelo qual um botão está desabilitado **pelo estado do dado**.
///
/// É contrato do componente, não um `onPressed: null` solto
/// (docs/design-system.md §5.7): botão desabilitado sem motivo é um botão que
/// o usuário fica tentando clicar.
@immutable
class DesabilitadoCom {
  const DesabilitadoCom(this.motivo)
    : assert(motivo != '', 'motivo obrigatório');

  final String motivo;
}

enum NivelBotao { primario, secundario, terciario, destrutivo }

/// A regra de exibição do card 2.6 (decisão 1), em código e em um lugar só:
///
/// - **sem permissão → o botão não é renderizado.** Permissão não destrava na
///   tela; um botão desabilitado sugeriria que preencher algo o destrava.
/// - **sem estado → visível e desabilitado, com o motivo** em tooltip (desktop)
///   e legenda de apoio (mobile).
class BotaoAcao extends ConsumerWidget {
  const BotaoAcao({
    super.key,
    required this.rotulo,
    this.aoTocar,
    this.exigePermissao,
    this.desabilitado,
    this.nivel = NivelBotao.primario,
    this.icone,
  });

  final String rotulo;
  final VoidCallback? aoTocar;

  /// Código de permissão de **ação** (`estoque.lancar_saida`, `turmas.alocar`).
  /// Nulo = botão sem guarda de permissão.
  final String? exigePermissao;

  final DesabilitadoCom? desabilitado;
  final NivelBotao nivel;
  final IconData? icone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissoes = ref.watch(permissoesProvider);
    final codigo = exigePermissao;
    if (codigo != null && !permissoes.contains(codigo)) {
      return const SizedBox.shrink();
    }

    final motivo = desabilitado?.motivo;
    final botao = _botao(context, habilitado: motivo == null);
    if (motivo == null) return botao;

    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
    final comTooltip = Tooltip(message: motivo, child: botao);
    if (!mobile) return comTooltip;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        comTooltip,
        const SizedBox(height: Dim.e4),
        Text(
          motivo,
          style: Tipografia.apoio.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _botao(BuildContext context, {required bool habilitado}) {
    final aoPressionar = habilitado ? aoTocar : null;
    final filho = icone == null
        ? Text(rotulo)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 18),
              const SizedBox(width: Dim.e8),
              Text(rotulo),
            ],
          );

    return switch (nivel) {
      NivelBotao.primario => FilledButton(
        onPressed: aoPressionar,
        child: filho,
      ),
      NivelBotao.secundario => FilledButton.tonal(
        onPressed: aoPressionar,
        child: filho,
      ),
      NivelBotao.terciario => TextButton(onPressed: aoPressionar, child: filho),
      NivelBotao.destrutivo => FilledButton(
        onPressed: aoPressionar,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        child: filho,
      ),
    };
  }
}
