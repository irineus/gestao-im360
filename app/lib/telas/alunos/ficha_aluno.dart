import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../alunos/alunos.dart';
import '../../alunos/alunos_provider.dart';
import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../erros/erro_app.dart';
import '../../rotas/rotas.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../widgets/badge_status.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import 'aba_trilha.dart';
import 'aba_turmas.dart';
import 'formularios.dart';

/// A ficha do aluno (docs/wireframes.md §6.2) — cabeçalho com status e as
/// ações do dia a dia, e as abas. Existem **Dados** e **Histórico** desde o
/// card 4.6, **Turmas** desde o 5.7 e **Trilha** desde o 6.6; Certificado (8.6)
/// fica no lugar, dizendo qual card a entrega, para a ordem das abas não mudar
/// debaixo de quem já aprendeu a tela.
///
/// É uma **página** (`/alunos/:id`), e não um painel sobre a lista: a ficha é
/// o destino de deep-link e o ponto de partida da jornada nº 1 do monitor
/// (ficha → Trilha → Registrar entrega, card 2.6 §3.2).
class FichaAluno extends ConsumerWidget {
  const FichaAluno({super.key, required this.alunoId, this.aba});

  final String alunoId;

  /// A aba que abre, vinda de `?aba=` — é como a central de pendências manda
  /// "Alocar" para Turmas e "Ver checklist" para Certificado, em vez de largar
  /// os oito tipos que apontam para a ficha na primeira aba (wireframe §14.3).
  /// Nula ou desconhecida abre em Dados.
  final String? aba;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aluno = ref.watch(alunoProvider(alunoId));
    return aluno.when(
      loading: () => const EstadoCarregando(),
      error: (erro, _) {
        final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
        return EstadoErro(
          mensagem: traduzido.mensagem,
          codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
          aoRepetir: ref.read(versaoAlunosProvider.notifier).incrementar,
        );
      },
      data: (a) => a == null
          ? EstadoVazio(
              mensagem: fichaInexistente,
              icone: Icons.person_off_outlined,
              rotuloAcao: 'Voltar para Alunos',
              aoAgir: () => context.go(caminhoAlunos),
            )
          : _Ficha(aluno: a, aba: aba),
    );
  }
}

/// Aluno que não existe — ou de outra unidade, que para o app é o mesmo
/// (`ALUNO_INEXISTENTE`, card 4.2).
const fichaInexistente = 'Este aluno não existe ou você não tem acesso a ele.';

class _Ficha extends ConsumerWidget {
  const _Ficha({required this.aluno, this.aba});

  final Aluno aluno;
  final String? aba;

