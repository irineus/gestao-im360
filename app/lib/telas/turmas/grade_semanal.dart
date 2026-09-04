import 'package:flutter/material.dart';

import '../../theme/cores.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/turmas.dart';

/// A grade semanal do wireframe §7.1: dia × horário, cada célula com método,
/// ocupação/capacidade e professor.
///
/// Duas faixas (card 2.6 §2.1): no `desktop` e no `tablet` a matriz inteira;
/// no `mobile`, **um dia por vez** em abas, com as células em lista — uma
/// matriz de seis colunas num celular só se lê com zoom.
///
/// A célula é uma **lista** de blocos, não um bloco: a `unique` de
/// `bloco_horario` é por `(unidade, sala, dia, hora)`, então duas salas podem
/// ter aula no mesmo horário (card 5.1). Mostrar só o primeiro perderia a outra
/// turma em silêncio.
class GradeSemanal extends StatelessWidget {
  const GradeSemanal({
    super.key,
    required this.grade,
    required this.aoTocarBloco,
    this.aoTocarVazio,
  });

  final GradeSemana grade;
  final void Function(CelulaGrade celula) aoTocarBloco;

  /// Nulo quando o usuário não tem `turmas.criar`: a célula vazia deixa de ser
  /// tocável em vez de oferecer uma ação que a RLS recusaria (card 2.6 dec. 1).
  final void Function(int dia, String hora)? aoTocarVazio;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, restricoes) =>
        faixaDe(restricoes.maxWidth) == Faixa.mobile
        ? _GradeMobile(
            grade: grade,
            aoTocarBloco: aoTocarBloco,
            aoTocarVazio: aoTocarVazio,
          )
        : _GradeDesktop(
            grade: grade,
            aoTocarBloco: aoTocarBloco,
            aoTocarVazio: aoTocarVazio,
          ),
  );
}

const _larguraHora = 72.0;

class _GradeDesktop extends StatelessWidget {
  const _GradeDesktop({
    required this.grade,
    required this.aoTocarBloco,
    this.aoTocarVazio,
  });

  final GradeSemana grade;
  final void Function(CelulaGrade celula) aoTocarBloco;
  final void Function(int dia, String hora)? aoTocarVazio;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Dim.e16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(width: _larguraHora),
              for (final dia in grade.dias)
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
                          formatarDataCurta(grade.dataDe(dia)),
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
          for (final hora in grade.horas) ...[
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _larguraHora,
                    child: Padding(
                      padding: const EdgeInsets.only(top: Dim.e8),
                      child: Text(
                        hora,
                        style: Tipografia.numero(Tipografia.rotulo),
                      ),
                    ),
                  ),
                  for (final dia in grade.dias)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Dim.e4,
                          vertical: Dim.e4,
                        ),
                        child: _Celula(
                          blocos: grade.em(dia, hora),
                          aoTocarBloco: aoTocarBloco,
                          aoTocarVazio: aoTocarVazio == null
                              ? null
                              : () => aoTocarVazio!(dia, hora),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          const SizedBox(height: Dim.e8),
          const _Legenda(),
        ],
      ),
    );
  }
}

class _GradeMobile extends StatelessWidget {
  const _GradeMobile({
    required this.grade,
    required this.aoTocarBloco,
    this.aoTocarVazio,
  });

