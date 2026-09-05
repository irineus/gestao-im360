import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alunos/alunos.dart';
import '../../alunos/alunos_provider.dart';
import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../erros/erro_app.dart';
import '../../infraestrutura/infraestrutura_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/modular.dart';
import '../../turmas/modular_provider.dart';
import '../../widgets/botoes.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import 'formularios_alocacao.dart' show ListaCandidatos, escolhaAluno;

/// Os formulários da tela 5 — Turmas Modular (card 7.3, wireframe §8): cadastro
/// da turma, cronograma (montar, datar, remover), entrada e saída de aluno e o
/// avanço conjunto de módulo.
///
/// Nenhum deles verifica regra: submete e traduz o erro pelo `codigo`
/// (card 2.6 decisão 2). O que se valida aqui é **formato** — obrigatório,
/// inteiro positivo, data como `dd/mm/aaaa`. Quem recusa turma lotada é
/// `tg_turma_modular_aluno_admissao` com o advisory lock (`TURMA_LOTADA`); quem
/// recusa aluno de outro método é o mesmo trigger, em duas checagens
/// (`ALUNO_NAO_MODULAR` e `METODO_INCOMPATIVEL`); quem recusa apagar turma com
/// histórico é `tg_turma_modular_exclusao_valida` (`TURMA_COM_ALUNO`).

/// A capacidade da turma Modular é **coluna**, e é isto que o campo precisa
/// dizer: aqui não há PC nenhum de onde ela saia (card 7.1).
const ajudaCapacidadeModular =
    'Quantos alunos cabem nesta turma. Diferente do bloco de horário, aqui a '
    'capacidade é digitada: a sala modular não tem computadores de onde a conta '
    'saia. Para fechar a turma, desative-a em vez de pôr 0.';

// ---------------------------------------------------------------------------
// A turma
// ---------------------------------------------------------------------------

class FormularioTurmaModular extends ConsumerStatefulWidget {
  const FormularioTurmaModular({super.key, this.turma, this.inativa = false});

  /// Nulo = turma nova.
  final TurmaModular? turma;

  /// A turma veio da lista de **inativas** — a view de lotação filtra
  /// `t.ativo`, então de lá ela chega sem saber que está desativada, e o
  /// interruptor abriria ligado propondo reativá-la sem que ninguém pedisse.
  final bool inativa;

  @override
  ConsumerState<FormularioTurmaModular> createState() =>
      _FormularioTurmaModularState();
}

