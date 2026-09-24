import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../pendencias/pendencias.dart';
import '../../pendencias/pendencias_provider.dart';
import '../../projecao/projecao.dart';
import '../../projecao/projecao_provider.dart';
import '../../rotas/rotas.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/async_valor.dart';
import '../../widgets/abertura_por_url.dart';
import '../../widgets/barra_filtros.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import '../../widgets/recalcular_agora.dart';
import '../../widgets/tabela_im360.dart';
import 'painel_celula.dart';

/// Tela 8 — Projeção de demanda (docs/wireframes.md §11).
///
/// Responde "quanta apostila vou precisar, de qual, em que mês — e por quê".
/// A grade é material × mês com o total ao lado; o drill-down de uma célula diz
/// **quais alunos** somam ali e **por qual degrau da cascata**.
///
/// Rota: `materiais.ler + estoque.ler + alunos.ler + turmas.ler`
/// (docs/permissoes-matriz.md §6, linha 8). O `turmas.ler` entrou com a parcela
/// Modular, que lê o cronograma da turma: sem ele a projeção não vem errada, vem
/// **vazia** (card 2.3 §3.4).
///
/// ⚠️ **Duas leituras com relógios diferentes, e a tela diz isso.** O total vem
/// da tabela que a rotina gravou na madrugada; o detalhe é lido ao vivo. Podem
/// divergir ao longo do dia — uma entrega registrada hoje de manhã basta —, e
/// essa divergência é esperada. É por isso que o `calculado_em` é obrigatório no
/// cabeçalho: número de projeção sem a data do cálculo é número sem validade.
class TelaProjecao extends ConsumerWidget {
  const TelaProjecao({super.key, this.materialId});

  /// `?material=<id>` — o mesmo desenho de `?material=` na tela 6 e de
  /// `?pedido=` na 7: a tela abre já com o drill-down daquele material. Existe
  /// para o dia em que a tela de Compras mandar "de onde vem esta projeção?"
  /// para cá.
  final String? materialId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _Grade(materialId: materialId);
}

class _Grade extends ConsumerStatefulWidget {
  const _Grade({this.materialId});

  final String? materialId;

  @override
  ConsumerState<_Grade> createState() => _GradeState();
}

class _GradeState extends ConsumerState<_Grade> with AberturaPorUrl {
  @override
  void didUpdateWidget(_Grade anterior) {
    super.didUpdateWidget(anterior);
    if (widget.materialId != null && widget.materialId != anterior.materialId) {
      reabrirNaProxima();
    }
  }

