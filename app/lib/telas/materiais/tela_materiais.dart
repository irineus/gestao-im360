import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../estoque/estoque.dart';
import '../../estoque/estoque_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/cores.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../widgets/abertura_por_url.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import '../../widgets/painel_mobile.dart';
import '../../widgets/tabela_im360.dart';
import 'detalhes.dart';
import 'filtros_catalogo.dart';
import 'formularios.dart';
import 'painel_estoque.dart';

/// Tela 6 — Materiais e estoque (docs/wireframes.md §9). O catálogo nasceu no
/// card 4.4 (materiais, cursos com sequência e módulos, combos); o **estoque**
/// — saldo, mínimo × saldo, movimentações e o ajuste — entrou no card 6.7, que
/// trocou a fonte da aba de materiais da tabela `material` para
/// `v_estoque_atual` (card 6.4) e acrescentou o painel de `v_material_movimento`.
///
/// Cursos, módulos e combos moram aqui, junto do uso, e não na Administração
/// (card 2.6, apontamento 1).
class TelaMateriais extends StatelessWidget {
  const TelaMateriais({super.key, this.materialId});

  /// `?material=<id>` — o atalho da central de pendências (os três tipos de
  /// estoque levam para cá, wireframe §14.3). A tela abre o material pedido;
  /// sem o id, "Ver material" abria o catálogo inteiro e a pessoa procurava de
  /// novo o que a pendência já sabia.
  final String? materialId;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Materiais'),
            Tab(text: 'Cursos'),
            Tab(text: 'Combos'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              AbaMateriais(materialId: materialId),
              const AbaCursos(),
              const AbaCombos(),
            ],
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Materiais
// ---------------------------------------------------------------------------

/// Estado vazio da tela (design-system §7.2) — os textos são os do card 2.7;
/// "Nenhum … com esses filtros" difere só pelo objeto da aba.
const vazioMateriais = 'Nenhum material cadastrado.';
const vazioMateriaisFiltro = 'Nenhum material com esses filtros.';
const vazioCursos = 'Nenhum curso cadastrado.';
const vazioCursosFiltro = 'Nenhum curso com esses filtros.';
const vazioCombos = 'Nenhum combo cadastrado.';
const vazioCombosFiltro = 'Nenhum combo com esses filtros.';

class AbaMateriais extends ConsumerStatefulWidget {
  const AbaMateriais({super.key, this.materialId});

  /// O material pedido na URL.
  final String? materialId;

  @override
  ConsumerState<AbaMateriais> createState() => _AbaMateriaisState();
}

class _AbaMateriaisState extends ConsumerState<AbaMateriais>
    with AberturaPorUrl<AbaMateriais> {
  /// O material do painel de movimentações. Nulo = painel fechado.
  ///
  /// Guarda o **id**, não a linha: a lista recarrega a cada ajuste, e segurar o
  /// objeto deixaria o cabeçalho do painel mostrando o saldo de antes do
  /// lançamento — o mesmo defeito do `AsyncValue` reaproveitado do card 4.4.
  String? _selecionado;

  @override
  void didUpdateWidget(AbaMateriais anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.materialId != widget.materialId) reabrirNaProxima();
  }

