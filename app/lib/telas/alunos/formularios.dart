import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alunos/alunos.dart';
import '../../alunos/alunos_provider.dart';
import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../erros/erro_app.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/modular.dart';
import '../../turmas/modular_provider.dart';
import '../../turmas/turmas_provider.dart';
import '../../widgets/badge_status.dart';
import '../../widgets/formulario.dart';
import '../turmas/formularios_modular.dart'
    show EscolhaModuloEntrada, moduloDeEntrada, temEscolhaDeEntrada;

/// Os formulários da tela de Alunos (card 4.6): matrícula/dados, alterar
/// status e reverter status. Todos devolvem `'salvo'` ao fechar, para a tela
/// mostrar a confirmação efêmera certa (design-system §5.8).
///
/// Nenhum deles verifica regra: submete e traduz o erro pelo código
/// (card 2.6 decisão 2). O que se valida aqui é formato — obrigatório e data.

void _recarregar(WidgetRef ref) =>
    ref.read(versaoAlunosProvider.notifier).incrementar();

/// Texto final do apontamento 6 do card 2.6 (design-system §7.3).
const avisoTrocaCombo =
    'Trocar o combo não refaz a trilha do aluno — será aberta uma pendência '
    'para revisar a trilha.';

/// Design-system §7.3, "Sair de ATIVO/ACELERAR".
const avisoSaiDasTurmas = 'O aluno será removido das turmas ao confirmar.';

// ---------------------------------------------------------------------------
// Matrícula e dados cadastrais
// ---------------------------------------------------------------------------

class FormularioAluno extends ConsumerStatefulWidget {
  const FormularioAluno({super.key, this.aluno});

  /// Nulo = matrícula.
  final Aluno? aluno;

  @override
  ConsumerState<FormularioAluno> createState() => _FormularioAlunoState();
}