  Future<void> _abrir(CelulaPedida celula) async {
    // O painel do drill-down é leitura: fecha sem devolver nada, e não move
    // versão nenhuma — não há o que salvar numa tela que só lê.
    await mostrarFormulario<void>(
      context,
      largura: larguraDetalhe,
      construtor: (_) => PainelCelula(celula: celula),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ Os três estados do catálogo, e não `.value ?? []` (item B3): em erro
    // a coluna Método mostrava `—` em TODA linha e o filtro oferecia só
    // "Todos", para sempre e sem nenhum erro em tela. A saída definitiva é a
    // view expor o código do método (divergência E1, migração, fora deste
    // card); até lá a coluna diz "não lido" e a tela diz por quê.
    final catalogo = ref.watch(metodosProvider);
    final metodos = catalogo.value ?? const <Metodo>[];
    final metodosNaoLidos = catalogo.hasError;
    final metodosPorId = {for (final m in metodos) m.id: m};
    String nomeDoMetodo(String metodoId) =>
        metodosNaoLidos ? metodoNaoLido : metodosPorId[metodoId]?.nome ?? '—';
    final grade = ref.watch(gradeProjecaoProvider);
    final filtro = ref.watch(filtroProjecaoProvider);
    // ⚠️ Os três estados, e não `.value ?? false` (card 9.2,62): em carga e em
    // erro o `false` fazia a tela afirmar "Sem demanda projetada" — exatamente
    // o que o design-system §7.2 proíbe quando não se sabe se a rotina falhou.
    final rotina = ref.watch(rotinaProjecaoFalhouProvider);

    final todas = grade.value ?? const <CelulaProjecao>[];

    // ⚠️ As colunas de mês saem de TODAS as células, nunca das filtradas: com o
    // cabeçalho derivado do recorte, escolher um método reescreveria a tabela e
    // a pessoa compararia dois recortes achando que compara o mesmo.
    final meses = mesesDaProjecao(todas);
    final comAno = mesesCruzamAno(meses);

    final linhas = pivotar(filtrarCelulas(todas, filtro));

    // Chegou por `?material=`: abre o painel assim que a grade tiver dado, uma
    // vez só (o mixin `AberturaPorUrl`, item F1).
    if (grade.hasValue) {
      abrirUmaVez(
        widget.materialId,
        (id) => _abrir(CelulaPedida(materialId: id)),
      );
    }

    final tabela = TabelaIm360<LinhaProjecao>(
      filtros: _FiltrosProjecao(
        filtro: filtro,
        metodos: metodos,
        categorias: categoriasProjetadas(todas),
        regras: regrasPresentes(todas),
      ),
      filtrosAtivos: filtro.ativos,
      colunas: [
        ColunaIm360(
          titulo: 'Código',
          texto: (l) => l.codigo,
          flex: 1,
          larguraMin: 90,
        ),
        ColunaIm360(
          titulo: 'Material',
          texto: (l) => l.nome,
          flex: 3,
          larguraMin: 180,
        ),
        ColunaIm360(
          titulo: 'Método',
          texto: (l) => nomeDoMetodo(l.metodoId),
          prioridade: 4,
          larguraMin: 120,
        ),
        // A proveniência no TOTAL, e não só no detalhe (card 2.3 §5.3):
        // projeção sem ela não é revisável. Linha atendida por mais de um
        // degrau diz "Várias" — e o filtro por regra é quem a separa.
        ColunaIm360(
          titulo: 'Regra',
          texto: (l) => l.rotuloProveniencia,
          prioridade: 3,
          flex: 2,
          larguraMin: 140,
        ),
        for (final mes in meses)
          ColunaIm360(
            titulo: rotuloMes(mes, comAno: comAno),
            // O traço, e não `0`: mês sem projeção não é mês com projeção zero.
            texto: (l) => l.temMes(mes) ? '${l.quantidadeEm(mes)}' : '—',
            celula: (l) => _CelulaMes(
              linha: l,
              mes: mes,
              comAno: comAno,
              aoAbrir: () =>
                  _abrir(CelulaPedida(materialId: l.materialId, mes: mes)),
            ),
            numerica: true,
            prioridade: 2,
            flex: 1,
            larguraMin: 72,
          ),
        ColunaIm360(
          titulo: 'Total',
          texto: (l) => '${l.total}',
          numerica: true,
          flex: 1,
          larguraMin: 80,
        ),
      ],
      linhas: grade.derivar((_) => linhas),
      // A linha inteira abre o material — é o alvo do celular, onde não há
      // célula de mês para tocar, e a saída do teclado no desktop.
      aoTocarLinha: (l) => _abrir(CelulaPedida(materialId: l.materialId)),
      cartao: (l) => CartaoIm360(
        titulo: l.nome,
        subtitulo: [
          l.codigo,
          nomeDoMetodo(l.metodoId),
          l.categoria,
        ].join(' · '),
        apoio: [
          for (final mes in meses)
            if (l.temMes(mes))
              '${rotuloMes(mes, comAno: comAno)} ${l.quantidadeEm(mes)}',
        ].join(' · '),
        destaque: 'total ${l.total}',
      ),
      estadoVazio: _vazio(
        temDado: todas.isNotEmpty,
        filtrado: filtro.ativos > 0,
        rotina: rotina,
      ),
      aoRepetir: ref.read(versaoProjecaoProvider.notifier).incrementar,
    );

    // O carimbo fica ACIMA da barra de filtros, e não dentro da tabela: ele vale
    // para a projeção inteira, não para as linhas que o filtro deixou passar.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Cabecalho(grade: grade),
        if (metodosNaoLidos)
          Padding(
            padding: const EdgeInsets.fromLTRB(Dim.e16, Dim.e12, Dim.e16, 0),
            child: AvisoTonal(
              mensagem: erroMetodosNaoLidos,
              rotuloAcao: 'Tentar de novo',
              aoAgir: () => ref.invalidate(metodosProvider),
            ),
          ),
        Expanded(child: tabela),
      ],
    );
  }

  /// Três vazios diferentes, e a diferença é o ponto (design-system §7.2).
  Widget _vazio({
    required bool temDado,
    required bool filtrado,
    required AsyncValue<bool> rotina,
  }) {
    if (temDado && filtrado) {
      return EstadoVazio(
        mensagem: vazioProjecaoFiltro,
        icone: Icons.filter_alt_off_outlined,
        rotuloAcao: 'Limpar filtros',
        aoAgir: ref.read(filtroProjecaoProvider.notifier).limpar,
      );
    }
    // ⚠️ A rotina que falha NÃO deixa a tabela vazia: `rt_projecao_demanda` faz
    // `delete` + `insert` na mesma transação, e o bloco de exceção de `rt_diaria`
    // reverte os dois — a projeção anterior sobrevive com o carimbo velho. Então
    // tabela vazia com pendência aberta é "nunca chegou a gravar", e é isso que
    // este texto diz; sem a pendência, é a escola que de fato não tem demanda no
    // horizonte. Sem os dois estados separados, um vazio honesto viraria um
    // alarme falso, e um alarme viraria silêncio.
    // Sem saber se a rotina falhou, nenhum dos dois vazios de baixo é verdade:
    // "sem demanda" seria alarme calado, "a rotina falhou" seria alarme falso.
    if (rotina.hasError) {
      return EstadoVazio(
        mensagem: vazioProjecaoRotinaNaoLida,
        icone: Icons.help_outline,
        rotuloAcao: 'Tentar de novo',
        aoAgir: () => ref.invalidate(rotinaProjecaoFalhouProvider),
      );
    }
    if (!rotina.hasValue) return const EstadoCarregando(linhas: 3);
    if (rotina.value!) {
      final permissoes = ref.watch(permissoesProvider);
      return EstadoVazio(
        mensagem: vazioProjecaoRotinaFalhou,
        icone: Icons.error_outline,
        // Sem permissão o botão não é renderizado (design-system §5.7):
        // oferecer o que leva a "Sem acesso" ensina a não clicar nos outros.
        rotuloAcao: permissoes.contains('pendencias.ler')
            ? 'Ver pendências'
            : null,
        // Com o filtro por TIPO definido antes de navegar (item B2): sem ele o
        // botão largava a pessoa na central inteira, para procurar de novo a
        // pendência que a tela acabou de nomear — o D3 do card 8.1,5 fechou o
        // mesmo caso na aba Trilha.
        aoAgir: () {
          ref
              .read(filtroPendenciasProvider.notifier)
              .definir(const FiltroPendencias(tipo: 'ROTINA_FALHOU'));
          context.go(caminhoDeRota('pendencias'));
        },
      );
    }
    return const EstadoVazio(
      mensagem: vazioProjecao,
      icone: Icons.event_available_outlined,
    );
  }
}

