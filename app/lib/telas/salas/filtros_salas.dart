import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infraestrutura/infraestrutura.dart';
import '../../infraestrutura/infraestrutura_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';

/// Barra de filtros da aba de salas (design-system §5.3): busca, tipo e o chip
/// "Só ativas". O estado mora no provider, não aqui.
class FiltrosSalas extends ConsumerStatefulWidget {
  const FiltrosSalas({super.key});

  @override
  ConsumerState<FiltrosSalas> createState() => _FiltrosSalasState();
}

class _FiltrosSalasState extends ConsumerState<FiltrosSalas> {
  late final _busca = TextEditingController(
    text: ref.read(filtroSalasProvider).busca,
  );

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Limpar filtros" vem de fora (estado vazio): o campo acompanha.
    ref.listen(filtroSalasProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = ref.watch(filtroSalasProvider);
    final controlador = ref.read(filtroSalasProvider.notifier);

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            controller: _busca,
            style: Tipografia.corpo,
            decoration: InputDecoration(
              labelText: 'Nome da sala',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: filtro.busca.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          controlador.definir(filtro.copiar(busca: '')),
                    ),
            ),
            onChanged: (valor) =>
                controlador.definir(filtro.copiar(busca: valor)),
          ),
        ),
        DropdownMenu<String>(
          // A chave força o menu a acompanhar o "Limpar filtros".
          key: ValueKey('tipo-${filtro.tipo}'),
          width: 180,
          label: const Text('Tipo'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.tipo ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final tipo in tiposSala.entries)
              DropdownMenuEntry(value: tipo.key, label: tipo.value),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              tipo: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        FilterChip(
          label: const Text('Só ativas'),
          selected: filtro.soAtivas,
          onSelected: (valor) =>
              controlador.definir(filtro.copiar(soAtivas: valor)),
        ),
      ],
    );
  }
}

/// Barra de filtros da aba de professores: busca e "Só ativos".
class FiltrosProfessores extends ConsumerStatefulWidget {
  const FiltrosProfessores({super.key});

  @override
  ConsumerState<FiltrosProfessores> createState() => _FiltrosProfessoresState();
}

class _FiltrosProfessoresState extends ConsumerState<FiltrosProfessores> {
  late final _busca = TextEditingController(
    text: ref.read(filtroProfessoresProvider).busca,
  );

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(filtroProfessoresProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = ref.watch(filtroProfessoresProvider);
    final controlador = ref.read(filtroProfessoresProvider.notifier);

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            controller: _busca,
            style: Tipografia.corpo,
            decoration: InputDecoration(
              labelText: 'Nome do professor',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: filtro.busca.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          controlador.definir(filtro.copiar(busca: '')),
                    ),
            ),
            onChanged: (valor) =>
                controlador.definir(filtro.copiar(busca: valor)),
          ),
        ),
        FilterChip(
          label: const Text('Só ativos'),
          selected: filtro.soAtivos,
          onSelected: (valor) =>
              controlador.definir(filtro.copiar(soAtivos: valor)),
        ),
      ],
    );
  }
}