class _FormularioTurmaModularState
    extends ConsumerState<FormularioTurmaModular> {
  final _chave = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.turma?.nome ?? '');
  late final _capacidade = TextEditingController(
    text: widget.turma?.capacidade.toString() ?? '',
  );
  late final _dataInicio = TextEditingController(
    text: widget.turma == null ? formatarData(hojeSaoPaulo()) : '',
  );
  late String? _cursoId = widget.turma?.cursoId;
  late String? _salaId = widget.turma?.salaId;
  late bool _ativo = !widget.inativa;

  @override
  void dispose() {
    _nome.dispose();
    _capacidade.dispose();
    _dataInicio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final turma = widget.turma;
    final editando = turma != null;
    final somenteLeitura = editando
        ? !permissoes.contains('turmas.editar')
        : !permissoes.contains('turmas.criar');

    // ⚠️ As duas listas são ESPERADAS, não lidas com `?? const []`.
    // `DropdownButtonFormField` tem um `assert` que exige o valor inicial entre
    // os itens: com a lista ainda vazia, abrir uma turma que já tem curso
    // derrubaria o formulário — a armadilha que o card 5.6 mediu.
    final cursosAsync = ref.watch(cursosProvider);
    final salasAsync = ref.watch(salasProvider);
    final metodosAsync = ref.watch(metodosProvider);
    if (!cursosAsync.hasValue ||
        !salasAsync.hasValue ||
        !metodosAsync.hasValue) {
      return FormularioIm360(
        titulo: editando ? 'Turma Modular' : 'Nova turma Modular',
        chave: _chave,
        somenteLeitura: true,
        legendaObrigatorio: false,
        campos: const [EstadoCarregando(linhas: 5)],
      );
    }

    // Só cursos do método MODULAR: turma Modular de curso de Inglês é o caso
    // que `METODO_INCOMPATIVEL` recusa na admissão do PRIMEIRO aluno — meses
    // depois, e falando de aluno, não de turma. Filtrar aqui é "não oferecer o
    // que vai falhar" (card 4.4 (d)), e não uma segunda regra: nada no schema
    // impede a turma de nascer assim, e é por isso que o card 7.2 precisou de
    // DUAS checagens no trigger.
    // Comparado pelo **código** (`Metodo.modular`), nunca pelo nome: a escola
    // pode renomear o método na tela, e o código é o que o banco guarda.
    String? modularId;
    for (final m in metodosAsync.requireValue) {
      if (m.modular) modularId = m.id;
    }
    final cursos = [
      for (final c in cursosAsync.requireValue)
        if (c.metodoId == modularId && (c.ativo || c.id == _cursoId)) c,
    ];
    final salas = salasAsync.requireValue;

    // Segunda barreira contra a mesma asserção: id que o catálogo não resolve
    // degrada para "não escolhido" em vez de derrubar o formulário.
    final cursoSelecionado = cursos.any((c) => c.id == _cursoId)
        ? _cursoId
        : null;
    final salaSelecionada = salas.any((s) => s.id == _salaId) ? _salaId : null;

    return FormularioIm360(
      titulo: editando ? 'Turma Modular' : 'Nova turma Modular',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      aviso: (!_ativo && (turma?.alocados ?? 0) > 0)
          ? 'Esta turma tem ${turma!.alocados} aluno(s). Desativá-la a tira da '
                'lista, mas não realoca ninguém — e na próxima execução da '
                'rotina diária (03:10) eles viram pendência "aluno sem turma". '
                'Realoque antes.'
          : null,
      campos: [
        TextFormField(
          controller: _nome,
          readOnly: somenteLeitura,
          decoration: const InputDecoration(
            labelText: 'Nome da turma *',
            hintText: 'Eletricista 2026.1',
            helperText: 'Único na unidade — é como a escola chama a turma.',
            helperMaxLines: 3,
          ),
          validator: (valor) => (valor == null || valor.trim().isEmpty)
              ? 'Campo obrigatório.'
              : null,
        ),
        DropdownButtonFormField<String>(
          initialValue: cursoSelecionado,
          decoration: InputDecoration(
            labelText: 'Curso *',
            helperText: cursos.isEmpty
                ? semCursoModular
                : 'Só cursos do método Modular. Os módulos do curso são o '
                      'cronograma da turma.',
            helperMaxLines: 3,
          ),
          items: [
            for (final c in cursos)
              DropdownMenuItem(value: c.id, child: Text(c.nome)),
          ],
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _cursoId = valor),
          validator: (valor) => valor == null ? 'Escolha o curso.' : null,
        ),
        DropdownButtonFormField<String>(
          initialValue: salaSelecionada,
          decoration: const InputDecoration(labelText: 'Sala *'),
          items: [
            for (final s in salas)
              if (s.id != null && (s.ativo || s.id == _salaId))
                DropdownMenuItem(value: s.id, child: Text(s.nome)),
          ],
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _salaId = valor),
          validator: (valor) => valor == null ? 'Escolha a sala.' : null,
        ),
        TextFormField(
          controller: _capacidade,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.number,
          inputFormatters: [somenteDigitos],
          decoration: const InputDecoration(
            labelText: 'Capacidade *',
            helperText: ajudaCapacidadeModular,
            helperMaxLines: 4,
          ),
          validator: validarInteiroPositivo,
        ),
        if (!editando)
          TextFormField(
            controller: _dataInicio,
            readOnly: somenteLeitura,
            style: Tipografia.numero(Tipografia.corpo),
            decoration: const InputDecoration(
              labelText: 'Início da turma *',
              hintText: 'dd/mm/aaaa',
              helperText:
                  'Quando a turma começou — não é a data do módulo corrente, '
                  'que fica no cronograma.',
              helperMaxLines: 3,
            ),
            validator: validarData,
          ),
        if (editando)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ativa', style: Tipografia.corpo),
            subtitle: const Text(
              'Inativa sai da lista e não recebe aluno novo; os alunos, o '
              'cronograma e o histórico ficam.',
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
            .read(modularRepositorioProvider)
            .salvarTurma(
              id: turma?.id,
              nome: _nome.text.trim(),
              cursoId: _cursoId!,
              salaId: _salaId!,
              capacidade: int.parse(_capacidade.text.trim()),
              // Na edição a data de início não é oferecida (ela não muda depois
              // que a turma começou); o banco exige a coluna, então reenviamos a
              // de hoje só quando é turma nova.
              dataInicio: lerData(_dataInicio.text) ?? hojeSaoPaulo(),
              ativo: _ativo,
            );
        recarregarModular(ref);
        return 'salvo';
      },
      acoes: [
        if (editando)
          AcaoFormulario(
            rotulo: 'Excluir',
            nivel: NivelBotao.destrutivo,
            exigePermissao: 'turmas.excluir',
            confirmacao: const ConfirmacaoAcao(
              titulo: 'Excluir turma?',
              mensagem:
                  'Se algum aluno já esteve nesta turma — mesmo tendo saído —, '
                  'a exclusão é recusada; nesse caso, desative a turma.',
              rotulo: 'Excluir',
            ),
            executar: () async {
              await ref.read(modularRepositorioProvider).excluirTurma(turma.id);
              recarregarModular(ref);
              return 'excluido';
            },
          ),
      ],
    );
  }
}