  final GradeSemana grade;
  final void Function(CelulaGrade celula) aoTocarBloco;
  final void Function(int dia, String hora)? aoTocarVazio;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: grade.dias.length,
    child: Column(
      children: [
        TabBar(
          isScrollable: true,
          tabs: [
            for (final dia in grade.dias)
              Tab(
                text:
                    '${nomeDiaCurto(dia)} '
                    '${formatarDataCurta(grade.dataDe(dia))}',
              ),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              for (final dia in grade.dias)
                ListView(
                  padding: const EdgeInsets.all(Dim.e16),
                  children: [
                    for (final hora in grade.horas)
                      if (grade.em(dia, hora).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Dim.e12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                hora,
                                style: Tipografia.numero(Tipografia.rotulo),
                              ),
                              const SizedBox(height: Dim.e4),
                              _Celula(
                                blocos: grade.em(dia, hora),
                                aoTocarBloco: aoTocarBloco,
                              ),
                            ],
                          ),
                        ),
                    if (grade.horas.every((h) => grade.em(dia, h).isEmpty))
                      Padding(
                        padding: const EdgeInsets.all(Dim.e24),
                        child: Text(
                          'Nenhum bloco em ${nomeDia(dia).toLowerCase()}.',
                          textAlign: TextAlign.center,
                          style: Tipografia.corpo,
                        ),
                      ),
                    const SizedBox(height: Dim.e8),
                    const _Legenda(),
                  ],
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Celula extends StatelessWidget {
  const _Celula({
    required this.blocos,
    required this.aoTocarBloco,
    this.aoTocarVazio,
  });

  final List<CelulaGrade> blocos;
  final void Function(CelulaGrade celula) aoTocarBloco;
  final VoidCallback? aoTocarVazio;

  @override
  Widget build(BuildContext context) {
    if (blocos.isEmpty) {
      if (aoTocarVazio == null) return const SizedBox(height: Dim.e32);
      return InkWell(
        onTap: aoTocarVazio,
        borderRadius: BorderRadius.circular(Dim.raio),
        child: SizedBox(
          height: Dim.e32,
          child: Center(
            child: Icon(
              Icons.add,
              size: 16,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final bloco in blocos)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.e4),
            child: _CartaoBloco(
              celula: bloco,
              aoTocar: () => aoTocarBloco(bloco),
            ),
          ),
      ],
    );
  }
}

/// A célula do wireframe: método · ocupação/capacidade · professor, com os dois
/// alertas do §7.1. O rótulo é sempre texto — a cor nunca é o único portador do
/// significado (card 1.9).
class _CartaoBloco extends StatelessWidget {
  const _CartaoBloco({required this.celula, required this.aoTocar});

  final CelulaGrade celula;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final escuro = tema.brightness == Brightness.dark;
    final alertas = alertasDo(celula);
    final grave = alertas.contains(AlertaBloco.acimaCapacidade);
    final corAtencao = escuro ? Cores.atencaoEscuro : Cores.atencao;

    return Semantics(
      button: true,
      label:
          '${celula.metodoCodigo}, ${celula.ocupacao} de ${celula.capacidade}, '
          '${celula.salaNome}, '
          '${celula.professorNome ?? 'sem professor'}'
          '${grave ? ', acima da capacidade' : ''}',
      child: InkWell(
        onTap: aoTocar,
        borderRadius: BorderRadius.circular(Dim.raio),
        child: Container(
          padding: const EdgeInsets.all(Dim.e8),
          decoration: BoxDecoration(
            border: Border.all(
              color: grave ? cores.error : cores.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(Dim.raio),
            color: grave ? cores.errorContainer : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      celula.metodoCodigo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tipografia.badge.copyWith(
                        color: cores.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (grave)
                    Tooltip(
                      message: 'Acima da capacidade',
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: cores.error,
                      ),
                    ),
                  if (alertas.contains(AlertaBloco.semProfessor))
                    Tooltip(
                      message: 'Sem professor',
                      child: Icon(
                        Icons.person_off_outlined,
                        size: 16,
                        color: corAtencao,
                      ),
                    ),
                ],
              ),
              Text(
                celula.ocupacaoTexto,
                style: Tipografia.numero(Tipografia.rotulo),
              ),
              Text(
                celula.professorNome ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
              ),
              Text(
                celula.salaNome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A legenda existe porque os dois ⚠ da grade significam coisas diferentes e a
/// forma sozinha não diz qual é qual.
class _Legenda extends StatelessWidget {
  const _Legenda();

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
        Text('Célula: método · alocados/capacidade · professor', style: estilo),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: cores.error),
            const SizedBox(width: Dim.e4),
            Text('acima da capacidade', style: estilo),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 14, color: corAtencao),
            const SizedBox(width: Dim.e4),
            Text('sem professor', style: estilo),
          ],
        ),
      ],
    );
  }
}
