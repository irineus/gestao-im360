import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';
import 'estados.dart';

/// Uma coluna da [TabelaIm360].
///
/// [prioridade] 1 nunca sai; números maiores saem primeiro quando a largura
/// não comporta todas (a coluna `†` do wireframe, card 2.6 decisão 7). A
/// degradação é por coluna, nunca por rolagem horizontal da página.
class ColunaIm360<T> {
  const ColunaIm360({
    required this.titulo,
    required this.texto,
    this.numerica = false,
    this.prioridade = 1,
    this.flex = 2,
    this.larguraMin = 120,
  }) : assert(prioridade >= 1, 'prioridade começa em 1');

  final String titulo;
  final String Function(T item) texto;

  /// Alinhada à direita e com numerais tabulares (`tnum`), obrigatórios em
  /// tabela e em valor de estoque (card 1.9 §4).
  final bool numerica;
  final int prioridade;
  final int flex;
  final double larguraMin;
}

/// O que uma linha vira no mobile: cartão com título, linha secundária e um
/// número em destaque à direita (design-system §5.2).
class CartaoIm360 {
  const CartaoIm360({
    required this.titulo,
    this.subtitulo,
    this.apoio,
    this.destaque,
  });

  final String titulo;
  final String? subtitulo;
  final String? apoio;
  final String? destaque;
}

/// Tabela com filtros e os quatro estados num contrato único
/// (design-system §5.2) — o componente central do sistema.
///
/// `AsyncValue` liga os estados: `loading` → skeleton, `error` → [EstadoErro],
/// `data` vazio → [estadoVazio] (texto da tela, design-system §7.2), `data` →
/// linhas. No mobile, com [cartao] declarado, as linhas viram cartões e os
/// filtros migram para uma folha inferior atrás de "Filtrar (n)".
class TabelaIm360<T> extends StatelessWidget {
  const TabelaIm360({
    super.key,
    required this.colunas,
    required this.linhas,
    required this.estadoVazio,
    this.filtros,
    this.filtrosAtivos = 0,
    this.acoes = const [],
    this.aoTocarLinha,
    this.cartao,
    this.aoRepetir,
  });

  final List<ColunaIm360<T>> colunas;
  final AsyncValue<List<T>> linhas;
  final Widget estadoVazio;

  /// Barra de filtros da tela (design-system §5.3). Sempre visível — inclusive
  /// no estado vazio por filtro, senão "Limpar filtros" não teria onde agir.
  final Widget? filtros;

  /// Quantos filtros estão ligados — o `(n)` do botão no mobile.
  final int filtrosAtivos;

  /// Botões da tela (`+ Novo …`), à direita dos filtros. Ficam fora da folha
  /// inferior de propósito: ação não é filtro.
  final List<Widget> acoes;

  final void Function(T item)? aoTocarLinha;
  final CartaoIm360 Function(T item)? cartao;
  final VoidCallback? aoRepetir;

  /// Quais colunas cabem em [largura]: sai primeiro a de maior [prioridade];
  /// as de prioridade 1 ficam sempre, mesmo apertadas.
  static List<ColunaIm360<T>> colunasVisiveis<T>(
    List<ColunaIm360<T>> colunas,
    double largura,
  ) {
    final visiveis = List.of(colunas);
    double total() => visiveis.fold(0.0, (soma, c) => soma + c.larguraMin);
    while (total() > largura) {
      ColunaIm360<T>? candidata;
      for (final coluna in visiveis) {
        if (coluna.prioridade > 1 &&
            (candidata == null || coluna.prioridade >= candidata.prioridade)) {
          candidata = coluna;
        }
      }
      if (candidata == null) break;
      visiveis.remove(candidata);
    }
    return visiveis;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, restricoes) {
      final mobile =
          faixaDe(restricoes.maxWidth) == Faixa.mobile && cartao != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (filtros != null || acoes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Dim.e16,
                Dim.e16,
                Dim.e16,
                Dim.e8,
              ),
              child: mobile ? _barraMobile(context) : _barra(),
            ),
          Expanded(
            child: linhas.when(
              loading: () => const EstadoCarregando(),
              error: (erro, _) {
                final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
                return EstadoErro(
                  mensagem: traduzido.mensagem,
                  codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
                  aoRepetir: aoRepetir,
                );
              },
              data: (itens) => itens.isEmpty
                  ? estadoVazio
                  : mobile
                  ? _cartoes(context, itens)
                  : _tabela(context, itens, restricoes.maxWidth),
            ),
          ),
        ],
      );
    },
  );

  Widget _barra() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: filtros ?? const SizedBox.shrink()),
      for (final acao in acoes) ...[const SizedBox(width: Dim.e8), acao],
    ],
  );

  Widget _barraMobile(BuildContext context) => Row(
    children: [
      if (filtros != null)
        OutlinedButton.icon(
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
      const Spacer(),
      for (final acao in acoes) ...[const SizedBox(width: Dim.e8), acao],
    ],
  );

  Widget _tabela(BuildContext context, List<T> itens, double largura) {
    final visiveis = colunasVisiveis(colunas, largura - Dim.e32);
    return Column(
      children: [
        _linha(
          visiveis,
          celulas: [for (final c in visiveis) c.titulo],
          cabecalho: true,
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: itens.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final item = itens[i];
              final tocar = aoTocarLinha;
              return InkWell(
                onTap: tocar == null ? null : () => tocar(item),
                child: _linha(
                  visiveis,
                  celulas: [for (final c in visiveis) c.texto(item)],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _linha(
    List<ColunaIm360<T>> visiveis, {
    required List<String> celulas,
    bool cabecalho = false,
  }) => SizedBox(
    height: Dim.alturaLinha,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Dim.e16),
      child: Row(
        children: [
          for (var i = 0; i < visiveis.length; i++)
            Expanded(
              flex: visiveis[i].flex,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Dim.e8),
                child: Text(
                  celulas[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: visiveis[i].numerica
                      ? TextAlign.end
                      : TextAlign.start,
                  style: cabecalho
                      ? Tipografia.cabecalhoTabela
                      : visiveis[i].numerica
                      ? Tipografia.numero(Tipografia.corpoTabela)
                      : Tipografia.corpoTabela,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _cartoes(BuildContext context, List<T> itens) {
    final cores = Theme.of(context).colorScheme;
    final montar = cartao!;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: Dim.e16),
      itemCount: itens.length,
      separatorBuilder: (_, _) => const SizedBox(height: Dim.e8),
      itemBuilder: (context, i) {
        final item = itens[i];
        final dados = montar(item);
        final tocar = aoTocarLinha;
        return Material(
          color: cores.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: cores.outlineVariant),
            borderRadius: BorderRadius.circular(Dim.raio),
          ),
          child: InkWell(
            onTap: tocar == null ? null : () => tocar(item),
            borderRadius: BorderRadius.circular(Dim.raio),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Dim.alvoMobile),
              child: Padding(
                padding: const EdgeInsets.all(Dim.e12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dados.titulo, style: Tipografia.rotulo),
                          if (dados.subtitulo != null)
                            Text(
                              dados.subtitulo!,
                              style: Tipografia.corpoTabela.copyWith(
                                color: cores.onSurfaceVariant,
                              ),
                            ),
                          if (dados.apoio != null)
                            Text(
                              dados.apoio!,
                              style: Tipografia.apoio.copyWith(
                                color: cores.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (dados.destaque != null) ...[
                      const SizedBox(width: Dim.e12),
                      Text(
                        dados.destaque!,
                        style: Tipografia.numero(Tipografia.rotulo),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
