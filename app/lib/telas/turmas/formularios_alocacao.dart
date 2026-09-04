import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alunos/alunos.dart';
import '../../alunos/alunos_provider.dart';
import '../../erros/erro_app.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/turmas.dart';
import '../../turmas/turmas_provider.dart';
import '../../turmas/turmas_widgets.dart';
import '../../widgets/badge_status.dart';
import '../../widgets/botoes.dart';
import '../../widgets/escolha.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import 'formularios.dart';

/// Os formulários de **alocação** do card 5.7: adicionar aluno ao bloco,
/// remover/desmarcar e lançar reposição pontual.
///
/// Os três orquestram funções do card 5.3 e não reescrevem regra nenhuma
/// (card 2.6 decisão 2): a vaga é conferida por `tg_bloco_aluno_admissao` com o
/// advisory lock que só o banco tem como dar, `BLOCO_LOTADO` e
/// `METODO_INCOMPATIVEL` chegam traduzidos pelo código, e a permissão de lançar
/// reposição retroativa é cobrada por `tg_reposicao_admissao`.
///
/// O que existe aqui de decisão é o que **oferecer** e o que **avisar** —
/// consequência que não se adivinha vira aviso antes do clique, e nunca uma
/// segunda checagem em Dart.

/// Busca de aluno + tipo, e chama `fn_bloco_admitir` (wireframe §7.2).
///
/// **Os candidatos são filtrados; a regra continua no banco.** A lista oferece
/// só quem está ATIVO/ACELERAR, é do método do bloco e ainda não está nele — é
/// o mesmo desenho do card 4.4 (d), *não oferecer o que vai falhar*, e não uma
/// pré-validação: se o status mudar entre a abertura do formulário e o clique,
/// quem recusa é o trigger, e o `ALUNO_INATIVO` vira banner.
class FormularioAdicionarAluno extends ConsumerStatefulWidget {
  const FormularioAdicionarAluno({super.key, required this.celula});

  final CelulaGrade celula;

  @override
  ConsumerState<FormularioAdicionarAluno> createState() =>
      _FormularioAdicionarAlunoState();
}

