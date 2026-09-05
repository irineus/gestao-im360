import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../erros/erro_app.dart';
import '../../rotas/rotas.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/modular.dart';
import '../../turmas/modular_provider.dart';
import '../../turmas/turmas_widgets.dart';
import '../../util/texto.dart';
import '../../widgets/abertura_por_url.dart';
import '../../widgets/barra_filtros.dart';
import '../../widgets/badge_status.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import 'formularios_modular.dart';

/// Tela 5 — Turmas Modular (docs/wireframes.md §8), card 7.3. Substitui as abas
/// Massagem…Depilação da planilha.
///
/// Um **acordeão de turmas**, e não a grade da tela 4: turma Modular não tem dia
/// nem horário — ela tem um curso, uma sala, uma capacidade própria e um
/// cronograma de módulos que a turma inteira percorre em conjunto (card 2.2 §9).
/// Dentro do cartão expandido moram as três regiões do §8: cronograma, alunos e
/// o `[Avançar módulo →]`.
///
/// Nada aqui calcula lotação, vaga ou módulo corrente: os três chegam prontos de
/// `v_turma_modular_lotacao` e `v_turma_modular_cronograma` (card 7.3), e as
/// escritas passam pelas funções do card 7.2. A tela orquestra.
class TelaTurmasModular extends ConsumerStatefulWidget {
  const TelaTurmasModular({super.key, this.turmaId});

  /// `?turma=<id>` — o mesmo desenho de `?bloco=`, `?material=` e `?pc=`: a
  /// tela abre já com aquela turma expandida. Quem o usará é a pendência
  /// `TURMA_MODULAR_SEM_CRONOGRAMA` (card 8.1), e ele existe desde já porque
  /// "Ver turma" sem o id larga a pessoa na lista inteira.
  final String? turmaId;

  @override
  ConsumerState<TelaTurmasModular> createState() => _TelaTurmasModularState();
}

