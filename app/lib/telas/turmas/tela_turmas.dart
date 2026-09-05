import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../widgets/barra_filtros.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/abertura_por_url.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import 'formularios.dart';
import 'grade_semanal.dart';
import 'painel_bloco.dart';

/// Tela 4 — Turmas por horário, a grade semanal (docs/wireframes.md §7.1),
/// card 5.6. Substitui as seis abas Segunda…Sábado da planilha.
///
/// A fonte é `fn_grade_semana(p_segunda)`, e não a view `v_bloco_vagas_semana`:
/// **a lotação é de uma data** — a alocação vale toda semana, a reposição vale
/// só no dia (card 2.1 §8) —, e por isso a tela navega semanas. A view é a
/// mesma grade na semana corrente e serve ao dashboard do card 5.9.
///
/// Nada aqui calcula capacidade, ocupação ou vaga: os três números chegam
/// prontos do banco (card 5.2 é o dono da fórmula). A tela mostra e navega.
///
/// **Tocar a célula abre os alunos daquele bloco naquela data** ([PainelBloco],
/// card 5.7) — e não o cadastro do bloco, que fica no `[Editar bloco]` de dentro
/// do painel. A troca é o que o wireframe §7.2 desenha, e é a leitura certa do
/// gesto: quem clica numa turma quer ver quem está nela; editar horário e sala
/// é o caso raro.
class TelaTurmas extends ConsumerStatefulWidget {
  const TelaTurmas({super.key, this.blocoId});

  /// `?bloco=<id>` — o atalho da central de pendências (`BLOCO_ACIMA_CAPACIDADE`
  /// leva para cá, wireframe §14.3). A tela vai para a semana corrente e abre o
  /// painel daquele bloco assim que a grade chega; sem isso, "Ver turma" abria
  /// a grade inteira e a pessoa procurava de novo o que a lista já sabia.
  final String? blocoId;

  @override
  ConsumerState<TelaTurmas> createState() => _TelaTurmasState();
}

class _TelaTurmasState extends ConsumerState<TelaTurmas>
    with AberturaPorUrl<TelaTurmas> {
  @override
  void initState() {
    super.initState();
    // A pendência é sobre **agora**: a semana em que alguém deixou esta tela
    // não é onde o bloco apontado precisa ser visto.
    if (widget.blocoId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(semanaProvider.notifier).hoje();
      });
    }
  }

  @override
  void didUpdateWidget(TelaTurmas anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.blocoId != widget.blocoId) reabrirNaProxima();
  }

  Future<void> _novoBloco(
    BuildContext context, {
    int? diaSemana,
    String? horaInicio,
  }) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) =>
          FormularioBloco(diaSemana: diaSemana, horaInicio: horaInicio),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Bloco salvo.');
    }
  }

  /// O painel devolve o resultado do formulário de bloco quando alguém edita ou
  /// exclui lá dentro — a confirmação é dada aqui, porque lá o painel já pode
  /// estar descrevendo um bloco que deixou de existir.
  Future<void> _abrirBloco(BuildContext context, CelulaGrade celula) async {
    final resultado = await mostrarFormulario<String>(
      context,
      largura: larguraDetalhe,
      construtor: (_) => PainelBloco(celula: celula),
    );
    if (resultado == 'excluido' && context.mounted) {
      confirmarEfemero(context, 'Bloco excluído.');
    } else if (resultado == 'salvo' && context.mounted) {
      confirmarEfemero(context, 'Bloco salvo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final semana = ref.watch(semanaProvider);
    final grade = ref.watch(gradeProvider);
    final filtro = ref.watch(filtroGradeProvider);
    final permissoes = ref.watch(permissoesProvider);
    final inativos = ref.watch(blocosInativosProvider);

    final todas = grade.value ?? const <CelulaGrade>[];
    final visiveis = filtrarGrade(todas, filtro);
    final montada = montarGrade(semana, visiveis);

    // O atalho abre o painel do bloco pedido — na primeira grade que o
    // contenha, e uma vez só.
    final pedido = widget.blocoId;
    if (pedido != null && grade.hasValue) {
      CelulaGrade? alvo;
      for (final c in todas) {
        if (c.blocoId == pedido) alvo ??= c;
      }
      abrirUmaVez(alvo, (celula) => _abrirBloco(context, celula));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Dim.e16, Dim.e16, Dim.e16, Dim.e8),
          // A MESMA barra da `TabelaIm360` (item H4): no celular os filtros vão
          // para a folha "Filtrar (n)" e as ações descem para a segunda linha,
          // em vez de empilharem à esquerda com larguras diferentes. A
          // navegação de semana **não** é filtro e fica acima, em largura
          // total: é o controle mais tocado da tela.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _NavegacaoSemana(
                semana: semana,
                incluiDomingo: montada.dias.contains(7),
              ),
              const SizedBox(height: Dim.e8),
              BarraFiltrosIm360(
                filtros: const FiltrosGrade(),
                filtrosAtivos: filtro.ativos,
                acoes: [
                  if (inativos.isNotEmpty)
                    BotaoAcao(
                      rotulo: 'Inativos (${inativos.length})',
                      icone: Icons.visibility_off_outlined,
                      nivel: NivelBotao.terciario,
                      exigePermissao: 'turmas.editar',
                      aoTocar: () => mostrarFormulario<String>(
                        context,
                        construtor: (_) => const DialogoBlocosInativos(),
                      ),
                    ),
                  BotaoAcao(
                    rotulo: 'Novo bloco',
                    icone: Icons.add,
                    exigePermissao: 'turmas.criar',
                    aoTocar: () => _novoBloco(context),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          // O mesmo contrato de estados da `TabelaIm360` (design-system §5.6),
          // escrito à mão porque a grade é uma matriz e não uma lista.
          child: grade.when(
            loading: () => const EstadoCarregando(),
            error: (erro, _) {
              final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
              return EstadoErro(
                mensagem: traduzido.mensagem,
                codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
                aoRepetir: ref.read(versaoTurmasProvider.notifier).incrementar,
              );
            },
            data: (_) => montada.vazia
                ? _Vazio(
                    // "Nenhum bloco com esses filtros" **também** quando existe
                    // filtro ligado e nada casou: sem esta metade a tela dizia
                    // "nenhum bloco cadastrado" — que é falso — e não oferecia
                    // "Limpar filtros", que é a saída.
                    temGrade: todas.isNotEmpty || filtro.ativos > 0,
                    podeCriar: permissoes.contains('turmas.criar'),
                    aoLimpar: ref.read(filtroGradeProvider.notifier).limpar,
                    aoCriar: () => _novoBloco(context),
                  )
                : GradeSemanal(
                    grade: montada,
                    aoTocarBloco: (celula) => _abrirBloco(context, celula),
                    aoTocarVazio: permissoes.contains('turmas.criar')
                        ? (dia, hora) => _novoBloco(
                            context,
                            diaSemana: dia,
                            horaInicio: hora,
                          )
                        : null,
                  ),
          ),
        ),
      ],
    );
  }
}