class _FormularioAlunoState extends ConsumerState<FormularioAluno> {
  final _chave = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.aluno?.nome ?? '');
  late final _codigo = TextEditingController(
    text: widget.aluno?.codigoSgf ?? '',
  );
  late final _inicio = TextEditingController(
    text: formatarData(widget.aluno?.dataInicio ?? DateTime.now()),
  );
  late final _previsao = TextEditingController(
    text: widget.aluno?.prevConclusaoCurso == null
        ? ''
        : formatarData(widget.aluno!.prevConclusaoCurso!),
  );
  late final _observacoes = TextEditingController(
    text: widget.aluno?.observacoes ?? '',
  );
  late String? _metodoId = widget.aluno?.metodoId;
  late String? _comboId = widget.aluno?.comboId;

  /// Card 9.2,905 — só na matrícula de aluno Modular: a turma em que ele já
  /// entra e se começa no módulo atual ou no próximo.
  String? _turmaId;
  bool _noProximo = false;

  @override
  void dispose() {
    _nome.dispose();
    _codigo.dispose();
    _inicio.dispose();
    _previsao.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final combos = ref.watch(combosProvider).value ?? const <Combo>[];
    final aluno = widget.aluno;
    final editando = aluno != null;
    final somenteLeitura = editando
        ? !permissoes.contains('alunos.editar')
        : !permissoes.contains('alunos.criar');
    // Combo é do método: só os do método escolhido, ativos — mais o atual,
    // se ficou inativo depois da matrícula.
    final combosDoMetodo = [
      for (final c in combos)
        if (c.metodoId == _metodoId && (c.ativo || c.id == _comboId)) c,
    ];
    final trocouCombo = editando && _comboId != aluno.comboId;

    // -- Card 9.2,905: a turma Modular na matrícula ---------------------------
    // Só para método Modular e para quem pode alocar: `fn_turma_modular_admitir`
    // exige `turmas.alocar`, e oferecer a turma a quem não pode daria uma
    // matrícula que "funciona pela metade" toda vez.
    final modular = metodos.any((m) => m.id == _metodoId && m.modular);
    final podeAlocar =
        permissoes.contains('turmas.alocar') &&
        permissoes.contains('turmas.ler');
    final turmas = !editando && modular && podeAlocar
        ? (ref.watch(turmasModularProvider).value ?? const <TurmaModular>[])
        : const <TurmaModular>[];
    TurmaModular? turma;
    for (final t in turmas) {
      if (t.id == _turmaId) turma = t;
    }

    // -- Decisão D2: em turma Modular, a previsão é a calculada ---------------
    final calculada = editando && aluno.id != null
        ? previsaoCalculada(
            ref.watch(progressoModularProvider).value ??
                const <ProgressoAlunoModular>[],
            aluno.id!,
          )
        : (emTurma: false, data: null);

    return FormularioIm360(
      titulo: editando ? 'Dados do aluno' : 'Matricular aluno',
      rotuloSalvar: editando ? 'Salvar' : 'Matricular',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      aviso: trocouCombo ? avisoTrocaCombo : null,
      campos: [
        TextFormField(
          controller: _nome,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Nome *'),
          validator: validarObrigatorio,
        ),
        TextFormField(
          controller: _codigo,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Código SGF',
            helperText:
                'Opcional — o número do aluno no SGF. Único na unidade.',
            helperMaxLines: 3,
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: _metodoId,
          decoration: InputDecoration(
            labelText: 'Método *',
            helperText: editando
                ? 'O método não muda depois da matrícula.'
                : 'Combo, trilha e turmas são do método.',
            helperMaxLines: 3,
          ),
          items: [
            for (final m in metodos)
              if (m.ativo || m.id == _metodoId)
                DropdownMenuItem(value: m.id, child: Text(m.nome)),
          ],
          onChanged: somenteLeitura || editando
              ? null
              : (valor) => setState(() {
                  _metodoId = valor;
                  _comboId = null;
                }),
          validator: (valor) => valor == null ? 'Escolha o método.' : null,
        ),
        DropdownButtonFormField<String>(
          // A chave acompanha o método: trocar o método zera o combo.
          key: ValueKey('combo-$_metodoId'),
          initialValue: _comboId ?? '',
          decoration: const InputDecoration(
            labelText: 'Combo',
            helperText: 'A trilha do aluno nasce do combo na matrícula.',
            helperMaxLines: 3,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Nenhum')),
            for (final c in combosDoMetodo)
              DropdownMenuItem(value: c.id, child: Text(c.nome)),
          ],
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(
                  () => _comboId = (valor == null || valor.isEmpty)
                      ? null
                      : valor,
                ),
        ),
        TextFormField(
          controller: _inicio,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(
            labelText: 'Data de início *',
            hintText: 'dd/mm/aaaa',
          ),
          validator: validarData,
        ),
        if (turmas.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('turma-$_metodoId'),
            initialValue: _turmaId ?? '',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Turma Modular',
              helperText:
                  'O aluno já entra na turma ao matricular. Dá para deixar '
                  'para depois e adicioná-lo na tela Turmas Modular.',
              helperMaxLines: 3,
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('Nenhuma — alocar depois'),
              ),
              for (final t in turmas)
                DropdownMenuItem(
                  value: t.id,
                  child: Text(
                    '${t.nome} · ${t.cursoNome} · ${t.lotacaoTexto}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (valor) => setState(() {
              _turmaId = (valor == null || valor.isEmpty) ? null : valor;
              _noProximo = false;
            }),
          ),
          if (turma != null && turma.vagasLivres <= 0)
            AvisoTonal(
              mensagem:
                  'Esta turma está com ${turma.lotacaoTexto} — sem vaga livre. '
                  'O sistema confere ao matricular; se não couber, o aluno é '
                  'matriculado e fica sem turma.',
            ),
          if (turma != null && temEscolhaDeEntrada(turma))
            EscolhaModuloEntrada(
              turma: turma,
              noProximo: _noProximo,
              aoMudar: (valor) => setState(() => _noProximo = valor),
            ),
        ],
        if (calculada.emTurma)
          // Decisão D2 (card 9.2,87): para o aluno em turma Modular a previsão
          // é só a calculada. O campo NÃO some — some a edição, com o motivo.
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Previsão de conclusão',
              helperText: previsaoCalculadaAjuda,
              helperMaxLines: 4,
            ),
            child: Text(
              calculada.data == null
                  ? previsaoCalculadaSemData
                  : formatarData(calculada.data!),
              style: Tipografia.numero(Tipografia.corpo),
            ),
          )
        else
          TextFormField(
            controller: _previsao,
            readOnly: somenteLeitura,
            style: Tipografia.numero(Tipografia.corpo),
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(
              labelText: 'Previsão de conclusão',
              hintText: 'dd/mm/aaaa',
              helperText: turma != null
                  ? 'Não precisa informar: com o aluno na turma, a previsão '
                        'passa a ser calculada pela agenda dela.'
                  : 'Opcional, informada manualmente. Alimenta a projeção de '
                        'demanda de apostilas.',
              helperMaxLines: 3,
            ),
            validator: (valor) => validarData(valor, obrigatorio: false),
          ),
        TextFormField(
          controller: _observacoes,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Observações'),
        ),
      ],
      aoSalvar: () async {
        final salvo = await ref
            .read(alunosRepositorioProvider)
            .salvarAluno(
              Aluno(
                id: aluno?.id,
                nome: _nome.text,
                metodoId: _metodoId!,
                codigoSgf: _codigo.text,
                comboId: _comboId,
                status: aluno?.status ?? 'ATIVO',
                dataInicio: lerData(_inicio.text),
                prevConclusaoCurso: _previsao.text.trim().isEmpty
                    ? null
                    : lerData(_previsao.text),
                observacoes: _observacoes.text,
              ),
            );
        _recarregar(ref);

        // Card 9.2,905: a matrícula são DUAS chamadas — criar o aluno e
        // admiti-lo na turma. ⚠️ Se a segunda falhar, o aluno JÁ EXISTE: deixar
        // o erro subir manteria o formulário aberto, e um segundo clique em
        // "Matricular" criaria o aluno de novo. O formulário fecha, e quem
        // chamou diz o que aconteceu — em diálogo, com o motivo.
        final turmaEscolhida = turma;
        if (!editando && turmaEscolhida != null && salvo.id != null) {
          try {
            await ref
                .read(modularRepositorioProvider)
                .admitir(
                  turmaId: turmaEscolhida.id,
                  alunoId: salvo.id!,
                  moduloEntradaId: moduloDeEntrada(
                    turmaEscolhida,
                    noProximo: _noProximo,
                  ),
                );
          } catch (erro) {
            ref.read(versaoTurmasProvider.notifier).incrementar();
            return matriculadoSemTurma(
              turmaEscolhida.nome,
              traduzirErro(erro).mensagem,
            );
          }
          recarregarModular(ref);
          ref.read(versaoTurmasProvider.notifier).incrementar();
        }
        return 'salvo';
      },
    );
  }
}

