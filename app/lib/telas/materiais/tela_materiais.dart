import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import '../../widgets/tabela_im360.dart';
import 'detalhes.dart';
import 'filtros_catalogo.dart';
import 'formularios.dart';

/// Tela 6 — Materiais e estoque (docs/wireframes.md §9), parte **catálogo**
/// (card 4.4): materiais, cursos (com sequência e módulos) e combos. O estoque
/// — saldo, mínimo × saldo, movimentações — é o card 6.7, que troca a fonte da
/// aba de materiais para `v_estoque_atual` e acrescenta as colunas.
///
/// Cursos, módulos e combos moram aqui, junto do uso, e não na Administração
/// (card 2.6, apontamento 1).
class TelaMateriais extends StatelessWidget {
  const TelaMateriais({super.key});

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
              const AbaMateriais(),
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

class AbaMateriais extends ConsumerWidget {
  const AbaMateriais({super.key});

  Future<void> _abrir(BuildContext context, MaterialDidatico? material) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioMaterial(material: material),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(
        context,
        resultado == 'excluido' ? 'Material excluído.' : 'Material salvo.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final metodosPorId = {for (final m in metodos) m.id: m};
    final materiais = ref.watch(materiaisProvider);
    final filtro = ref.watch(filtroMateriaisProvider);
    final permissoes = ref.watch(permissoesProvider);
    final haCadastro = materiais.value?.isNotEmpty ?? false;

    return TabelaIm360<MaterialDidatico>(
      filtros: FiltrosCatalogo(
        provider: filtroMateriaisProvider,
        metodos: metodos,
        categorias: categoriasDe(materiais.value ?? const []),
        rotuloBusca: 'Código ou nome',
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
          aoTocar: () => _abrir(context, null),
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
        ColunaIm360(
          titulo: 'Mínimo',
          texto: (m) => '${m.estoqueMinimo}',
          numerica: true,
          prioridade: 2,
          flex: 1,
          larguraMin: 90,
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
      linhas: materiais.whenData(
        (lista) => filtrarMateriais(lista, filtro)
          ..sort((a, b) {
            final porMetodo = (metodosPorId[a.metodoId]?.nome ?? '').compareTo(
              metodosPorId[b.metodoId]?.nome ?? '',
            );
            return porMetodo != 0 ? porMetodo : a.codigo.compareTo(b.codigo);
          }),
      ),
      cartao: (m) => CartaoIm360(
        titulo: m.nome,
        subtitulo: [
          m.codigo,
          metodosPorId[m.metodoId]?.nome ?? '—',
          m.categoria,
        ].join(' · '),
        apoio: m.ativo ? null : 'Inativo',
        destaque: 'mín. ${m.estoqueMinimo}',
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
              aoAgir: () => _abrir(context, null),
            ),
      aoTocarLinha: (m) => _abrir(context, m),
      aoRepetir: ref.read(versaoCatalogoProvider.notifier).incrementar,
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
