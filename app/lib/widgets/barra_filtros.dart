import 'package:flutter/material.dart';

import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// A barra de filtros e ações de uma tela (design-system §5.2/§5.3).
///
/// Nasceu **dentro** da [TabelaIm360] e saiu de lá na revisão das telas 06/07
/// (item H4): as telas 4 (Turmas) e 5 (Turmas Modular) não usam a tabela — uma
/// é grade, a outra é acordeão — e por isso empilhavam os próprios controles à
/// esquerda, com larguras diferentes, sem a folha "Filtrar (n)" que todas as
/// demais têm no celular. Duas barras para a mesma função é o defeito que o
/// card 5.11 pagou com as duas formas da matriz semanal.
///
/// No mobile os filtros vão para uma folha inferior atrás de `Filtrar (n)` e as
/// ações descem para uma segunda linha em [Wrap] — ação e filtro não disputam a
/// mesma linha de 390 px (item H3).
class BarraFiltrosIm360 extends StatelessWidget {
  const BarraFiltrosIm360({
    super.key,
    this.filtros,
    this.filtrosAtivos = 0,
    this.acoes = const [],
    this.mobile,
  });

  final Widget? filtros;

  /// Quantos filtros estão ligados — o `(n)` do botão no mobile.
  final int filtrosAtivos;

  /// Botões da tela (`+ Novo …`). Ficam **fora** da folha de propósito: ação
  /// não é filtro.
  final List<Widget> acoes;

  /// Força a forma. Nulo decide pela largura disponível — a [TabelaIm360]
  /// passa o valor dela, que também depende de haver cartão declarado.
  final bool? mobile;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, restricoes) {
      final estreita = mobile ?? (faixaDe(restricoes.maxWidth) == Faixa.mobile);
      return estreita ? _estreita(context) : _ampla();
    },
  );

  Widget _ampla() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: filtros ?? const SizedBox.shrink()),
      for (final acao in acoes) ...[const SizedBox(width: Dim.e8), acao],
    ],
  );

  /// ⚠️ Era uma `Row` com `Spacer`, e estourava: medido em 390 px, Compras dava
  /// `RenderFlex overflowed by 295 px` (537 com mais permissões) e Materiais,
  /// 135 px. A causa não era o número de botões — era o `BotaoAcao`
  /// **desabilitado com motivo**, que no mobile vira uma `Column` com a legenda
  /// embaixo e, dentro de uma `Row`, não tem largura nenhuma para quebrar.
  Widget _estreita(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (filtros != null)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (contexto) => SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    Dim.e16,
                    Dim.e16,
                    Dim.e16,
                    Dim.e16 + MediaQuery.viewInsetsOf(contexto).bottom,
                  ),
                  child: filtros,
                ),
              ),
            ),
            icon: const Icon(Icons.filter_list),
            label: Text(
              filtrosAtivos > 0 ? 'Filtrar ($filtrosAtivos)' : 'Filtrar',
            ),
          ),
        ),
      if (acoes.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(top: filtros != null ? Dim.e8 : 0),
          child: Wrap(
            spacing: Dim.e8,
            runSpacing: Dim.e8,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: acoes,
          ),
        ),
    ],
  );
}

/// Um `DropdownMenu` de filtro com a largura certa por faixa.
///
/// ⚠️ Todo filtro do sistema fixava `width` (180, 200, 240): dentro da folha do
/// celular eles ficavam estreitos e **irregulares entre si** — é o que as
/// capturas de Turmas mostram (item H4). No mobile a largura passa a ser a
/// total (`expandedInsets: EdgeInsets.zero`); fora dele, a de sempre.
class FiltroSuspenso<T> extends StatelessWidget {
  const FiltroSuspenso({
    super.key,
    required this.rotulo,
    required this.selecao,
    required this.entradas,
    required this.aoSelecionar,
    this.largura = 180,
  });

  final String rotulo;
  final T selecao;
  final List<DropdownMenuEntry<T>> entradas;
  final void Function(T? valor) aoSelecionar;
  final double largura;

  @override
  Widget build(BuildContext context) {
    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
    return DropdownMenu<T>(
      width: mobile ? null : largura,
      expandedInsets: mobile ? EdgeInsets.zero : null,
      label: Text(rotulo),
      textStyle: Tipografia.corpo,
      initialSelection: selecao,
      dropdownMenuEntries: entradas,
      onSelected: aoSelecionar,
    );
  }
}

/// O mesmo para o campo de busca: largura fixa fora do mobile, total dentro da
/// folha de filtros.
class CampoBusca extends StatelessWidget {
  const CampoBusca({
    super.key,
    required this.controlador,
    required this.rotulo,
    required this.aoMudar,
    this.aoLimpar,
    this.largura = 240,
  });

  final TextEditingController controlador;
  final String rotulo;
  final ValueChanged<String> aoMudar;
  final VoidCallback? aoLimpar;
  final double largura;

  @override
  Widget build(BuildContext context) {
    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
    final campo = TextField(
      controller: controlador,
      style: Tipografia.corpo,
      decoration: InputDecoration(
        labelText: rotulo,
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        suffixIcon: (aoLimpar == null || controlador.text.isEmpty)
            ? null
            : IconButton(
                tooltip: 'Limpar busca',
                icon: const Icon(Icons.clear),
                onPressed: aoLimpar,
              ),
      ),
      onChanged: aoMudar,
    );
    return mobile ? campo : SizedBox(width: largura, child: campo);
  }
}
