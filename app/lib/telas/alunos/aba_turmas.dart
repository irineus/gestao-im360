import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alunos/alunos.dart';
import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../erros/erro_app.dart';
import '../../infraestrutura/infraestrutura.dart';
import '../../infraestrutura/infraestrutura_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/turmas.dart';
import '../../turmas/turmas_provider.dart';
import '../../widgets/badge_tipo.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';

/// Aba **Turmas** da ficha do aluno (docs/wireframes.md §6.4), card 5.7.
///
/// Três seções, e a ordem é a do que se olha primeiro: os blocos em que ele
/// está (com o badge de contorno do tipo e o `tipo_desde`), a situação REP
/// quando há o que dizer, e as reposições pontuais.
///
/// **A aba exige `turmas.ler`, que a rota da ficha não exige** (o conjunto
/// mínimo de `/alunos` é `alunos.ler + materiais.ler`, card 2.4 §6). Sem ela,
/// `v_bloco_alunos` viria vazia e `fn_rep_situacao` erraria — e "vazio" aqui
/// seria indistinguível de "este aluno não está em turma nenhuma", que é
/// exatamente a mentira que o projeto cataloga. Por isso a aba diz o que falta
/// em vez de mostrar uma lista vazia.
class AbaTurmas extends ConsumerWidget {
  const AbaTurmas({super.key, required this.aluno});

  final Aluno aluno;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissoes = ref.watch(permissoesProvider);
    if (!permissoes.contains('turmas.ler')) {
      return const EstadoSemAcesso(faltando: {'turmas.ler'});
    }

    final turmas = ref.watch(turmasProvider);
    final reposicoes = ref.watch(reposicoesAlunoProvider(aluno.id!));

    return ListView(
      padding: const EdgeInsets.all(Dim.e16),
      children: [
        const TituloSecao(
          texto: 'Blocos',
          apoio:
              'Alocação vale toda semana. O tipo diz como o aluno assiste; '
              'REP é reposição contínua, que ocupa vaga fixa.',
        ),
        turmas.when(
          loading: () => const EstadoCarregando(linhas: 2),
          error: (erro, _) => EstadoErro(
            mensagem: (erro is ErroApp ? erro : traduzirErro(erro)).mensagem,
            aoRepetir: ref.read(versaoTurmasProvider.notifier).incrementar,
          ),
          data: (todas) => _Blocos(
            turmas: ref.watch(turmasPorAlunoProvider)[aluno.id!] ?? const [],
            aluno: aluno,
          ),
        ),
        const SizedBox(height: Dim.e24),
        _SituacaoRep(aluno: aluno),
        const TituloSecao(
          texto: 'Reposições',
          apoio:
              'Lançamentos pontuais com data. Só a PREVISTA ocupa vaga, e só '
              'no dia dela.',
        ),
        reposicoes.when(
          loading: () => const EstadoCarregando(linhas: 2),
          error: (erro, _) => EstadoErro(
            mensagem: (erro is ErroApp ? erro : traduzirErro(erro)).mensagem,
            aoRepetir: ref.read(versaoTurmasProvider.notifier).incrementar,
          ),
          data: (lista) => _Reposicoes(reposicoes: lista),
        ),
      ],
    );
  }
}

const vazioTurmasAluno = 'Este aluno não está em nenhuma turma.';
const vazioReposicoes = 'Nenhuma reposição lançada para este aluno.';

/// O aviso que a lista de alunos também dá, aqui com o detalhe que só a ficha
/// tem: **qual** bloco está desativado.
const avisoTurmaDesativada =
    'Este aluno está alocado num bloco desativado, que não aparece mais na '
    'grade. Para o sistema ele está sem turma — realoque-o num bloco ativo pela '
    'tela de Turmas.';

const avisoSemTurma =
    'Aluno em curso sem nenhuma turma ativa. A rotina diária abre a pendência '
    '"aluno sem turma" enquanto isso valer.';

class _Blocos extends ConsumerWidget {
  const _Blocos({required this.turmas, required this.aluno});

  final List<TurmaDoAluno> turmas;
  final Aluno aluno;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final salas = {
      for (final s in ref.watch(salasProvider).value ?? const <Sala>[])
        s.id: s.nome,
    };
    final metodos = {
      for (final m in ref.watch(metodosProvider).value ?? const <Metodo>[])
        m.id: m.nome,
    };
    final orfa = turmas.any((t) => !t.blocoAtivo);
    final ativas = turmas.where((t) => t.blocoAtivo).length;

