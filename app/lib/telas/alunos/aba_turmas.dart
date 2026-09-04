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
import '../../turmas/turmas_widgets.dart';
import '../../widgets/badge_tipo.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import '../turmas/formularios_alocacao.dart';

/// Aba **Turmas** da ficha do aluno (docs/wireframes.md §6.4), card 5.7.
///
/// Três seções, e a ordem é a do que se olha primeiro: os blocos em que ele
/// está (com o badge de contorno do tipo e o `tipo_desde`), a situação REP
/// quando há o que dizer, e as reposições pontuais.
///
/// **Aqui se age, e não só se lê** (revisão da fase 05, item A2): alocar em
/// bloco, lançar reposição e remover, os três com `turmas.alocar`. Sem eles a
/// aba mostrava o problema e mandava resolvê-lo noutro lugar — e, no caso da
/// alocação em bloco **desativado**, noutro lugar que não existe: aquele bloco
/// não está na grade, então o painel do bloco nunca abre para ele, e o aluno
/// ficava marcado como "sem turma" sem nenhuma tela capaz de desfazê-lo.
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
      return const EstadoSemAcesso(
        texto: semAcessoTurmasDoAluno,
        faltando: {'turmas.ler'},
      );
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
          error: (erro, _) => _Erro(erro: erro),
          data: (_) => _Blocos(
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
          error: (erro, _) => _Erro(erro: erro),
          data: (lista) => _Reposicoes(reposicoes: lista, aluno: aluno),
        ),
      ],
    );
  }
}

/// O estado de erro da aba, com o código técnico — o mesmo contrato da ficha
/// inteira (design-system §5.6).
class _Erro extends ConsumerWidget {
  const _Erro({required this.erro});

  final Object erro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final original = erro;
    final traduzido = original is ErroApp ? original : traduzirErro(original);
    return EstadoErro(
      mensagem: traduzido.mensagem,
      codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
      aoRepetir: ref.read(versaoTurmasProvider.notifier).incrementar,
    );
  }
}

const semAcessoTurmasDoAluno =
    'As turmas deste aluno não aparecem para o seu perfil. Peça a permissão de '
    'ver turmas a quem administra o acesso.';

const vazioTurmasAluno = 'O aluno não está em nenhuma turma.';
const vazioReposicoes = 'Nenhuma reposição lançada para este aluno.';

/// O aviso que a lista de alunos também dá, aqui com o detalhe que só a ficha
/// tem: **qual** bloco está desativado, e o botão que o desfaz.
const avisoTurmaDesativada =
    'Este aluno está alocado num bloco desativado, que não aparece mais na '
    'grade. Para o sistema ele está sem turma — remova-o aqui e aloque-o num '
    'bloco ativo.';

const avisoSemTurma =
    'Aluno em curso sem nenhuma turma ativa. A rotina diária abre a pendência '
    '"aluno sem turma" enquanto isso valer.';