const semCursoModular =
    'Nenhum curso do método Modular cadastrado. Cadastre o curso e os módulos '
    'dele em Materiais antes de criar a turma.';

// ---------------------------------------------------------------------------
// O cronograma
// ---------------------------------------------------------------------------

/// Monta (ou completa) o cronograma da turma com os módulos do curso que ainda
/// não estão lá — o que fecha a pendência `TURMA_MODULAR_SEM_CRONOGRAMA` e o
/// `TURMA_SEM_CRONOGRAMA` de `fn_turma_modular_avancar`.
///
/// Entra **sem datas**: quem as informa é quem conhece a turma, módulo a módulo,
/// e o avanço preenche o próximo com o passo médio. Inventar datas aqui daria à
/// projeção Modular um cronograma inteiro de palpite com cara de planejamento.
class FormularioMontarCronograma extends ConsumerStatefulWidget {
  const FormularioMontarCronograma({
    super.key,
    required this.turma,
    required this.faltantes,
  });

  final TurmaModular turma;

  /// Módulos do curso ainda fora do cronograma, na ordem do catálogo.
  final List<Modulo> faltantes;

  @override
  ConsumerState<FormularioMontarCronograma> createState() =>
      _FormularioMontarCronogramaState();
}

class _FormularioMontarCronogramaState
    extends ConsumerState<FormularioMontarCronograma> {
  final _chave = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final faltantes = widget.faltantes;

    return FormularioIm360(
      titulo: 'Montar cronograma',
      chave: _chave,
      rotuloSalvar: 'Acrescentar',
      somenteLeitura: faltantes.isEmpty,
      legendaObrigatorio: false,
      campos: [
        Text(
          faltantes.isEmpty
              ? cronogramaCompleto
              : 'Estes módulos de ${widget.turma.cursoNome} entram no '
                    'cronograma de ${widget.turma.nome}, na ordem do curso e '
                    'sem datas:',
          style: Tipografia.corpo,
        ),
        for (final m in faltantes)
          Padding(
            padding: const EdgeInsets.only(top: Dim.e4),
            child: Text(
              rotuloModulo(m.ordem, m.nome),
              style: Tipografia.numero(Tipografia.corpo),
            ),
          ),
        if (faltantes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Dim.e8),
            child: Text(
              'As datas de cada módulo se informam depois, um a um. O avanço de '
              'módulo preenche as do seguinte com o ritmo médio da turma.',
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            ),
          ),
      ],
      aoSalvar: () async {
        await ref
            .read(modularRepositorioProvider)
            .incluirModulos(
              turmaId: widget.turma.id,
              moduloIds: [
                for (final m in faltantes)
                  if (m.id != null) m.id!,
              ],
            );
        recarregarModular(ref);
        return 'salvo';
      },
    );
  }
}

