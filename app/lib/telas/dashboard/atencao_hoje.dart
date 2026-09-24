import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pendencias/pendencias.dart';
import '../../pendencias/pendencias_provider.dart';
import '../../rotas/rotas.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/estados.dart';

/// "Atenção hoje" — o que pede ação, no TOPO do Dashboard (card 9.2,71).
///
/// Visto em 24/09/2026: o Dashboard abria com uma nota técnica e contagens, e o
/// que pedia ação hoje estava no fim da página, abaixo da grade de vagas.
///
/// **Sem regra nova** (decisão do card): os três números saem das pendências
/// abertas que o shell já carrega para o contador do menu — o mesmo
/// `pendenciasProvider` da região de pendências, mais abaixo. Cada número é
/// atalho para a central já filtrada (wireframes §3.3); o zero fica em segundo
/// plano e não é alvo — abrir uma lista vazia não é ação.
class AtencaoHoje extends ConsumerWidget {
  const AtencaoHoje({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final abertas = ref.watch(pendenciasProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(tituloAtencaoHoje, style: Tipografia.subtitulo),
        const SizedBox(height: Dim.e8),
        // `hasError` antes de `hasValue` (design-system §5.6).
        if (abertas.hasError)
          EstadoErro(
            mensagem: erroAtencaoHoje,
            aoRepetir: ref.read(versaoPendenciasProvider.notifier).incrementar,
          )
        else if (!abertas.hasValue)
          const EstadoCarregando(linhas: 1)
        else
          Builder(
            builder: (context) {
              final itens = itensAtencao(abertas.requireValue);
              if (itens.every((i) => i.quantidade == 0)) {
                return Text(
                  semAtencaoHoje,
                  style: Tipografia.apoio.copyWith(
                    color: cores.onSurfaceVariant,
                  ),
                );
              }
              return Wrap(
                spacing: Dim.e24,
                runSpacing: Dim.e8,
                children: [
                  for (final item in itens)
                    _ItemAtencao(
                      item: item,
                      aoTocar: () {
                        ref
                            .read(filtroPendenciasProvider.notifier)
                            .definir(item.filtro);
                        context.go(caminhoDeRota('pendencias'));
                      },
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

const tituloAtencaoHoje = 'Atenção hoje';

const semAtencaoHoje =
    'Nada pedindo ação agora: nenhuma pendência de severidade alta, nenhuma '
    'entrega bloqueada e nenhum material abaixo do mínimo.';

const erroAtencaoHoje =
    'Não foi possível saber o que pede atenção agora. Abra a central de '
    'pendências para conferir.';

/// Um número da faixa: quantos, o que são e o filtro da central que os mostra.
@immutable
class ItemAtencao {
  const ItemAtencao({
    required this.quantidade,
    required this.singular,
    required this.plural,
    required this.filtro,
  });

  final int quantidade;
  final String singular;
  final String plural;
  final FiltroPendencias filtro;

  String get rotulo => quantidade == 1 ? singular : plural;
}

/// Os três números, contados das pendências abertas — ALTA por severidade; a
/// entrega bloqueada e o material abaixo do mínimo pelo TIPO que a rotina e as
/// entregas já abrem (fase 6).
List<ItemAtencao> itensAtencao(List<Pendencia> abertas) => [
  ItemAtencao(
    quantidade: abertas.where((p) => p.severidade == 'ALTA').length,
    singular: 'pendência de severidade alta',
    plural: 'pendências de severidade alta',
    filtro: const FiltroPendencias(severidade: 'ALTA'),
  ),
  ItemAtencao(
    quantidade: abertas.where((p) => p.tipo == 'COMPRA_SEM_ESTOQUE').length,
    singular: 'entrega bloqueada sem estoque',
    plural: 'entregas bloqueadas sem estoque',
    filtro: const FiltroPendencias(tipo: 'COMPRA_SEM_ESTOQUE'),
  ),
  ItemAtencao(
    quantidade: abertas.where((p) => p.tipo == 'ESTOQUE_ABAIXO_MINIMO').length,
    singular: 'material abaixo do mínimo',
    plural: 'materiais abaixo do mínimo',
    filtro: const FiltroPendencias(tipo: 'ESTOQUE_ABAIXO_MINIMO'),
  ),
];

class _ItemAtencao extends StatelessWidget {
  const _ItemAtencao({required this.item, required this.aoTocar});

  final ItemAtencao item;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final zero = item.quantidade == 0;
    final conteudo = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '${item.quantidade}',
          style: Tipografia.numero(zero ? Tipografia.corpo : Tipografia.titulo)
              .copyWith(color: zero ? cores.onSurfaceVariant : null),
        ),
        const SizedBox(width: Dim.e8),
        Flexible(
          child: Text(
            item.rotulo,
            style: (zero ? Tipografia.apoio : Tipografia.corpo).copyWith(
              color: zero ? cores.onSurfaceVariant : null,
            ),
          ),
        ),
      ],
    );
    // Zero em segundo plano, e sem alvo: o mesmo tratamento das linhas zeradas
    // dos cartões de aluno (card 9.2,71).
    if (zero) return conteudo;

    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
    return Semantics(
      button: true,
      label: '${item.quantidade} ${item.rotulo}, abrir a central de pendências',
      excludeSemantics: true,
      child: InkWell(
        onTap: aoTocar,
        borderRadius: BorderRadius.circular(Dim.raioBadge),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: mobile ? Dim.alvoMobile : Dim.alturaBotao,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Dim.e4),
            child: conteudo,
          ),
        ),
      ),
    );
  }
}