  Future<void> _editar(BuildContext context, MaterialDidatico? material) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioMaterial(material: material),
    );
    if (resultado != null && context.mounted) {
      // O cadastro muda o mínimo e o "ativo", que são colunas de
      // `v_estoque_atual`: as duas versões precisam andar juntas, senão a lista
      // continuaria mostrando o mínimo antigo depois de salvar.
      ref.read(versaoEstoqueProvider.notifier).incrementar();
      confirmarEfemero(
        context,
        resultado == 'excluido' ? 'Material excluído.' : 'Material salvo.',
      );
      if (resultado == 'excluido') setState(() => _selecionado = null);
    }
  }

  Future<void> _ajustar(BuildContext context, MaterialEstoque material) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioAjusteEstoque(material: material),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, resultado);
    }
  }

  /// Abre o painel do material. No desktop ele mora **abaixo da tabela**, como
  /// o wireframe §9 desenha; no mobile não há altura para os dois, e ele vira
  /// um painel de tela cheia (design-system §5.4).
  void _selecionar(BuildContext context, MaterialEstoque material) {
    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
    setState(() => _selecionado = material.materialId);
    if (!mobile) return;
    mostrarFormulario<void>(
      context,
      largura: larguraDetalhe,
      construtor: (contexto) => _PainelMobile(
        materialId: material.materialId,
        aoEditar: (cadastro) => _editar(contexto, cadastro),
        aoAjustar: (linha) => _ajustar(contexto, linha),
      ),
    );
  }

  MaterialDidatico? _cadastroDe(String materialId) {
    for (final m in ref.read(materiaisProvider).value ?? const []) {
      if (m.id == materialId) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final metodosPorId = {for (final m in metodos) m.id: m};
    // O catálogo continua observado: o formulário de material grava por ele, e
    // é dele que sai o `MaterialDidatico` que o formulário edita.
    ref.watch(materiaisProvider);
    final estoque = ref.watch(estoqueProvider);

    final pedido = widget.materialId;
    if (pedido != null && estoque.hasValue) {
      MaterialEstoque? alvo;
      for (final m in estoque.requireValue) {
        if (m.materialId == pedido) alvo = m;
      }
      // O atalho da central de pendências (wireframe §14.3) abre o material no
      // PAINEL, e não no formulário de cadastro: as três pendências de estoque
      // perguntam "quanto tem e por quê", e a resposta é a história do material.
      abrirUmaVez(alvo, (material) => _selecionar(context, material));
    }
    final filtro = ref.watch(filtroMateriaisProvider);
    final permissoes = ref.watch(permissoesProvider);
    final haCadastro = estoque.value?.isNotEmpty ?? false;

    final tabela = TabelaIm360<MaterialEstoque>(
      filtros: FiltrosCatalogo(
        provider: filtroMateriaisProvider,
        metodos: metodos,
        categorias: categoriasDoEstoque(estoque.value ?? const []),
        rotuloBusca: 'Código ou nome',
        abaixoMinimo: true,
      ),
      filtrosAtivos: filtro.ativos,
      acoes: [
        BotaoAcao(
          rotulo: 'Métodos',
          nivel: NivelBotao.secundario,
          exigePermissao: 'materiais.editar',
          aoTocar: () async {
            final resultado = await mostrarFormulario<String>(
              context,
              construtor: (_) => FormularioMetodos(metodos: metodos),
            );
            if (resultado != null && context.mounted) {
              confirmarEfemero(context, 'Métodos salvos.');
            }
          },
        ),
        BotaoAcao(
          rotulo: 'Novo material',
          icone: Icons.add,
          exigePermissao: 'materiais.criar',
          aoTocar: () => _editar(context, null),
        ),
      ],
      colunas: [
        ColunaIm360(
          titulo: 'Código',
          texto: (m) => m.codigo,
          flex: 1,
          larguraMin: 90,
        ),
        ColunaIm360(
          titulo: 'Material',
          texto: (m) => m.nome,
          flex: 3,
          larguraMin: 200,
        ),
        ColunaIm360(
          titulo: 'Método',
          texto: (m) => metodosPorId[m.metodoId]?.nome ?? '—',
          prioridade: 2,
          larguraMin: 130,
        ),
        ColunaIm360(
          titulo: 'Categoria',
          texto: (m) => m.categoria,
          prioridade: 3,
          larguraMin: 140,
        ),
        // ⚠️ Saldo negativo é DESTACADO, nunca escondido (card 2.3 §4.1): é
        // sintoma de AJUSTE errado ou de divergência da migração, e some da
        // tela é como um erro de contagem vira um erro de compra.
        ColunaIm360(
          titulo: 'Saldo',
          texto: (m) => '${m.saldo}',
          celula: (m) => _CelulaSaldo(material: m),
          numerica: true,
          flex: 1,
          larguraMin: 110,
        ),
        ColunaIm360(
          titulo: 'Mínimo',
          texto: (m) => '${m.estoqueMinimo}',
          numerica: true,
          prioridade: 2,
          flex: 1,
          larguraMin: 90,
        ),
        ColunaIm360(
          // ⚠️ `dd/mm/aaaa` com `flex: 1` saía "28/05/…" na faixa tablet
          // (medido em 800 px): data com elipse não é data — 28/05 de que ano?
          // A coluna degrada ANTES de Mínimo (prioridade maior) e, enquanto
          // fica, tem largura para a data inteira (item D2).
          titulo: 'Último',
          texto: (m) => m.ultimoMovimentoEm == null
              ? '—'
              : formatarData(m.ultimoMovimentoEm!),
          numerica: true,
          prioridade: 3,
          flex: 2,
          larguraMin: 120,
        ),
        ColunaIm360(
          titulo: 'Situação',
          texto: (m) => m.ativo ? 'Ativo' : 'Inativo',
          prioridade: 3,
          flex: 1,
          larguraMin: 100,
        ),
      ],
      // Método e código: a planilha numera cada catálogo do zero, então
      // ordenar só por código intercala os três métodos.
      linhas: estoque.whenData(
        (lista) =>
            filtrarEstoque(
              lista,
              busca: filtro.busca,
              metodoId: filtro.metodoId,
              categoria: filtro.categoria,
              soAtivos: filtro.soAtivos,
              soAbaixoMinimo: filtro.soAbaixoMinimo,
            )..sort((a, b) {
              final porMetodo = (metodosPorId[a.metodoId]?.nome ?? '')
                  .compareTo(metodosPorId[b.metodoId]?.nome ?? '');
              return porMetodo != 0 ? porMetodo : a.codigo.compareTo(b.codigo);
            }),
      ),
      tomDaLinha: (m) => switch (situacaoEstoqueDe(m)) {
        SituacaoEstoque.negativo => TomLinha.erro,
        SituacaoEstoque.abaixoMinimo => TomLinha.atencao,
        SituacaoEstoque.normal => TomLinha.nenhum,
      },
      linhaSelecionada: (m) => m.materialId == _selecionado,
      cartao: (m) => CartaoIm360(
        titulo: m.nome,
        subtitulo: [
          m.codigo,
          metodosPorId[m.metodoId]?.nome ?? '—',
          m.categoria,
        ].join(' · '),
        apoio: rotuloSituacaoEstoque(m) ?? (m.ativo ? null : 'Inativo'),
        iconeApoio: switch (situacaoEstoqueDe(m)) {
          SituacaoEstoque.negativo => Icons.error_outline,
          SituacaoEstoque.abaixoMinimo => Icons.warning_amber_outlined,
          SituacaoEstoque.normal => null,
        },
        corApoio: switch (situacaoEstoqueDe(m)) {
          SituacaoEstoque.negativo => Theme.of(context).colorScheme.error,
          SituacaoEstoque.abaixoMinimo => Cores.atencao,
          SituacaoEstoque.normal => null,
        },
        destaque: 'saldo ${m.saldo} · mín. ${m.estoqueMinimo}',
      ),
      estadoVazio: haCadastro
          ? EstadoVazio(
              mensagem: vazioMateriaisFiltro,
              icone: Icons.filter_alt_off_outlined,
              rotuloAcao: 'Limpar filtros',
              aoAgir: ref.read(filtroMateriaisProvider.notifier).limpar,
            )
          : EstadoVazio(
              mensagem: vazioMateriais,
              rotuloAcao: permissoes.contains('materiais.criar')
                  ? '+ Novo material'
                  : null,
              aoAgir: () => _editar(context, null),
            ),
      aoTocarLinha: (m) => _selecionar(context, m),
      aoRepetir: ref.read(versaoEstoqueProvider.notifier).incrementar,
    );

    final selecionado = _selecionadoDe(estoque.value);
    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
    if (selecionado == null || mobile) return tabela;

    return Column(
      children: [
        Expanded(flex: 3, child: tabela),
        const Divider(height: 1),
        Expanded(
          flex: 2,
          child: PainelMovimentos(
            material: selecionado,
            aoEditar: () =>
                _editar(context, _cadastroDe(selecionado.materialId)),
            aoAjustar: () => _ajustar(context, selecionado),
            aoFechar: () => setState(() => _selecionado = null),
          ),
        ),
      ],
    );
  }

  /// A linha atual do material escolhido — relida da lista a cada build, para o
  /// cabeçalho do painel mostrar o saldo de depois do ajuste.
  MaterialEstoque? _selecionadoDe(List<MaterialEstoque>? lista) {
    final id = _selecionado;
    if (id == null || lista == null) return null;
    for (final m in lista) {
      if (m.materialId == id) return m;
    }
    return null;
  }
}