const cronogramaCompleto =
    'Todos os módulos deste curso já estão no cronograma da turma.';

/// As datas de um módulo do cronograma (wireframe §8: "datas editáveis").
///
/// ⚠️ As duas datas são **opcionais**, e apagá-las é uma edição legítima: nulo
/// aqui é "ainda não sabemos", não "vencido" — é o que separa o módulo sem
/// previsão do módulo atrasado na faixa do cronograma.
class FormularioDatasModulo extends ConsumerStatefulWidget {
  const FormularioDatasModulo({
    super.key,
    required this.turma,
    required this.modulo,
  });

  final TurmaModular turma;
  final ModuloDaTurma modulo;

  @override
  ConsumerState<FormularioDatasModulo> createState() =>
      _FormularioDatasModuloState();
}

class _FormularioDatasModuloState extends ConsumerState<FormularioDatasModulo> {
  final _chave = GlobalKey<FormState>();
  late final _inicio = TextEditingController(
    text: widget.modulo.dataInicio == null
        ? ''
        : formatarData(widget.modulo.dataInicio!),
  );
  late final _prev = TextEditingController(
    text: widget.modulo.prevConclusao == null
        ? ''
        : formatarData(widget.modulo.prevConclusao!),
  );

  @override
  void dispose() {
    _inicio.dispose();
    _prev.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modulo = widget.modulo;
    final somenteLeitura = !ref
        .watch(permissoesProvider)
        .contains('turmas.editar');

    return FormularioIm360(
      titulo: rotuloModulo(modulo.moduloOrdem, modulo.moduloNome),
      chave: _chave,
      somenteLeitura: somenteLeitura,
      legendaObrigatorio: false,
      // Módulo já concluído: a `prev_conclusao` dele é a data REAL em que a
      // turma o fechou (fn_turma_modular_avancar §5), e é dela que a projeção
      // tira o início do módulo seguinte. Reescrevê-la desloca o cronograma
      // inteiro, e quem faz isso precisa saber antes de salvar.
      aviso: modulo.concluido ? avisoEditarConcluido : null,
      campos: [
        Text(
          '${widget.turma.nome} · ${widget.turma.cursoNome}',
          style: Tipografia.corpo,
        ),
        TextFormField(
          controller: _inicio,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          decoration: const InputDecoration(
            labelText: 'Início do módulo',
            hintText: 'dd/mm/aaaa',
            helperText: 'Vazio = ainda não começou.',
            helperMaxLines: 3,
          ),
          validator: (valor) => validarData(valor, obrigatorio: false),
        ),
        TextFormField(
          controller: _prev,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          decoration: InputDecoration(
            labelText: modulo.concluido
                ? 'Conclusão (data real)'
                : 'Previsão de conclusão',
            hintText: 'dd/mm/aaaa',
            helperText: modulo.concluido
                ? 'A data em que a turma fechou este módulo.'
                : 'Vazio = sem previsão. Vencida, o módulo aparece atrasado.',
            helperMaxLines: 3,
          ),
          validator: (valor) => validarData(valor, obrigatorio: false),
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(modularRepositorioProvider)
            .salvarDatasModulo(
              cronogramaId: modulo.id,
              dataInicio: lerData(_inicio.text),
              prevConclusao: lerData(_prev.text),
            );
        recarregarModular(ref);
        return 'salvo';
      },
      acoes: [
        AcaoFormulario(
          rotulo: 'Tirar do cronograma',
          nivel: NivelBotao.destrutivo,
          exigePermissao: 'turmas.excluir',
          confirmacao: const ConfirmacaoAcao(
            titulo: 'Tirar módulo do cronograma?',
            mensagem:
                'O módulo continua no curso; sai só do cronograma desta turma. '
                'A previsão de apostilas dele deixa de existir para os alunos '
                'daqui.',
            rotulo: 'Tirar do cronograma',
          ),
          executar: () async {
            await ref.read(modularRepositorioProvider).excluirModulo(modulo.id);
            recarregarModular(ref);
            return 'excluido';
          },
        ),
      ],
    );
  }
}

const avisoEditarConcluido =
    'Este módulo já foi concluído, e a data de conclusão é de onde a previsão '
    'do módulo seguinte é calculada. Mudá-la desloca o resto do cronograma.';

// ---------------------------------------------------------------------------
// Entrada e saída de aluno
// ---------------------------------------------------------------------------

/// Busca de aluno e `fn_turma_modular_admitir` (wireframe §8: "[+ Adicionar]").
///
/// **Os candidatos são filtrados; a regra continua no banco.** A lista oferece
/// só quem está ATIVO/ACELERAR, é do método do curso da turma e ainda não está
/// nela — o mesmo desenho do card 5.7, e não uma pré-validação: se o status
/// mudar entre abrir o formulário e clicar, quem recusa é o trigger, e
/// `ALUNO_INATIVO` vira banner.
class FormularioAdicionarNaTurmaModular extends ConsumerStatefulWidget {
  const FormularioAdicionarNaTurmaModular({super.key, required this.turma});

