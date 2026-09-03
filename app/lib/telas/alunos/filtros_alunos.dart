import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alunos/alunos.dart';
import '../../alunos/alunos_provider.dart';
import '../../catalogo/catalogo.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';

/// Barra de filtros da lista de alunos (design-system §5.3): busca por nome
/// ou código SGF, método, status, combo e o chip que esconde os terminais. O
/// filtro de **turma** entra na Fase 5 (nota do card 4.6). O estado mora no
/// provider, não aqui.
class FiltrosAlunos extends ConsumerStatefulWidget {
  const FiltrosAlunos({super.key, required this.metodos, required this.combos});

  final List<Metodo> metodos;
  final List<Combo> combos;

  @override
  ConsumerState<FiltrosAlunos> createState() => _FiltrosAlunosState();
}

class _FiltrosAlunosState extends ConsumerState<FiltrosAlunos> {
  late final _busca = TextEditingController(
    text: ref.read(filtroAlunosProvider).busca,
  );

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Limpar filtros" vem de fora (estado vazio): o campo acompanha.
    ref.listen(filtroAlunosProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = ref.watch(filtroAlunosProvider);
    final controlador = ref.read(filtroAlunosProvider.notifier);
    // Combo é do método: com um método escolhido, só os combos dele.
    final combos = [
      for (final c in widget.combos)
        if (filtro.metodoId == null || c.metodoId == filtro.metodoId) c,
    ];

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
              labelText: 'Nome ou código SGF',
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
          key: ValueKey('metodo-${filtro.metodoId}'),
          width: 170,
          label: const Text('Método'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.metodoId ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final metodo in widget.metodos)
              DropdownMenuEntry(value: metodo.id, label: metodo.nome),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              metodoId: () => (valor == null || valor.isEmpty) ? null : valor,
              // Combo de outro método deixaria a lista vazia sem dizer por quê.
              comboId: () => null,
            ),
          ),
        ),
        DropdownMenu<String>(
          key: ValueKey('status-${filtro.status}'),
          width: 160,
          label: const Text('Status'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.status ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final status in statusAluno.keys)
              DropdownMenuEntry(value: status, label: status),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              status: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        DropdownMenu<String>(
          key: ValueKey('combo-${filtro.comboId}-${filtro.metodoId}'),
          width: 220,
          label: const Text('Combo'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.comboId ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final combo in combos)
              DropdownMenuEntry(value: combo.id!, label: combo.nome),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              comboId: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        FilterChip(
          label: const Text('Ocultar formados e cancelados'),
          selected: filtro.ocultarEncerrados,
          onSelected: (valor) =>
              controlador.definir(filtro.copiar(ocultarEncerrados: valor)),
        ),
      ],
    );
  }
}