/// "Projeção calculada em …" — a validade de tudo o que está abaixo, e
/// obrigatória (design-system §7.3).
///
/// **Dois** estados aqui, e não os três de Compras (item B5 da revisão das
/// telas 08/09): o carimbo sai da MESMA leitura que a grade, então "não foi
/// possível ler quando foi calculada" nunca acontece sozinho — quando a grade
/// falha, a tabela já mostra o erro com "Tentar de novo", e uma segunda frase
/// de erro para a mesma falha seria dizer duas vezes. A que **nunca rodou** não
/// é a que rodou e não previu nada, e nenhuma das duas é um traço mudo.
/// Enquanto carrega (a primeira vez) não desenha nada — piscar "ainda não foi
/// calculada" por meio segundo é dizer uma coisa falsa; na recarga o carimbo
/// anterior fica (item A2).
class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.grade});

  final AsyncValue<List<CelulaProjecao>> grade;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final texto = grade.when(
      skipLoadingOnReload: true,
      loading: () => null,
      error: (_, _) => null,
      data: (celulas) {
        final quando = calculadoEmDe(celulas);
        return quando == null
            ? projecaoSemCarimbo
            : projecaoCalculadaEm(formatarDataHora(quando));
      },
    );
    if (texto == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(Dim.e16, Dim.e12, Dim.e16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.update_outlined, size: 16, color: cores.onSurfaceVariant),
          const SizedBox(width: Dim.e8),
          // `Expanded`, e não largura fixa: em 390 px a frase da projeção sem
          // carimbo ocupa três linhas, e sem isto ela estoura a `Row`
          // (design-system §11, item 19). Expandido para o botão ficar na
          // borda direita (card 9.2,65).
          Expanded(
            child: Text(
              texto,
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: Dim.e8),
          const BotaoRecalcularAgora(),
        ],
      ),
    );
  }
}

