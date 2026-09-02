import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../erros/erro_app.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/botoes.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import 'editor_sequencia.dart';
import 'formularios.dart';

/// Largura do painel de detalhe — mais largo que um formulário, porque a
/// sequência tem código e nome lado a lado.
const larguraDetalhe = 760.0;

/// Confirmação efêmera (design-system §5.8): salvou, excluiu.
void confirmarEfemero(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));
}

/// Cabeçalho e rodapé comuns aos dois painéis de detalhe.
class _Painel extends StatelessWidget {
  const _Painel({
    required this.titulo,
    required this.subtitulo,
    required this.acoes,
    required this.filho,
  });

  final String titulo;
  final String subtitulo;
  final List<Widget> acoes;
  final Widget filho;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Dim.e24, Dim.e16, Dim.e12, Dim.e8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: Tipografia.subtitulo),
                    Text(
                      subtitulo,
                      style: Tipografia.apoio.copyWith(
                        color: cores.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              ...acoes,
              IconButton(
                tooltip: 'Fechar',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Dim.e24),
            child: filho,
          ),
        ),
      ],
    );
  }
}

Widget _titulo(BuildContext context, String texto, String apoio) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(texto, style: Tipografia.rotulo),
    Text(
      apoio,
      style: Tipografia.apoio.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: Dim.e8),
  ],
);

