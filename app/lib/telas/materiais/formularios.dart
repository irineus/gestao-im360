import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/tipografia.dart';
import '../../widgets/botoes.dart';
import '../../widgets/formulario.dart';

/// Os formulários do catálogo (card 4.4). Todos devolvem `'salvo'` ou
/// `'excluido'` ao fechar, para a aba mostrar a confirmação efêmera certa
/// (design-system §5.8).
///
/// Nenhum deles verifica regra: submete e traduz o erro pelo código
/// (card 2.6 decisão 2). O que se valida aqui é formato — obrigatório, número.

/// O método **não muda depois de criado**, em material, curso e combo: a
/// composição (curso → material, combo → curso) é montada dentro de um método,
/// e trocá-lo num cadastro já composto deixaria a sequência de outro método
/// sem que o banco recusasse (o schema do card 4.1 não amarra isso — ver a
/// pendência registrada no card). Quem errou o método cria outro cadastro.
const _apoioMetodoFixo = 'O método não muda depois de criado.';

List<DropdownMenuItem<String>> _itensMetodo(
  List<Metodo> metodos,
  String? selecionado,
) => [
  for (final metodo in metodos)
    if (metodo.ativo || metodo.id == selecionado)
      DropdownMenuItem(value: metodo.id, child: Text(metodo.nome)),
];

String? _validarMetodo(String? valor) =>
    valor == null ? 'Escolha o método.' : null;

void _recarregar(WidgetRef ref) =>
    ref.read(versaoCatalogoProvider.notifier).incrementar();

// ---------------------------------------------------------------------------
// Material
// ---------------------------------------------------------------------------

class FormularioMaterial extends ConsumerStatefulWidget {
  const FormularioMaterial({super.key, this.material});

  /// Nulo = novo material.
  final MaterialDidatico? material;

  @override
  ConsumerState<FormularioMaterial> createState() => _FormularioMaterialState();
}

class _FormularioMaterialState extends ConsumerState<FormularioMaterial> {
  final _chave = GlobalKey<FormState>();
  late final _codigo = TextEditingController(
    text: widget.material?.codigo ?? '',
  );
  late final _nome = TextEditingController(text: widget.material?.nome ?? '');
  late final _categoria = TextEditingController(
    text: widget.material?.categoria ?? '',
  );
  final _categoriaFoco = FocusNode();
  late final _minimo = TextEditingController(
    text: '${widget.material?.estoqueMinimo ?? 0}',
  );
  late String? _metodoId = widget.material?.metodoId;
  late bool _ativo = widget.material?.ativo ?? true;

