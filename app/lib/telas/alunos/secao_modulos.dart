import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alunos/alunos.dart';
import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../erros/erro_app.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/modular.dart';
import '../../turmas/modular_provider.dart';
import '../../turmas/turmas_provider.dart';
import '../../turmas/turmas_widgets.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';

/// A **sequência de módulos** do aluno Modular, na aba Turmas da ficha (card
/// 9.2,905, `docs/turma-rodizio.md` §5.2).
///
/// Duas listas, e a ordem é a de quem lê: o que ele **já fez**, com a data e de
/// onde veio o registro, e o que **falta**, na ordem em que a turma dará e com
/// a data prevista. Em cima, a previsão de conclusão — **calculada**, sem
/// edição (decisão D2).
///
/// **Nada aqui é guardado como lista.** Os feitos são `aluno_modulo`; os que
/// faltam e as datas saem da agenda da turma (`v_aluno_modular_modulo`). É por
/// isso que os que faltam só aparecem para quem está numa turma: sem turma não
/// há agenda de onde tirar a ordem nem as datas, e inventá-las seria a segunda
/// conta que o projeto proíbe.
///
/// **A exceção à mão** (regra 6 do card 9.2,88) mora aqui: registrar um módulo
/// feito por fora do avanço da turma e remover um registro, os dois com
/// `alunos.editar_trilha` — a mesma permissão de quem mexe na trilha de livros.
class SecaoModulosDoAluno extends ConsumerWidget {
  const SecaoModulosDoAluno({super.key, required this.aluno});

  final Aluno aluno;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final alunoId = aluno.id!;
    final feitosAsync = ref.watch(modulosFeitosProvider(alunoId));
    final aFazerAsync = ref.watch(modulosAFazerProvider(alunoId));
    final progressoAsync = ref.watch(progressoModularProvider);

    // `hasError` antes de `hasValue` (design-system §5.6): durante a recarga o
    // `AsyncValue` ainda carrega o valor anterior, e mostrá-lo com a leitura
    // falhando seria afirmar o que ninguém sabe.
    final erro = feitosAsync.error ?? aFazerAsync.error;
    final pronto = feitosAsync.hasValue && aFazerAsync.hasValue;

