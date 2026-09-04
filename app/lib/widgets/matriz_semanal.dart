import 'package:flutter/material.dart';

import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';
import '../turmas/turmas.dart' show formatarDataCurta, nomeDia, nomeDiaCurto;

/// A matriz **dia × horário** das duas telas que a têm: a grade de Turmas
/// (wireframe §7.1) e a grade de vagas do dashboard (§5).
///
/// Era o mesmo desenho escrito duas vezes — cabeçalho com dia e data, coluna de
/// hora, divisores entre as linhas e a legenda no rodapé —, e as duas cópias já
/// tinham divergido no mobile: Turmas em abas Seg–Sáb, dashboard em lista
/// vertical por dia. **A forma é uma só desde 04/09/2026** (decisão de Irineu,
/// revisão da fase 05): abas nas duas telas, como o design-system §6 manda para
/// as telas 2 e 4, abrindo no dia de hoje.
///
/// O que muda de uma tela para a outra é [celula] — o que se desenha no
/// cruzamento — e a [legenda], que existe porque `2/10` tem duas leituras
/// dentro deste mesmo sistema.
class MatrizSemanal extends StatelessWidget {
  const MatrizSemanal({
    super.key,
    required this.dias,
    required this.horas,
    required this.dataDe,
    required this.temConteudo,
    required this.celula,
    required this.legenda,
    this.larguraHora = 64,
    this.diaInicial,
    this.mostrarHorasVazias = false,
    this.vazioDoDia,
    this.padding = const EdgeInsets.all(Dim.e16),
    this.alturaLinhaMobile = 96,
  });

  /// As colunas: Seg–Sáb, mais domingo quando houver bloco nele.
  final List<int> dias;

  /// As linhas — só os horários que existem. A grade não inventa horário.
  final List<String> horas;

  final DateTime Function(int dia) dataDe;

  /// Se há algo naquele cruzamento — decide o que o mobile pula.
  final bool Function(int dia, String hora) temConteudo;

  final Widget Function(int dia, String hora) celula;
  final Widget legenda;

  final double larguraHora;

  /// A aba que abre no mobile. Nulo = a primeira. **Hoje**, nas duas telas: a
  /// grade de terça é a resposta errada para quem abre o app na quinta.
  final int? diaInicial;

  /// Renderizar também o cruzamento vazio no mobile. Verdadeiro só quando a
  /// célula vazia **faz alguma coisa** — em Turmas ela cria um bloco ali, e sem
  /// isto o gesto existe no desktop e não no celular (achado da revisão da
  /// fase 05).
  final bool mostrarHorasVazias;

  /// O que dizer quando o dia inteiro está vazio no mobile.
  final String? vazioDoDia;

  final EdgeInsets padding;

  /// Quanto uma linha de horário ocupa no mobile — só para **estimar** a altura
  /// das abas quando o pai não dá altura nenhuma (ver [build]). A grade de
  /// Turmas desenha cartões; a de vagas, uma caixinha.
  final double alturaLinhaMobile;

  /// ⚠️ `TabBarView` exige altura **limitada**, e a grade de vagas vive dentro
  /// de um `SingleChildScrollView` — altura infinita. Sem esta divisão o
  /// dashboard no celular quebrava no layout ("RenderFlex children have
  /// non-zero flex but incoming height constraints are unbounded"), que é erro
  /// de framework e não aparece em tela nenhuma até alguém abrir no celular.
  ///
  /// Onde há altura (a grade de Turmas, dentro de um `Expanded`), as abas a
  /// ocupam. Onde não há, a altura é estimada pelo número de horários — e é
  /// **estimativa mesmo**: a lista rola por dentro, então errar para menos
  /// custa rolagem, não conteúdo escondido.
  double get alturaEstimadaDasAbas {
    const barra = 60.0, legenda = 88.0;
    final linhas = horas.isEmpty ? 1 : horas.length.clamp(1, 8);
    return barra + legenda + linhas * alturaLinhaMobile;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, restricoes) {
      if (faixaDe(restricoes.maxWidth) != Faixa.mobile) {
        return _Matriz(matriz: this);
      }
      final abas = _Abas(matriz: this);
      return restricoes.maxHeight.isFinite
          ? abas
          : SizedBox(height: alturaEstimadaDasAbas, child: abas);
    },
  );
}

class _Matriz extends StatelessWidget {
  const _Matriz({required this.matriz});

  final MatrizSemanal matriz;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: matriz.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(width: matriz.larguraHora),
              for (final dia in matriz.dias)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Dim.e4),
                    child: Column(
                      children: [
                        Text(
                          nomeDiaCurto(dia),
                          style: Tipografia.cabecalhoTabela,
                        ),
                        Text(
                          formatarDataCurta(matriz.dataDe(dia)),
                          style: Tipografia.numero(Tipografia.apoio)
                              .copyWith(color: cores.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const Divider(),
          for (final hora in matriz.horas) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: matriz.larguraHora,
                    child: Padding(
                      padding: const EdgeInsets.only(top: Dim.e8),
                      child: Text(
                        hora,
                        style: Tipografia.numero(Tipografia.rotulo),
                      ),
                    ),
                  ),
                  for (final dia in matriz.dias)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Dim.e4,
                          vertical: Dim.e4,
                        ),
                        child: matriz.celula(dia, hora),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          const SizedBox(height: Dim.e8),
          matriz.legenda,
        ],
      ),
    );
  }
}

/// O mobile: **um dia por vez**, em abas. Uma matriz de seis colunas num
/// celular só se lê com zoom (card 2.6 §2.1).
class _Abas extends StatelessWidget {
  const _Abas({required this.matriz});

  final MatrizSemanal matriz;

  @override
  Widget build(BuildContext context) {
    final inicial = matriz.dias.indexOf(matriz.diaInicial ?? -1);
    return DefaultTabController(
      length: matriz.dias.length,
      initialIndex: inicial < 0 ? 0 : inicial,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final dia in matriz.dias)
                Tab(
                  text:
                      '${nomeDiaCurto(dia)} '
                      '${formatarDataCurta(matriz.dataDe(dia))}',
                ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final dia in matriz.dias) _Dia(matriz: matriz, dia: dia),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dia extends StatelessWidget {
  const _Dia({required this.matriz, required this.dia});

  final MatrizSemanal matriz;
  final int dia;

  @override
  Widget build(BuildContext context) {
    final visiveis = [
      for (final hora in matriz.horas)
        if (matriz.mostrarHorasVazias || matriz.temConteudo(dia, hora)) hora,
    ];
    final vazio = matriz.horas.every((h) => !matriz.temConteudo(dia, h));

    return ListView(
      padding: matriz.padding,
      children: [
        if (vazio && matriz.vazioDoDia != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.e12),
            child: Text(
              '${matriz.vazioDoDia!} ${nomeDia(dia).toLowerCase()}.',
              textAlign: TextAlign.center,
              style: Tipografia.corpo,
            ),
          ),
        for (final hora in visiveis)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.e12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: matriz.larguraHora,
                  child: Text(
                    hora,
                    style: Tipografia.numero(Tipografia.rotulo),
                  ),
                ),
                Expanded(child: matriz.celula(dia, hora)),
              ],
            ),
          ),
        const SizedBox(height: Dim.e8),
        matriz.legenda,
      ],
    );
  }
}