/// A célula de um mês: o número, e o número é o alvo do drill-down
/// (wireframe §11, "célula INT-04 × out").
///
/// ⚠️ Só é alvo quando **há** quantidade. Um traço que abre um painel vazio é a
/// promessa que não se cumpre; o mês sem projeção não tem o que detalhar, e a
/// linha inteira continua clicável para quem quiser o material todo.
class _CelulaMes extends StatelessWidget {
  const _CelulaMes({
    required this.linha,
    required this.mes,
    required this.comAno,
    required this.aoAbrir,
  });

  final LinhaProjecao linha;
  final DateTime mes;
  final bool comAno;
  final VoidCallback aoAbrir;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    if (!linha.temMes(mes)) {
      return Text(
        '—',
        style: Tipografia.numero(Tipografia.corpoTabela)
            .copyWith(color: cores.onSurfaceVariant),
      );
    }
    final rotulo = rotuloMes(mes, comAno: comAno);
    return Tooltip(
      message: 'Ver os alunos de ${linha.nome} em $rotulo',
      child: InkWell(
        onTap: aoAbrir,
        borderRadius: BorderRadius.circular(Dim.raio),
        child: Semantics(
          button: true,
          label: '${linha.quantidadeEm(mes)} em $rotulo, ver os alunos',
          excludeSemantics: true,
          // O alvo ocupa a altura da linha, e não só o número (item D3): com o
          // padding de 4 px o `InkWell` media ~28 px numa linha de 44, contra
          // o mínimo de 40 do design-system §8.4.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Dim.alturaBotao),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Dim.e8),
                child: Text(
                  '${linha.quantidadeEm(mes)}',
                  style: Tipografia.numero(Tipografia.corpoTabela).copyWith(
                    color: cores.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: cores.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Busca, método, categoria e regra (design-system §5.3 e wireframe §11).
class _FiltrosProjecao extends ConsumerStatefulWidget {
  const _FiltrosProjecao({
    required this.filtro,
    required this.metodos,
    required this.categorias,
    required this.regras,
  });

  final FiltroProjecao filtro;
  final List<Metodo> metodos;
  final List<String> categorias;
  final List<String> regras;

  @override
  ConsumerState<_FiltrosProjecao> createState() => _FiltrosProjecaoState();
}

class _FiltrosProjecaoState extends ConsumerState<_FiltrosProjecao> {
  late final _busca = TextEditingController(text: widget.filtro.busca);

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Limpar filtros" vem de fora (estado vazio): o campo acompanha.
    ref.listen(filtroProjecaoProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = widget.filtro;
    final controlador = ref.read(filtroProjecaoProvider.notifier);

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // O `CampoBusca` do card 8.1,5, e não um `TextField` de 240 px cru
        // (item B1): dentro da folha "Filtrar" do celular ele mede a largura da
        // folha, como os três menus ao lado.
        CampoBusca(
          controlador: _busca,
          rotulo: 'Código ou material',
          aoMudar: (valor) => controlador.definir(filtro.copiar(busca: valor)),
          aoLimpar: () => controlador.definir(filtro.copiar(busca: '')),
        ),
        FiltroSuspenso<String>(
          key: ValueKey('metodo-${filtro.metodoId}'),
          rotulo: 'Método',
          largura: 180,
          selecao: filtro.metodoId ?? '',
          entradas: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final metodo in widget.metodos)
              DropdownMenuEntry(value: metodo.id, label: metodo.nome),
          ],
          aoSelecionar: (valor) => controlador.definir(
            filtro.copiar(
              metodoId: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        FiltroSuspenso<String>(
          key: ValueKey('categoria-${filtro.categoria}'),
          rotulo: 'Categoria',
          largura: 180,
          selecao: filtro.categoria ?? '',
          entradas: [
            const DropdownMenuEntry(value: '', label: 'Todas'),
            for (final categoria in widget.categorias)
              DropdownMenuEntry(value: categoria, label: categoria),
          ],
          aoSelecionar: (valor) => controlador.definir(
            filtro.copiar(
              categoria: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        // O filtro que responde "quanto desta compra é cronograma datado e
        // quanto é média do método" (wireframe §11). Só oferece o degrau que
        // existe na projeção de hoje.
        FiltroSuspenso<String>(
          key: ValueKey('regra-${filtro.regra}'),
          rotulo: 'Regra',
          largura: 200,
          selecao: filtro.regra ?? '',
          entradas: [
            const DropdownMenuEntry(value: '', label: 'Todas'),
            for (final regra in widget.regras)
              DropdownMenuEntry(value: regra, label: rotuloRegra(regra)),
          ],
          aoSelecionar: (valor) => controlador.definir(
            filtro.copiar(
              regra: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
      ],
    );
  }
}
