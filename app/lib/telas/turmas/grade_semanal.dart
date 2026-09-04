import 'package:flutter/material.dart';

import '../../theme/cores.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/turmas.dart';
import '../../widgets/matriz_semanal.dart';

/// A grade semanal do wireframe §7.1: dia × horário, cada célula com método,
/// ocupação/capacidade e professor.
///
/// A forma da matriz — cabeçalho, coluna de hora, abas no mobile — é a
/// [MatrizSemanal], compartilhada com a grade de vagas do dashboard. O que é
/// desta tela é o **conteúdo** da célula.
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
  Widget build(BuildContext context) => MatrizSemanal(
    dias: grade.dias,
    horas: grade.horas,
    dataDe: grade.dataDe,
    temConteudo: (dia, hora) => grade.em(dia, hora).isNotEmpty,
    larguraHora: 72,
    // Abre no dia de hoje, e não sempre em segunda: a grade de segunda é a
    // resposta errada para quem abre o app na quinta.
    diaInicial: hojeSaoPaulo().weekday,
    // ⚠️ No mobile os cruzamentos vazios só aparecem para quem pode criar
    // bloco — e aparecem justamente para que "célula vazia → criar bloco ali"
    // exista no celular, e não só no desktop (achado da revisão da fase 05).
    mostrarHorasVazias: aoTocarVazio != null,
    vazioDoDia: 'Nenhum bloco em',
    celula: (dia, hora) => _Celula(
      dia: dia,
      hora: hora,
      blocos: grade.em(dia, hora),
      aoTocarBloco: aoTocarBloco,
      aoTocarVazio: aoTocarVazio == null
          ? null
          : () => aoTocarVazio!(dia, hora),
    ),
    legenda: const _Legenda(),
  );
}

class _Celula extends StatelessWidget {
  const _Celula({
    required this.dia,
    required this.hora,
    required this.blocos,
    required this.aoTocarBloco,
    this.aoTocarVazio,
  });

  final int dia;
  final String hora;
  final List<CelulaGrade> blocos;
  final void Function(CelulaGrade celula) aoTocarBloco;
  final VoidCallback? aoTocarVazio;

  @override
  Widget build(BuildContext context) {
    if (blocos.isEmpty) {
      if (aoTocarVazio == null) return const SizedBox(height: Dim.alturaBotao);
      return Semantics(
        button: true,
        label: '${nomeDia(dia)} $hora, sem turma, criar bloco',
        excludeSemantics: true,
        child: InkWell(
          onTap: aoTocarVazio,
          borderRadius: BorderRadius.circular(Dim.raio),
          child: SizedBox(
            // Alvo de toque: 32 px era menos que o mínimo do §8.4 nas duas
            // faixas, e no celular esta é a área que cria um bloco.
            height: Dim.alturaBotao,
            child: Center(
              child: Icon(
                Icons.add,
                size: 16,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
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
      // ⚠️ Dia e hora primeiro: numa matriz, o `Semantics` de uma célula sem a
      // coordenada anuncia "Interativo, 8 de 10" sem dizer QUANDO — e quem lê
      // por leitor de tela não tem a coluna nem a linha à vista (§8.5).
      label:
          '${nomeDia(celula.diaSemana)} ${celula.horaInicio}, '
          '${celula.metodoCodigo}, ${celula.ocupacao} de ${celula.capacidade}, '
          '${celula.salaNome}, '
          '${celula.professorNome ?? 'sem professor'}'
          '${grave ? ', acima da capacidade' : ''}'
          '${celula.lotado ? ', lotado' : ''}'
          '${celula.semCapacidade ? ', sem capacidade' : ''}',
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
                      // `apoio` em caixa alta, e não `badge` (§6): badge é o
                      // vocabulário do status do aluno e do tipo na turma, e
                      // aqui isto é só o rótulo do método.
                      style: Tipografia.apoio.copyWith(
                        color: grave
                            ? cores.onErrorContainer
                            : cores.onSurfaceVariant,
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
                // **Lotado é peso, não cor** (design-system §6): lotado é fato,
                // não problema — a turma cheia é o sistema funcionando. Cor de
                // alerta ali gasta o alerta que a turma ESTOURADA precisa.
                style: Tipografia.numero(Tipografia.rotulo).copyWith(
                  fontWeight: celula.lotado ? FontWeight.w600 : FontWeight.w500,
                  color: grave ? cores.onErrorContainer : null,
                ),
              ),
              Text(
                celula.professorNome ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tipografia.apoio.copyWith(
                  color: grave
                      ? cores.onErrorContainer
                      : cores.onSurfaceVariant,
                ),
              ),
              Text(
                celula.salaNome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tipografia.apoio.copyWith(
                  color: grave
                      ? cores.onErrorContainer
                      : cores.onSurfaceVariant,
                ),
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
        Text(
          'bloco lotado',
          style: estilo.copyWith(fontWeight: FontWeight.w600),
        ),
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
