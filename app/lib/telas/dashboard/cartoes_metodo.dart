import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/dashboard.dart';
import '../../dashboard/dashboard_provider.dart';
import '../../theme/cores.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';

/// Os totais por método do wireframe §5 — e, ao mesmo tempo, o **seletor** da
/// grade de vagas abaixo.
///
/// As duas coisas num componente só, de propósito: a grade mostra **um** método
/// por vez (vaga de Inglês não serve a aluno de Interativo — ver [vagasDa]), e
/// um seletor separado dos números faria a tela ter dois lugares dizendo qual
/// método está em foco. Aqui o cartão em destaque **é** a resposta.
class CartoesMetodo extends ConsumerWidget {
  const CartoesMetodo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totais = ref.watch(totaisPorMetodoProvider);
    final visivel = ref.watch(metodoVisivelProvider);
    final controlador = ref.read(metodoDashboardProvider.notifier);

    return Wrap(
      spacing: Dim.e12,
      runSpacing: Dim.e12,
      children: [
        for (final total in totais)
          _CartaoMetodo(
            total: total,
            selecionado: total.metodoId == visivel?.metodoId,
            // Um método só: o cartão continua mostrando os números, mas não se
            // anuncia como botão que não muda nada.
            aoTocar: totais.length == 1
                ? null
                : () => controlador.escolher(total.metodoId),
          ),
      ],
    );
  }
}

const _larguraCartao = 200.0;

class _CartaoMetodo extends StatelessWidget {
  const _CartaoMetodo({
    required this.total,
    required this.selecionado,
    this.aoTocar,
  });

  final TotalMetodo total;
  final bool selecionado;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final escuro = tema.brightness == Brightness.dark;
    final corAtencao = escuro ? Cores.atencaoEscuro : Cores.atencao;

    final conteudo = Container(
      width: _larguraCartao,
      padding: const EdgeInsets.all(Dim.e12),
      decoration: BoxDecoration(
        // Sistema plano com bordas (design-system §2.4): a seleção é borda mais
        // forte e fundo tonal, nunca sombra.
        border: Border.all(
          color: selecionado ? cores.primary : cores.outlineVariant,
          width: selecionado ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(Dim.raio),
        color: selecionado ? cores.surfaceContainerHighest : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            total.metodoCodigo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tipografia.badge.copyWith(color: cores.onSurfaceVariant),
          ),
          const SizedBox(height: Dim.e4),
          Text(
            '${total.vagasLivres}',
            style: Tipografia.numero(Tipografia.titulo),
          ),
          Text(
            total.vagasLivres == 1 ? 'vaga livre' : 'vagas livres',
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          ),
          const SizedBox(height: Dim.e8),
          Text(
            '${total.ocupacaoTexto} ocupados · ${total.blocosTexto}',
            style: Tipografia.numero(Tipografia.apoio),
          ),
          if (total.blocosLotados > 0)
            Text(
              '${total.blocosLotados} '
              '${total.blocosLotados == 1 ? 'lotada' : 'lotadas'}',
              style: Tipografia.apoio.copyWith(color: corAtencao),
            ),
          if (total.temAlerta)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: cores.error),
                const SizedBox(width: Dim.e4),
                Flexible(
                  child: Text(
                    '${total.blocosAcimaCapacidade} acima da capacidade',
                    style: Tipografia.apoio.copyWith(color: cores.error),
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    return Semantics(
      button: aoTocar != null,
      selected: selecionado,
      label: descricaoMetodo(total),
      excludeSemantics: true,
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

/// O cartão é uma pilha de números; sem isto a leitura de tela anuncia
/// "INTERATIVO 7 vagas livres 23/30 ocupados 3 turmas" sem separar o que é o quê.
String descricaoMetodo(TotalMetodo total) {
  final partes = <String>[
    total.metodoCodigo,
    total.vagasTexto,
    '${total.ocupacao} ocupados de ${total.capacidade}',
    total.blocosTexto,
    if (total.blocosLotados > 0) '${total.blocosLotados} lotadas',
    if (total.temAlerta) '${total.blocosAcimaCapacidade} acima da capacidade',
  ];
  return partes.join(', ');
}
