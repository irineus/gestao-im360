import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../alunos/alunos.dart';
import '../../alunos/alunos_provider.dart';
import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../rotas/rotas.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../trilha/trilha.dart';
import '../../trilha/trilha_provider.dart';
import '../../turmas/turmas.dart';
import '../../turmas/turmas_provider.dart';
import '../../util/async_valor.dart';
import '../../widgets/badge_status.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/tabela_im360.dart';
import '../turmas/formularios.dart' show recarregarTurmas;
import 'filtros_alunos.dart';
import 'formularios.dart';

/// Tela 3 — Alunos, a lista (docs/wireframes.md §6.1), card 4.6. Tocar a
/// linha abre a ficha (`/alunos/:id`, [FichaAluno]); "Matricular" exige
/// `alunos.criar`.
///
/// A coluna **Turmas** e o ⚠ de aluno em curso sem turma entraram no card 5.7.
/// A fonte continua sendo a tabela `aluno`, com método e combo resolvidos pelo
/// catálogo já carregado, mais `v_aluno_turmas` para as turmas (bloco e
/// Modular, card 9.2,6; até ali era `v_bloco_alunos`, e todo aluno Modular
/// saía "sem turma") — e não uma
/// `v_aluno_lista`, que juntaria os três num objeto de banco a mais sem tirar
/// nenhuma consulta da tela (divergência com o card 2.3 §12.1, registrada).
///
/// ⚠️ **A coluna só existe para quem tem `turmas.ler`**, e essa é a decisão do
/// card aqui: o conjunto mínimo desta rota é `alunos.ler + materiais.ler`
/// (card 2.4 §6), então um perfil sem `turmas.ler` chega até esta tela — e para
/// ele a consulta de turmas devolveria vazio pela RLS, marcando **todo mundo**
/// com o ⚠ de "sem turma". Coluna ausente é honesta; coluna cheia de alerta
/// falso é a família de falha calada que o projeto cataloga (card 2.6 decisão 1
/// aplicada a uma coluna).
class TelaAlunos extends ConsumerWidget {
  const TelaAlunos({super.key});