bool _mesmaLista(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Curso: sequência de apostilas + módulos (Modular)
// ---------------------------------------------------------------------------

class DetalheCurso extends ConsumerStatefulWidget {
  const DetalheCurso({super.key, required this.cursoId});

  final String cursoId;

  @override
  ConsumerState<DetalheCurso> createState() => _DetalheCursoState();
}

class _DetalheCursoState extends ConsumerState<DetalheCurso> {
  /// Ids de material na ordem em edição. Nulo até a sequência carregar (e de
  /// novo depois de salvar, para recomeçar do que o banco gravou).
  List<String>? _sequencia;
  bool _salvando = false;
  String? _erro;

  Future<void> _salvarSequencia() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await ref
          .read(catalogoRepositorioProvider)
          .salvarSequenciaDoCurso(widget.cursoId, _sequencia!);
      ref.read(versaoCatalogoProvider.notifier).incrementar();
      if (mounted) {
        setState(() => _sequencia = null);
        confirmarEfemero(context, 'Sequência salva.');
      }
    } catch (erro) {
      if (mounted) setState(() => _erro = traduzirErro(erro).mensagem);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _reordenarModulos(List<Modulo> modulos, int de, int para) async {
    // `onReorderItem` entrega o destino já ajustado pela remoção.
    final lista = List.of(modulos);
    lista.insert(para, lista.removeAt(de));
    setState(() => _erro = null);
    try {
      await ref.read(catalogoRepositorioProvider).reordenarModulos(
        widget.cursoId,
        [for (final m in lista) m.id!],
      );
      ref.read(versaoCatalogoProvider.notifier).incrementar();
    } catch (erro) {
      if (mounted) setState(() => _erro = traduzirErro(erro).mensagem);
    }
  }

  Future<void> _abrirModulo(
    BuildContext context, {
    required String metodoId,
    required int proximaOrdem,
    Modulo? modulo,
  }) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioModulo(
        cursoId: widget.cursoId,
        metodoId: metodoId,
        proximaOrdem: proximaOrdem,
        modulo: modulo,
      ),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(
        context,
        resultado == 'excluido' ? 'Módulo excluído.' : 'Módulo salvo.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cursos = ref.watch(cursosProvider).value ?? const <Curso>[];
    Curso? curso;
    for (final c in cursos) {
      if (c.id == widget.cursoId) curso = c;
    }
    if (curso == null) {
      // Excluído por outra pessoa enquanto o painel estava aberto.
      return const _Painel(
        titulo: 'Curso',
        subtitulo: '',
        acoes: [],
        filho: EstadoVazio(mensagem: 'Este curso não existe mais.'),
      );
    }
    final cursoAtual = curso;

    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    Metodo? metodo;
    for (final m in metodos) {
      if (m.id == cursoAtual.metodoId) metodo = m;
    }
    final materiais =
        ref.watch(materiaisProvider).value ?? const <MaterialDidatico>[];
    final materiaisPorId = {for (final m in materiais) m.id!: m};
    final sequencia = ref.watch(sequenciaDoCursoProvider(widget.cursoId));
    final modulos = ref.watch(modulosProvider(widget.cursoId));
    final permissoes = ref.watch(permissoesProvider);
    final podeEditar = permissoes.contains('materiais.editar');

    final gravada = [
      for (final linha in sequencia.value ?? const <LinhaOrdenada>[])
        linha.filhoId,
    ];
    // Só (re)inicia com dado ASSENTADO. Durante a recarga que segue um salvar
    // o `AsyncValue` ainda carrega o valor ANTERIOR (`isLoading` com
    // `hasValue`): iniciar dali fazia o painel voltar à ordem velha, com o
    // botão de salvar aceso, logo depois de o banco ter gravado a nova —
    // medido contra o stack local.
    if (_sequencia == null && sequencia.hasValue && !sequencia.isLoading) {
      _sequencia = gravada;
    }
    final emEdicao = _sequencia ?? const <String>[];
    final alterada = !_mesmaLista(emEdicao, gravada);

    return _Painel(
      titulo: cursoAtual.nome,
      subtitulo: [
        metodo?.nome ?? '—',
        if (!cursoAtual.ativo) 'inativo',
      ].join(' · '),
      acoes: [
        BotaoAcao(
          rotulo: 'Editar',
          nivel: NivelBotao.secundario,
          exigePermissao: 'materiais.editar',
          icone: Icons.edit_outlined,
          aoTocar: () async {
            final resultado = await mostrarFormulario<String>(
              context,
              construtor: (_) => FormularioCurso(curso: cursoAtual),
            );
            if (!context.mounted || resultado == null) return;
            if (resultado == 'excluido') {
              Navigator.of(context).pop('excluido');
            } else {
              confirmarEfemero(context, 'Curso salvo.');
            }
          },
        ),
      ],
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo(
            context,
            'Sequência de apostilas',
            'A ordem daqui é a ordem da trilha gerada na matrícula. Arraste '
                'para reordenar; nada é gravado até "Salvar sequência".',
          ),
          sequencia.when(
            loading: () => const EstadoCarregando(linhas: 3),
            error: (erro, _) => EstadoErro(
              mensagem: (erro is ErroApp ? erro : traduzirErro(erro)).mensagem,
              aoRepetir: () =>
                  ref.invalidate(sequenciaDoCursoProvider(widget.cursoId)),
            ),
            data: (_) => EditorSequencia<MaterialDidatico>(
              itens: [
                for (final id in emEdicao)
                  if (materiaisPorId[id] != null) materiaisPorId[id]!,
              ],
              disponiveis: [
                for (final m in materiais)
                  if (m.metodoId == cursoAtual.metodoId &&
                      (m.ativo || emEdicao.contains(m.id)))
                    m,
              ],
              rotulo: (m) => '${m.codigo} · ${m.nome}',
              chave: (m) => m.id!,
              podeEditar: podeEditar,
              rotuloAdicionar: 'Adicionar apostila',
              vazio: 'Nenhuma apostila na sequência.',
              aoMudar: (lista) =>
                  setState(() => _sequencia = [for (final m in lista) m.id!]),
            ),
          ),
          if (_erro != null) ...[
            const SizedBox(height: Dim.e8),
            AvisoTonal(mensagem: _erro!, erro: true),
          ],
          const SizedBox(height: Dim.e12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              BotaoAcao(
                rotulo: _salvando ? 'Salvando…' : 'Salvar sequência',
                exigePermissao: 'materiais.editar',
                desabilitado: alterada && !_salvando
                    ? null
                    : const DesabilitadoCom('Nenhuma alteração na sequência.'),
                aoTocar: _salvarSequencia,
              ),
            ],
          ),
          if (metodo?.modular ?? false) ...[
            const Divider(height: Dim.e32),
            _titulo(
              context,
              'Módulos',
              'A turma Modular avança pelos módulos em conjunto; vários '
                  'módulos podem usar o mesmo livro. Arraste para reordenar.',
            ),
            modulos.when(
              loading: () => const EstadoCarregando(linhas: 3),
              error: (erro, _) => EstadoErro(
                mensagem:
                    (erro is ErroApp ? erro : traduzirErro(erro)).mensagem,
                aoRepetir: () =>
                    ref.invalidate(modulosProvider(widget.cursoId)),
              ),
              data: (lista) => lista.isEmpty
                  ? Text(
                      'Nenhum módulo.',
                      style: Tipografia.corpoTabela.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  : ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      // Alça própria à esquerda — a padrão fica sobre o
                      // `trailing` (ver editor_sequencia.dart).
                      buildDefaultDragHandles: false,
                      onReorderItem: (de, para) =>
                          _reordenarModulos(lista, de, para),
                      children: [
                        for (var i = 0; i < lista.length; i++)
                          ListTile(
                            key: ValueKey(lista[i].id),
                            minTileHeight: Dim.alvoMobile,
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (podeEditar)
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: Icon(
                                      Icons.drag_indicator,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                const SizedBox(width: Dim.e8),
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: Text(
                                    '${i + 1}',
                                    style: Tipografia.numero(Tipografia.apoio)
                                        .copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              lista[i].nome,
                              style: Tipografia.corpoTabela,
                            ),
                            subtitle: Text(
                              materiaisPorId[lista[i].materialId]?.nome ?? '—',
                              style: Tipografia.apoio,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _abrirModulo(
                              context,
                              metodoId: cursoAtual.metodoId,
                              proximaOrdem: lista.length + 1,
                              modulo: lista[i],
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: Dim.e12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                BotaoAcao(
                  rotulo: 'Novo módulo',
                  icone: Icons.add,
                  nivel: NivelBotao.secundario,
                  exigePermissao: 'materiais.criar',
                  aoTocar: () => _abrirModulo(
                    context,
                    metodoId: cursoAtual.metodoId,
                    proximaOrdem: (modulos.value?.length ?? 0) + 1,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Combo: cursos na ordem
// ---------------------------------------------------------------------------

class DetalheCombo extends ConsumerStatefulWidget {
  const DetalheCombo({super.key, required this.comboId});

  final String comboId;

  @override
  ConsumerState<DetalheCombo> createState() => _DetalheComboState();
}

class _DetalheComboState extends ConsumerState<DetalheCombo> {
  List<String>? _cursos;
  bool _salvando = false;
  String? _erro;

  Future<void> _salvar() async {
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await ref
          .read(catalogoRepositorioProvider)
          .salvarCursosDoCombo(widget.comboId, _cursos!);
      ref.read(versaoCatalogoProvider.notifier).incrementar();
      if (mounted) {
        setState(() => _cursos = null);
        confirmarEfemero(context, 'Cursos do combo salvos.');
      }
    } catch (erro) {
      if (mounted) setState(() => _erro = traduzirErro(erro).mensagem);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final combos = ref.watch(combosProvider).value ?? const <Combo>[];
    Combo? combo;
    for (final c in combos) {
      if (c.id == widget.comboId) combo = c;
    }
    if (combo == null) {
      return const _Painel(
        titulo: 'Combo',
        subtitulo: '',
        acoes: [],
        filho: EstadoVazio(mensagem: 'Este combo não existe mais.'),
      );
    }
    final comboAtual = combo;

    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    Metodo? metodo;
    for (final m in metodos) {
      if (m.id == comboAtual.metodoId) metodo = m;
    }
    final cursos = ref.watch(cursosProvider).value ?? const <Curso>[];
    final cursosPorId = {for (final c in cursos) c.id!: c};
    final composicao = ref.watch(cursosDoComboProvider(widget.comboId));
    final podeEditar = ref
        .watch(permissoesProvider)
        .contains('materiais.editar');

    final gravada = [
      for (final linha in composicao.value ?? const <LinhaOrdenada>[])
        linha.filhoId,
    ];
    // Só com dado assentado — ver o comentário equivalente em DetalheCurso.
    if (_cursos == null && composicao.hasValue && !composicao.isLoading) {
      _cursos = gravada;
    }
    final emEdicao = _cursos ?? const <String>[];
    final alterada = !_mesmaLista(emEdicao, gravada);

    return _Painel(
      titulo: comboAtual.nome,
      subtitulo: [
        metodo?.nome ?? '—',
        if (!comboAtual.ativo) 'inativo',
      ].join(' · '),
      acoes: [
        BotaoAcao(
          rotulo: 'Editar',
          nivel: NivelBotao.secundario,
          exigePermissao: 'materiais.editar',
          icone: Icons.edit_outlined,
          aoTocar: () async {
            final resultado = await mostrarFormulario<String>(
              context,
              construtor: (_) => FormularioCombo(combo: comboAtual),
            );
            if (!context.mounted || resultado == null) return;
            if (resultado == 'excluido') {
              Navigator.of(context).pop('excluido');
            } else {
              confirmarEfemero(context, 'Combo salvo.');
            }
          },
        ),
      ],
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _titulo(
            context,
            'Cursos do combo',
            'Na matrícula, a trilha do aluno é a sequência de cada curso, na '
                'ordem daqui. Arraste para reordenar; nada é gravado até '
                '"Salvar cursos".',
          ),
          composicao.when(
            loading: () => const EstadoCarregando(linhas: 3),
            error: (erro, _) => EstadoErro(
              mensagem: (erro is ErroApp ? erro : traduzirErro(erro)).mensagem,
              aoRepetir: () =>
                  ref.invalidate(cursosDoComboProvider(widget.comboId)),
            ),
            data: (_) => EditorSequencia<Curso>(
              itens: [
                for (final id in emEdicao)
                  if (cursosPorId[id] != null) cursosPorId[id]!,
              ],
              disponiveis: [
                for (final c in cursos)
                  if (c.metodoId == comboAtual.metodoId &&
                      (c.ativo || emEdicao.contains(c.id)))
                    c,
              ],
              rotulo: (c) => c.nome,
              chave: (c) => c.id!,
              podeEditar: podeEditar,
              rotuloAdicionar: 'Adicionar curso',
              vazio: 'Nenhum curso no combo.',
              aoMudar: (lista) =>
                  setState(() => _cursos = [for (final c in lista) c.id!]),
            ),
          ),
          if (_erro != null) ...[
            const SizedBox(height: Dim.e8),
            AvisoTonal(mensagem: _erro!, erro: true),
          ],
          const SizedBox(height: Dim.e12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              BotaoAcao(
                rotulo: _salvando ? 'Salvando…' : 'Salvar cursos',
                exigePermissao: 'materiais.editar',
                desabilitado: alterada && !_salvando
                    ? null
                    : const DesabilitadoCom('Nenhuma alteração nos cursos.'),
                aoTocar: _salvar,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