    if (turmas.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            vazioTurmasAluno,
            style: Tipografia.corpo.copyWith(color: cores.onSurfaceVariant),
          ),
          if (aluno.emAula) ...[
            const SizedBox(height: Dim.e8),
            const AvisoTonal(mensagem: avisoSemTurma),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final turma in turmas)
          Padding(
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
                          Text(
                            turma.rotulo,
                            style: Tipografia.numero(Tipografia.rotulo),
                          ),
                          BadgeTipo(turma.tipo),
                          if (!turma.blocoAtivo)
                            Text(
                              'bloco desativado',
                              style: Tipografia.apoio.copyWith(
                                color: cores.error,
                              ),
                            ),
                        ],
                      ),
                      Text(
                        [
                          metodos[turma.metodoId] ?? '—',
                          salas[turma.salaId] ?? '—',
                          if (turma.tipoDesde != null)
                            '${turma.tipo} desde '
                                '${formatarData(turma.tipoDesde!)}',
                          if (turma.dataInicioPrevista != null)
                            'início previsto '
                                '${formatarData(turma.dataInicioPrevista!)}',
                        ].join(' · '),
                        style: Tipografia.apoio.copyWith(
                          color: cores.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (orfa) ...[
          const SizedBox(height: Dim.e8),
          const AvisoTonal(mensagem: avisoTurmaDesativada),
        ],
        if (aluno.emAula && ativas == 0 && !orfa) ...[
          const SizedBox(height: Dim.e8),
          const AvisoTonal(mensagem: avisoSemTurma),
        ],
      ],
    );
  }
}

/// A situação REP do card 2.5, mostrada **com os números** e não só com o
/// veredito: "3 aulas em aberto, a mais antiga de 12/09, prazo até 12/10,
/// cabem 2" é acionável; "sugerido virar contínuo" não é (card 5.3).
///
/// Só aparece quando há o que dizer — débito, aluno já contínuo, ou veredito
/// diferente de MANTER. Um painel permanente dizendo "0 aulas a repor" em toda
/// ficha treina a pessoa a não olhar para ele.
class _SituacaoRep extends ConsumerWidget {
  const _SituacaoRep({required this.aluno});

  final Aluno aluno;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final situacao = ref.watch(situacaoRepProvider(aluno.id!)).value;
    if (situacao == null || !situacao.relevante) return const SizedBox.shrink();

    // A MESMA frase que a central de pendências mostra ao lado do REP_VIRADA
    // (card 5.8) — uma implementação só, em `turmas.dart`.
    final linhas = resumoSituacaoRep(situacao);

    final aviso = avisoVeredito(situacao.veredito);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloSecao(
          texto: 'Situação de reposição',
          apoio:
              'O débito de aulas cabe no prazo, ou a reposição '
              'vira contínua? Quem decide é uma pessoa, pela central de '
              'pendências.',
        ),
        Text(linhas.join(' · '), style: Tipografia.corpoTabela),
        if (aviso != null) ...[
          const SizedBox(height: Dim.e8),
          AvisoTonal(mensagem: aviso),
        ],
        const SizedBox(height: Dim.e24),
      ],
    );
  }
}

class _Reposicoes extends ConsumerWidget {
  const _Reposicoes({required this.reposicoes});

  final List<ReposicaoAluno> reposicoes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    if (reposicoes.isEmpty) {
      return Text(
        vazioReposicoes,
        style: Tipografia.corpo.copyWith(color: cores.onSurfaceVariant),
      );
    }

    final blocos = ref.watch(blocosPorIdProvider);
    String rotulo(String? id) {
      final bloco = id == null ? null : blocos[id];
      return bloco == null
          ? '—'
          : rotuloBloco(bloco.diaSemana, bloco.horaInicio);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in reposicoes)
          Padding(
            padding: const EdgeInsets.only(bottom: Dim.e8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatarData(r.data)} · ${rotulo(r.blocoId)} · '
                  '${rotuloStatusReposicao(r.status)}',
                  style: Tipografia.numero(Tipografia.corpoTabela),
                ),
                Text(
                  [
                    if (r.blocoOrigemId != null)
                      'aula de ${rotulo(r.blocoOrigemId)}'
                    else
                      'origem não informada',
                    if (r.dataOrigem != null)
                      'perdida em ${formatarData(r.dataOrigem!)}',
                    if (r.observacao != null && r.observacao!.trim().isNotEmpty)
                      r.observacao!.trim(),
                  ].join(' · '),
                  style: Tipografia.apoio.copyWith(
                    color: cores.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
