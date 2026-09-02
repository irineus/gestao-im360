import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';

/// Barra de filtros das três abas do catálogo (design-system §5.3): busca,
/// método, categoria (só nos materiais) e o chip "Só ativos".
///
/// O estado mora no [provider] da aba, não aqui — sobrevive à navegação de ida
/// e volta dentro da sessão.
class FiltrosCatalogo extends ConsumerStatefulWidget {
  const FiltrosCatalogo({
    super.key,
    required this.provider,
    required this.metodos,
    this.categorias,
    this.rotuloBusca = 'Buscar',
  });

  final NotifierProvider<FiltroCatalogoNotifier, FiltroCatalogo> provider;
  final List<Metodo> metodos;

  /// Nulo = a aba não filtra por categoria.
  final List<String>? categorias;
  final String rotuloBusca;

  @override
  ConsumerState<FiltrosCatalogo> createState() => _FiltrosCatalogoState();
}

class _FiltrosCatalogoState extends ConsumerState<FiltrosCatalogo> {
  late final _busca = TextEditingController(
    text: ref.read(widget.provider).busca,
  );

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Limpar filtros" vem de fora (estado vazio): o campo acompanha.
    ref.listen(widget.provider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = ref.watch(widget.provider);
    final controlador = ref.read(widget.provider.notifier);
    final categorias = widget.categorias;

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
              labelText: widget.rotuloBusca,
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
          width: 180,
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
            ),
          ),
        ),
        if (categorias != null)
          DropdownMenu<String>(
            key: ValueKey('categoria-${filtro.categoria}'),
            width: 180,
            label: const Text('Categoria'),
            textStyle: Tipografia.corpo,
            initialSelection: filtro.categoria ?? '',
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: '', label: 'Todas'),
              for (final categoria in categorias)
                DropdownMenuEntry(value: categoria, label: categoria),
            ],
            onSelected: (valor) => controlador.definir(
              filtro.copiar(
                categoria: () =>
                    (valor == null || valor.isEmpty) ? null : valor,
              ),
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
