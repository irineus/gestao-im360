import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../alunos/alunos.dart';
import '../../alunos/alunos_provider.dart';
import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../rotas/rotas.dart';
import '../../sessao/sessao_provider.dart';
import '../../widgets/badge_status.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/tabela_im360.dart';
import 'filtros_alunos.dart';
import 'formularios.dart';

/// Tela 3 — Alunos, a lista (docs/wireframes.md §6.1), card 4.6. Tocar a
/// linha abre a ficha (`/alunos/:id`, [FichaAluno]); "Matricular" exige
/// `alunos.criar`.
///
/// A coluna **Turmas** do wireframe — e o ⚠ de aluno ATIVO sem turma — é da
/// Fase 5 (`bloco_aluno`, card 5.1/5.7); até lá a lista mostra o combo no
/// lugar dela. A fonte é a tabela `aluno` com método e combo resolvidos pelo
/// catálogo já carregado, não uma view: `v_aluno_lista` só passa a valer a
/// pena quando houver turma para juntar (card 2.3 §12.1).
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
    String metodoDe(Aluno a) => metodosPorId[a.metodoId]?.nome ?? '—';
    String comboDe(Aluno a) => combosPorId[a.comboId]?.nome ?? '—';

    return TabelaIm360<Aluno>(
      filtros: FiltrosAlunos(metodos: metodos, combos: combos),
      filtrosAtivos: filtro.ativos,
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
      ],
      linhas: alunos.whenData((lista) => filtrarAlunos(lista, filtro)),
      cartao: (a) => CartaoIm360(
        titulo: a.nome,
        subtitulo: [
          if (a.codigoSgf != null) a.codigoSgf!,
          metodoDe(a),
        ].join(' · '),
        apoio: a.comboId == null ? null : comboDe(a),
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