/// Estado vazio da tela — os textos são os do design-system §7.2, que pede a
/// ação junto: estado vazio de tabela nunca é só uma tabela sem linhas.
const vazioTurmas = 'Nenhum bloco de horário cadastrado.';
const vazioTurmasFiltro = 'Nenhum bloco com esses filtros nesta semana.';

class _Vazio extends StatelessWidget {
  const _Vazio({
    required this.temGrade,
    required this.podeCriar,
    required this.aoLimpar,
    required this.aoCriar,
  });

  final bool temGrade;
  final bool podeCriar;
  final VoidCallback aoLimpar;
  final VoidCallback aoCriar;

  @override
  Widget build(BuildContext context) => temGrade
      ? EstadoVazio(
          mensagem: vazioTurmasFiltro,
          icone: Icons.filter_alt_off_outlined,
          rotuloAcao: 'Limpar filtros',
          aoAgir: aoLimpar,
        )
      : EstadoVazio(
          mensagem: vazioTurmas,
          icone: Icons.grid_view_outlined,
          rotuloAcao: podeCriar ? '+ Novo bloco' : null,
          aoAgir: aoCriar,
        );
}

/// `[◄ semana 31/08–05/09 ►]` do wireframe §7.1, mais "Hoje" — sem ele, quem
/// navegasse quatro semanas à frente teria de contar os cliques de volta.
class _NavegacaoSemana extends ConsumerWidget {
  const _NavegacaoSemana({required this.semana, required this.incluiDomingo});

  final DateTime semana;
  final bool incluiDomingo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controlador = ref.read(semanaProvider.notifier);
    // A semana corrente é a de São Paulo — a mesma que o banco fixa com
    // `fn_hoje()`. Pelo relógio do aparelho, "Hoje" podia levar à semana errada.
    final corrente = segundaDe(hojeSaoPaulo());
    final ehCorrente = semana.isAtSameMomentAs(corrente);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Semana anterior',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => controlador.mover(-1),
        ),
        Text(
          'Semana ${rotuloSemana(semana, incluiDomingo: incluiDomingo)}',
          style: Tipografia.numero(Tipografia.rotulo),
        ),
        IconButton(
          tooltip: 'Próxima semana',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => controlador.mover(1),
        ),
        if (!ehCorrente)
          TextButton(onPressed: controlador.hoje, child: const Text('Hoje')),
      ],
    );
  }
}

/// Barra de filtros da grade (design-system §5.3): método e sala. O estado mora
/// no provider, não aqui.
///
/// Não há busca por texto: a grade é um calendário, não uma lista — o que se
/// procura nela é um horário, e para isso serve a própria grade.
class FiltrosGrade extends ConsumerWidget {
  const FiltrosGrade({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroGradeProvider);
    final controlador = ref.read(filtroGradeProvider.notifier);
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final salas = ref.watch(salasProvider).value ?? const <Sala>[];

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FiltroSuspenso<String>(
          key: ValueKey('metodo-${filtro.metodoId}'),
          rotulo: 'Método',
          largura: 180,
          selecao: filtro.metodoId ?? '',
          entradas: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final m in metodos)
              DropdownMenuEntry(value: m.id, label: m.nome),
          ],
          aoSelecionar: (valor) => controlador.definir(
            filtro.copiar(
              metodoId: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        FiltroSuspenso<String>(
          key: ValueKey('sala-${filtro.salaId}'),
          rotulo: 'Sala',
          largura: 200,
          selecao: filtro.salaId ?? '',
          entradas: [
            const DropdownMenuEntry(value: '', label: 'Todas'),
            for (final s in salas)
              if (s.id != null) DropdownMenuEntry(value: s.id!, label: s.nome),
          ],
          aoSelecionar: (valor) => controlador.definir(
            filtro.copiar(
              salaId: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
      ],
    );
  }
}
