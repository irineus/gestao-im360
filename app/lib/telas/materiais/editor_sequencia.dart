import 'package:flutter/material.dart';

import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';

/// Lista ordenada editável — a sequência de apostilas de um curso e a de
/// cursos de um combo usam o mesmo componente.
///
/// Quem é dono da lista é o pai: cada mudança sai por [aoMudar] com a lista
/// nova, e nada é gravado aqui. Gravar é uma decisão da tela (botão "Salvar
/// sequência"), porque a ordem é **um** `update` no banco (card 2.1 (e)), não
/// uma escrita por arraste.
class EditorSequencia<T> extends StatelessWidget {
  const EditorSequencia({
    super.key,
    required this.itens,
    required this.disponiveis,
    required this.rotulo,
    required this.chave,
    required this.aoMudar,
    this.podeEditar = true,
    this.rotuloAdicionar = 'Adicionar',
    this.vazio = 'Nenhum item na sequência.',
  });

  final List<T> itens;

  /// Candidatos a entrar — os que já estão em [itens] são filtrados aqui.
  final List<T> disponiveis;
  final String Function(T item) rotulo;
  final String Function(T item) chave;
  final ValueChanged<List<T>> aoMudar;
  final bool podeEditar;
  final String rotuloAdicionar;
  final String vazio;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final presentes = {for (final item in itens) chave(item)};
    final candidatos = [
      for (final item in disponiveis)
        if (!presentes.contains(chave(item))) item,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (itens.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Dim.e8),
            child: Text(
              vazio,
              style: Tipografia.corpoTabela.copyWith(
                color: cores.onSurfaceVariant,
              ),
            ),
          )
        else
          // Alça de arraste PRÓPRIA, à esquerda. A alça padrão do
          // `ReorderableListView` em plataforma desktop é um ícone posicionado
          // sobre a área do `trailing` — exatamente onde está o botão de
          // remover — e no mobile não existe alça nenhuma (é toque longo).
          // Uma alça explícita dá a mesma affordance para mouse e para toque
          // e deixa o `trailing` livre.
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            // `onReorderItem` já entrega o índice de destino ajustado pela
            // remoção — sem o `para - 1` que o `onReorder` antigo exigia.
            onReorderItem: (de, para) {
              if (!podeEditar) return;
              final lista = List.of(itens);
              lista.insert(para, lista.removeAt(de));
              aoMudar(lista);
            },
            children: [
              for (var i = 0; i < itens.length; i++)
                ListTile(
                  key: ValueKey(chave(itens[i])),
                  minTileHeight: Dim.alvoMobile,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (podeEditar)
                        ReorderableDragStartListener(
                          index: i,
                          child: Icon(
                            Icons.drag_indicator,
                            color: cores.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(width: Dim.e8),
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: cores.surfaceContainerHighest,
                        child: Text(
                          '${i + 1}',
                          style: Tipografia.numero(Tipografia.apoio)
                              .copyWith(color: cores.onSurface),
                        ),
                      ),
                    ],
                  ),
                  title: Text(rotulo(itens[i]), style: Tipografia.corpoTabela),
                  trailing: podeEditar
                      ? IconButton(
                          tooltip: 'Remover da sequência',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => aoMudar([
                            for (final item in itens)
                              if (chave(item) != chave(itens[i])) item,
                          ]),
                        )
                      : null,
                ),
            ],
          ),
        if (podeEditar) ...[
          const SizedBox(height: Dim.e8),
          if (candidatos.isEmpty)
            Text(
              'Nada mais para adicionar.',
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            )
          else
            DropdownMenu<String>(
              // Muda a chave a cada inclusão: o menu volta a "vazio" em vez de
              // continuar mostrando o item que acabou de entrar.
              key: ValueKey('adicionar-${itens.length}'),
              width: 360,
              label: Text(rotuloAdicionar),
              textStyle: Tipografia.corpo,
              enableFilter: true,
              requestFocusOnTap: true,
              dropdownMenuEntries: [
                for (final item in candidatos)
                  DropdownMenuEntry(value: chave(item), label: rotulo(item)),
              ],
              onSelected: (id) {
                if (id == null) return;
                for (final item in candidatos) {
                  if (chave(item) == id) {
                    aoMudar([...itens, item]);
                    return;
                  }
                }
              },
            ),
        ],
      ],
    );
  }
}