class _FormularioAdicionarAlunoState
    extends ConsumerState<FormularioAdicionarAluno> {
  final _chave = GlobalKey<FormState>();
  final _busca = TextEditingController();
  final _dataPrevista = TextEditingController();
  String _tipo = 'REM';
  String? _alunoId;

  @override
  void dispose() {
    _busca.dispose();
    _dataPrevista.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final celula = widget.celula;
    final alunosAsync = ref.watch(alunosProvider);
    final chave = BlocoNaData(celula.blocoId, celula.dataReferencia);
    final noBloco = ref.watch(alunosDoBlocoProvider(chave));

    // Mesma barreira do formulário de bloco (card 5.6): esperar as listas em vez
    // de ler com `?? const []`. Aqui o preço de não esperar não é um `assert`, é
    // uma busca que não acha ninguém e faz a pessoa concluir que o aluno não
    // existe.
    if (!alunosAsync.hasValue || !noBloco.hasValue) {
      return FormularioIm360(
        titulo: 'Adicionar aluno',
        chave: _chave,
        somenteLeitura: true,
        legendaObrigatorio: false,
        campos: const [EstadoCarregando(linhas: 4)],
      );
    }

    final jaNoBloco = {
      for (final a in noBloco.requireValue)
        if (!a.ehReposicao) a.alunoId,
    };
    final candidatos = [
      for (final a in alunosAsync.requireValue)
        if (a.emAula &&
            a.metodoId == celula.metodoId &&
            !jaNoBloco.contains(a.id))
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
      // ⚠️ O aviso é INFORMATIVO e sai da lista que já está carregada, não de
      // `celula.vagasLivres`: a célula é a grade de quando o painel abriu, e
      // depois de adicionar alguém ela erraria por um. Quem decide se cabe é o
      // banco, na transação, com o advisory lock (card 5.3) — a tela diz o que
      // sabe para a escolha ser informada, não para poupar a chamada. E diz o
      // que SABE, não o que a regra vai decidir: a vaga pode ter sido liberada
      // entre abrir o formulário e clicar (§2.2).
      aviso: noBloco.requireValue.length >= celula.capacidade
          ? 'Não há vaga livre em '
                '${formatarData(celula.dataReferencia)} — o sistema vai '
                'conferir ao salvar. Remova alguém antes, ou escolha outro '
                'bloco.'
          : null,
      campos: [
        TextFormField(
          controller: _busca,
          decoration: InputDecoration(
            labelText: 'Buscar aluno',
            hintText: 'nome ou código SGF',
            helperText:
                'Só alunos ATIVO/ACELERAR do método ${celula.metodoCodigo} '
                'que ainda não estão neste bloco.',
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        ListaCandidatos(
          candidatos: visiveis,
          totalCandidatos: candidatos.length,
          selecionado: _alunoId,
          aoSelecionar: (id) => setState(() => _alunoId = id),
        ),
        DropdownButtonFormField<String>(
          initialValue: _tipo,
          decoration: const InputDecoration(
            labelText: 'Tipo na turma *',
            helperText:
                'REP aqui é a reposição CONTÍNUA, que ocupa vaga toda semana. '
                'Para repor uma aula perdida, use "Lançar reposição".',
            helperMaxLines: 3,
          ),
          items: [
            for (final entrada in tiposNaTurma.entries)
              DropdownMenuItem(
                value: entrada.key,
                child: Text('${entrada.key} — ${entrada.value}'),
              ),
          ],
          onChanged: (valor) => setState(() => _tipo = valor!),
        ),
        if (_tipo == 'NOVO')
          TextFormField(
            controller: _dataPrevista,
            style: Tipografia.numero(Tipografia.corpo),
            decoration: const InputDecoration(
              labelText: 'Início previsto',
              hintText: 'dd/mm/aaaa',
              helperText:
                  'A vaga fica reservada desde esta data, senão ela é vendida '
                  'duas vezes.',
              helperMaxLines: 3,
            ),
            // Formato, e só. Que NOVO exige a data é regra do banco
            // (`DATA_PREVISTA_OBRIGATORIA`), e é ele quem a cobra.
            validator: (valor) => validarData(valor, obrigatorio: false),
          ),
      ],
      aoSalvar: () async {
        final aluno = _alunoId;
        if (aluno == null) {
          throw const ErroApp(mensagem: escolhaAluno, traduzido: true);
        }
        await ref
            .read(turmasRepositorioProvider)
            .admitir(
              blocoId: celula.blocoId,
              alunoId: aluno,
              tipo: _tipo,
              dataInicioPrevista: lerData(_dataPrevista.text),
            );
        recarregarTurmas(ref);
        return 'salvo';
      },
    );
  }
}

/// Falta de escolha na lista **não** é erro do banco: é o formulário dizendo o
/// que falta, como qualquer validação de formato (design-system §5.4).
const escolhaAluno = 'Escolha um aluno na lista acima.';

/// A lista de candidatos da busca.
///
/// Não é `DropdownButtonFormField`: com o filtro mudando a cada tecla, o valor
/// selecionado sairia dos itens e o `assert` do widget derrubaria a tela — a
/// mesma armadilha que o card 5.6 mediu no formulário de bloco. Aqui a seleção
/// sobrevive ao filtro porque não depende dele.
class ListaCandidatos extends StatelessWidget {
  const ListaCandidatos({
    super.key,
    required this.candidatos,
    required this.totalCandidatos,
    required this.selecionado,
    required this.aoSelecionar,
  });

  /// Quantos a lista mostra de uma vez. Mais do que isto vira rolagem dentro de
  /// rolagem; quem tem muitos resultados refina a busca.
  static const maximo = 8;

  final List<Aluno> candidatos;
  final int totalCandidatos;
  final String? selecionado;
  final void Function(String id) aoSelecionar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    if (totalCandidatos == 0) {
      return Text(
        semCandidatos,
        style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
      );
    }
    if (candidatos.isEmpty) {
      return Text(
        'Nenhum aluno com esse texto entre os $totalCandidatos elegíveis.',
        style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
      );
    }

    final mostrados = candidatos.take(maximo).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final aluno in mostrados)
          LinhaEscolha(
            rotulo: aluno.codigoSgf == null
                ? aluno.nome
                : '${aluno.nome} (${aluno.codigoSgf})',
            marcada: aluno.id == selecionado,
            aoTocar: () => aoSelecionar(aluno.id!),
            direita: aluno.status == 'ATIVO' ? null : BadgeStatus(aluno.status),
          ),
        if (candidatos.length > maximo)
          Padding(
            padding: const EdgeInsets.only(top: Dim.e4),
            child: Text(
              'mais ${candidatos.length - maximo} — refine a busca',
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

const semCandidatos =
    'Nenhum aluno elegível: os do método já estão neste bloco, ou não há aluno '
    'ATIVO/ACELERAR neste método.';

/// Remove a alocação (`fn_bloco_remover`) ou desmarca a reposição
/// (`fn_reposicao_cancelar`) — as duas metades do REP híbrido saem por funções
/// diferentes, e o formulário é um só porque para quem usa a ação é a mesma.
///
/// ⚠️ Os dois avisos existem porque a consequência não é adivinhável: remover a
/// última turma do aluno abre `ALUNO_SEM_TURMA` na execução seguinte da rotina
/// (03:10, card 5.5), e desmarcar a reposição **não repõe a aula** — o débito
/// continua pesando até alguém remarcar (card 2.5 §3.2).
class FormularioRemoverAluno extends ConsumerStatefulWidget {
  const FormularioRemoverAluno({
    super.key,
    required this.aluno,
    required this.celula,
  });

  final AlunoDoBloco aluno;
  final CelulaGrade celula;

  @override
  ConsumerState<FormularioRemoverAluno> createState() =>
      _FormularioRemoverAlunoState();
}

class _FormularioRemoverAlunoState
    extends ConsumerState<FormularioRemoverAluno> {
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
    final celula = widget.celula;
    final reposicao = aluno.ehReposicao;
    // ⚠️ Só afirma "ficará sem nenhuma turma" com a lista **carregada**: em
    // `loading` e em `error` o mapa vem vazio, e o aviso apareceria para todo
    // mundo — inclusive para quem tem cinco turmas. Aviso falso ensina a não ler
    // os avisos (achado da revisão da fase 05).
    final todasAsTurmas = ref.watch(turmasProvider);
    final turmas = ref.watch(turmasPorAlunoProvider)[aluno.alunoId] ?? const [];
    final ultimaTurma =
        !reposicao &&
        todasAsTurmas.hasValue &&
        turmas.where((t) => t.blocoAtivo).length <= 1;

    return FormularioIm360(
      titulo: reposicao ? 'Desmarcar reposição' : 'Remover da turma',
      chave: _chave,
      rotuloSalvar: reposicao ? 'Desmarcar' : 'Remover',
      // Remover encerra a alocação: primário vermelho (§5.7). Desmarcar a
      // reposição é do dia e se refaz lançando outra — não é da mesma família.
      nivelSalvar: reposicao ? NivelBotao.primario : NivelBotao.destrutivo,
      aviso: reposicao
          ? avisoDesmarcarReposicao
          : ultimaTurma
          ? '${aluno.alunoNome} ficará sem nenhuma turma. Na próxima execução '
                'da rotina diária (03:10) isso vira uma pendência '
                '"aluno sem turma" na central.'
          : null,
      campos: [
        Text(
          reposicao
              ? '${aluno.alunoNome} — ${aluno.rotuloReposicao}, em '
                    '${formatarData(celula.dataReferencia)}.'
              : '${aluno.alunoNome} sai de '
                    '${rotuloBloco(celula.diaSemana, celula.horaInicio)}'
                    ' · ${celula.salaNome}.',
          style: Tipografia.corpo,
        ),
        TextFormField(
          controller: _motivo,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: reposicao ? 'Observação' : 'Motivo da saída',
            helperText: reposicao
                ? 'Fica registrada na reposição.'
                : 'Fica registrado na alocação encerrada — é o que explica a '
                      'saída para quem olhar a turma depois.',
            helperMaxLines: 3,
          ),
        ),
      ],
      aoSalvar: () async {
        final repositorio = ref.read(turmasRepositorioProvider);
        final texto = _motivo.text.trim();
        if (reposicao) {
          // Vazio vira `null`, nunca `''`: `fn_reposicao_cancelar` faz
          // `coalesce(p_observacao, observacao)`, e `''` **apaga** a observação
          // que já estava lá.
          await repositorio.cancelarReposicao(
            aluno.registroId,
            texto.isEmpty ? null : texto,
          );
        } else {
          await repositorio.remover(
            blocoId: celula.blocoId,
            alunoId: aluno.alunoId,
            motivo: texto.isEmpty ? null : texto,
          );
        }
        recarregarTurmas(ref);
        return 'removido';
      },
    );
  }
}

const avisoDesmarcarReposicao =
    'Desmarcar não repõe a aula: ela continua em aberto e volta a pesar no '
    'prazo do aluno até ser remarcada.';

/// Lança uma reposição pontual neste bloco (`fn_reposicao_agendar`).
///
/// **A data padrão é a da célula de onde o painel abriu**, que é o caso comum —
/// quem lança está olhando o dia em que vai encaixar o aluno. Data no passado
/// exige `turmas.lancar_reposicao_retroativa` e quem cobra é
/// `tg_reposicao_admissao`; a tela avisa antes, em vez de deixar o erro de
/// permissão aparecer sem contexto.
class FormularioLancarReposicao extends ConsumerStatefulWidget {
  const FormularioLancarReposicao({super.key, required this.celula});

  final CelulaGrade celula;

  @override
  ConsumerState<FormularioLancarReposicao> createState() =>
      _FormularioLancarReposicaoState();
}

class _FormularioLancarReposicaoState
    extends ConsumerState<FormularioLancarReposicao> {
  final _chave = GlobalKey<FormState>();
  final _busca = TextEditingController();
  late final _data = TextEditingController(
    text: formatarData(widget.celula.dataReferencia),
  );
  final _dataOrigem = TextEditingController();
  final _observacao = TextEditingController();
  String? _alunoId;
  String? _blocoOrigemId;

  @override
  void dispose() {
    _busca.dispose();
    _data.dispose();
    _dataOrigem.dispose();
    _observacao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final celula = widget.celula;
    final alunosAsync = ref.watch(alunosProvider);
    final blocosAsync = ref.watch(blocosProvider);
    final permissoes = ref.watch(permissoesProvider);

    if (!alunosAsync.hasValue || !blocosAsync.hasValue) {
      return FormularioIm360(
        titulo: 'Lançar reposição',
        chave: _chave,
        somenteLeitura: true,
        legendaObrigatorio: false,
        campos: const [EstadoCarregando(linhas: 5)],
      );
    }

    // Ao contrário da admissão, quem já está no bloco CONTINUA elegível: repor é
    // encaixe de um dia, e o aluno de terça pode vir repor na quarta no mesmo
    // horário — outro bloco, ou o mesmo em outra data.
    final candidatos = [
      for (final a in alunosAsync.requireValue)
        if (a.emAula && a.metodoId == celula.metodoId) a,
    ];
    final visiveis = filtrarAlunos(
      candidatos,
      FiltroAlunos(busca: _busca.text, ocultarEncerrados: false),
    );

    final blocosDoMetodo = [
      for (final b in blocosAsync.requireValue)
        if (b.metodoId == celula.metodoId && b.id != null) b,
    ];
    final origemValida = blocosDoMetodo.any((b) => b.id == _blocoOrigemId)
        ? _blocoOrigemId!
        : '';

    final data = lerData(_data.text);
    // "Hoje" é o de São Paulo, que é o que `fn_hoje()` responde e o que
    // `tg_reposicao_admissao` usa para decidir se a data é retroativa. Pelo
    // relógio do aparelho o aviso apareceria (ou faltaria) por um dia.
    final retroativa = data != null && data.isBefore(hojeSaoPaulo());
    final podeRetroativa = permissoes.contains(
      'turmas.lancar_reposicao_retroativa',
    );

    return FormularioIm360(
      titulo: 'Lançar reposição',
      chave: _chave,
      rotuloSalvar: 'Lançar',
      aviso: retroativa && !podeRetroativa ? avisoRetroativa : null,
      campos: [
        TextFormField(
          controller: _busca,
          decoration: InputDecoration(
            labelText: 'Buscar aluno',
            hintText: 'nome ou código SGF',
            helperText:
                'Alunos ATIVO/ACELERAR do método ${celula.metodoCodigo} — '
                'inclusive quem já está neste bloco, porque repor é encaixe '
                'de um dia.',
            helperMaxLines: 3,
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        ListaCandidatos(
          candidatos: visiveis,
          totalCandidatos: candidatos.length,
          selecionado: _alunoId,
          aoSelecionar: (id) => setState(() => _alunoId = id),
        ),
        TextFormField(
          controller: _data,
          style: Tipografia.numero(Tipografia.corpo),
          decoration: const InputDecoration(
            labelText: 'Data da reposição *',
            hintText: 'dd/mm/aaaa',
            helperText:
                'O dia em que o aluno vem repor. Só ela ocupa vaga, e só '
                'nesse dia.',
            helperMaxLines: 3,
          ),
          validator: validarData,
          onChanged: (_) => setState(() {}),
        ),
        // A origem é opcional de propósito (card 2.5 §3.1): a escola nem sempre
        // sabe qual encontro foi perdido, e exigir o dado produziria
        // preenchimento inventado. O preço está escrito no texto de apoio.
        DropdownButtonFormField<String>(
          initialValue: origemValida,
          decoration: const InputDecoration(
            labelText: 'Aula perdida — bloco',
            helperText:
                'Opcional. Sem a origem, esta reposição só quita a si mesma no '
                'cálculo do débito.',
            helperMaxLines: 3,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Não informado')),
            for (final b in blocosDoMetodo)
              DropdownMenuItem(
                value: b.id,
                child: Text(rotuloBloco(b.diaSemana, b.horaInicio)),
              ),
          ],
          onChanged: (valor) => setState(
            () => _blocoOrigemId = (valor == null || valor.isEmpty)
                ? null
                : valor,
          ),
        ),
        TextFormField(
          controller: _dataOrigem,
          style: Tipografia.numero(Tipografia.corpo),
          decoration: const InputDecoration(
            labelText: 'Aula perdida — data',
            hintText: 'dd/mm/aaaa',
            helperText: 'Opcional, e é ela que define o prazo dos 30 dias.',
            helperMaxLines: 3,
          ),
          validator: (valor) => validarData(valor, obrigatorio: false),
        ),
        TextFormField(
          controller: _observacao,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Observação'),
        ),
      ],
      aoSalvar: () async {
        final aluno = _alunoId;
        if (aluno == null) {
          throw const ErroApp(mensagem: escolhaAluno, traduzido: true);
        }
        final texto = _observacao.text.trim();
        await ref
            .read(turmasRepositorioProvider)
            .agendarReposicao(
              blocoId: celula.blocoId,
              alunoId: aluno,
              data: lerData(_data.text)!,
              blocoOrigemId: _blocoOrigemId,
              dataOrigem: lerData(_dataOrigem.text),
              observacao: texto.isEmpty ? null : texto,
            );
        recarregarTurmas(ref);
        return 'salvo';
      },
    );
  }
}

const avisoRetroativa =
    'Data no passado exige a permissão de lançar reposição retroativa, que '
    'este perfil não tem. O banco vai recusar.';

// ---------------------------------------------------------------------------
// As mesmas três ações, a partir da FICHA DO ALUNO (aba Turmas, wireframe §6.4)
// ---------------------------------------------------------------------------
//
// Os de cima partem de um bloco numa data e escolhem o aluno; estes partem do
// aluno e escolhem o bloco. São formulários diferentes porque a pergunta é a
// outra — o que se compartilha é o `SeletorBloco`, os avisos e as funções do
// banco, que são as mesmas.
//
// ⚠️ Existir aqui **não é conveniência**: a ficha é a única tela de onde se
// desfaz uma alocação em bloco DESATIVADO. O bloco inativo não está na grade
// (ela é das vagas, e bloco inativo não tem vaga a oferecer), então o painel do
// bloco nunca abre para ele — e, sem o botão desta aba, o aluno ficava marcado
// como "sem turma" para sempre, sem nenhuma tela capaz de resolvê-lo.

/// Aloca o aluno num bloco (`fn_bloco_admitir`), escolhendo o horário.
class FormularioAlocarEmBloco extends ConsumerStatefulWidget {
  const FormularioAlocarEmBloco({super.key, required this.aluno});

  final Aluno aluno;

  @override
  ConsumerState<FormularioAlocarEmBloco> createState() =>
      _FormularioAlocarEmBlocoState();
}

class _FormularioAlocarEmBlocoState
    extends ConsumerState<FormularioAlocarEmBloco> {
  final _chave = GlobalKey<FormState>();
  final _dataPrevista = TextEditingController();
  String _tipo = 'REM';
  String? _blocoId;

  @override
  void dispose() {
    _dataPrevista.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aluno = widget.aluno;
    // A grade da semana CORRENTE, não a que ficou aberta na tela de Turmas: a
    // alocação vale toda semana, e a vaga que decide é a de agora.
    final grade = ref.watch(gradeCorrenteProvider);
    if (!grade.hasValue) {
      return FormularioIm360(
        titulo: 'Alocar em bloco',
        chave: _chave,
        somenteLeitura: true,
        legendaObrigatorio: false,
        campos: const [EstadoCarregando(linhas: 4)],
      );
    }

    final jaAlocado = <String>{
      for (final t
          in ref.watch(turmasPorAlunoProvider)[aluno.id!] ??
              const <TurmaDoAluno>[])
        if (t.blocoAtivo) t.blocoId,
    };
    final blocos = [
      for (final c in blocosParaEscolha(
        grade.requireValue,
        metodoId: aluno.metodoId,
      ))
        if (!jaAlocado.contains(c.blocoId)) c,
    ];

    return FormularioIm360(
      titulo: 'Alocar em bloco',
      chave: _chave,
      rotuloSalvar: 'Alocar',
      campos: [
        Text(
          '${aluno.nome} passa a vir toda semana no horário escolhido.',
          style: Tipografia.corpo,
        ),
        SeletorBloco(
          rotulo: 'Bloco de horário *',
          blocos: blocos,
          selecionado: _blocoId,
          aoSelecionar: (id) => setState(() => _blocoId = id),
          vazio: semBlocoParaAlocar,
        ),
        DropdownButtonFormField<String>(
          initialValue: _tipo,
          decoration: const InputDecoration(
            labelText: 'Tipo na turma *',
            helperText:
                'REP aqui é a reposição CONTÍNUA, que ocupa vaga toda semana. '
                'Para repor uma aula perdida, use "Lançar reposição".',
            helperMaxLines: 3,
          ),
          items: [
            for (final entrada in tiposNaTurma.entries)
              DropdownMenuItem(
                value: entrada.key,
                child: Text('${entrada.key} — ${entrada.value}'),
              ),
          ],
          onChanged: (valor) => setState(() => _tipo = valor!),
        ),
        if (_tipo == 'NOVO')
          TextFormField(
            controller: _dataPrevista,
            style: Tipografia.numero(Tipografia.corpo),
            decoration: const InputDecoration(
              labelText: 'Início previsto',
              hintText: 'dd/mm/aaaa',
              helperText:
                  'A vaga fica reservada desde esta data, senão ela é vendida '
                  'duas vezes.',
              helperMaxLines: 3,
            ),
            validator: (valor) => validarData(valor, obrigatorio: false),
          ),
      ],
      aoSalvar: () async {
        final bloco = _blocoId;
        if (bloco == null) {
          throw const ErroApp(mensagem: escolhaBloco, traduzido: true);
        }
        await ref
            .read(turmasRepositorioProvider)
            .admitir(
              blocoId: bloco,
              alunoId: aluno.id!,
              tipo: _tipo,
              dataInicioPrevista: lerData(_dataPrevista.text),
            );
        recarregarTurmas(ref);
        return 'salvo';
      },
    );
  }
}

const semBlocoParaAlocar =
    'Nenhum horário deste método com vaga livre nesta semana em que o aluno '
    'ainda não esteja. Libere uma vaga, aumente a capacidade manual de um bloco '
    'ou cadastre outro horário.';

/// Lança uma reposição pontual do aluno (`fn_reposicao_agendar`), escolhendo o
/// bloco e o dia.
class FormularioReposicaoDoAluno extends ConsumerStatefulWidget {
  const FormularioReposicaoDoAluno({super.key, required this.aluno});

  final Aluno aluno;

  @override
  ConsumerState<FormularioReposicaoDoAluno> createState() =>
      _FormularioReposicaoDoAlunoState();
}

class _FormularioReposicaoDoAlunoState
    extends ConsumerState<FormularioReposicaoDoAluno> {
  final _chave = GlobalKey<FormState>();
  final _data = TextEditingController(text: formatarData(hojeSaoPaulo()));
  final _dataOrigem = TextEditingController();
  final _observacao = TextEditingController();
  String? _blocoId;
  String? _blocoOrigemId;

  @override
  void dispose() {
    _data.dispose();
    _dataOrigem.dispose();
    _observacao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aluno = widget.aluno;
    final grade = ref.watch(gradeCorrenteProvider);
    final blocosAsync = ref.watch(blocosProvider);
    final permissoes = ref.watch(permissoesProvider);

    if (!grade.hasValue || !blocosAsync.hasValue) {
      return FormularioIm360(
        titulo: 'Lançar reposição',
        chave: _chave,
        somenteLeitura: true,
        legendaObrigatorio: false,
        campos: const [EstadoCarregando(linhas: 5)],
      );
    }

    // Ao contrário da alocação, o bloco em que o aluno JÁ está continua
    // elegível: repor é encaixe de um dia, e ele pode vir na quarta repor a
    // aula de terça no mesmo horário.
    final blocos = blocosParaEscolha(
      grade.requireValue,
      metodoId: aluno.metodoId,
      somenteComVaga: false,
    );
    final blocosDoMetodo = [
      for (final b in blocosAsync.requireValue)
        if (b.metodoId == aluno.metodoId && b.id != null) b,
    ];
    final origemValida = blocosDoMetodo.any((b) => b.id == _blocoOrigemId)
        ? _blocoOrigemId!
        : '';

    final data = lerData(_data.text);
    final retroativa = data != null && data.isBefore(hojeSaoPaulo());
    final podeRetroativa = permissoes.contains(
      'turmas.lancar_reposicao_retroativa',
    );

    return FormularioIm360(
      titulo: 'Lançar reposição',
      chave: _chave,
      rotuloSalvar: 'Lançar',
      aviso: retroativa && !podeRetroativa ? avisoRetroativa : null,
      campos: [
        Text(
          '${aluno.nome} vem repor uma aula num dia só.',
          style: Tipografia.corpo,
        ),
        SeletorBloco(
          rotulo: 'Bloco em que vai repor *',
          blocos: blocos,
          selecionado: _blocoId,
          aoSelecionar: (id) => setState(() => _blocoId = id),
          vazio: semBlocoDoMetodo,
        ),
        TextFormField(
          controller: _data,
          style: Tipografia.numero(Tipografia.corpo),
          decoration: const InputDecoration(
            labelText: 'Data da reposição *',
            hintText: 'dd/mm/aaaa',
            helperText:
                'O dia em que o aluno vem repor. Só ela ocupa vaga, e só '
                'nesse dia.',
            helperMaxLines: 3,
          ),
          validator: validarData,
          onChanged: (_) => setState(() {}),
        ),
        DropdownButtonFormField<String>(
          initialValue: origemValida,
          decoration: const InputDecoration(
            labelText: 'Aula perdida — bloco',
            helperText:
                'Opcional. Sem a origem, esta reposição só quita a si mesma no '
                'cálculo do débito.',
            helperMaxLines: 3,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Não informado')),
            for (final b in blocosDoMetodo)
              DropdownMenuItem(
                value: b.id,
                child: Text(rotuloBloco(b.diaSemana, b.horaInicio)),
              ),
          ],
          onChanged: (valor) => setState(
            () => _blocoOrigemId = (valor == null || valor.isEmpty)
                ? null
                : valor,
          ),
        ),
        TextFormField(
          controller: _dataOrigem,
          style: Tipografia.numero(Tipografia.corpo),
          decoration: const InputDecoration(
            labelText: 'Aula perdida — data',
            hintText: 'dd/mm/aaaa',
            helperText: 'Opcional, e é ela que define o prazo dos 30 dias.',
            helperMaxLines: 3,
          ),
          validator: (valor) => validarData(valor, obrigatorio: false),
        ),
        TextFormField(
          controller: _observacao,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Observação'),
        ),
      ],
      aoSalvar: () async {
        final bloco = _blocoId;
        if (bloco == null) {
          throw const ErroApp(mensagem: escolhaBloco, traduzido: true);
        }
        final texto = _observacao.text.trim();
        await ref
            .read(turmasRepositorioProvider)
            .agendarReposicao(
              blocoId: bloco,
              alunoId: aluno.id!,
              data: lerData(_data.text)!,
              blocoOrigemId: _blocoOrigemId,
              dataOrigem: lerData(_dataOrigem.text),
              observacao: texto.isEmpty ? null : texto,
            );
        recarregarTurmas(ref);
        return 'salvo';
      },
    );
  }
}

const semBlocoDoMetodo =
    'Nenhum horário cadastrado neste método. Cadastre um bloco antes de lançar '
    'a reposição.';

/// Remove a alocação do aluno num bloco (`fn_bloco_remover`), a partir da ficha.
///
/// ⚠️ É a única saída para a alocação em **bloco desativado**: aquele bloco não
/// está na grade, então o painel do bloco nunca abre para ele.
class FormularioRemoverDaTurma extends ConsumerStatefulWidget {
  const FormularioRemoverDaTurma({
    super.key,
    required this.aluno,
    required this.turma,
    required this.ultimaAtiva,
  });

  final Aluno aluno;
  final TurmaDoAluno turma;

  /// Verdadeiro quando esta é a última alocação em bloco **ativo** — aí sair
  /// deixa o aluno sem turma, e a rotina diária abre a pendência.
  final bool ultimaAtiva;

  @override
  ConsumerState<FormularioRemoverDaTurma> createState() =>
      _FormularioRemoverDaTurmaState();
}

class _FormularioRemoverDaTurmaState
    extends ConsumerState<FormularioRemoverDaTurma> {
  final _chave = GlobalKey<FormState>();
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final turma = widget.turma;
    return FormularioIm360(
      titulo: 'Remover da turma',
      chave: _chave,
      rotuloSalvar: 'Remover',
      nivelSalvar: NivelBotao.destrutivo,
      aviso: widget.ultimaAtiva && widget.aluno.emAula
          ? '${widget.aluno.nome} ficará sem nenhuma turma. Na próxima '
                'execução da rotina diária (03:10) isso vira uma pendência '
                '"aluno sem turma" na central.'
          : null,
      campos: [
        Text(
          '${widget.aluno.nome} sai de ${turma.rotulo}'
          '${turma.blocoAtivo ? '' : ' (bloco desativado)'}.',
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
            .read(turmasRepositorioProvider)
            .remover(
              blocoId: turma.blocoId,
              alunoId: turma.alunoId,
              motivo: texto.isEmpty ? null : texto,
            );
        recarregarTurmas(ref);
        return 'removido';
      },
    );
  }
}