    Widget corpo;
    if (erro != null) {
      final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
      corpo = EstadoErro(
        mensagem: traduzido.mensagem,
        codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
        aoRepetir: ref.read(versaoModularProvider.notifier).incrementar,
      );
    } else if (!pronto) {
      corpo = const EstadoCarregando(linhas: 3);
    } else {
      final feitos = feitosAsync.requireValue;
      final aFazer = aFazerAsync.requireValue;
      final previsao = previsaoCalculada(
        progressoAsync.value ?? const <ProgressoAlunoModular>[],
        alunoId,
      );
      corpo = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (previsao.emTurma) ...[
            Text(
              previsao.data == null
                  ? 'Conclusão prevista: $previsaoCalculadaSemData'
                  : 'Conclusão prevista: ${formatarData(previsao.data!)}',
              style: Tipografia.numero(Tipografia.corpo),
            ),
            Text(
              previsaoCalculadaAjuda,
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            ),
            const SizedBox(height: Dim.e12),
          ],
          if (feitos.isEmpty && aFazer.isEmpty)
            Text(
              vazioModulosDoAluno,
              style: Tipografia.corpo.copyWith(color: cores.onSurfaceVariant),
            ),
          if (feitos.isNotEmpty) ...[
            _Subtitulo('Feitos', feitos.length),
            for (final m in feitos)
              LinhaTurma(
                titulo: rotuloModulo(m.moduloOrdem, m.moduloNome),
                apoio: [
                  if (m.cursoNome.isNotEmpty) m.cursoNome,
                  apoioModuloFeito(m),
                ].join(' · '),
                acao: BotaoAcao(
                  rotulo: 'Remover',
                  nivel: NivelBotao.terciario,
                  exigePermissao: 'alunos.editar_trilha',
                  aoTocar: () => _abrir(
                    context,
                    construtor: (_) =>
                        FormularioRemoverModulo(aluno: aluno, modulo: m),
                    confirmacao: 'Módulo removido do registro do aluno.',
                  ),
                ),
              ),
          ],
          if (aFazer.isNotEmpty) ...[
            if (feitos.isNotEmpty) const SizedBox(height: Dim.e12),
            _Subtitulo('A fazer', aFazer.length),
            for (final m in aFazer)
              LinhaTurma(
                titulo: rotuloModulo(m.moduloOrdem, m.moduloNome),
                apoio: apoioModuloAFazer(m),
              ),
          ] else if (feitos.isNotEmpty && !previsao.emTurma) ...[
            const SizedBox(height: Dim.e8),
            Text(
              semTurmaSemAgenda,
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: Dim.e12),
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoAcao(
              rotulo: 'Registrar módulo feito',
              icone: Icons.add,
              nivel: NivelBotao.secundario,
              exigePermissao: 'alunos.editar_trilha',
              aoTocar: () => _abrir(
                context,
                construtor: (_) => FormularioRegistrarModulo(
                  aluno: aluno,
                  feitos: {for (final m in feitos) m.moduloId},
                  aFazer: aFazer,
                ),
                confirmacao: 'Módulo registrado.',
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloSecao(
          texto: 'Módulos',
          apoio:
              'O que o aluno já fez e o que falta, na ordem em que a turma '
              'dará. Os feitos entram sozinhos quando a turma avança.',
        ),
        corpo,
      ],
    );
  }
}

Future<void> _abrir(
  BuildContext context, {
  required WidgetBuilder construtor,
  required String confirmacao,
}) async {
  final resultado = await mostrarFormulario<String>(
    context,
    construtor: construtor,
  );
  if (resultado != null && context.mounted) {
    confirmarEfemero(context, confirmacao);
  }
}

/// `Feitos (3)` — a contagem é da lista que está na tela, e não um número à
/// parte.
class _Subtitulo extends StatelessWidget {
  const _Subtitulo(this.texto, this.quantos);

