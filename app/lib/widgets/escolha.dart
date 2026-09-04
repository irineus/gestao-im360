import 'package:flutter/material.dart';

import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// Uma linha de escolha única — o "rádio" das listas de candidatos e de blocos
/// (design-system §8.5).
///
/// Existe como componente por dois motivos medidos na revisão da fase 05:
///
/// 1. **Alvo de toque.** As três listas de escolha do sistema tinham linhas de
///    26 a 28 px, contra os 40 px do desktop e 44 px da jornada mobile que o
///    §8.4 exige — e a jornada de alocar aluno é do monitor, no celular.
/// 2. **Semântica.** O ícone `radio_button_checked` desenha um rádio e não é
///    um: a leitura de tela anunciava o texto solto, sem dizer que é uma
///    escolha entre várias nem qual está marcada.
///
/// Não é `RadioListTile`: o visual é o do sistema (ícone de 18 px alinhado ao
/// texto, sem o padding de `ListTile`) e o `RadioGroup` do Material exige um
/// ancestral que estas listas, montadas dentro de `FormularioIm360`, não têm.
class LinhaEscolha extends StatelessWidget {
  const LinhaEscolha({
    super.key,
    required this.rotulo,
    required this.marcada,
    required this.aoTocar,
    this.apoio,
    this.direita,
  });

  /// O que a linha diz — e o que a leitura de tela anuncia.
  final String rotulo;
  final bool marcada;
  final VoidCallback aoTocar;

  /// Segunda linha, quando há um detalhe que não cabe no rótulo.
  final String? apoio;

  /// Um badge à direita (o status do aluno, na lista de candidatos).
  final Widget? direita;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: marcada,
      label: apoio == null ? rotulo : '$rotulo, $apoio',
      excludeSemantics: true,
      child: InkWell(
        onTap: aoTocar,
        borderRadius: BorderRadius.circular(Dim.raio),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Dim.alvoMobile),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Dim.e4,
              horizontal: Dim.e4,
            ),
            child: Row(
              children: [
                Icon(
                  marcada
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: marcada ? cores.primary : cores.onSurfaceVariant,
                ),
                const SizedBox(width: Dim.e8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(rotulo, style: Tipografia.corpoTabela),
                      if (apoio != null)
                        Text(
                          apoio!,
                          style: Tipografia.apoio.copyWith(
                            color: cores.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (direita != null) ...[
                  const SizedBox(width: Dim.e8),
                  direita!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