/// Abre o formulário e confirma; devolve `true` quando algo mudou.
Future<void> _abrirEConfirmar(
  BuildContext context, {
  required WidgetBuilder construtor,
  required String confirmacao,
}) async {
  final resultado = await mostrarFormulario<String>(
    context,
    construtor: construtor,
  );
  if (resultado != null && context.mounted) {
    confirmarEfemero(context, confirmacao);
  }
}

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

    final acoes = _AcoesDaAba(aluno: aluno);

    if (turmas.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _alturaVazio,
            child: EstadoVazio(
              mensagem: vazioTurmasAluno,
              icone: Icons.grid_view_outlined,
              rotuloAcao:
                  ref.watch(permissoesProvider).contains('turmas.alocar')
                  ? '+ Alocar em bloco'
                  : null,
              aoAgir: () => _abrirEConfirmar(
                context,
                construtor: (_) => FormularioAlocarEmBloco(aluno: aluno),
                confirmacao: 'Aluno alocado.',
              ),
            ),
          ),
          if (aluno.emAula) ...[
            const SizedBox(height: Dim.e8),
            const AvisoTonal(mensagem: avisoSemTurma),
          ],
          const SizedBox(height: Dim.e12),
          acoes,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final turma in turmas)
          LinhaTurma(
            titulo: turma.rotulo,
            badges: [
              BadgeTipo(turma.tipo),
              if (!turma.blocoAtivo)
                Text(
                  'bloco desativado',
                  style: Tipografia.apoio.copyWith(color: cores.error),
                ),
            ],
            apoio: [
              metodos[turma.metodoId] ?? '—',
              salas[turma.salaId] ?? '—',
              if (turma.tipoDesde != null)
                '${turma.tipo} desde ${formatarData(turma.tipoDesde!)}',
              if (turma.dataInicioPrevista != null)
                'início previsto ${formatarData(turma.dataInicioPrevista!)}',
            ].join(' · '),
            // ⚠️ O Remover existe SEMPRE, e para o bloco desativado ele é a
            // única saída que o sistema tem.
            acao: BotaoAcao(
              rotulo: 'Remover',
              nivel: NivelBotao.terciario,
              exigePermissao: 'turmas.alocar',
              aoTocar: () => _abrirEConfirmar(
                context,
                construtor: (_) => FormularioRemoverDaTurma(
                  aluno: aluno,
                  turma: turma,
                  ultimaAtiva: turma.blocoAtivo && ativas <= 1,
                ),
                confirmacao: 'Aluno removido da turma.',
              ),
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
        const SizedBox(height: Dim.e12),
        acoes,
      ],
    );
  }
}

/// O estado vazio é um componente centrado e vive dentro de uma lista rolável:
/// sem altura ele tentaria ocupar o infinito (a lição do dashboard).
const _alturaVazio = 260.0;

/// As duas ações que abrem alocação a partir da ficha. Sem `turmas.alocar` o
/// [BotaoAcao] não renderiza nenhuma das duas, e a linha some sozinha.
class _AcoesDaAba extends StatelessWidget {
  const _AcoesDaAba({required this.aluno});

  final Aluno aluno;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Dim.e8,
    runSpacing: Dim.e8,
    children: [
      BotaoAcao(
        rotulo: 'Alocar em bloco',
        icone: Icons.add,
        exigePermissao: 'turmas.alocar',
        aoTocar: () => _abrirEConfirmar(
          context,
          construtor: (_) => FormularioAlocarEmBloco(aluno: aluno),
          confirmacao: 'Aluno alocado.',
        ),
      ),
      BotaoAcao(
        rotulo: 'Lançar reposição',
        icone: Icons.event_repeat_outlined,
        nivel: NivelBotao.secundario,
        exigePermissao: 'turmas.alocar',
        aoTocar: () => _abrirEConfirmar(
          context,
          construtor: (_) => FormularioReposicaoDoAluno(aluno: aluno),
          confirmacao: 'Reposição lançada.',
        ),
      ),
    ],
  );
}

/// A situação REP do card 2.5, mostrada **com os números** e não só com o
/// veredito: "3 aulas em aberto, a mais antiga de 12/09, prazo até 12/10,
/// cabem 2" é acionável; "sugerido virar contínuo" não é (card 5.3).
///
/// Só aparece quando há o que dizer — débito, aluno já contínuo, ou veredito
/// diferente de MANTER. Um painel permanente dizendo "0 aulas a repor" em toda
/// ficha treina a pessoa a não olhar para ele.
///
/// ⚠️ Erro **não** é silêncio. Antes lia `.value` e tratava nulo como "nada a
/// dizer": `ALUNO_INEXISTENTE`, falta de permissão e queda de rede ficavam
/// indistinguíveis de um aluno em dia (achado da revisão da fase 05).
class _SituacaoRep extends ConsumerWidget {
  const _SituacaoRep({required this.aluno});

  final Aluno aluno;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final situacao = ref.watch(situacaoRepProvider(aluno.id!));