/// O painel do mobile: mesma coisa do desktop, em tela cheia.
///
/// ⚠️ **Editar e ajustar passam pelos MESMOS callbacks da aba** (item A6).
/// Antes ele chamava `mostrarFormulario` direto, sem passar por `_editar` /
/// `_ajustar` — que são quem incrementa `versaoEstoqueProvider` (o cadastro
/// muda `estoque_minimo` e `ativo`, colunas de `v_estoque_atual`), mostra a
/// confirmação e fecha o painel no `'excluido'`. No celular, salvar o mínimo
/// deixava lista e cabeçalho no valor antigo, e excluir deixava um diálogo de
/// tela cheia **vazio**.
class _PainelMobile extends ConsumerWidget {
  const _PainelMobile({
    required this.materialId,
    required this.aoEditar,
    required this.aoAjustar,
  });

  final String materialId;
  final void Function(MaterialDidatico? cadastro) aoEditar;
  final void Function(MaterialEstoque material) aoAjustar;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PainelMobileDe<MaterialEstoque>(
        itens: (ref) => ref.watch(estoqueProvider),
        id: materialId,
        idDe: (m) => m.materialId,
        construtor: (context, material) {
          MaterialDidatico? cadastro;
          for (final m in ref.watch(materiaisProvider).value ?? const []) {
            if (m.id == materialId) cadastro = m;
          }
          return PainelMovimentos(
            material: material,
            aoEditar: () => aoEditar(cadastro),
            aoAjustar: () => aoAjustar(material),
          );
        },
      );
}