  @override
  void dispose() {
    _codigo.dispose();
    _nome.dispose();
    _categoria.dispose();
    _categoriaFoco.dispose();
    _minimo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final categorias = categoriasDe(
      ref.watch(materiaisProvider).value ?? const [],
    );
    final permissoes = ref.watch(permissoesProvider);
    final material = widget.material;
    final editando = material != null;
    final somenteLeitura = editando
        ? !permissoes.contains('materiais.editar')
        : !permissoes.contains('materiais.criar');

    return FormularioIm360(
      titulo: editando ? 'Material' : 'Novo material',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      campos: [
        DropdownButtonFormField<String>(
          initialValue: _metodoId,
          decoration: InputDecoration(
            labelText: 'Método *',
            helperText: editando ? _apoioMetodoFixo : null,
            helperMaxLines: 3,
          ),
          items: _itensMetodo(metodos, _metodoId),
          onChanged: somenteLeitura || editando
              ? null
              : (valor) => setState(() => _metodoId = valor),
          validator: _validarMetodo,
        ),
        TextFormField(
          controller: _codigo,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Código *',
            helperText:
                'Único dentro do método — o mesmo código pode existir em '
                'outro método.',
            helperMaxLines: 3,
          ),
          validator: validarObrigatorio,
        ),
        TextFormField(
          controller: _nome,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Nome *'),
          validator: validarObrigatorio,
        ),
        // Categoria é texto livre (sem lista fechada no schema); as já usadas
        // aparecem como sugestão para a grafia não divergir.
        RawAutocomplete<String>(
          textEditingController: _categoria,
          focusNode: _categoriaFoco,
          optionsBuilder: (valor) {
            final termo = valor.text.trim().toLowerCase();
            return [
              for (final categoria in categorias)
                if (categoria.toLowerCase().contains(termo) &&
                    categoria != valor.text)
                  categoria,
            ];
          },
          onSelected: (valor) => _categoria.text = valor,
          fieldViewBuilder: (context, controlador, foco, aoSubmeter) =>
              TextFormField(
                controller: controlador,
                focusNode: foco,
                readOnly: somenteLeitura,
                style: Tipografia.corpo,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Categoria *',
                  helperText:
                      'Ex.: Informática, Kids, Inglês, Modular. As já usadas '
                      'aparecem como sugestão.',
                  helperMaxLines: 3,
                ),
                validator: validarObrigatorio,
                onFieldSubmitted: (_) => aoSubmeter(),
              ),
          optionsViewBuilder: (context, aoEscolher, opcoes) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 200,
                  maxWidth: 400,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final opcao in opcoes)
                      ListTile(
                        title: Text(opcao, style: Tipografia.corpoTabela),
                        onTap: () => aoEscolher(opcao),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        TextFormField(
          controller: _minimo,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.number,
          inputFormatters: [somenteDigitos],
          decoration: const InputDecoration(
            labelText: 'Estoque mínimo *',
            helperText: 'Piso que entra no pedido sugerido.',
            helperMaxLines: 3,
          ),
          validator: validarInteiroNaoNegativo,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ativo', style: Tipografia.corpo),
          subtitle: const Text(
            'Inativo sai das listas e do pedido sugerido; o histórico fica.',
            style: Tipografia.apoio,
          ),
          value: _ativo,
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _ativo = valor),
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(catalogoRepositorioProvider)
            .salvarMaterial(
              MaterialDidatico(
                id: material?.id,
                metodoId: _metodoId!,
                codigo: _codigo.text.trim(),
                nome: _nome.text.trim(),
                categoria: _categoria.text.trim(),
                estoqueMinimo: int.parse(_minimo.text.trim()),
                ativo: _ativo,
              ),
            );
        _recarregar(ref);
        return 'salvo';
      },
      acoes: [
        if (editando)
          AcaoFormulario(
            rotulo: 'Excluir',
            nivel: NivelBotao.destrutivo,
            exigePermissao: 'materiais.excluir',
            confirmacao: ConfirmacaoAcao(
              titulo: 'Excluir material?',
              mensagem:
                  '"${material.nome}" será excluído. Se estiver em uso — em '
                  'curso, módulo, trilha ou estoque —, a exclusão é recusada; '
                  'nesse caso, marque-o como inativo.',
              rotulo: 'Excluir',
            ),
            executar: () async {
              await ref
                  .read(catalogoRepositorioProvider)
                  .excluirMaterial(material.id!);
              _recarregar(ref);
              return 'excluido';
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Curso e combo — a mesma forma (método, nome, ativo)
// ---------------------------------------------------------------------------

class FormularioCurso extends ConsumerStatefulWidget {
  const FormularioCurso({super.key, this.curso});

  final Curso? curso;

  @override
  ConsumerState<FormularioCurso> createState() => _FormularioCursoState();
}

class _FormularioCursoState extends ConsumerState<FormularioCurso> {
  final _chave = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.curso?.nome ?? '');
  late String? _metodoId = widget.curso?.metodoId;
  late bool _ativo = widget.curso?.ativo ?? true;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final permissoes = ref.watch(permissoesProvider);
    final curso = widget.curso;
    final editando = curso != null;
    final somenteLeitura = editando
        ? !permissoes.contains('materiais.editar')
        : !permissoes.contains('materiais.criar');

    return FormularioIm360(
      titulo: editando ? 'Curso' : 'Novo curso',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      campos: [
        DropdownButtonFormField<String>(
          initialValue: _metodoId,
          decoration: InputDecoration(
            labelText: 'Método *',
            helperText: editando ? _apoioMetodoFixo : null,
            helperMaxLines: 3,
          ),
          items: _itensMetodo(metodos, _metodoId),
          onChanged: somenteLeitura || editando
              ? null
              : (valor) => setState(() => _metodoId = valor),
          validator: _validarMetodo,
        ),
        TextFormField(
          controller: _nome,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          decoration: const InputDecoration(
            labelText: 'Nome *',
            helperText: 'Único dentro do método.',
            helperMaxLines: 3,
          ),
          validator: validarObrigatorio,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ativo', style: Tipografia.corpo),
          value: _ativo,
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _ativo = valor),
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(catalogoRepositorioProvider)
            .salvarCurso(
              Curso(
                id: curso?.id,
                metodoId: _metodoId!,
                nome: _nome.text.trim(),
                ativo: _ativo,
              ),
            );
        _recarregar(ref);
        return 'salvo';
      },
      acoes: [
        if (editando)
          AcaoFormulario(
            rotulo: 'Excluir',
            nivel: NivelBotao.destrutivo,
            exigePermissao: 'materiais.excluir',
            confirmacao: ConfirmacaoAcao(
              titulo: 'Excluir curso?',
              mensagem:
                  '"${curso.nome}" será excluído junto com a sua sequência de '
                  'apostilas e os seus módulos. Se estiver em algum combo, a '
                  'exclusão é recusada; nesse caso, marque-o como inativo.',
              rotulo: 'Excluir',
            ),
            executar: () async {
              await ref
                  .read(catalogoRepositorioProvider)
                  .excluirCurso(curso.id!);
              _recarregar(ref);
              return 'excluido';
            },
          ),
      ],
    );
  }
}

class FormularioCombo extends ConsumerStatefulWidget {
  const FormularioCombo({super.key, this.combo});

  final Combo? combo;

  @override
  ConsumerState<FormularioCombo> createState() => _FormularioComboState();
}

class _FormularioComboState extends ConsumerState<FormularioCombo> {
  final _chave = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.combo?.nome ?? '');
  late String? _metodoId = widget.combo?.metodoId;
  late bool _ativo = widget.combo?.ativo ?? true;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final permissoes = ref.watch(permissoesProvider);
    final combo = widget.combo;
    final editando = combo != null;
    final somenteLeitura = editando
        ? !permissoes.contains('materiais.editar')
        : !permissoes.contains('materiais.criar');

    return FormularioIm360(
      titulo: editando ? 'Combo' : 'Novo combo',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      campos: [
        DropdownButtonFormField<String>(
          initialValue: _metodoId,
          decoration: InputDecoration(
            labelText: 'Método *',
            helperText: editando ? _apoioMetodoFixo : null,
            helperMaxLines: 3,
          ),
          items: _itensMetodo(metodos, _metodoId),
          onChanged: somenteLeitura || editando
              ? null
              : (valor) => setState(() => _metodoId = valor),
          validator: _validarMetodo,
        ),
        TextFormField(
          controller: _nome,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          decoration: const InputDecoration(
            labelText: 'Nome *',
            helperText: 'Único na unidade.',
            helperMaxLines: 3,
          ),
          validator: validarObrigatorio,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ativo', style: Tipografia.corpo),
          value: _ativo,
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _ativo = valor),
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(catalogoRepositorioProvider)
            .salvarCombo(
              Combo(
                id: combo?.id,
                metodoId: _metodoId!,
                nome: _nome.text.trim(),
                ativo: _ativo,
              ),
            );
        _recarregar(ref);
        return 'salvo';
      },
      acoes: [
        if (editando)
          AcaoFormulario(
            rotulo: 'Excluir',
            nivel: NivelBotao.destrutivo,
            exigePermissao: 'materiais.excluir',
            confirmacao: ConfirmacaoAcao(
              titulo: 'Excluir combo?',
              mensagem:
                  '"${combo.nome}" será excluído junto com a sua lista de '
                  'cursos. Se algum aluno estiver matriculado nele, a exclusão '
                  'é recusada; nesse caso, marque-o como inativo.',
              rotulo: 'Excluir',
            ),
            executar: () async {
              await ref
                  .read(catalogoRepositorioProvider)
                  .excluirCombo(combo.id!);
              _recarregar(ref);
              return 'excluido';
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Módulo (só no curso Modular)
// ---------------------------------------------------------------------------

class FormularioModulo extends ConsumerStatefulWidget {
  const FormularioModulo({
    super.key,
    required this.cursoId,
    required this.metodoId,
    required this.proximaOrdem,
    this.modulo,
  });

  final String cursoId;
  final String metodoId;

  /// Posição de um módulo novo — o último + 1. Reordenar é na lista.
  final int proximaOrdem;
  final Modulo? modulo;

  @override
  ConsumerState<FormularioModulo> createState() => _FormularioModuloState();
}

class _FormularioModuloState extends ConsumerState<FormularioModulo> {
  final _chave = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.modulo?.nome ?? '');
  late String? _materialId = widget.modulo?.materialId;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final materiais = ref.watch(materiaisProvider).value ?? const [];
    final permissoes = ref.watch(permissoesProvider);
    final modulo = widget.modulo;
    final editando = modulo != null;
    final somenteLeitura = editando
        ? !permissoes.contains('materiais.editar')
        : !permissoes.contains('materiais.criar');

    // Só os livros do método do curso — e o já escolhido, mesmo inativo.
    final livros = [
      for (final m in materiais)
        if (m.metodoId == widget.metodoId && (m.ativo || m.id == _materialId))
          m,
    ];

    return FormularioIm360(
      titulo: editando ? 'Módulo' : 'Novo módulo',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      campos: [
        TextFormField(
          controller: _nome,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          decoration: const InputDecoration(labelText: 'Nome *'),
          validator: validarObrigatorio,
        ),
        DropdownButtonFormField<String>(
          initialValue: _materialId,
          decoration: const InputDecoration(
            labelText: 'Livro *',
            helperText:
                'Vários módulos podem usar o mesmo livro: no Modular o que '
                'avança é o módulo.',
            helperMaxLines: 3,
          ),
          items: [
            for (final m in livros)
              DropdownMenuItem(
                value: m.id,
                child: Text('${m.codigo} · ${m.nome}'),
              ),
          ],
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _materialId = valor),
          validator: (valor) => valor == null ? 'Escolha o livro.' : null,
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(catalogoRepositorioProvider)
            .salvarModulo(
              Modulo(
                id: modulo?.id,
                cursoId: widget.cursoId,
                materialId: _materialId!,
                nome: _nome.text.trim(),
                ordem: modulo?.ordem ?? widget.proximaOrdem,
              ),
            );
        _recarregar(ref);
        return 'salvo';
      },
      acoes: [
        if (editando)
          AcaoFormulario(
            rotulo: 'Excluir',
            nivel: NivelBotao.destrutivo,
            exigePermissao: 'materiais.excluir',
            confirmacao: ConfirmacaoAcao(
              titulo: 'Excluir módulo?',
              mensagem:
                  '"${modulo.nome}" será excluído. Se alguma turma Modular já '
                  'passou por ele, a exclusão é recusada.',
              rotulo: 'Excluir',
            ),
            executar: () async {
              await ref
                  .read(catalogoRepositorioProvider)
                  .excluirModulo(modulo.id!);
              _recarregar(ref);
              return 'excluido';
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Métodos — só o nome e o "ativo" (card 4.1: o código é chave natural)
// ---------------------------------------------------------------------------

class FormularioMetodos extends ConsumerStatefulWidget {
  const FormularioMetodos({super.key, required this.metodos});

  final List<Metodo> metodos;

  @override
  ConsumerState<FormularioMetodos> createState() => _FormularioMetodosState();
}

class _FormularioMetodosState extends ConsumerState<FormularioMetodos> {
  final _chave = GlobalKey<FormState>();
  late final _nomes = {
    for (final m in widget.metodos) m.id: TextEditingController(text: m.nome),
  };
  late final _ativos = {for (final m in widget.metodos) m.id: m.ativo};

  @override
  void dispose() {
    for (final controlador in _nomes.values) {
      controlador.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final somenteLeitura = !ref
        .watch(permissoesProvider)
        .contains('materiais.editar');

    return FormularioIm360(
      titulo: 'Métodos de ensino',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      legendaObrigatorio: false,
      aviso:
          'Os três métodos são fixos no produto; aqui muda só como aparecem. '
          'Método inativo some dos filtros e dos cadastros novos.',
      campos: [
        for (final metodo in widget.metodos)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _nomes[metodo.id],
                  readOnly: somenteLeitura,
                  style: Tipografia.corpo,
                  decoration: InputDecoration(
                    labelText: 'Nome (${metodo.codigo})',
                  ),
                  validator: validarObrigatorio,
                ),
              ),
              const SizedBox(width: 16),
              Switch(
                value: _ativos[metodo.id]!,
                onChanged: somenteLeitura
                    ? null
                    : (valor) => setState(() => _ativos[metodo.id] = valor),
              ),
            ],
          ),
      ],
      aoSalvar: () async {
        final repositorio = ref.read(catalogoRepositorioProvider);
        for (final metodo in widget.metodos) {
          final nome = _nomes[metodo.id]!.text.trim();
          final ativo = _ativos[metodo.id]!;
          if (nome == metodo.nome && ativo == metodo.ativo) continue;
          await repositorio.salvarMetodo(
            metodo.copiar(nome: nome, ativo: ativo),
          );
        }
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}