  Future<void> _alterarStatus(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioAlterarStatus(aluno: aluno),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Status alterado.');
    }
  }

  Future<void> _editar(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioAluno(aluno: aluno),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Dados salvos.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final combos = ref.watch(combosProvider).value ?? const <Combo>[];
    String? nomeMetodo;
    for (final m in metodos) {
      if (m.id == aluno.metodoId) nomeMetodo = m.nome;
    }
    String? nomeCombo;
    for (final c in combos) {
      if (c.id == aluno.comboId) nomeCombo = c.nome;
    }
    final linhaApoio = [
      nomeMetodo ?? 'método —',
      nomeCombo == null ? 'sem combo' : 'combo $nomeCombo',
      if (aluno.prevConclusaoCurso != null)
        'prev. conclusão ${formatarData(aluno.prevConclusaoCurso!)}',
      if (aluno.statusDesde != null)
        '${aluno.status} desde ${formatarData(aluno.statusDesde!)}',
    ].join(' · ');

    return DefaultTabController(
      length: abasFicha.length,
      initialIndex: indiceAbaFicha(aba),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Dim.e16, Dim.e8, Dim.e16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.go(caminhoAlunos),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Alunos'),
                  ),
                ),
                const SizedBox(height: Dim.e4),
                Wrap(
                  spacing: Dim.e12,
                  runSpacing: Dim.e4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(aluno.nome, style: Tipografia.titulo),
                    BadgeStatus(aluno.status),
                    if (aluno.codigoSgf != null)
                      Text(
                        'código SGF ${aluno.codigoSgf}',
                        style: Tipografia.numero(Tipografia.apoio)
                            .copyWith(color: cores.onSurfaceVariant),
                      ),
                  ],
                ),
                const SizedBox(height: Dim.e4),
                Text(
                  linhaApoio,
                  style: Tipografia.corpoTabela.copyWith(
                    color: cores.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Dim.e12),
                Wrap(
                  spacing: Dim.e8,
                  runSpacing: Dim.e8,
                  children: [
                    // Sem transição comum a partir do status atual (só o
                    // CANCELADO hoje), a saída é a reversão — ação rara, que
                    // mora no Histórico (wireframe §6.2). O botão fica visível
                    // e desabilitado com o motivo (card 2.6 decisão 1: sem
                    // estado, não sem permissão).
                    BotaoAcao(
                      rotulo: 'Alterar status',
                      icone: Icons.swap_horiz,
                      exigePermissao: 'alunos.alterar_status',
                      desabilitado: transicoesDe(aluno.status).isEmpty
                          ? const DesabilitadoCom(
                              'Status terminal: para reverter, use a aba '
                              'Histórico.',
                            )
                          : null,
                      aoTocar: () => _alterarStatus(context),
                    ),
                    BotaoAcao(
                      rotulo: 'Editar dados',
                      icone: Icons.edit_outlined,
                      nivel: NivelBotao.secundario,
                      exigePermissao: 'alunos.editar',
                      aoTocar: () => _editar(context),
                    ),
                  ],
                ),
                const SizedBox(height: Dim.e8),
              ],
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Dados'),
              Tab(text: 'Trilha'),
              Tab(text: 'Turmas'),
              Tab(text: 'Histórico'),
              Tab(text: 'Certificado'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                AbaDados(
                  aluno: aluno,
                  nomeMetodo: nomeMetodo,
                  nomeCombo: nomeCombo,
                ),
                AbaTrilha(aluno: aluno),
                AbaTurmas(aluno: aluno),
                AbaHistorico(aluno: aluno),
                const _AbaFutura(nome: 'Certificado', card: '8.6'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aba Dados (wireframe §6.4): leitura; a edição é o formulário do cabeçalho.
class AbaDados extends StatelessWidget {
  const AbaDados({
    super.key,
    required this.aluno,
    this.nomeMetodo,
    this.nomeCombo,
  });

  final Aluno aluno;
  final String? nomeMetodo;
  final String? nomeCombo;

  @override
  Widget build(BuildContext context) {
    final campos = <(String, String)>[
      ('Nome', aluno.nome),
      ('Código SGF', aluno.codigoSgf ?? '—'),
      ('Método', nomeMetodo ?? '—'),
      ('Combo', nomeCombo ?? '—'),
      (
        'Data de início',
        aluno.dataInicio == null ? '—' : formatarData(aluno.dataInicio!),
      ),
      (
        'Status desde',
        aluno.statusDesde == null ? '—' : formatarData(aluno.statusDesde!),
      ),
      (
        'Previsão de conclusão',
        aluno.prevConclusaoCurso == null
            ? '—'
            : formatarData(aluno.prevConclusaoCurso!),
      ),
      if (aluno.conferido) ('Conferência da migração', 'Conferido'),
    ];
    final cores = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(Dim.e16),
      children: [
        Wrap(
          spacing: Dim.e24,
          runSpacing: Dim.e16,
          children: [
            for (final (rotulo, valor) in campos)
              SizedBox(
                width: 240,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rotulo,
                      style: Tipografia.apoio.copyWith(
                        color: cores.onSurfaceVariant,
                      ),
                    ),
                    Text(valor, style: Tipografia.numero(Tipografia.corpo)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: Dim.e16),
        Text(
          'Observações',
          style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
        ),
        Text(
          aluno.observacoes?.trim().isNotEmpty == true
              ? aluno.observacoes!
              : '—',
          style: Tipografia.corpo,
        ),
      ],
    );
  }
}

/// Aba Histórico (wireframe §6.5): a linha do tempo de `aluno_status_hist`
/// e, para FORMADO/CANCELADO, o "Reverter status" no rodapé.
class AbaHistorico extends ConsumerWidget {
  const AbaHistorico({super.key, required this.aluno});

  final Aluno aluno;

  Future<void> _reverter(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioReverterStatus(aluno: aluno),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Status revertido.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historico = ref.watch(historicoAlunoProvider(aluno.id!));
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: historico.when(
            loading: () => const EstadoCarregando(linhas: 3),
            error: (erro, _) => EstadoErro(
              mensagem: (erro is ErroApp ? erro : traduzirErro(erro)).mensagem,
              aoRepetir: ref.read(versaoAlunosProvider.notifier).incrementar,
            ),
            data: (linhas) => linhas.isEmpty
                ? const EstadoVazio(
                    mensagem: vazioHistorico,
                    icone: Icons.history,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: Dim.e8),
                    itemCount: linhas.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final t = linhas[i];
                      final quando = formatarDataHora(t.ocorridoEm);
                      final quem = t.usuarioNome == null
                          ? ''
                          : ' · por ${t.usuarioNome}';
                      return ListTile(
                        leading: Icon(
                          Icons.swap_horiz,
                          color: cores.onSurfaceVariant,
                        ),
                        title: Wrap(
                          spacing: Dim.e8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (t.statusAnterior != null) ...[
                              BadgeStatus(t.statusAnterior!),
                              Icon(
                                Icons.arrow_forward,
                                size: 16,
                                color: cores.onSurfaceVariant,
                              ),
                            ],
                            BadgeStatus(t.statusNovo),
                          ],
                        ),
                        subtitle: Text(
                          '$quando$quem'
                          '${t.motivo == null ? '' : '\n${t.motivo}'}',
                          style: Tipografia.apoio.copyWith(
                            color: cores.onSurfaceVariant,
                          ),
                        ),
                        isThreeLine: t.motivo != null,
                      );
                    },
                  ),
          ),
        ),
        if (aluno.terminal)
          Padding(
            padding: const EdgeInsets.all(Dim.e16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: BotaoAcao(
                rotulo: 'Reverter status',
                icone: Icons.undo,
                nivel: NivelBotao.secundario,
                exigePermissao: 'alunos.reverter_status',
                aoTocar: () => _reverter(context),
              ),
            ),
          ),
      ],
    );
  }
}

const vazioHistorico = 'Nenhuma mudança de status registrada.';

/// Aba cujo card ainda não chegou — diz qual, para não virar destino
/// permanente (mesmo papel da `TelaEmConstrucao`).
class _AbaFutura extends StatelessWidget {
  const _AbaFutura({required this.nome, required this.card});

  final String nome;
  final String card;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      '$nome — aba do card $card.',
      style: Tipografia.apoio.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