  final TurmaModular turma;

  @override
  ConsumerState<FormularioAdicionarNaTurmaModular> createState() =>
      _FormularioAdicionarNaTurmaModularState();
}

class _FormularioAdicionarNaTurmaModularState
    extends ConsumerState<FormularioAdicionarNaTurmaModular> {
  final _chave = GlobalKey<FormState>();
  final _busca = TextEditingController();
  String? _alunoId;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final turma = widget.turma;
    final alunosAsync = ref.watch(alunosProvider);
    final cursosAsync = ref.watch(cursosProvider);
    final naTurmaAsync = ref.watch(alunosModularProvider);

    // Esperar as listas em vez de ler com `?? const []`: aqui o preço de não
    // esperar é uma busca que não acha ninguém e faz a pessoa concluir que o
    // aluno não existe (lição do card 5.7).
    if (!alunosAsync.hasValue ||
        !cursosAsync.hasValue ||
        !naTurmaAsync.hasValue) {
      return FormularioIm360(
        titulo: 'Adicionar aluno',
        chave: _chave,
        somenteLeitura: true,
        legendaObrigatorio: false,
        campos: const [EstadoCarregando(linhas: 4)],
      );
    }

    // O método do CURSO da turma, que é o que o trigger compara com o do aluno
    // (`METODO_INCOMPATIVEL`). Nulo quando o curso não é legível — aí não se
    // filtra por método, e quem recusa é o banco.
    String? metodoDoCurso;
    for (final c in cursosAsync.requireValue) {
      if (c.id == turma.cursoId) metodoDoCurso = c.metodoId;
    }

    final naTurma = {
      for (final a in naTurmaAsync.requireValue)
        if (a.turmaId == turma.id && a.ativo) a.alunoId,
    };
    final candidatos = [
      for (final a in alunosAsync.requireValue)
        if (a.emAula &&
            (metodoDoCurso == null || a.metodoId == metodoDoCurso) &&
            !naTurma.contains(a.id))
          a,
    ];
    final visiveis = filtrarAlunos(
      candidatos,
      FiltroAlunos(busca: _busca.text, ocultarEncerrados: false),
    );

    return FormularioIm360(
      titulo: 'Adicionar aluno',
      chave: _chave,
      rotuloSalvar: 'Adicionar',
      // ⚠️ Informativo, e sai da LOTAÇÃO que já veio da view — não de uma conta
      // feita aqui. Quem decide se cabe é o banco, na transação, com o advisory
      // lock (card 7.2): a vaga pode ter sido liberada entre abrir o formulário
      // e clicar, e a tela diz o que SABE, não o que a regra vai decidir.
      aviso: turma.vagasLivres <= 0
          ? 'A turma está com ${turma.lotacaoTexto} — sem vaga livre. O sistema '
                'confere ao salvar; remova alguém antes, ou aumente a '
                'capacidade da turma.'
          : null,
      campos: [
        Text(
          '${turma.nome} · ${turma.cursoNome} · ${turma.lotacaoTexto}',
          style: Tipografia.corpo,
        ),
        TextFormField(
          controller: _busca,
          decoration: const InputDecoration(
            labelText: 'Buscar aluno',
            hintText: 'nome ou código SGF',
            helperText:
                'Só alunos ATIVO/ACELERAR do método do curso que ainda não '
                'estão nesta turma.',
            helperMaxLines: 3,
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        ListaCandidatos(
          candidatos: visiveis,
          totalCandidatos: candidatos.length,
          selecionado: _alunoId,
          aoSelecionar: (id) => setState(() => _alunoId = id),
        ),
        Text(
          entraNoModuloCorrente,
          style: Tipografia.apoio.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      aoSalvar: () async {
        final aluno = _alunoId;
        if (aluno == null) {
          throw const ErroApp(mensagem: escolhaAluno, traduzido: true);
        }
        await ref
            .read(modularRepositorioProvider)
            .admitir(turmaId: turma.id, alunoId: aluno);
        recarregarModular(ref);
        return 'salvo';
      },
    );
  }
}

/// A consequência que não se adivinha: quem entra hoje entra no módulo em que a
/// turma está, e não no primeiro (card 2.2 §9 — a turma avança em conjunto).
const entraNoModuloCorrente =
    'O aluno entra no módulo em que a turma está agora, não no primeiro: a '
    'turma Modular avança em conjunto.';

/// Tira o aluno da turma (`fn_turma_modular_remover`). Saída é `ativo = false`
/// com o motivo gravado — a tabela não tem `delete` para ninguém (card 2.4 §4).
class FormularioRemoverDaTurmaModular extends ConsumerStatefulWidget {
  const FormularioRemoverDaTurmaModular({
    super.key,
    required this.turma,
    required this.aluno,
  });

  final TurmaModular turma;
  final AlunoDaTurmaModular aluno;

  @override
  ConsumerState<FormularioRemoverDaTurmaModular> createState() =>
      _FormularioRemoverDaTurmaModularState();
}

class _FormularioRemoverDaTurmaModularState
    extends ConsumerState<FormularioRemoverDaTurmaModular> {
  final _chave = GlobalKey<FormState>();
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aluno = widget.aluno;
    return FormularioIm360(
      titulo: 'Remover da turma',
      chave: _chave,
      rotuloSalvar: 'Remover',
      nivelSalvar: NivelBotao.destrutivo,
      // A turma Modular é a única do aluno MODULAR — ele não é alocado em bloco
      // de horário (card 7.2). Sair dela é ficar sem turma nenhuma, e a rotina
      // diária abre a pendência no dia seguinte.
      aviso: aluno.alunoStatus == 'ATIVO' || aluno.alunoStatus == 'ACELERAR'
          ? '${aluno.alunoNome} ficará sem turma. Na próxima execução da rotina '
                'diária (03:10) isso vira uma pendência "aluno sem turma" na '
                'central.'
          : null,
      campos: [
        Text(
          '${aluno.alunoNome} sai de ${widget.turma.nome}.',
          style: Tipografia.corpo,
        ),
        TextFormField(
          controller: _motivo,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Motivo da saída',
            helperText:
                'Fica registrado na alocação encerrada — é o que explica a '
                'saída para quem olhar a turma depois.',
            helperMaxLines: 3,
          ),
        ),
      ],
      aoSalvar: () async {
        final texto = _motivo.text.trim();
        await ref
            .read(modularRepositorioProvider)
            .remover(
              turmaId: widget.turma.id,
              alunoId: aluno.alunoId,
              motivo: texto.isEmpty ? null : texto,
            );
        recarregarModular(ref);
        return 'removido';
      },
    );
  }
}

// ---------------------------------------------------------------------------
// O avanço conjunto de módulo
// ---------------------------------------------------------------------------

/// `[Avançar módulo →]` (wireframe §8): chama `fn_turma_modular_avancar`, que
/// fecha o módulo corrente com a data informada e abre o seguinte.
///
/// Exige `turmas.editar` e não `turmas.alocar`: o catálogo do card 2.4 §3.4
/// descreve `turmas.editar` como "cronograma e avanço de módulo", com todas as
/// letras. Quem cobra é a própria função.
class FormularioAvancarModulo extends ConsumerStatefulWidget {
  const FormularioAvancarModulo({
    super.key,
    required this.turma,
    required this.cronograma,
  });

  final TurmaModular turma;

  /// O cronograma da turma, na ordem do catálogo — é dele que saem o módulo que
  /// fecha e o que abre, para o diálogo dizer os dois antes do clique.
  final List<ModuloDaTurma> cronograma;

  @override
  ConsumerState<FormularioAvancarModulo> createState() =>
      _FormularioAvancarModuloState();
}

class _FormularioAvancarModuloState
    extends ConsumerState<FormularioAvancarModulo> {
  final _chave = GlobalKey<FormState>();
  final _data = TextEditingController(text: formatarData(hojeSaoPaulo()));

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final naoConcluidos = [
      for (final m in widget.cronograma)
        if (!m.concluido) m,
    ];
    final corrente = naoConcluidos.isEmpty ? null : naoConcluidos.first;
    final proximo = naoConcluidos.length > 1 ? naoConcluidos[1] : null;
    // "Hoje" é o de São Paulo, que é o default de `p_data_conclusao` no banco
    // (`fn_hoje()`). Pelo relógio do aparelho o formulário abriria com um dia
    // de diferença do que a função usaria.
    final data = lerData(_data.text) ?? hojeSaoPaulo();

    return FormularioIm360(
      titulo: 'Avançar módulo',
      chave: _chave,
      rotuloSalvar: 'Avançar',
      aviso: avisoAvancoConjunto,
      campos: [
        Text(
          '${widget.turma.nome} · ${widget.turma.cursoNome}',
          style: Tipografia.corpo,
        ),
        for (final linha in resumoAvanco(
          corrente: corrente,
          proximo: proximo,
          dataConclusao: data,
        ))
          Padding(
            padding: const EdgeInsets.only(top: Dim.e4),
            child: Text(linha, style: Tipografia.corpo),
          ),
        TextFormField(
          controller: _data,
          style: Tipografia.numero(Tipografia.corpo),
          decoration: const InputDecoration(
            labelText: 'Conclusão do módulo atual *',
            hintText: 'dd/mm/aaaa',
            helperText:
                'A data REAL em que a turma fechou o módulo. É dela que sai a '
                'previsão do seguinte.',
            helperMaxLines: 3,
          ),
          validator: validarData,
          onChanged: (_) => setState(() {}),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Dim.e8),
          child: Text(
            proximo != null && proximo.semDatas
                ? 'O módulo seguinte está sem datas: elas serão preenchidas com '
                      'o ritmo médio desta turma. Datas já informadas são '
                      'preservadas.'
                : 'Datas já informadas no módulo seguinte são preservadas.',
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          ),
        ),
      ],
      aoSalvar: () async {
        final proximoId = await ref
            .read(modularRepositorioProvider)
            .avancar(
              turmaId: widget.turma.id,
              dataConclusao: lerData(_data.text)!,
            );
        recarregarModular(ref);
        // Nulo = a turma terminou. O resultado muda a próxima ação de quem
        // avançou (não há mais o que avançar), então ele volta à tela, que
        // mostra o diálogo do design-system §5.8 em vez de um snackbar.
        return proximoId == null ? 'terminou' : 'avancou';
      },
    );
  }
}
