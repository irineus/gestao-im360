import 'package:flutter/material.dart';

import '../../dashboard/dashboard.dart';
import '../../theme/cores.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';

/// A grade de vagas do wireframe §5: dia × horário, cada célula com **vagas
/// livres / capacidade** — a leitura que responde "onde ainda cabe alguém".
///
/// ⚠️ É a leitura **oposta** à da célula da tela de Turmas (card 5.6), que
/// mostra alocados/capacidade. As duas saem da mesma view e nunca divergem em
/// número; o que pode divergir é quem lê `2/10`. Por isso a legenda é parte da
/// grade e não um enfeite abaixo dela, e cada célula carrega um `Semantics` que
/// diz "2 vagas livres de 10" por extenso.
///
/// Duas faixas (card 2.6 §2.1): no `desktop` e no `tablet` a matriz inteira; no
/// `mobile`, uma lista vertical por dia — uma matriz de seis colunas num celular
/// só se lê com zoom, e o wireframe §5 já manda degradá-la assim.
class GradeVagas extends StatelessWidget {
  const GradeVagas({super.key, required this.grade, this.aoTocarCelula});

  final GradeSemana grade;

  /// Nulo deixa a célula sem toque. Toda célula/número do dashboard é atalho
  /// (wireframes §3.3), e o destino daqui é a grade de Turmas — mas quem não
  /// pode abri-la não recebe um atalho que leva a "Sem acesso" (card 5.8 (1)).
  final void Function(int dia, String hora)? aoTocarCelula;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, restricoes) =>
        faixaDe(restricoes.maxWidth) == Faixa.mobile
        ? _ListaPorDia(grade: grade, aoTocarCelula: aoTocarCelula)
        : _MatrizVagas(grade: grade, aoTocarCelula: aoTocarCelula),
  );
}

const _larguraHora = 64.0;

class _MatrizVagas extends StatelessWidget {
  const _MatrizVagas({required this.grade, this.aoTocarCelula});

