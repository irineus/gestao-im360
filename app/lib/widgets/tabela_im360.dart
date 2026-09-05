import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';
import 'barra_filtros.dart';
import 'estados.dart';

/// O tom de uma linha em alerta (design-system §5.2). `atencao` é o par tonal
/// terciário (âmbar), `erro` é o par de erro — e nenhum dos dois substitui o
/// ícone e a palavra que dão o motivo: cor não é portadora única (§8.2).
enum TomLinha { nenhum, atencao, erro }

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
    this.celula,
  }) : assert(prioridade >= 1, 'prioridade começa em 1');

  final String titulo;

  /// O texto da célula — e o que a busca, o cartão e a leitura de tela veem.
  final String Function(T item) texto;

  /// Célula em widget (um badge, por exemplo) no lugar do texto. Nasceu no
  /// card 4.6, para a coluna de status do aluno ser o `BadgeStatus` do
  /// design-system §5.1 e não a palavra solta; [texto] continua obrigatório,
  /// porque o cartão do mobile e a acessibilidade leem por ele.
  final Widget Function(T item)? celula;

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
    this.iconeApoio,
    this.corApoio,
    this.destaque,
    this.badge,
  });

  final String titulo;
  final String? subtitulo;
  final String? apoio;

  /// Ícone antes da linha de apoio — é como o ⚠ de "sem turma" existe no
  /// celular.
  ///
  /// ⚠️ **Ícone, e nunca o caractere.** O app empacota só Inter e Roboto: um
  /// `⚠` no texto vira caixa vazia na web (a CSP bloqueia o download da fonte
  /// de emoji, cards 3.8/3.9) e o leitor de tela anuncia "sinal de aviso" antes
  /// do texto. A célula do desktop já fazia assim; o cartão do mobile ficou
  /// para trás e perdeu o alerta inteiro quando o glifo saiu (revisão da
  /// fase 05, item A1).
  final IconData? iconeApoio;
  final Color? corApoio;

  final String? destaque;

  /// Badge à direita do título (design-system §5.2: "título, linha
  /// secundária, badge") — o status do aluno, no card 4.6.
  final Widget? badge;
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
    this.tomDaLinha,
    this.linhaSelecionada,
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

  /// "Linha em alerta" do design-system §5.2: fundo tonal de atenção ou de erro.
  /// Nasceu na tela 6 (card 6.7), que é a primeira com linha em alerta — saldo
  /// abaixo do mínimo (atenção) e saldo negativo (erro).
  ///
  /// ⚠️ O fundo tonal é a **segunda** metade do contrato: cor nunca é portadora
  /// única (§8.2), e o ícone com forma própria mora na célula que dá o motivo —
  /// no caso da tela 6, a do Saldo. Ver a divergência registrada no §11 do
  /// design-system: o documento pede o ícone na PRIMEIRA célula, e ele fica na
  /// do número.
  final TomLinha Function(T item)? tomDaLinha;

  /// A linha destacada como escolhida — o painel de detalhe abaixo da tabela
  /// (tela 6) mostra o conteúdo dela, e sem a marca a lista não diz de quem é o
  /// painel. Nasceu no card 6.7.
  final bool Function(T item)? linhaSelecionada;

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
              child: _barra(context, mobile),
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

  /// A barra saiu deste arquivo na revisão das telas 06/07 (item H4): as telas
  /// 4 e 5 não usam a tabela e precisavam da MESMA barra.
  Widget _barra(BuildContext context, bool mobile) => BarraFiltrosIm360(
    filtros: filtros,
    filtrosAtivos: filtrosAtivos,
    acoes: acoes,
    mobile: mobile,
  );

  Widget _tabela(BuildContext context, List<T> itens, double largura) {
    final visiveis = colunasVisiveis(colunas, largura - Dim.e32);
    return Column(
      children: [
        _linha(visiveis, celulas: [for (final c in visiveis) c.titulo]),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: itens.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final item = itens[i];
              final tocar = aoTocarLinha;
              final cores = Theme.of(context).colorScheme;
              final tom = tomDaLinha?.call(item) ?? TomLinha.nenhum;
              final selecionada = linhaSelecionada?.call(item) ?? false;
              final fundo = switch (tom) {
                TomLinha.erro => cores.errorContainer,
                TomLinha.atencao => cores.tertiaryContainer,
                TomLinha.nenhum =>
                  selecionada ? cores.surfaceContainerHighest : null,
              };
              // O texto acompanha o fundo tonal. Sem isto a célula ficava com
              // o `onSurface` da tabela sobre um fundo que não é o da tabela —
              // o par de contraste verificado é (container, onContainer), e
              // metade dele não estava sendo usada (item A1).
              final corTexto = switch (tom) {
                TomLinha.erro => cores.onErrorContainer,
                TomLinha.atencao => cores.onTertiaryContainer,
                TomLinha.nenhum => null,
              };
              final linha = _linha(
                visiveis,
                item: item,
                selecionada: selecionada,
                cores: cores,
              );
              return Material(
                color: fundo ?? Colors.transparent,
                child: InkWell(
                  onTap: tocar == null ? null : () => tocar(item),
                  child: corTexto == null
                      ? linha
                      : DefaultTextStyle.merge(
                          style: TextStyle(color: corTexto),
                          child: linha,
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Uma linha: o cabeçalho ([celulas] com os títulos) ou o [item].
  Widget _linha(
    List<ColunaIm360<T>> visiveis, {
    List<String>? celulas,
    T? item,
    bool selecionada = false,
    ColorScheme? cores,
  }) => Container(
    height: Dim.alturaLinha,
    decoration: selecionada && cores != null
        // Barra à esquerda, e não só o fundo: a marca de "é esta a linha do
        // painel" precisa sobreviver ao fundo tonal de alerta, que já ocupa a
        // cor da própria linha.
        ? BoxDecoration(
            border: Border(left: BorderSide(color: cores.primary, width: 3)),
          )
        : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Dim.e16),
      child: Row(
        children: [
          for (var i = 0; i < visiveis.length; i++)
            Expanded(
              flex: visiveis[i].flex,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Dim.e8),
                child: _celula(visiveis[i], celulas?[i], item),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _celula(ColunaIm360<T> coluna, String? titulo, T? item) {
    if (titulo != null || item == null) {
      return Text(
        titulo ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: coluna.numerica ? TextAlign.end : TextAlign.start,
        style: Tipografia.cabecalhoTabela,
      );
    }
    final construtor = coluna.celula;
    if (construtor != null) {
      return Align(
        alignment: coluna.numerica
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: construtor(item),
      );
    }
    return Text(
      coluna.texto(item),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: coluna.numerica ? TextAlign.end : TextAlign.start,
      style: coluna.numerica
          ? Tipografia.numero(Tipografia.corpoTabela)
          : Tipografia.corpoTabela,
    );
  }

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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  dados.titulo,
                                  style: Tipografia.rotulo,
                                ),
                              ),
                              if (dados.badge != null) ...[
                                const SizedBox(width: Dim.e8),
                                dados.badge!,
                              ],
                            ],
                          ),
                          if (dados.subtitulo != null)
                            Text(
                              dados.subtitulo!,
                              style: Tipografia.corpoTabela.copyWith(
                                color: cores.onSurfaceVariant,
                              ),
                            ),
                          if (dados.apoio != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (dados.iconeApoio != null) ...[
                                  Icon(
                                    dados.iconeApoio,
                                    size: 14,
                                    color:
                                        dados.corApoio ??
                                        cores.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: Dim.e4),
                                ],
                                Flexible(
                                  child: Text(
                                    dados.apoio!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Tipografia.apoio.copyWith(
                                      color:
                                          dados.corApoio ??
                                          cores.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
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
