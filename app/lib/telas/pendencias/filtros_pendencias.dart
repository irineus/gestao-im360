import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pendencias/pendencias.dart';
import '../../pendencias/pendencias_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';

/// Barra de filtros da central (wireframe §14.1): severidade, tipo e idade. O
/// estado mora no provider, não aqui (design-system §5.3).
///
/// **O filtro de tipo só oferece os tipos que estão na lista carregada**, e não
/// os quinze do `check`. Oferecer os quinze produziria treze escolhas que
/// esvaziam a tela sem que nada explique por quê — e "nenhuma pendência com
/// esses filtros" é uma resposta pior do que a opção não existir. Não há busca
/// por texto: a descrição é gerada pela rotina, e o que se procura numa fila de
/// trabalho é severidade e idade.
class FiltrosPendencias extends ConsumerWidget {
  const FiltrosPendencias({super.key, required this.tiposPresentes});

  /// Os tipos que aparecem na lista **sem filtro de tipo** — senão escolher um
  /// tipo tiraria todos os outros do próprio menu, e a pessoa ficaria sem como
  /// voltar sem passar por "Limpar filtros".
  final List<String> tiposPresentes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroPendenciasProvider);
    final controlador = ref.read(filtroPendenciasProvider.notifier);

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownMenu<String>(
          // A chave força o menu a acompanhar o "Limpar filtros" que vem do
          // estado vazio (mesma razão do card 4.6).
          key: ValueKey('severidade-${filtro.severidade}'),
          width: 170,
          label: const Text('Severidade'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.severidade ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todas'),
            for (final entrada in severidadesPendencia.entries)
              DropdownMenuEntry(value: entrada.key, label: entrada.value),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              severidade: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        DropdownMenu<String>(
          key: ValueKey('tipo-${filtro.tipo}'),
          width: 280,
          label: const Text('Tipo'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.tipo ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final tipo in tiposPresentes)
              DropdownMenuEntry(value: tipo, label: rotuloTipoPendencia(tipo)),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              tipo: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        DropdownMenu<String>(
          key: ValueKey('idade-${filtro.diasMinimos}'),
          width: 200,
          label: const Text('Aberta'),
          textStyle: Tipografia.corpo,
          initialSelection: '${filtro.diasMinimos ?? ''}',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Qualquer tempo'),
            for (final entrada in opcoesIdade.entries)
              DropdownMenuEntry(value: '${entrada.key}', label: entrada.value),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              diasMinimos: () =>
                  (valor == null || valor.isEmpty) ? null : int.parse(valor),
            ),
          ),
        ),
      ],
    );
  }
}