    return situacao.when(
      loading: () => const SizedBox.shrink(),
      error: (erro, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TituloSecao(
            texto: 'Situação de reposição',
            apoio:
                'O débito de aulas cabe no prazo, ou a reposição '
                'vira contínua? Quem decide é uma pessoa, pela central de '
                'pendências.',
          ),
          _Erro(erro: erro),
          const SizedBox(height: Dim.e24),
        ],
      ),
      data: (s) {
        if (!s.relevante) return const SizedBox.shrink();
        // A MESMA frase que a central de pendências mostra ao lado do
        // REP_VIRADA (card 5.8) — uma implementação só, em `turmas.dart`.
        final linhas = resumoSituacaoRep(s);
        final aviso = avisoVeredito(s.veredito);
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
      },
    );
  }
}

/// As reposições do aluno, em duas listas.
///
/// ⚠️ **Próximas e histórico separados** (wireframe §6.4, que fala em
/// "reposições pontuais futuras"): a lista trazia tudo com o mesmo peso —
/// PREVISTA de amanhã ao lado de uma CANCELADA de março —, e o que decide hoje
/// é a de amanhã. O histórico fica, e fica **completo**: é dele que o débito do
/// card 2.5 se compõe, e escondê-lo tiraria a explicação do número que a seção
/// de cima mostra.
class _Reposicoes extends ConsumerWidget {
  const _Reposicoes({required this.reposicoes, required this.aluno});

  final List<ReposicaoAluno> reposicoes;
  final Aluno aluno;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    if (reposicoes.isEmpty) {
      return Text(
        vazioReposicoes,
        style: Tipografia.corpo.copyWith(color: cores.onSurfaceVariant),
      );
    }

    final hoje = hojeSaoPaulo();
    final proximas = [
      for (final r in reposicoes)
        if (r.prevista && !r.data.isBefore(hoje)) r,
    ]..sort((a, b) => a.data.compareTo(b.data));
    final historico = [
      for (final r in reposicoes)
        if (!(r.prevista && !r.data.isBefore(hoje))) r,
    ];

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
        if (proximas.isNotEmpty) ...[
          Text('Próximas', style: Tipografia.rotulo),
          const SizedBox(height: Dim.e4),
          for (final r in proximas)
            _LinhaReposicao(r: r, rotuloDoBloco: rotulo),
          const SizedBox(height: Dim.e12),
        ],
        if (historico.isNotEmpty) ...[
          Text('Histórico', style: Tipografia.rotulo),
          const SizedBox(height: Dim.e4),
          for (final r in historico)
            _LinhaReposicao(r: r, rotuloDoBloco: rotulo, rebaixada: true),
        ],
      ],
    );
  }
}

class _LinhaReposicao extends StatelessWidget {
  const _LinhaReposicao({
    required this.r,
    required this.rotuloDoBloco,
    this.rebaixada = false,
  });

  final ReposicaoAluno r;
  final String Function(String? id) rotuloDoBloco;

  /// O histórico é apoio, não fila de trabalho: cor secundária, para a lista de
  /// cima continuar sendo a que se lê primeiro.
  final bool rebaixada;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final corPrincipal = rebaixada || r.status == 'CANCELADA'
        ? cores.onSurfaceVariant
        : cores.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dim.e8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatarData(r.data)} · ${rotuloDoBloco(r.blocoId)} · '
            '${rotuloStatusReposicao(r.status)}',
            style: Tipografia.numero(Tipografia.corpoTabela)
                .copyWith(color: corPrincipal),
          ),
          Text(
            [
              if (r.blocoOrigemId != null)
                'aula de ${rotuloDoBloco(r.blocoOrigemId)}'
              else
                'origem não informada',
              if (r.dataOrigem != null)
                'perdida em ${formatarData(r.dataOrigem!)}',
              if (r.observacao != null && r.observacao!.trim().isNotEmpty)
                r.observacao!.trim(),
            ].join(' · '),
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