  final String texto;
  final int quantos;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Dim.e4),
    child: Text(
      '$texto ($quantos)',
      style: Tipografia.rotulo.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

const vazioModulosDoAluno =
    'Nenhum módulo registrado. Eles entram aqui quando a turma do aluno avança '
    'de módulo.';

/// Aluno com módulos feitos e fora de turma: a lista do que falta não existe,
/// e a tela diz por quê em vez de mostrar uma lista vazia.
const semTurmaSemAgenda =
    'O aluno não está em turma Modular: os módulos que faltam, e as datas '
    'previstas, aparecem quando ele entrar numa turma.';

/// Depois de uma escrita em `aluno_modulo`, o que pode ter mudado: a sequência
/// (Modular), e o vínculo com a turma — registrar o último módulo do curso
/// tira o aluno dela.
void _recarregar(WidgetRef ref) {
  recarregarModular(ref);
  ref.read(versaoTurmasProvider.notifier).incrementar();
}

// ---------------------------------------------------------------------------
// Registrar um módulo feito por fora da turma
// ---------------------------------------------------------------------------

/// `fn_aluno_modulo_registrar` (regra 6 do card 9.2,88).
///
/// O caso comum é o do aluno que está numa turma e fez um módulo por fora —
/// então o formulário abre nos módulos que **faltam a ele na turma**. O curso
/// é trocável para o outro caso: aluno sem turma, ou módulo de outro curso do
/// combo.
///
/// A tela não pré-valida "já fez": a lista só oferece o que não está nos
/// feitos, e se alguém registrar entre abrir e salvar, quem recusa é o banco
/// (`MODULO_JA_REGISTRADO`).
class FormularioRegistrarModulo extends ConsumerStatefulWidget {
  const FormularioRegistrarModulo({
    super.key,
    required this.aluno,
    required this.feitos,
    required this.aFazer,
  });

  final Aluno aluno;

  /// `modulo_id` dos que o aluno já fez — ficam fora da lista.
  final Set<String> feitos;

  /// Os que faltam na turma: é deles que sai o curso em que o formulário abre.
  final List<ModuloAFazer> aFazer;

  @override
  ConsumerState<FormularioRegistrarModulo> createState() =>
      _FormularioRegistrarModuloState();
}

class _FormularioRegistrarModuloState
    extends ConsumerState<FormularioRegistrarModulo> {
  final _chave = GlobalKey<FormState>();
  final _data = TextEditingController(text: formatarData(hojeSaoPaulo()));
  final _observacao = TextEditingController();
  String? _cursoId;
  String? _moduloId;

  @override
  void dispose() {
    _data.dispose();
    _observacao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final aluno = widget.aluno;
    final cursosAsync = ref.watch(cursosProvider);
    final turmasAsync = ref.watch(turmasModularProvider);

    if (!cursosAsync.hasValue) {
      return FormularioIm360(
        titulo: 'Registrar módulo feito',
        chave: _chave,
        somenteLeitura: true,
        legendaObrigatorio: false,
        campos: const [EstadoCarregando(linhas: 3)],
      );
    }

    // Os cursos do método do aluno. Curso inativo fica: módulo feito num curso
    // que saiu de catálogo continua sendo um fato a registrar.
    final cursos = [
      for (final c in cursosAsync.requireValue)
        if (c.metodoId == aluno.metodoId && c.id != null) c,
    ];
    // O curso em que o formulário abre: o da turma do aluno e, sem turma, o
    // único que houver. Com vários e sem turma, a pessoa escolhe.
    String? cursoDaTurma;
    if (widget.aFazer.isNotEmpty) {
      for (final t in turmasAsync.value ?? const <TurmaModular>[]) {
        if (t.id == widget.aFazer.first.turmaId) cursoDaTurma = t.cursoId;
      }
    }
    final cursoId =
        _cursoId ??
        cursoDaTurma ??
        (cursos.length == 1 ? cursos.first.id : null);

    final modulosAsync = cursoId == null
        ? null
        : ref.watch(modulosProvider(cursoId));
    final candidatos = [
      for (final m in modulosAsync?.value ?? const <Modulo>[])
        if (m.id != null && !widget.feitos.contains(m.id)) m,
    ];

    return FormularioIm360(
      titulo: 'Registrar módulo feito',
      chave: _chave,
      rotuloSalvar: 'Registrar',
      aviso: avisoRegistrarModulo,
      campos: [
        Text(aluno.nome, style: Tipografia.corpo),
        DropdownButtonFormField<String>(
          key: ValueKey('curso-$cursoId'),
          initialValue: cursoId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Curso *'),
          items: [
            for (final c in cursos)
              DropdownMenuItem(
                value: c.id,
                child: Text(c.nome, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (valor) => setState(() {
            _cursoId = valor;
            _moduloId = null;
          }),
          validator: (valor) => valor == null ? 'Escolha o curso.' : null,
        ),
        if (modulosAsync != null && modulosAsync.hasError)
          Text(
            'Não foi possível ler os módulos deste curso.',
            style: Tipografia.apoio.copyWith(color: cores.error),
          )
        else if (modulosAsync != null && !modulosAsync.hasValue)
          const EstadoCarregando(linhas: 1)
        else
          DropdownButtonFormField<String>(
            // A chave acompanha o curso: trocar o curso zera o módulo.
            key: ValueKey('modulo-$cursoId'),
            initialValue: _moduloId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Módulo *',
              helperText: cursoId != null && candidatos.isEmpty
                  ? 'O aluno já fez todos os módulos deste curso.'
                  : 'Só os módulos que o aluno ainda não fez.',
              helperMaxLines: 2,
            ),
            items: [
              for (final m in candidatos)
                DropdownMenuItem(
                  value: m.id,
                  child: Text(
                    rotuloModulo(m.ordem, m.nome),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (valor) => setState(() => _moduloId = valor),
            validator: (valor) => valor == null ? 'Escolha o módulo.' : null,
          ),
        TextFormField(
          controller: _data,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(
            labelText: 'Concluído em *',
            hintText: 'dd/mm/aaaa',
          ),
          validator: validarData,
        ),
        TextFormField(
          controller: _observacao,
          style: Tipografia.corpo,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Observação',
            helperText:
                'Opcional — onde o aluno fez o módulo (outra turma, reposição, '
                'outra escola).',
            helperMaxLines: 2,
          ),
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(modularRepositorioProvider)
            .registrarModulo(
              alunoId: aluno.id!,
              moduloId: _moduloId!,
              dataConclusao: lerData(_data.text)!,
              observacao: _observacao.text,
            );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}

/// A consequência que não se adivinha: registrar o ÚLTIMO módulo conclui o
/// curso, com tudo o que a conclusão faz (card 9.2,885).
const avisoRegistrarModulo =
    'Se este for o último módulo que falta ao aluno no curso, ele conclui o '
    'curso: sai da turma e, com todos os cursos do combo concluídos, entra na '
    'fila de certificados.';

// ---------------------------------------------------------------------------
// Remover um módulo do registro
// ---------------------------------------------------------------------------

/// `fn_aluno_modulo_remover`: o aluno precisa refazer o módulo. O motivo é
/// obrigatório e vai para o histórico (`aluno_modulo_hist`).
class FormularioRemoverModulo extends ConsumerStatefulWidget {
  const FormularioRemoverModulo({
    super.key,
    required this.aluno,
    required this.modulo,
  });

  final Aluno aluno;
  final ModuloFeito modulo;

  @override
  ConsumerState<FormularioRemoverModulo> createState() =>
      _FormularioRemoverModuloState();
}

class _FormularioRemoverModuloState
    extends ConsumerState<FormularioRemoverModulo> {
  final _chave = GlobalKey<FormState>();
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.modulo;
    return FormularioIm360(
      titulo: 'Remover módulo do registro',
      chave: _chave,
      rotuloSalvar: 'Remover',
      nivelSalvar: NivelBotao.destrutivo,
      aviso: avisoRemoverModulo,
      campos: [
        Text(
          '${widget.aluno.nome} — ${rotuloModulo(m.moduloOrdem, m.moduloNome)}, '
          '${apoioModuloFeito(m)}.',
          style: Tipografia.corpo,
        ),
        TextFormField(
          controller: _motivo,
          style: Tipografia.corpo,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Motivo *',
            helperText: 'Fica no histórico do registro.',
          ),
          validator: validarObrigatorio,
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(modularRepositorioProvider)
            .removerModulo(
              alunoId: widget.aluno.id!,
              moduloId: m.moduloId,
              motivo: _motivo.text,
            );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}

/// O que a remoção faz e — tão importante — o que ela **não** faz.
const avisoRemoverModulo =
    'O módulo volta a faltar ao aluno: ele o refaz quando a turma voltar a '
    'ele. Se o aluno já tinha concluído o curso, a conclusão é desfeita — mas '
    'ele não volta sozinho para a turma: adicione-o de novo na tela Turmas '
    'Modular.';

/// `3 de 6 módulos · falta Confeitaria e mais 2` — o resumo do progresso para
/// a linha da turma Modular, sem a parte da previsão (que tem linha própria
/// na seção de módulos).
String resumoProgressoNaFicha(ProgressoAlunoModular p) => [
  if (p.moduloEntradaNome != null) 'entrou em ${p.moduloEntradaNome}',
  p.feitosTexto,
  if (p.aguardandoEntrada) 'começa no próximo módulo',
].join(' · ');