  final GradeSemana grade;
  final void Function(int dia, String hora)? aoTocarCelula;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SizedBox(width: _larguraHora),
            for (final dia in grade.dias)
              Expanded(
                child: Column(
                  children: [
                    Text(nomeDiaCurto(dia), style: Tipografia.cabecalhoTabela),
                    Text(
                      formatarDataCurta(grade.dataDe(dia)),
                      style: Tipografia.numero(Tipografia.apoio)
                          .copyWith(color: cores.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const Divider(),
        for (final hora in grade.horas) ...[
          Row(
            children: [
              SizedBox(
                width: _larguraHora,
                child: Text(hora, style: Tipografia.numero(Tipografia.rotulo)),
              ),
              for (final dia in grade.dias)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(Dim.e4),
                    child: _CelulaVagas(
                      dia: dia,
                      hora: hora,
                      vagas: vagasDa(grade.em(dia, hora)),
                      aoTocar: aoTocarCelula,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 1),
        ],
        const SizedBox(height: Dim.e8),
        const LegendaVagas(),
      ],
    );
  }
}

class _ListaPorDia extends StatelessWidget {
  const _ListaPorDia({required this.grade, this.aoTocarCelula});

  final GradeSemana grade;
  final void Function(int dia, String hora)? aoTocarCelula;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final dia in grade.dias)
          // Dia sem turma nenhuma não vira seção vazia na lista: no celular a
          // rolagem é o recurso escasso, e "Quinta — nada" ocuparia o espaço de
          // um horário que existe. Na matriz a coluna fica, porque lá a forma
          // fixa é o que deixa comparar os dias.
          if (grade.horas.any((h) => grade.em(dia, h).isNotEmpty)) ...[
            Padding(
              padding: const EdgeInsets.only(top: Dim.e12, bottom: Dim.e4),
              child: Text(
                '${nomeDia(dia)} ${formatarDataCurta(grade.dataDe(dia))}',
                style: Tipografia.cabecalhoTabela.copyWith(
                  color: cores.onSurfaceVariant,
                ),
              ),
            ),
            for (final hora in grade.horas)
              if (grade.em(dia, hora).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: Dim.e4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: _larguraHora,
                        child: Text(
                          hora,
                          style: Tipografia.numero(Tipografia.rotulo),
                        ),
                      ),
                      Expanded(
                        child: _CelulaVagas(
                          dia: dia,
                          hora: hora,
                          vagas: vagasDa(grade.em(dia, hora)),
                          aoTocar: aoTocarCelula,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        const SizedBox(height: Dim.e12),
        const LegendaVagas(),
      ],
    );
  }
}

/// `2/10` = duas vagas livres de dez lugares. A cor nunca é o único portador do
/// significado (card 1.9): lotada e acima da capacidade têm cada uma o seu
/// ícone e o seu texto na legenda.
class _CelulaVagas extends StatelessWidget {
  const _CelulaVagas({
    required this.dia,
    required this.hora,
    required this.vagas,
    this.aoTocar,
  });

  final int dia;
  final String hora;
  final VagasNaCelula vagas;
  final void Function(int dia, String hora)? aoTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final escuro = tema.brightness == Brightness.dark;

    if (vagas.semBloco) {
      return SizedBox(
        height: Dim.e32,
        child: Center(
          child: Text(
            '·',
            style: Tipografia.apoio.copyWith(color: cores.outlineVariant),
          ),
        ),
      );
    }

    final corTexto = vagas.acimaCapacidade
        ? cores.error
        : vagas.lotada
        ? (escuro ? Cores.atencaoEscuro : Cores.atencao)
        : cores.onSurface;

    final conteudo = Container(
      height: Dim.e32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(
          color: vagas.acimaCapacidade ? cores.error : cores.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(Dim.raio),
        color: vagas.acimaCapacidade ? cores.errorContainer : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            vagas.texto,
            style: Tipografia.numero(Tipografia.rotulo)
                .copyWith(color: corTexto),
          ),
          if (vagas.acimaCapacidade) ...[
            const SizedBox(width: Dim.e4),
            Icon(Icons.warning_amber_rounded, size: 14, color: cores.error),
          ] else if (vagas.lotada) ...[
            const SizedBox(width: Dim.e4),
            Icon(Icons.block, size: 14, color: corTexto),
          ],
          if (vagas.salas > 1) ...[
            const SizedBox(width: Dim.e4),
            Text(
              '${vagas.salas}×',
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      button: aoTocar != null,
      label: descricaoCelula(dia, hora, vagas),
      excludeSemantics: true,
      child: aoTocar == null
          ? conteudo
          : InkWell(
              onTap: () => aoTocar!(dia, hora),
              borderRadius: BorderRadius.circular(Dim.raio),
              child: conteudo,
            ),
    );
  }
}

/// A legenda existe porque `2/10` tem duas leituras possíveis dentro deste mesmo
/// sistema, e a grade de Turmas usa a outra.
class LegendaVagas extends StatelessWidget {
  const LegendaVagas({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final corAtencao = tema.brightness == Brightness.dark
        ? Cores.atencaoEscuro
        : Cores.atencao;
    final estilo = Tipografia.apoio.copyWith(color: cores.onSurfaceVariant);

    return Wrap(
      spacing: Dim.e16,
      runSpacing: Dim.e4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(rotuloLegendaVagas, style: estilo),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 14, color: corAtencao),
            const SizedBox(width: Dim.e4),
            Text('turma lotada', style: estilo),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: cores.error),
            const SizedBox(width: Dim.e4),
            Text('acima da capacidade', style: estilo),
          ],
        ),
        Text('2× = duas salas no mesmo horário', style: estilo),
      ],
    );
  }
}

/// Texto único, para a tela e o teste lerem a mesma frase.
const rotuloLegendaVagas = 'Célula: vagas livres / capacidade';
