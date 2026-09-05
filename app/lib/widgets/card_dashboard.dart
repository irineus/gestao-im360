import 'package:flutter/material.dart';

import '../theme/dimensoes.dart';

/// O cartão de número do dashboard (design-system §5.5).
///
/// Nasceu privado dentro dos cartões por método (card 5.9) e virou componente
/// na revisão da fase 05: o card 8.7 traz mais cinco — alunos por método,
/// conclusões por semestre, tipos por bloco —, e cinco cópias de uma borda com
/// padding divergiriam antes da primeira semana.
///
/// **Sistema plano com bordas** (§2.4): a seleção é borda mais forte e fundo
/// tonal, nunca sombra.
class CardDashboard extends StatelessWidget {
  const CardDashboard({
    super.key,
    required this.filho,
    required this.semantica,
    this.selecionado = false,
    this.aoTocar,
    this.largura,
    this.alvosInternos = false,
  });

  final Widget filho;

  /// O cartão é uma pilha de números; sem isto a leitura de tela os anuncia em
  /// sequência, sem separar o que é o quê (§8.5).
  final String semantica;

  final bool selecionado;
  final VoidCallback? aoTocar;

  /// Nula = ocupa a largura que o pai der. É o que o mobile usa: dois cartões
  /// lado a lado numa tela de 430 px é o oposto de "mobile empilha" (§3).
  final double? largura;

  /// Quando o cartão tem **alvos próprios dentro** — o §5.5 escreve "números
  /// secundários com alerta também são alvos individuais", e o wireframe §5 dá
  /// o exemplo: o "9 standby" abre a lista de alunos filtrada.
  ///
  /// ⚠️ Muda a semântica, e é o ponto: com `excludeSemantics: true` (o padrão,
  /// que os cartões de vaga e de lotação usam) a leitura de tela **apaga** os
  /// filhos e anuncia só o rótulo do cartão — os botões de dentro deixariam de
  /// existir para quem navega por leitor de tela, sem nada em tela dizendo.
  /// Ligado, o cartão vira um GRUPO rotulado com nós filhos explícitos: o
  /// rótulo continua sendo lido de uma vez e cada número segue alcançável.
  final bool alvosInternos;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;

    final conteudo = Container(
      width: largura,
      padding: const EdgeInsets.all(Dim.e12),
      decoration: BoxDecoration(
        border: Border.all(
          color: selecionado ? cores.primary : cores.outlineVariant,
          width: selecionado ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(Dim.raio),
        color: selecionado ? cores.surfaceContainerHighest : null,
      ),
      child: filho,
    );

    return Semantics(
      button: aoTocar != null,
      selected: selecionado,
      label: semantica,
      container: alvosInternos,
      explicitChildNodes: alvosInternos,
      excludeSemantics: !alvosInternos,
      child: aoTocar == null
          ? conteudo
          : InkWell(
              onTap: aoTocar,
              borderRadius: BorderRadius.circular(Dim.raio),
              child: conteudo,
            ),
    );
  }
}

/// A largura do cartão no desktop e no tablet. No mobile ele ocupa a linha.
const larguraCardDashboard = 200.0;