  Future<void> _matricular(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => const FormularioAluno(),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Aluno matriculado.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alunos = ref.watch(alunosProvider);
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final combos = ref.watch(combosProvider).value ?? const <Combo>[];
    final metodosPorId = {for (final m in metodos) m.id: m};
    final combosPorId = {for (final c in combos) c.id: c};
    final filtro = ref.watch(filtroAlunosProvider);
    final permissoes = ref.watch(permissoesProvider);
    final haCadastro = alunos.value?.isNotEmpty ?? false;
    final mostraTurmas = permissoes.contains('turmas.ler');
    final turmasAsync = ref.watch(vinculosTurmaProvider);
    final vinculosPorAluno = ref.watch(vinculosPorAlunoProvider);
    final emTurma = ref.watch(alunosEmTurmaProvider);
    final cores = Theme.of(context).colorScheme;
    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
    // O próximo livro de cada aluno, só no celular — é a informação da
    // jornada nº 1 do monitor (card 9.2,64). Em carga ou erro a linha
    // simplesmente não aparece: nenhum livro é afirmado sem ter sido lido.
    final proximos = mobile
        ? ref.watch(proximosLivrosProvider).value ?? const <String, String>{}
        : const <String, String>{};
    String metodoDe(Aluno a) => metodosPorId[a.metodoId]?.nome ?? '—';
    String comboDe(Aluno a) => combosPorId[a.comboId]?.nome ?? '—';

    // ⚠️ **Os três estados da coluna**, e não só o `data`.
    //
    // `vinculosPorAlunoProvider` e `alunosEmTurmaProvider` leem
    // `vinculosTurmaProvider.value ?? []`: em `loading` e em `error` o conjunto é
    // vazio, e o alerta de "sem turma" caía sobre TODO aluno ATIVO/ACELERAR —
    // no erro, para sempre, e sem nada em tela dizendo que a leitura falhou.
    // Alerta falso na tela inteira é a família de falha calada que este projeto
    // cataloga (achado da revisão da fase 05).
    //
    // O mesmo fato da pendência `ALUNO_SEM_TURMA` (card 5.5), visto de onde a
    // secretaria olha — e com a mesma definição, que mora no banco
    // (`v_aluno_turmas.turma_ativa`, card 9.2,6): bloco OU turma Modular, e
    // vínculo com turma desativada não conta. Duas contas diferentes divergiram
    // de fato — até o card 9.2,6 a tela olhava só bloco, e todo aluno Modular
    // saía "sem turma" com o banco dizendo o contrário.
    EstadoTurmas turmasDe(Aluno a) {
      if (turmasAsync.hasError) return const EstadoTurmas.erro();
      if (!turmasAsync.hasValue) return const EstadoTurmas.carregando();
      final semTurma = a.emAula && !emTurma.contains(a.id);
      return EstadoTurmas(
        texto: semTurma
            ? 'sem turma'
            : rotuloTurmasDoAluno(vinculosPorAluno[a.id] ?? const []),
        alerta: semTurma,
      );
    }

    return TabelaIm360<Aluno>(
      // No celular a busca sai da folha e fica sempre à vista (card 9.2,64):
      // a primeira coisa que o monitor faz é procurar o aluno à frente dele.
      buscaMobile: const CampoBuscaAlunos(),
      filtros: FiltrosAlunos(
        metodos: metodos,
        combos: combos,
        comBusca: !mobile,
      ),
      filtrosAtivos:
          filtro.ativos - (mobile && filtro.busca.trim().isNotEmpty ? 1 : 0),
      acoes: [
        BotaoAcao(
          rotulo: 'Matricular',
          icone: Icons.person_add_alt_1_outlined,
          exigePermissao: 'alunos.criar',
          aoTocar: () => _matricular(context),
        ),
      ],
      colunas: [
        ColunaIm360(
          titulo: 'Código',
          texto: (a) => a.codigoSgf ?? '—',
          flex: 1,
          larguraMin: 90,
        ),
        ColunaIm360(
          titulo: 'Nome',
          texto: (a) => a.nome,
          flex: 3,
          larguraMin: 200,
        ),
        ColunaIm360(
          titulo: 'Método',
          texto: metodoDe,
          prioridade: 2,
          larguraMin: 130,
        ),
        ColunaIm360(
          titulo: 'Status',
          texto: (a) => a.status,
          celula: (a) => BadgeStatus(a.status),
          flex: 1,
          larguraMin: 120,
        ),
        ColunaIm360(
          titulo: 'Combo',
          texto: comboDe,
          prioridade: 3,
          larguraMin: 180,
        ),
        if (mostraTurmas)
          ColunaIm360(
            titulo: 'Turmas',
            texto: (a) => turmasDe(a).texto,
            celula: (a) => _CelulaTurmas(
              estado: turmasDe(a),
              aoRepetir: () => recarregarTurmas(ref),
            ),
            prioridade: 2,
            // `larguraMin` decide se a coluna SAI; quem reparte o que sobra é o
            // `flex` — o card 4.7,7 pagou por isto com "Convite p…" na tela.
            flex: 2,
            larguraMin: 170,
          ),
      ],
      linhas: alunos.derivar((lista) => filtrarAlunos(lista, filtro)),
      cartao: (a) => CartaoIm360(
        titulo: a.nome,
        subtitulo: [
          if (a.codigoSgf != null) a.codigoSgf!,
          metodoDe(a),
        ].join(' · '),
        // No mobile a linha de apoio é uma só, e a turma vale mais que o combo:
        // é o que o monitor precisa para achar o aluno no laboratório.
        apoio: mostraTurmas
            ? turmasDe(a).texto
            : (a.comboId == null ? null : comboDe(a)),
        // O alerta existe no celular como ÍCONE — antes era o caractere que
        // Inter e Roboto não têm, e a correção que o tirou deixou o cartão sem
        // alerta nenhum (revisão da fase 05, item A1).
        iconeApoio: mostraTurmas && turmasDe(a).alerta
            ? Icons.warning_amber_rounded
            : null,
        corApoio: mostraTurmas && turmasDe(a).alerta ? cores.tertiary : null,
        informacao: proximos[a.id] == null
            ? null
            : '$rotuloProximoLivro ${proximos[a.id]}',
        iconeInformacao: Icons.menu_book_outlined,
        badge: BadgeStatus(a.status),
      ),
      estadoVazio: haCadastro
          ? EstadoVazio(
              mensagem: vazioAlunosFiltro,
              icone: Icons.filter_alt_off_outlined,
              rotuloAcao: 'Limpar filtros',
              aoAgir: ref.read(filtroAlunosProvider.notifier).limpar,
            )
          : EstadoVazio(
              mensagem: vazioAlunos,
              icone: Icons.people_outline,
              rotuloAcao: permissoes.contains('alunos.criar')
                  ? '+ Matricular'
                  : null,
              aoAgir: () => _matricular(context),
            ),
      aoTocarLinha: (a) => context.go(caminhoFichaAluno(a.id!)),
      aoRepetir: ref.read(versaoAlunosProvider.notifier).incrementar,
    );
  }
}