class _TelaTurmasModularState extends ConsumerState<TelaTurmasModular>
    with AberturaPorUrl<TelaTurmasModular> {
  @override
  void didUpdateWidget(TelaTurmasModular anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.turmaId != widget.turmaId) reabrirNaProxima();
  }

  Future<void> _novaTurma() async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => const FormularioTurmaModular(),
    );
    if (resultado != null && mounted) {
      confirmarEfemero(context, 'Turma salva.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final turmasAsync = ref.watch(turmasModularProvider);
    final filtro = ref.watch(filtroTurmasModularProvider);
    final permissoes = ref.watch(permissoesProvider);
    final inativas = ref.watch(turmasModularInativasProvider).value ?? const [];

    final todas = turmasAsync.value ?? const <TurmaModular>[];
    final visiveis = ordenarTurmas(filtrarTurmas(todas, filtro));

    // O atalho expande a turma pedida, uma vez só.
    final pedida = widget.turmaId;
    if (pedida != null && turmasAsync.hasValue) {
      TurmaModular? alvo;
      for (final t in todas) {
        if (t.id == pedida) alvo ??= t;
      }
      abrirUmaVez(
        alvo,
        (turma) => ref.read(turmaAbertaProvider.notifier).abrir(turma.id),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Dim.e16, Dim.e16, Dim.e16, Dim.e8),
          // A MESMA barra da `TabelaIm360` (item H4): no celular os filtros
          // vão para a folha "Filtrar (n)" e as ações descem para a segunda
          // linha, em vez de empilharem à esquerda com larguras diferentes.
          child: BarraFiltrosIm360(
            filtros: const _FiltrosTurmasModular(),
            filtrosAtivos: filtro.ativos,
            acoes: [
              if (inativas.isNotEmpty)
                BotaoAcao(
                  rotulo: 'Inativas (${inativas.length})',
                  icone: Icons.visibility_off_outlined,
                  nivel: NivelBotao.terciario,
                  exigePermissao: 'turmas.editar',
                  aoTocar: () => mostrarFormulario<String>(
                    context,
                    construtor: (_) => const DialogoTurmasInativas(),
                  ),
                ),
              BotaoAcao(
                rotulo: 'Nova turma',
                icone: Icons.add,
                exigePermissao: 'turmas.criar',
                aoTocar: _novaTurma,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          // O mesmo contrato de estados da `TabelaIm360` (design-system §5.6),
          // escrito à mão porque a lista é um acordeão e não uma tabela.
          child: turmasAsync.when(
            loading: () => const EstadoCarregando(),
            error: (erro, _) {
              final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
              return EstadoErro(
                mensagem: traduzido.mensagem,
                codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
                aoRepetir: ref.read(versaoModularProvider.notifier).incrementar,
              );
            },
            data: (_) => visiveis.isEmpty
                ? _Vazio(
                    // "Nenhuma turma com esses filtros" **também** quando há
                    // filtro ligado e nada casou: sem esta metade a tela diria
                    // "nenhuma turma cadastrada" — que é falso — e não ofereceria
                    // "Limpar filtros", que é a saída.
                    temTurma: todas.isNotEmpty || filtro.ativos > 0,
                    podeCriar: permissoes.contains('turmas.criar'),
                    aoLimpar: ref
                        .read(filtroTurmasModularProvider.notifier)
                        .limpar,
                    aoCriar: _novaTurma,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      Dim.e16,
                      Dim.e8,
                      Dim.e16,
                      Dim.e24,
                    ),
                    itemCount: visiveis.length,
                    itemBuilder: (_, i) =>
                        CartaoTurmaModular(turma: visiveis[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Estado vazio da tela — texto do design-system §7.2, que pede a ação junto.
const vazioTurmasModular = 'Nenhuma turma Modular.';
const vazioTurmasModularFiltro = 'Nenhuma turma Modular com esses filtros.';

class _Vazio extends StatelessWidget {
  const _Vazio({
    required this.temTurma,
    required this.podeCriar,
    required this.aoLimpar,
    required this.aoCriar,
  });

  final bool temTurma;
  final bool podeCriar;
  final VoidCallback aoLimpar;
  final VoidCallback aoCriar;

  @override
  Widget build(BuildContext context) => temTurma
      ? EstadoVazio(
          mensagem: vazioTurmasModularFiltro,
          icone: Icons.filter_alt_off_outlined,
          rotuloAcao: 'Limpar filtros',
          aoAgir: aoLimpar,
        )
      : EstadoVazio(
          mensagem: vazioTurmasModular,
          icone: Icons.view_module_outlined,
          rotuloAcao: podeCriar ? '+ Nova turma' : null,
          aoAgir: aoCriar,
        );
}

/// Filtros da lista (design-system §5.3): curso e busca. Estado no provider.
///
/// ⚠️ A busca usa **controller**, e não `initialValue`: sem ele "Limpar
/// filtros" (que vem de fora, do estado vazio) e o filtro por curso vindo do
/// dashboard limpavam o provider e deixavam o texto na tela — a lista voltava
/// cheia com o campo dizendo o contrário. É o padrão que `_FiltrosSugerido` de
/// Compras já usava (item B4).
class _FiltrosTurmasModular extends ConsumerStatefulWidget {
  const _FiltrosTurmasModular();

  @override
  ConsumerState<_FiltrosTurmasModular> createState() =>
      _FiltrosTurmasModularState();
}

class _FiltrosTurmasModularState extends ConsumerState<_FiltrosTurmasModular> {
  late final _busca = TextEditingController(
    text: ref.read(filtroTurmasModularProvider).busca,
  );

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(filtroTurmasModularProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = ref.watch(filtroTurmasModularProvider);
    final controlador = ref.read(filtroTurmasModularProvider.notifier);
    // Só os cursos que têm turma: um dropdown com o catálogo inteiro ofereceria
    // filtros que devolvem lista vazia — e "nenhuma turma com esses filtros" é
    // resposta pior do que não ter oferecido a opção.
    final cursos = <String, String>{
      for (final t
          in ref.watch(turmasModularProvider).value ?? const <TurmaModular>[])
        t.cursoId: t.cursoNome,
    };

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        CampoBusca(
          key: const Key('busca_turma_modular'),
          controlador: _busca,
          rotulo: 'Buscar turma',
          largura: 240,
          aoMudar: (valor) => controlador.definir(filtro.copiar(busca: valor)),
        ),
        FiltroSuspenso<String>(
          key: ValueKey('curso-${filtro.cursoId}'),
          rotulo: 'Curso',
          largura: 240,
          selecao: filtro.cursoId ?? '',
          entradas: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final entrada in cursos.entries)
              DropdownMenuEntry(value: entrada.key, label: entrada.value),
          ],
          aoSelecionar: (valor) => controlador.definir(
            filtro.copiar(
              cursoId: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// O cartão da turma
// ---------------------------------------------------------------------------

/// Em que pé está a leitura do cronograma daquela turma — os **três** estados
/// do `AsyncValue`, e não só o valor (item A3).
enum _EstadoCronograma { carregando, erro, pronto }

/// O estado combinado de várias leituras: erro vence, depois carregamento.
///
/// ⚠️ `hasError` **antes** de `hasValue`: sob o Riverpod 3 o provider que falha
/// passa por `AsyncError` e volta a `AsyncLoading` guardando o erro, e casar
/// pela classe faz a mensagem piscar (design-system §5.6, card 5.11).
_EstadoCronograma _estadoDe(List<AsyncValue<Object?>> leituras) {
  for (final leitura in leituras) {
    if (leitura.hasError) return _EstadoCronograma.erro;
  }
  for (final leitura in leituras) {
    if (!leitura.hasValue) return _EstadoCronograma.carregando;
  }
  return _EstadoCronograma.pronto;
}

const erroCronogramaModular =
    'Não foi possível ler o cronograma desta turma. O resto do cartão continua '
    'visível.';

/// `⠿ Massagem — Turma A · Sala 2 · 8/10 ▼` e, aberto, as três regiões do §8.
///
/// Colapsado por padrão em **todas** as faixas, e não só no celular: o §8
/// desenha a lista assim, e o conteúdo aberto de uma turma (cronograma, alunos
/// e três ações) empurraria as outras turmas para fora da primeira tela mesmo no
/// desktop.
class CartaoTurmaModular extends ConsumerStatefulWidget {
  const CartaoTurmaModular({super.key, required this.turma});

  final TurmaModular turma;

  @override
  ConsumerState<CartaoTurmaModular> createState() => _CartaoTurmaModularState();
}

class _CartaoTurmaModularState extends ConsumerState<CartaoTurmaModular> {
  // ⚠️ Havia aqui um `String? _erro` e um `AvisoTonal` que o mostrava — e
  // **nada nunca o atribuía**: estado morto com um banner que não aparecia
  // nunca (item B6). Toda escrita desta tela passa por um `FormularioIm360`,
  // que já tem o próprio banner de erro; quando nascer uma que não passe, o
  // banner volta com quem o preenche, e não antes.

  Future<void> _editar() async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioTurmaModular(turma: widget.turma),
    );
    if (!mounted || resultado == null) return;
    confirmarEfemero(
      context,
      resultado == 'excluido' ? 'Turma excluída.' : 'Turma salva.',
    );
  }

  Future<void> _adicionar() async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioAdicionarNaTurmaModular(turma: widget.turma),
    );
    if (resultado != null && mounted) {
      confirmarEfemero(context, 'Aluno adicionado à turma.');
    }
  }

  Future<void> _avancar(
    List<ModuloDaTurma> cronograma,
    List<Modulo> faltantes,
  ) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioAvancarModulo(
        turma: widget.turma,
        cronograma: cronograma,
        // Sem isto o diálogo anunciava o fim da turma tendo módulos do curso
        // ainda fora do cronograma, ao lado de um botão "Acrescentar 2
        // módulo(s)" (item B2).
        faltantes: faltantes.length,
      ),
    );
    if (!mounted || resultado == null) return;
    // Resultado que muda o que a pessoa fará em seguida é **diálogo**, nunca
    // snackbar (design-system §5.8): "a turma terminou" some antes de ser lido,
    // e é a informação que decide se ainda há o que avançar.
    if (resultado == 'terminou') {
      await mostrarResultadoAvanco(context, turma: widget.turma);
    } else {
      confirmarEfemero(context, 'Módulo avançado.');
    }
  }

  Future<void> _montarCronograma(List<Modulo> faltantes) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) =>
          FormularioMontarCronograma(turma: widget.turma, faltantes: faltantes),
    );
    if (resultado != null && mounted) {
      confirmarEfemero(context, 'Cronograma atualizado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final turma = widget.turma;
    final aberta = ref.watch(turmaAbertaProvider) == turma.id;
    // ⚠️ As DUAS leituras precisam dos três estados do `AsyncValue`, e não do
    // `.value ?? []`: em `loading` e em `error` o cronograma sairia vazio, e a
    // tela dizia "Sem cronograma de módulos" e oferecia "Montar cronograma"
    // para uma turma que tem cronograma e módulo atrasado — com a leitura
    // falhando, para sempre. É o B1 do card 5.11 nesta tela (item A3).
    final asyncCronograma = ref.watch(cronogramaModularProvider);
    final asyncModulos = ref.watch(modulosProvider(turma.cursoId));
    final estadoCronograma = _estadoDe([asyncCronograma, asyncModulos]);
    final pronto = estadoCronograma == _EstadoCronograma.pronto;

    final cronograma = pronto
        ? (ref.watch(cronogramaPorTurmaProvider)[turma.id] ??
              const <ModuloDaTurma>[])
        : const <ModuloDaTurma>[];
    final modulosDoCurso = pronto
        ? (asyncModulos.value ?? const <Modulo>[])
        : const <Modulo>[];
    final noCronograma = modulosNoCronograma(cronograma);
    final faltantes = [
      for (final m in modulosDoCurso)
        if (m.id != null && !noCronograma.contains(m.id)) m,
    ];

    final subtitulo = [
      turma.cursoNome,
      turma.salaNome,
      turma.lotacaoTexto,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: Dim.e12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Semantics do design-system §8.5: a linha anuncia turma, curso e
          // lotação de uma vez, em vez de ler três textos soltos.
          Semantics(
            button: true,
            expanded: aberta,
            label: '${turma.nome}, $subtitulo',
            child: ExcludeSemantics(
              child: InkWell(
                onTap: () =>
                    ref.read(turmaAbertaProvider.notifier).alternar(turma.id),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Dim.alvoMobile),
                  child: Padding(
                    padding: const EdgeInsets.all(Dim.e12),
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
                                  Text(turma.nome, style: Tipografia.rotulo),
                                  if (turma.acimaCapacidade)
                                    const _Selo(
                                      texto: 'acima da capacidade',
                                      icone: Icons.error_outline,
                                      erro: true,
                                    )
                                  else if (turma.lotada)
                                    const _Selo(
                                      texto: 'lotada',
                                      icone: Icons.group_outlined,
                                    ),
                                  if (turma.moduloAtrasado)
                                    const _Selo(
                                      texto: 'módulo atrasado',
                                      icone: Icons.schedule_outlined,
                                    ),
                                ],
                              ),
                              Text(
                                subtitulo,
                                style: Tipografia.numero(Tipografia.apoio)
                                    .copyWith(color: cores.onSurfaceVariant),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: Dim.e4),
                                child: Text(
                                  _resumoModulo(
                                    turma,
                                    estadoCronograma,
                                    cronograma.isEmpty,
                                  ),
                                  style: Tipografia.apoio,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          aberta ? Icons.expand_less : Icons.expand_more,
                          color: cores.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (aberta) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(Dim.e12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (turma.acimaCapacidade) ...[
                    AvisoTonal(
                      mensagem: avisoAcimaCapacidadeTurma(
                        turma.alocados,
                        turma.capacidade,
                      ),
                      erro: true,
                    ),
                    const SizedBox(height: Dim.e12),
                  ],
                  // Os avisos só existem com o cronograma NA MÃO: dizer "sem
                  // cronograma" enquanto ele carrega é afirmar o que ninguém
                  // sabe ainda (item A3).
                  if (pronto)
                    if (cronograma.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: Dim.e12),
                        child: AvisoTonal(mensagem: avisoSemCronograma),
                      )
                    else if (turma.semModuloCorrente)
                      const Padding(
                        padding: EdgeInsets.only(bottom: Dim.e12),
                        child: AvisoTonal(mensagem: avisoTurmaTerminou),
                      ),
                  _Cronograma(
                    turma: turma,
                    estado: estadoCronograma,
                    linhas: cronograma,
                    faltantes: faltantes,
                    aoMontar: () => _montarCronograma(faltantes),
                    aoRepetir: ref
                        .read(versaoModularProvider.notifier)
                        .incrementar,
                  ),
                  const SizedBox(height: Dim.e16),
                  _AlunosDaTurma(turma: turma, aoAdicionar: _adicionar),
                  const SizedBox(height: Dim.e16),
                  Wrap(
                    spacing: Dim.e8,
                    runSpacing: Dim.e8,
                    children: [
                      // ⚠️ Enquanto o cronograma não chegou o botão fica
                      // AUSENTE, e não desabilitado: o motivo seria falso, e
                      // motivo falso é pior que motivo nenhum (item A3).
                      if (pronto)
                        BotaoAcao(
                          rotulo: 'Avançar módulo',
                          icone: Icons.arrow_forward,
                          exigePermissao: 'turmas.editar',
                          // Sem **estado** o botão fica visível e desabilitado
                          // com o motivo (design-system §5.7): esconder aqui
                          // ensinaria que a ação não existe, quando o que falta
                          // é o cronograma — que a própria tela oferece montar.
                          desabilitado: cronograma.isEmpty
                              ? const DesabilitadoCom(
                                  'Monte o cronograma da turma antes de avançar '
                                  'o módulo.',
                                )
                              : turma.semModuloCorrente
                              ? const DesabilitadoCom(
                                  'Todos os módulos do cronograma já foram '
                                  'concluídos.',
                                )
                              : null,
                          aoTocar: () => _avancar(cronograma, faltantes),
                        ),
                      BotaoAcao(
                        rotulo: 'Adicionar aluno',
                        icone: Icons.person_add_alt_1_outlined,
                        nivel: NivelBotao.secundario,
                        exigePermissao: 'turmas.alocar',
                        aoTocar: _adicionar,
                      ),
                      BotaoAcao(
                        rotulo: 'Editar turma',
                        nivel: NivelBotao.terciario,
                        exigePermissao: 'turmas.editar',
                        aoTocar: _editar,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A linha "módulo corrente: 3. Massoterapia (até 20/09) ⚠ atraso" do §8, com os
/// dois estados que ela também precisa dizer.
String _resumoModulo(
  TurmaModular turma,
  _EstadoCronograma estado,
  bool semCronograma,
) {
  // Enquanto a leitura não chega, o cabeçalho DIZ que está carregando — não
  // afirma que a turma não tem cronograma (item A3).
  switch (estado) {
    case _EstadoCronograma.carregando:
      return 'Carregando cronograma…';
    case _EstadoCronograma.erro:
      return 'O cronograma não carregou';
    case _EstadoCronograma.pronto:
      break;
  }
  if (semCronograma) return 'Sem cronograma de módulos';
  final rotulo = turma.moduloCorrenteRotulo;
  if (rotulo == null) return 'Turma terminou — todos os módulos concluídos';
  final prev = turma.moduloCorrentePrevConclusao;
  final periodo = prev == null
      ? 'sem previsão'
      : 'até ${formatarDataCurta(prev)}';
  return 'Módulo corrente: $rotulo ($periodo)';
}

String avisoAcimaCapacidadeTurma(int alocados, int capacidade) =>
    'Esta turma tem ${plural(alocados, 'aluno', 'alunos')} para uma '
    'capacidade de $capacidade. '
    'Novas admissões estão bloqueadas até normalizar — remova alguém ou '
    'aumente a capacidade da turma.';

/// Selo de estado do cartão: **ícone e texto**, nunca cor sozinha
/// (design-system §8.2). Não é `BadgeStatus` nem `BadgeTipo`: os dois têm
/// vocabulário próprio (status do aluno, tipo na turma) e misturá-los aqui
/// quebraria a regra do card 1.9 §6.
class _Selo extends StatelessWidget {
  const _Selo({required this.texto, required this.icone, this.erro = false});

  final String texto;
  final IconData icone;
  final bool erro;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final cor = erro ? cores.error : cores.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 16, color: cor),
        const SizedBox(width: Dim.e4),
        Text(texto, style: Tipografia.apoio.copyWith(color: cor)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cronograma
// ---------------------------------------------------------------------------

/// `▤ Cronograma: 1 ✓ · 2 ✓ · 3 ► (01/08–20/09) · 4 · 5` do §8, em linhas.
///
/// Em linhas e não na faixa horizontal do desenho: cada módulo precisa de nome,
/// período e um alvo de toque de 44 px para editar as datas, e cinco desses
/// lado a lado não cabem numa tela de 430 px (design-system §3).
class _Cronograma extends ConsumerWidget {
  const _Cronograma({
    required this.turma,
    required this.estado,
    required this.linhas,
    required this.faltantes,
    required this.aoMontar,
    required this.aoRepetir,
  });

  final TurmaModular turma;
  final _EstadoCronograma estado;
  final List<ModuloDaTurma> linhas;
  final List<Modulo> faltantes;
  final VoidCallback aoMontar;
  final VoidCallback aoRepetir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final podeEditar = ref.watch(permissoesProvider).contains('turmas.editar');

    // Carregamento e erro moram DENTRO da região, e o resto do cartão continua
    // de pé — design-system §7.2, a mesma forma da região de alunos (item A3).
    if (estado != _EstadoCronograma.pronto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TituloSecao(texto: 'Cronograma'),
          if (estado == _EstadoCronograma.carregando)
            const EstadoCarregando(linhas: 2)
          else
            EstadoErro(mensagem: erroCronogramaModular, aoRepetir: aoRepetir),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloSecao(
          texto: 'Cronograma',
          apoio: linhas.isEmpty
              ? 'nenhum módulo'
              : plural(linhas.length, 'módulo', 'módulos'),
        ),
        if (linhas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Dim.e8),
            child: Text(
              faltantes.isEmpty
                  ? semModuloNoCurso
                  : 'Os módulos do curso ainda não foram trazidos para esta '
                        'turma.',
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            ),
          ),
        for (final modulo in linhas)
          _LinhaModulo(turma: turma, modulo: modulo, podeEditar: podeEditar),
        if (faltantes.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoAcao(
              rotulo: linhas.isEmpty
                  ? 'Montar cronograma'
                  : 'Acrescentar ${plural(faltantes.length, 'módulo', 'módulos')}',
              icone: Icons.playlist_add,
              nivel: NivelBotao.secundario,
              exigePermissao: 'turmas.editar',
              aoTocar: aoMontar,
            ),
          ),
      ],
    );
  }
}

const semModuloNoCurso =
    'O curso desta turma não tem módulos cadastrados. Cadastre-os em Materiais '
    'antes de montar o cronograma.';

class _LinhaModulo extends StatelessWidget {
  const _LinhaModulo({
    required this.turma,
    required this.modulo,
    required this.podeEditar,
  });

  final TurmaModular turma;
  final ModuloDaTurma modulo;
  final bool podeEditar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    // ✓ / ► / — sempre com o número do módulo e o texto ao lado: símbolo não é
    // portador único (design-system §8.2).
    final (icone, cor, estado) = switch (modulo.estado) {
      EstadoModulo.concluido => (
        Icons.check_circle_outline,
        cores.onSurfaceVariant,
        'concluído',
      ),
      EstadoModulo.corrente => (
        Icons.play_circle_outline,
        cores.primary,
        'em curso',
      ),
      EstadoModulo.futuro => (
        Icons.circle_outlined,
        cores.onSurfaceVariant,
        'a fazer',
      ),
    };
    final apoio = modulo.atrasado
        ? '${modulo.periodo} · atrasado'
        : '${modulo.periodo} · $estado';

    final conteudo = Padding(
      padding: const EdgeInsets.symmetric(vertical: Dim.e4),
      child: Row(
        children: [
          Icon(icone, size: 18, color: cor),
          const SizedBox(width: Dim.e8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotuloModulo(modulo.moduloOrdem, modulo.moduloNome),
                  style: Tipografia.numero(Tipografia.corpoTabela),
                ),
                Text(
                  apoio,
                  style: Tipografia.numero(Tipografia.apoio).copyWith(
                    color: modulo.atrasado
                        ? cores.error
                        : cores.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (podeEditar)
            // O ícone é decorativo (o `Semantics` da linha já a anuncia), mas
            // no desktop nada dizia o que o clique faz — o `Tooltip` é a
            // metade que faltava (item D4).
            Tooltip(
              message: 'Editar datas',
              child: Icon(
                Icons.edit_outlined,
                size: 16,
                color: cores.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );

    // Sem `turmas.editar` a linha **não é clicável**: não há o que oferecer, e
    // um toque que abre um formulário só de leitura ensina a tocar em vão.
    if (!podeEditar) {
      return Semantics(
        label: '${rotuloModulo(modulo.moduloOrdem, modulo.moduloNome)}, $apoio',
        child: ExcludeSemantics(child: conteudo),
      );
    }
    return Semantics(
      button: true,
      label: '${rotuloModulo(modulo.moduloOrdem, modulo.moduloNome)}, $apoio',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => mostrarFormulario<String>(
            context,
            construtor: (_) =>
                FormularioDatasModulo(turma: turma, modulo: modulo),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Dim.alvoMobile),
            child: conteudo,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alunos
// ---------------------------------------------------------------------------

/// `▤ Alunos (8) [+ Adicionar]` do §8.
///
/// ⚠️ **Sem `alunos.ler` esta região declara o que falta, em vez de listar
/// vazio.** A rota da tela 5 é `turmas.ler` + `salas.ler` + `materiais.ler`
/// (permissoes-matriz §6, linha 5) e não inclui `alunos.ler`, mas
/// `v_turma_modular_aluno` junta `aluno` internamente — sem a permissão a lista
/// vem vazia enquanto a lotação, ao lado, diz `8/15`. Uma turma "sem aluno
/// nenhum" com oito alocados é a redução silenciosa do card 2.3 §3.4 na sua
/// forma mais enganosa, e o remédio é o texto por região do design-system §5.6.
class _AlunosDaTurma extends ConsumerWidget {
  const _AlunosDaTurma({required this.turma, required this.aoAdicionar});

  final TurmaModular turma;
  final VoidCallback aoAdicionar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissoes = ref.watch(permissoesProvider);
    if (!permissoes.contains('alunos.ler')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TituloSecao(
            texto: 'Alunos',
            apoio: plural(turma.alocados, 'aluno na turma', 'alunos na turma'),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: _alturaRegiao),
            child: EstadoSemAcesso(
              faltando: {'alunos.ler'},
              texto: semAcessoAlunos,
            ),
          ),
        ],
      );
    }

    final async = ref.watch(alunosModularProvider);
    final todos = ref.watch(alunosPorTurmaProvider)[turma.id] ?? const [];
    final ativos = [
      for (final a in todos)
        if (a.ativo) a,
    ];
    final saidas = [
      for (final a in todos)
        if (!a.ativo) a,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TituloSecao(
          texto: 'Alunos',
          apoio: '${ativos.length} de ${turma.capacidade}',
        ),
        // O erro e o carregamento moram DENTRO da região, nunca no lugar da
        // tela: o cronograma e o avanço não dependem desta consulta
        // (design-system §7.2, correção de 04/09/2026).
        if (async.isLoading && !async.hasValue)
          const EstadoCarregando(linhas: 3)
        else if (async.hasError)
          EstadoErro(
            mensagem:
                (async.error is ErroApp
                        ? async.error! as ErroApp
                        : traduzirErro(async.error!))
                    .mensagem,
            aoRepetir: ref.read(versaoModularProvider.notifier).incrementar,
          )
        else if (ativos.isEmpty && saidas.isEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _alturaRegiao),
            child: EstadoVazio(
              mensagem: vazioAlunosTurmaModular,
              icone: Icons.person_outline,
              rotuloAcao: permissoes.contains('turmas.alocar')
                  ? '+ Adicionar aluno'
                  : null,
              aoAgir: aoAdicionar,
            ),
          )
        else ...[
          for (final aluno in ativos)
            _LinhaAlunoModular(turma: turma, aluno: aluno),
          if (saidas.isNotEmpty) ...[
            const SizedBox(height: Dim.e8),
            TituloSecao(texto: 'Saíram', apoio: '${saidas.length}'),
            for (final aluno in saidas)
              _LinhaAlunoModular(turma: turma, aluno: aluno),
          ],
        ],
      ],
    );
  }
}

const vazioAlunosTurmaModular = 'Nenhum aluno nesta turma.';

const semAcessoAlunos =
    'Você não tem acesso à lista de alunos. A turma e o cronograma continuam '
    'visíveis; os nomes exigem a permissão de ler alunos.';

/// O estado da região vive dentro de uma coluna rolável: sem altura ele tentaria
/// ocupar o infinito.
///
/// **Mínimo, e não fixo** (item F4): desde a correção 16 do §11 os estados
/// rolam dentro do painel, então grampear 200 px só reservava espaço em branco
/// abaixo de um estado curto.
const _alturaRegiao = 200.0;

class _LinhaAlunoModular extends ConsumerWidget {
  const _LinhaAlunoModular({required this.turma, required this.aluno});

  final TurmaModular turma;
  final AlunoDaTurmaModular aluno;

  Future<void> _remover(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) =>
          FormularioRemoverDaTurmaModular(turma: turma, aluno: aluno),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Aluno removido da turma.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final apoio = <String>[
      if (aluno.codigoSgf != null) aluno.codigoSgf!,
      if (aluno.ativo)
        'desde ${formatarData(aluno.dataEntrada)}'
      else
        'saiu${aluno.motivoSaida == null ? '' : ' — ${aluno.motivoSaida}'}',
    ];

    return LinhaTurma(
      titulo: aluno.alunoNome,
      // O nome leva à ficha: daqui se chega à Trilha, que é a jornada nº 1 do
      // monitor (card 2.6 §3.2).
      aoTocarTitulo: () => context.go(caminhoFichaAluno(aluno.alunoId)),
      badges: [
        // O status só aparece quando NÃO é o esperado: dez badges "ATIVO"
        // iguais não informam nada e escondem o décimo primeiro.
        if (aluno.alunoStatus != 'ATIVO') BadgeStatus(aluno.alunoStatus),
        if (!aluno.ativo)
          Text(
            'fora da turma',
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          ),
      ],
      apoio: apoio.join(' · '),
      // Quem já saiu não tem ação: remover de novo devolveria
      // `ALOCACAO_INEXISTENTE`, e oferecer o que vai falhar é o que a decisão 1
      // do card 2.6 proíbe. A linha fica para `motivo_saida` ser lido.
      acao: aluno.ativo
          ? BotaoAcao(
              rotulo: 'Remover',
              nivel: NivelBotao.terciario,
              exigePermissao: 'turmas.alocar',
              aoTocar: () => _remover(context),
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Turmas inativas e o resultado do avanço
// ---------------------------------------------------------------------------

/// As turmas desativadas, que a view de lotação não traz (`where t.ativo`).
///
/// Existe para que desativar não seja porta de mão única: sem esta lista, a
/// turma desativada sumiria da única tela que fala de turma Modular e só voltaria
/// por alguém escrevendo no banco. Mesma decisão dos blocos inativos (card 5.6).
class DialogoTurmasInativas extends ConsumerWidget {
  const DialogoTurmasInativas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final inativas = ref.watch(turmasModularInativasProvider).value ?? const [];
    final cursos = {
      for (final c in ref.watch(cursosProvider).value ?? const <Curso>[])
        c.id: c.nome,
    };

    return PainelDetalhe(
      titulo: 'Turmas inativas',
      subtitulo: 'Fora da lista e sem receber aluno novo. Reabra para editar.',
      acoes: const [],
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inativas.isEmpty)
            Text(
              'Nenhuma turma inativa.',
              style: Tipografia.corpo.copyWith(color: cores.onSurfaceVariant),
            ),
          for (final turma in inativas)
            Padding(
              padding: const EdgeInsets.only(bottom: Dim.e8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(turma.nome, style: Tipografia.rotulo),
                        Text(
                          '${cursos[turma.cursoId] ?? '—'} · capacidade '
                          '${turma.capacidade}',
                          style: Tipografia.numero(Tipografia.apoio)
                              .copyWith(color: cores.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  BotaoAcao(
                    rotulo: 'Abrir',
                    nivel: NivelBotao.secundario,
                    exigePermissao: 'turmas.editar',
                    aoTocar: () async {
                      final resultado = await mostrarFormulario<String>(
                        context,
                        construtor: (_) =>
                            FormularioTurmaModular(turma: turma, inativa: true),
                      );
                      if (resultado != null && context.mounted) {
                        Navigator.of(context).pop(resultado);
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// O avanço que fechou o **último** módulo: a turma terminou.
///
/// Diálogo, e não confirmação efêmera (design-system §5.8): é o resultado que
/// muda a próxima ação de quem avançou — não há mais módulo, e o que resta é
/// decidir o que fazer com a turma.
Future<void> mostrarResultadoAvanco(
  BuildContext context, {
  required TurmaModular turma,
}) => showDialog<void>(
  context: context,
  builder: (contexto) => AlertDialog(
    title: const Text('Turma terminou'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Text(
        '${turma.nome} concluiu o último módulo do cronograma. A turma '
        'continua na lista: desative-a quando ela realmente encerrar, ou '
        'acrescente módulos ao cronograma.',
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