/// A célula de saldo: número, ícone e — para leitor de tela — a palavra.
///
/// ⚠️ **Divergência do design-system §5.2, registrada no §11:** o documento põe
/// o ícone da linha em alerta na **primeira** célula. Aqui ele fica na do
/// Saldo, que é onde o wireframe §9 o desenha (`0 ⚠`, `-2 ✖`) e onde ele
/// significa alguma coisa — na primeira célula, ao lado do código, o mesmo ícone
/// não diria de que o alerta é. O fundo tonal da linha continua sendo o do §5.2.
class _CelulaSaldo extends StatelessWidget {
  const _CelulaSaldo({required this.material});

  final MaterialEstoque material;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final situacao = situacaoEstoqueDe(material);
    final (icone, cor) = switch (situacao) {
      SituacaoEstoque.negativo => (Icons.error_outline, cores.error),
      SituacaoEstoque.abaixoMinimo => (
        Icons.warning_amber_outlined,
        Cores.atencao,
      ),
      SituacaoEstoque.normal => (null, cores.onSurface),
    };
    final rotulo = rotuloSituacaoEstoque(material);

    return Semantics(
      label: rotulo == null
          ? 'Saldo ${material.saldo}'
          : 'Saldo ${material.saldo}, $rotulo',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${material.saldo}',
            style: Tipografia.numero(Tipografia.corpoTabela).copyWith(
              color: cor,
              fontWeight: situacao == SituacaoEstoque.normal
                  ? null
                  : FontWeight.w600,
            ),
          ),
          if (icone != null) ...[
            const SizedBox(width: Dim.e4),
            Icon(icone, size: 16, color: cor),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cursos
// ---------------------------------------------------------------------------

class AbaCursos extends ConsumerWidget {
  const AbaCursos({super.key});

  Future<void> _novo(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => const FormularioCurso(),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Curso salvo.');
    }
  }

  Future<void> _detalhe(BuildContext context, Curso curso) async {
    final resultado = await mostrarFormulario<String>(
      context,
      largura: larguraDetalhe,
      construtor: (_) => DetalheCurso(cursoId: curso.id!),
    );
    if (resultado == 'excluido' && context.mounted) {
      confirmarEfemero(context, 'Curso excluído.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final metodosPorId = {for (final m in metodos) m.id: m};
    final cursos = ref.watch(cursosProvider);
    final apostilas = ref.watch(apostilasPorCursoProvider).value ?? const {};
    final filtro = ref.watch(filtroCursosProvider);
    final permissoes = ref.watch(permissoesProvider);
    final haCadastro = cursos.value?.isNotEmpty ?? false;

    return TabelaIm360<Curso>(
      filtros: FiltrosCatalogo(
        provider: filtroCursosProvider,
        metodos: metodos,
        rotuloBusca: 'Nome do curso',
      ),
      filtrosAtivos: filtro.ativos,
      acoes: [
        BotaoAcao(
          rotulo: 'Novo curso',
          icone: Icons.add,
          exigePermissao: 'materiais.criar',
          aoTocar: () => _novo(context),
        ),
      ],
      colunas: [
        ColunaIm360(
          titulo: 'Curso',
          texto: (c) => c.nome,
          flex: 3,
          larguraMin: 200,
        ),
        ColunaIm360(
          titulo: 'Método',
          texto: (c) => metodosPorId[c.metodoId]?.nome ?? '—',
          prioridade: 2,
          larguraMin: 130,
        ),
        ColunaIm360(
          titulo: 'Apostilas',
          texto: (c) => '${apostilas[c.id] ?? 0}',
          numerica: true,
          prioridade: 2,
          flex: 1,
          larguraMin: 100,
        ),
        ColunaIm360(
          titulo: 'Situação',
          texto: (c) => c.ativo ? 'Ativo' : 'Inativo',
          prioridade: 3,
          flex: 1,
          larguraMin: 100,
        ),
      ],
      linhas: cursos.whenData((lista) => filtrarCursos(lista, filtro)),
      cartao: (c) => CartaoIm360(
        titulo: c.nome,
        subtitulo: metodosPorId[c.metodoId]?.nome ?? '—',
        apoio: c.ativo ? null : 'Inativo',
        destaque: '${apostilas[c.id] ?? 0} apost.',
      ),
      estadoVazio: haCadastro
          ? EstadoVazio(
              mensagem: vazioCursosFiltro,
              icone: Icons.filter_alt_off_outlined,
              rotuloAcao: 'Limpar filtros',
              aoAgir: ref.read(filtroCursosProvider.notifier).limpar,
            )
          : EstadoVazio(
              mensagem: vazioCursos,
              rotuloAcao: permissoes.contains('materiais.criar')
                  ? '+ Novo curso'
                  : null,
              aoAgir: () => _novo(context),
            ),
      aoTocarLinha: (c) => _detalhe(context, c),
      aoRepetir: ref.read(versaoCatalogoProvider.notifier).incrementar,
    );
  }
}

// ---------------------------------------------------------------------------
// Combos
// ---------------------------------------------------------------------------

class AbaCombos extends ConsumerWidget {
  const AbaCombos({super.key});

  Future<void> _novo(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => const FormularioCombo(),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Combo salvo.');
    }
  }

  Future<void> _detalhe(BuildContext context, Combo combo) async {
    final resultado = await mostrarFormulario<String>(
      context,
      largura: larguraDetalhe,
      construtor: (_) => DetalheCombo(comboId: combo.id!),
    );
    if (resultado == 'excluido' && context.mounted) {
      confirmarEfemero(context, 'Combo excluído.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final metodosPorId = {for (final m in metodos) m.id: m};
    final combos = ref.watch(combosProvider);
    final cursos = ref.watch(cursosPorComboProvider).value ?? const {};
    final filtro = ref.watch(filtroCombosProvider);
    final permissoes = ref.watch(permissoesProvider);
    final haCadastro = combos.value?.isNotEmpty ?? false;

    return TabelaIm360<Combo>(
      filtros: FiltrosCatalogo(
        provider: filtroCombosProvider,
        metodos: metodos,
        rotuloBusca: 'Nome do combo',
      ),
      filtrosAtivos: filtro.ativos,
      acoes: [
        BotaoAcao(
          rotulo: 'Novo combo',
          icone: Icons.add,
          exigePermissao: 'materiais.criar',
          aoTocar: () => _novo(context),
        ),
      ],
      colunas: [
        ColunaIm360(
          titulo: 'Combo',
          texto: (c) => c.nome,
          flex: 3,
          larguraMin: 200,
        ),
        ColunaIm360(
          titulo: 'Método',
          texto: (c) => metodosPorId[c.metodoId]?.nome ?? '—',
          prioridade: 2,
          larguraMin: 130,
        ),
        ColunaIm360(
          titulo: 'Cursos',
          texto: (c) => '${cursos[c.id] ?? 0}',
          numerica: true,
          prioridade: 2,
          flex: 1,
          larguraMin: 90,
        ),
        ColunaIm360(
          titulo: 'Situação',
          texto: (c) => c.ativo ? 'Ativo' : 'Inativo',
          prioridade: 3,
          flex: 1,
          larguraMin: 100,
        ),
      ],
      linhas: combos.whenData((lista) => filtrarCombos(lista, filtro)),
      cartao: (c) => CartaoIm360(
        titulo: c.nome,
        subtitulo: metodosPorId[c.metodoId]?.nome ?? '—',
        apoio: c.ativo ? null : 'Inativo',
        destaque: '${cursos[c.id] ?? 0} curso(s)',
      ),
      estadoVazio: haCadastro
          ? EstadoVazio(
              mensagem: vazioCombosFiltro,
              icone: Icons.filter_alt_off_outlined,
              rotuloAcao: 'Limpar filtros',
              aoAgir: ref.read(filtroCombosProvider.notifier).limpar,
            )
          : EstadoVazio(
              mensagem: vazioCombos,
              rotuloAcao: permissoes.contains('materiais.criar')
                  ? '+ Novo combo'
                  : null,
              aoAgir: () => _novo(context),
            ),
      aoTocarLinha: (c) => _detalhe(context, c),
      aoRepetir: ref.read(versaoCatalogoProvider.notifier).incrementar,
    );
  }
}