/// Estado vazio da tela (design-system §7.2) — os textos são os do card 2.7.
const vazioAlunos = 'Nenhum aluno cadastrado.';
const vazioAlunosFiltro = 'Nenhum aluno com esses filtros.';

/// O que a coluna Turmas diz de um aluno — e em qual dos três estados.
@immutable
class EstadoTurmas {
  const EstadoTurmas({required this.texto, this.alerta = false})
    : erro = false,
      carregando = false;

  const EstadoTurmas.carregando()
    : texto = '…',
      alerta = false,
      erro = false,
      carregando = true;

  const EstadoTurmas.erro()
    : texto = '—',
      alerta = false,
      erro = true,
      carregando = false;

  final String texto;

  /// Aluno em curso sem nenhuma turma ativa.
  final bool alerta;

  final bool erro;
  final bool carregando;
}

/// Sem esta frase o traço do erro seria lido como "este aluno não tem turma".
const erroColunaTurmas =
    'Não foi possível ler as turmas. Toque para tentar de novo.';

/// A célula da coluna Turmas: os blocos, o alerta de quem está em curso e sem
/// turma, ou o que houve com a leitura. O símbolo nunca vai sozinho — a cor não
/// é o único portador do significado (card 1.9 §7), e o texto ao lado é o que a
/// leitura de tela lê.
class _CelulaTurmas extends StatelessWidget {
  const _CelulaTurmas({required this.estado, required this.aoRepetir});

  final EstadoTurmas estado;
  final VoidCallback aoRepetir;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;

    if (estado.erro) {
      // Card 9.2,72: o alvo era o InkWell do tamanho do ícone de 16 px e do
      // texto. Agora tem a altura mínima de alvo da faixa (design-system §8.4)
      // e se anuncia como botão, com a frase inteira.
      final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
      return Tooltip(
        message: erroColunaTurmas,
        child: Semantics(
          button: true,
          label: erroColunaTurmas,
          excludeSemantics: true,
          child: InkWell(
            onTap: aoRepetir,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: mobile ? Dim.alvoMobile : Dim.alturaBotao,
                minWidth: mobile ? Dim.alvoMobile : Dim.alturaBotao,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh, size: 16, color: cores.error),
                  const SizedBox(width: Dim.e4),
                  Text(
                    estado.texto,
                    style: Tipografia.corpoTabela.copyWith(color: cores.error),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!estado.alerta) {
      return Text(
        estado.texto,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Tipografia.numero(Tipografia.corpoTabela),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_rounded, size: 16, color: cores.tertiary),
        const SizedBox(width: Dim.e4),
        Flexible(
          child: Text(
            estado.texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tipografia.corpoTabela.copyWith(color: cores.tertiary),
          ),
        ),
      ],
    );
  }
}