/// O resultado da matrícula em que o aluno foi criado e a admissão na turma
/// falhou (card 9.2,905). Prefixo + texto: o formulário devolve `String`, e
/// quem o abre separa os dois casos com [mensagemSemTurma].
const _prefixoSemTurma = 'sem-turma:';

String matriculadoSemTurma(String turma, String motivo) =>
    '$_prefixoSemTurma'
    'O aluno foi matriculado, mas não entrou em $turma: $motivo '
    'Ele está sem turma — adicione-o pela tela Turmas Modular.';

/// O texto do diálogo quando [resultado] é o de uma matrícula sem turma; nulo
/// para a matrícula que deu inteira.
String? mensagemSemTurma(String? resultado) =>
    resultado != null && resultado.startsWith(_prefixoSemTurma)
    ? resultado.substring(_prefixoSemTurma.length)
    : null;

// ---------------------------------------------------------------------------
// Alterar status — só as transições válidas a partir do atual (§6.2)
// ---------------------------------------------------------------------------

class FormularioAlterarStatus extends ConsumerStatefulWidget {
  const FormularioAlterarStatus({super.key, required this.aluno});

  final Aluno aluno;

  @override
  ConsumerState<FormularioAlterarStatus> createState() =>
      _FormularioAlterarStatusState();
}

