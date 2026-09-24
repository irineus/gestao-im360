import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/dashboard.dart';
import '../../dashboard/dashboard_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/card_dashboard.dart';

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
    final nomeDoMetodo = ref.watch(nomeDoMetodoProvider);

    // ⚠️ No mobile os cartões **empilham** (design-system §3); no desktop
    // dividem a largura (card 9.2,71) — ver FileiraCartoes.
    return FileiraCartoes(
      quantidade: totais.length,
      cartao: (i, largura) {
        final total = totais[i];
        return _CartaoMetodo(
          total: total,
          nome: nomeDoMetodo(total.metodoCodigo),
          selecionado: total.metodoId == visivel?.metodoId,
          largura: largura,
          // Um método só: o cartão continua mostrando os números, mas não se
          // anuncia como botão que não muda nada.
          aoTocar: totais.length == 1
              ? null
              : () => controlador.escolher(total.metodoId),
        );
      },
    );
  }
}

class _CartaoMetodo extends StatelessWidget {
  const _CartaoMetodo({
    required this.total,
    required this.nome,
    required this.selecionado,
    this.largura,
    this.aoTocar,
  });

  final TotalMetodo total;

  /// O nome do método (card 9.2,71) — "Inglês", e não o código "INGLES".
  final String nome;
  final bool selecionado;
  final double? largura;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;

    return CardDashboard(
      selecionado: selecionado,
      aoTocar: aoTocar,
      largura: largura,
      semantica: descricaoMetodo(total),
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            nome,
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
            // "30 de 40 ocupados", e não "30/40": vinte e quatro pixels acima
            // de células que também dizem `n/m` — e ali `n/m` são vagas —, a
            // barra convida a ler a mesma coisa duas vezes de jeitos opostos.
            '${total.ocupacaoPorExtenso} · ${total.blocosTexto}',
            style: Tipografia.numero(Tipografia.apoio),
          ),
          if (total.blocosLotados > 0)
            Text(
              '${total.blocosLotados} '
              '${total.blocosLotados == 1 ? 'lotado' : 'lotados'}',
              // Lotado é **peso**, não cor de alerta (design-system §6): é o
              // sistema funcionando, e o âmbar aqui gastava o alerta que a
              // turma ESTOURADA, logo abaixo, precisa.
              style: Tipografia.apoio.copyWith(
                fontWeight: FontWeight.w600,
                color: cores.onSurfaceVariant,
              ),
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
  }
}

/// O cartão é uma pilha de números; sem isto a leitura de tela anuncia
/// "INTERATIVO 7 vagas livres 23/30 ocupados 3 turmas" sem separar o que é o quê.
String descricaoMetodo(TotalMetodo total) {
  final partes = <String>[
    total.metodoCodigo,
    total.vagasTexto,
    total.ocupacaoPorExtenso,
    total.blocosTexto,
    if (total.blocosLotados > 0) '${total.blocosLotados} lotados',
    if (total.temAlerta) '${total.blocosAcimaCapacidade} acima da capacidade',
  ];
  return partes.join(', ');
}
