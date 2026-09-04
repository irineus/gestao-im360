/// Os pedaços de tela que **duas** telas de turmas usam, escritos uma vez.
///
/// Moram aqui, e não em `telas/`, porque nenhum dos dois consumidores é dono:
/// o seletor de bloco é usado pelo painel da pendência `REP_VIRADA` (central) e
/// pela aba Turmas da ficha do aluno; o diálogo do veredito, pelo painel da
/// pendência e pelo painel do bloco. Duas cópias divergiriam na primeira vez
/// que alguém mexesse numa só — foi o que a revisão da fase 05 encontrou.
library;

import 'package:flutter/material.dart';

import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';
import '../widgets/escolha.dart';
import 'turmas.dart';

/// A lista de blocos com vaga, para escolher **um**.
///
/// ⚠️ O bloco em que o aluno **já está** é oferecido mesmo lotado: admitir só
/// disputa vaga quando a linha entra na conta (card 5.3, decisão 2), e virar o
/// tipo de uma alocação existente não muda a ocupação. Esconder o horário que o
/// aluno já frequenta esconderia exatamente a resposta mais provável.
class SeletorBloco extends StatelessWidget {
  const SeletorBloco({
    super.key,
    required this.blocos,
    required this.selecionado,
    required this.aoSelecionar,
    this.rotulo = 'Bloco *',
    this.jaAlocado = const {},
    this.vazio = semBlocoComVaga,
  });

  final List<CelulaGrade> blocos;
  final String? selecionado;
  final void Function(String blocoId) aoSelecionar;
  final String rotulo;

  /// Os blocos em que o aluno já está — a linha diz isso em vez do número de
  /// vagas, que ali não decide nada.
  final Set<String> jaAlocado;

  final String vazio;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    if (blocos.isEmpty) {
      return Text(
        vazio,
        style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          rotulo,
          style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
        ),
        for (final bloco in blocos)
          LinhaEscolha(
            rotulo: [
              rotuloBloco(bloco.diaSemana, bloco.horaInicio),
              bloco.salaNome,
              bloco.metodoCodigo,
            ].join(' · '),
            apoio: jaAlocado.contains(bloco.blocoId)
                ? 'já é a turma dele'
                : rotuloVagas(bloco.vagasLivres),
            marcada: bloco.blocoId == selecionado,
            aoTocar: () => aoSelecionar(bloco.blocoId),
          ),
      ],
    );
  }
}

String rotuloVagas(int vagas) =>
    '$vagas ${vagas == 1 ? 'vaga livre' : 'vagas livres'}';

/// Falta de escolha na lista **não** é erro do banco: é o formulário dizendo o
/// que falta, como qualquer validação de formato (design-system §5.4).
const escolhaBloco = 'Escolha o bloco na lista acima.';

const semBlocoComVaga =
    'Nenhum bloco com vaga livre nesta semana, e o aluno não está alocado em '
    'nenhum. Libere uma vaga, aumente a capacidade manual de um bloco ou '
    'cadastre outro horário antes de alocá-lo.';

/// Um bloco por horário a partir da grade da semana: a grade traz a mesma turma
/// uma vez por data, e repetir "Seg 08:00" cinco vezes faria a escolha parecer
/// maior do que é.
///
/// Ordena por dia, hora e sala — a ordem em que se lê um horário.
List<CelulaGrade> blocosParaEscolha(
  Iterable<CelulaGrade> grade, {
  String? metodoId,
  Set<String> jaAlocado = const {},
  bool somenteComVaga = true,
}) {
  final porBloco = <String, CelulaGrade>{};
  for (final c in grade) {
    if (metodoId != null && c.metodoId != metodoId) continue;
    if (somenteComVaga &&
        c.vagasLivres <= 0 &&
        !jaAlocado.contains(c.blocoId)) {
      continue;
    }
    porBloco.putIfAbsent(c.blocoId, () => c);
  }
  return porBloco.values.toList()..sort((a, b) {
    final dia = a.diaSemana.compareTo(b.diaSemana);
    if (dia != 0) return dia;
    final hora = a.horaInicio.compareTo(b.horaInicio);
    return hora != 0 ? hora : a.salaNome.compareTo(b.salaNome);
  });
}

// ---------------------------------------------------------------------------
// O veredito da virada REP
// ---------------------------------------------------------------------------

/// Mostra o **veredito** que `fn_reposicao_registrar` devolveu.
///
/// Resultado que muda a próxima ação é diálogo, nunca confirmação efêmera
/// (design-system §5.8): o veredito é o que diz se ainda há uma virada a
/// decidir. Aparece **onde quem marcou a presença está** — no painel do bloco e
/// no painel da pendência —, e não só no dia seguinte, quando a rotina das
/// 03:10 abrir a pendência (wireframe §7.2, ajuste 7 da regra de virada REP).
Future<void> mostrarVeredito(
  BuildContext context, {
  required bool veio,
  required String veredito,
}) => showDialog<void>(
  context: context,
  builder: (contexto) => AlertDialog(
    title: Text(veio ? 'Presença registrada' : 'Falta registrada'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Text(
        avisoVeredito(veredito) ?? avisoVereditoManter,
        style: Tipografia.corpo,
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.of(contexto).pop(),
        child: const Text('Entendi'),
      ),
    ],
  ),
);

const avisoVereditoManter =
    'A reposição foi registrada. A reposição deste aluno continua como está: o '
    'que ele tem a repor ainda cabe no prazo.';

// ---------------------------------------------------------------------------
// A linha de um aluno numa turma
// ---------------------------------------------------------------------------

/// Nome (opcionalmente clicável), badges e a linha de apoio — a mesma forma na
/// aba Turmas da ficha e na lista de alunos do painel do bloco, com a ação à
/// direita.
class LinhaTurma extends StatelessWidget {
  const LinhaTurma({
    super.key,
    required this.titulo,
    required this.apoio,
    this.badges = const [],
    this.aoTocarTitulo,
    this.acao,
  });

  final String titulo;

  /// Badge do tipo, status quando não é o esperado, "bloco desativado" — o que
  /// muda de uma tela para a outra.
  final List<Widget> badges;

  /// Os detalhes em uma linha, já unidos com `·`. Vazio some.
  final String apoio;

  final VoidCallback? aoTocarTitulo;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final texto = Text(
      titulo,
      style: aoTocarTitulo == null
          ? Tipografia.numero(Tipografia.rotulo)
          : Tipografia.rotulo.copyWith(decoration: TextDecoration.underline),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: Dim.e8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Dim.e8,
                  runSpacing: Dim.e4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (aoTocarTitulo == null)
                      texto
                    else
                      // Alvo de toque de 44 px: o nome leva à ficha, e é a
                      // jornada do monitor no celular (§8.4).
                      InkWell(
                        onTap: aoTocarTitulo,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: Dim.alvoMobile,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: texto,
                          ),
                        ),
                      ),
                    ...badges,
                  ],
                ),
                if (apoio.isNotEmpty)
                  Text(
                    apoio,
                    style: Tipografia.apoio.copyWith(
                      color: cores.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (acao != null) ...[const SizedBox(width: Dim.e8), acao!],
        ],
      ),
    );
  }
}