class _FormularioAlterarStatusState
    extends ConsumerState<FormularioAlterarStatus> {
  final _chave = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  String? _destino;

  /// Realce do campo quando o banco responde `MOTIVO_OBRIGATORIO`
  /// (design-system §5.4). A tela não pré-valida: o motivo é obrigatório por
  /// **destino**, e quem sabe a regra é `fn_aluno_alterar_status`.
  String? _erroMotivo;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aluno = widget.aluno;
    final destino = _destino;
    final avisa =
        destino != null && saiDasTurmas(de: aluno.status, para: destino);

    return FormularioIm360(
      titulo: 'Alterar status — ${aluno.nome}',
      rotuloSalvar: 'Alterar status',
      chave: _chave,
      somenteLeitura: !ref
          .watch(permissoesProvider)
          .contains('alunos.alterar_status'),
      aviso: avisa ? avisoSaiDasTurmas : null,
      aoErro: (erro) {
        if (erro.codigo == 'MOTIVO_OBRIGATORIO') {
          setState(() => _erroMotivo = erro.mensagem);
        }
      },
      campos: [
        Row(
          children: [
            const Text('Status atual', style: Tipografia.corpo),
            const SizedBox(width: Dim.e8),
            BadgeStatus(aluno.status),
          ],
        ),
        DropdownButtonFormField<String>(
          initialValue: _destino,
          decoration: const InputDecoration(
            labelText: 'Novo status *',
            helperText:
                'Só as mudanças permitidas a partir do status atual. FORMADO '
                'exige certificado entregue ou confirmação da direção.',
            helperMaxLines: 4,
          ),
          items: [
            for (final s in transicoesDe(aluno.status))
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (valor) => setState(() => _destino = valor),
          validator: (valor) => valor == null ? 'Escolha o novo status.' : null,
        ),
        TextFormField(
          controller: _motivo,
          style: Tipografia.corpo,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Motivo',
            helperText: 'Obrigatório para STANDBY, TRANCADO e CANCELADO.',
            helperMaxLines: 3,
            errorText: _erroMotivo,
          ),
          onChanged: (_) {
            if (_erroMotivo != null) setState(() => _erroMotivo = null);
          },
        ),
      ],
      aoSalvar: () async {
        final motivo = _motivo.text.trim();
        await ref
            .read(alunosRepositorioProvider)
            .alterarStatus(
              aluno.id!,
              status: _destino!,
              motivo: motivo.isEmpty ? null : motivo,
            );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Reverter status terminal — só a direção, motivo sempre obrigatório (§6.5)
// ---------------------------------------------------------------------------

class FormularioReverterStatus extends ConsumerStatefulWidget {
  const FormularioReverterStatus({super.key, required this.aluno});

  final Aluno aluno;

  @override
  ConsumerState<FormularioReverterStatus> createState() =>
      _FormularioReverterStatusState();
}

class _FormularioReverterStatusState
    extends ConsumerState<FormularioReverterStatus> {
  final _chave = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  String? _destino;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aluno = widget.aluno;
    return FormularioIm360(
      titulo: 'Reverter status — ${aluno.nome}',
      rotuloSalvar: 'Reverter',
      chave: _chave,
      somenteLeitura: !ref
          .watch(permissoesProvider)
          .contains('alunos.reverter_status'),
      aviso:
          'Reverter um status terminal é exceção: o motivo fica registrado no '
          'histórico com quem reverteu e quando.',
      campos: [
        Row(
          children: [
            const Text('Status atual', style: Tipografia.corpo),
            const SizedBox(width: Dim.e8),
            BadgeStatus(aluno.status),
          ],
        ),
        DropdownButtonFormField<String>(
          initialValue: _destino,
          decoration: const InputDecoration(labelText: 'Voltar para *'),
          items: [
            for (final s in destinosReversao(aluno.status))
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (valor) => setState(() => _destino = valor),
          validator: (valor) => valor == null ? 'Escolha o status.' : null,
        ),
        // Aqui o motivo é sempre obrigatório (card 4.2 (b)), então a
        // obrigatoriedade é formato e se valida localmente.
        TextFormField(
          controller: _motivo,
          style: Tipografia.corpo,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Motivo *'),
          validator: validarObrigatorio,
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(alunosRepositorioProvider)
            .reverterStatus(
              aluno.id!,
              destino: _destino!,
              motivo: _motivo.text.trim(),
            );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}
